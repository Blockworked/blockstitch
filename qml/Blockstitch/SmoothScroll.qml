import QtQuick

// Eases a Flickable to its scroll target, so a mouse wheel notch glides instead
// of jumping. A notch that lands mid-glide carries on at the glide's current
// speed rather than kicking it again, so spinning the wheel scrolls at an even
// pace. Touchpad pans (follow) trail their target by a few frames instead,
// which evens out uneven event timing without a noticeable lag. Instant
// animation speed moves the content directly.
QtObject {
    id: root
    property Flickable flickable: null
    property real targetX: 0
    property real targetY: 0
    readonly property bool glidingX: _gx !== null
    readonly property bool glidingY: _gy !== null
    // Current glide speed in px/s, 0 when still.
    readonly property real velocityX: _speed(_gx)
    readonly property real velocityY: _speed(_gy)

    // A glide follows f(s) = m s + (3 - 2m) s^2 + (m - 2) s^3, which starts
    // at slope m and stops at 1. From rest m = 2, a plain quadratic ease-out:
    // OutCubic (m = 3) moved a third of a notch in the first frame and read as
    // a jump with a tail. The glide outlasts the gap between notches of a
    // normal spin, so the view keeps moving instead of stopping at each one.
    readonly property real glideTime: Motion.dur(220) / 1000
    property var _gx: null
    property var _gy: null
    property real _clock: 0
    function _at(g, s) { return g.from + (g.to - g.from) * (g.m * s + (3 - 2 * g.m) * s * s + (g.m - 2) * s * s * s); }
    function _speed(g) {
        if (!g) return 0;
        const s = Math.min(1, (_clock - g.start) / g.time);
        return (g.to - g.from) * (g.m + 2 * (3 - 2 * g.m) * s + 3 * (g.m - 2) * s * s) / g.time;
    }
    function _glide(from, to, v0) {
        const d = to - from;
        let time = glideTime, m = 2;
        if (v0 * d > 0) {
            // Mid-glide, start at the current speed: arrive sooner when
            // already moving fast, or speed up gently when slow.
            time = Math.min(glideTime, Math.max(glideTime * 0.4, 2 * d / v0));
            m = Math.max(1, Math.min(2, v0 * time / d));
        }
        return { from: from, to: to, m: m, time: time, start: _clock };
    }
    readonly property FrameAnimation glider: FrameAnimation {
        running: root._gx !== null || root._gy !== null
        onTriggered: {
            const f = root.flickable;
            root._clock += Math.max(0, frameTime);
            if (!f) { root._gx = null; root._gy = null; return; }
            const gx = root._gx, gy = root._gy;
            if (gx) {
                const s = Math.min(1, (root._clock - gx.start) / gx.time);
                f.contentX = s >= 1 ? gx.to : root._at(gx, s);
                if (s >= 1) root._gx = null;
            }
            if (gy) {
                const s = Math.min(1, (root._clock - gy.start) / gy.time);
                f.contentY = s >= 1 ? gy.to : root._at(gy, s);
                if (s >= 1) root._gy = null;
            }
        }
    }

    // Touchpad follow: each frame closes the same share of the remaining
    // distance, about 95% within 100 ms at normal animation speed.
    property real followX: 0
    property real followY: 0
    property bool following: false
    readonly property real followTime: 0.035 * Motion.durationScale
    readonly property FrameAnimation follower: FrameAnimation {
        running: root.following
        onTriggered: {
            const f = root.flickable;
            if (!f) { root.following = false; return; }
            const k = Math.min(1, 1 - Math.exp(-Math.max(0, frameTime) / Math.max(0.001, root.followTime)));
            const dx = root.followX - f.contentX;
            const dy = root.followY - f.contentY;
            const done = Math.abs(dx) < 0.5 && Math.abs(dy) < 0.5;
            f.contentX = done ? root.followX : f.contentX + dx * k;
            f.contentY = done ? root.followY : f.contentY + dy * k;
            if (done) root.following = false;
        }
    }

    // A drag or flick takes over from a glide in progress.
    readonly property Connections userMove: Connections {
        target: root.flickable
        function onMovementStarted() { root.stop(); }
    }

    // Whether a wheel event comes from a touchpad rather than a mouse wheel.
    // - pixelDelta can't tell: Wayland gives every wheel notch one (the
    //   compositor's axis value), and so does X11 with libinput.
    // - Neither can the device type on X11: Qt types any XInput device with
    //   relative motion and a scroll valuator, i.e. every mouse, as TouchPad.
    // Touchpads on Wayland and macOS send scroll phases. On X11 the device
    // name is the only reliable hint.
    readonly property bool x11: Qt.platform.pluginName === "xcb"
    // Windows hands Qt a precision touchpad's scroll as plain WM_MOUSEWHEEL:
    // mouse device, no phase, no pixelDelta. Only the size gives it away, as
    // wheels step in whole 120s. Tests set this to play Windows events.
    property bool windows: Qt.platform.os === "windows"
    // A stream that showed a fine step stays a touchpad until it pauses, so
    // a whole 120 inside a fast swipe or the OS's coasting doesn't glide.
    readonly property int fineStreamGap: 200
    property real _fineUntil: 0
    function _windowsTouchpad(event) {
        const ad = event.angleDelta, now = Date.now();
        if (ad.x % 120 !== 0 || ad.y % 120 !== 0 || now < _fineUntil) {
            _fineUntil = now + fineStreamGap;
            return true;
        }
        return false;
    }
    function isTouchpad(event) {
        // The browser can't tell them apart; every wheel event there takes the
        // follow path, which keeps up when events arrive faster than frames.
        if (Qt.platform.os === "wasm") return true;
        if (event.phase !== Qt.NoScrollPhase) return true;
        // Hi-res wheels count as touchpads here too, which suits their small steps.
        if (windows) return _windowsTouchpad(event);
        const dev = event.device;
        if (x11) return !!dev && /touch ?pad|track ?pad|synaptics|glidepoint/i.test(dev.name);
        if (Qt.platform.pluginName === "wayland" || Qt.platform.os === "osx") return false;
        return !!dev && dev.type === PointerDevice.TouchPad;
    }

    // Pixels to pan for one axis of a wheel event. A mouse wheel gets Qt's own
    // Flickable step per notch (angleDelta 120, less on hi-res wheels) with no
    // acceleration; a touchpad gets an accelerated pan starting at `base` px
    // per unit. pixelDelta is truncated to ints on touchpads; angleDelta
    // carries the real resolution (about 12 units per px). A Windows
    // touchpad driver already accelerates and coasts its steps (a quick flick
    // sends 50+ notches' worth), so there it pans at the plain wheel rate.
    function wheelStep(angleDelta, pixelDelta, touchpad, base) {
        if (!touchpad || windows) return angleDelta / 120 * Qt.styleHints.wheelScrollLines * 24;
        const d = angleDelta !== 0 ? angleDelta / 12 : pixelDelta;
        return d * Math.min(24, (base === undefined ? 6 : base) + 1.5 * Math.abs(d));
    }

    function stop() { _gx = null; _gy = null; following = false; }

    // Pans by (dx, dy) px from a touchpad, trailing slightly behind; positive
    // moves the view up/left, like scrollBy.
    function follow(dx, dy) {
        const f = flickable;
        if (!f) return;
        if (!Motion.enabled) { scrollBy(dx, dy, false); return; }
        _gx = null;
        _gy = null;
        const bx = following ? followX : f.contentX;
        const by = following ? followY : f.contentY;
        followX = Math.max(f.originX, Math.min(f.originX + Math.max(0, f.contentWidth - f.width), bx - dx));
        followY = Math.max(f.originY, Math.min(f.originY + Math.max(0, f.contentHeight - f.height), by - dy));
        following = true;
    }

    // Scrolls by (dx, dy) px; positive moves the view up/left, like a wheel turned away.
    function scrollBy(dx, dy, smooth) {
        const f = flickable;
        if (!f) return;
        scrollTo(dx !== 0 ? (glidingX ? targetX : f.contentX) - dx : NaN,
                 dy !== 0 ? (glidingY ? targetY : f.contentY) - dy : NaN, smooth);
    }

    // Scrolls to content position (x, y), clamped to the content; NaN leaves
    // that axis alone. vx, vy (px/s) start a glide already moving, for one
    // that was paused; otherwise a running glide's own speed carries over.
    function scrollTo(x, y, smooth, vx, vy) {
        const f = flickable;
        if (!f) return;
        const glide = smooth && Motion.enabled;
        following = false;
        if (!isNaN(x)) {
            targetX = Math.max(f.originX, Math.min(f.originX + Math.max(0, f.contentWidth - f.width), x));
            const v = glidingX ? velocityX : (vx || 0);
            _gx = null;
            if (!glide || Math.abs(f.contentX - targetX) < 0.5) f.contentX = targetX;
            else _gx = _glide(f.contentX, targetX, v);
        }
        if (!isNaN(y)) {
            targetY = Math.max(f.originY, Math.min(f.originY + Math.max(0, f.contentHeight - f.height), y));
            const v = glidingY ? velocityY : (vy || 0);
            _gy = null;
            if (!glide || Math.abs(f.contentY - targetY) < 0.5) f.contentY = targetY;
            else _gy = _glide(f.contentY, targetY, v);
        }
    }
}
