import QtQuick

// Eases a Flickable to its scroll target, so a mouse wheel notch glides instead
// of jumping. Notches that land mid-glide add to the target. Touchpads (already
// smooth) and Instant animation speed move the content directly.
QtObject {
    id: root
    property Flickable flickable: null
    property real targetX: 0
    property real targetY: 0

    readonly property NumberAnimation animX: NumberAnimation {
        target: root.flickable; property: "contentX"; duration: Motion.scroll; easing.type: Easing.OutCubic
    }
    readonly property NumberAnimation animY: NumberAnimation {
        target: root.flickable; property: "contentY"; duration: Motion.scroll; easing.type: Easing.OutCubic
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
    function isTouchpad(event) {
        if (event.phase !== Qt.NoScrollPhase) return true;
        const dev = event.device;
        if (x11) return !!dev && /touch ?pad|track ?pad|synaptics|glidepoint/i.test(dev.name);
        if (Qt.platform.pluginName === "wayland" || Qt.platform.os === "osx") return false;
        return !!dev && dev.type === PointerDevice.TouchPad;
    }

    function stop() { animX.stop(); animY.stop(); }

    // Scrolls by (dx, dy) px; positive moves the view up/left, like a wheel turned away.
    function scrollBy(dx, dy, smooth) {
        const f = flickable;
        if (!f) return;
        scrollTo(dx !== 0 ? (animX.running ? targetX : f.contentX) - dx : NaN,
                 dy !== 0 ? (animY.running ? targetY : f.contentY) - dy : NaN, smooth);
    }

    // Scrolls to content position (x, y), clamped to the content; NaN leaves that axis alone.
    function scrollTo(x, y, smooth) {
        const f = flickable;
        if (!f) return;
        const glide = smooth && Motion.enabled;
        if (!isNaN(x)) {
            targetX = Math.max(f.originX, Math.min(f.originX + Math.max(0, f.contentWidth - f.width), x));
            move(animX, "contentX", targetX, glide);
        }
        if (!isNaN(y)) {
            targetY = Math.max(f.originY, Math.min(f.originY + Math.max(0, f.contentHeight - f.height), y));
            move(animY, "contentY", targetY, glide);
        }
    }

    function move(anim, prop, to, glide) {
        anim.stop();
        if (!glide || flickable[prop] === to) { flickable[prop] = to; return; }
        anim.from = flickable[prop];
        anim.to = to;
        anim.start();
    }
}
