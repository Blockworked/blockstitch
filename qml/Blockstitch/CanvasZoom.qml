import QtQuick

// A BlockCanvas's zoom. Zooming keeps one workspace point (the anchor) under
// one viewport point, also on every frame of a glide, so the view never
// drifts while it scales. A glide can also carry the anchor to another
// viewport point (resetView).
QtObject {
    id: zoomer
    required property Item canvas
    required property Flickable flick
    required property SmoothScroll scroll
    readonly property bool gliding: glide.running
    // Where a glide in progress ends, else the current zoom.
    readonly property real target: glide.running ? toZoom : canvas.zoom
    property real anchorX: 0
    property real anchorY: 0
    property real fromViewX: 0
    property real fromViewY: 0
    property real viewX: 0
    property real viewY: 0
    property real fromZoom: 1
    property real toZoom: 1
    property real progress: 1
    property NumberAnimation glide: NumberAnimation {
        target: zoomer
        property: "progress"
        from: 0
        to: 1
        duration: Motion.scroll
        easing.type: Easing.OutCubic
    }
    onProgressChanged: if (glide.running)
        apply(progress)
    function stop() { glide.stop(); }
    function apply(t) {
        const z = fromZoom + (toZoom - fromZoom) * t;
        const vx = fromViewX + (viewX - fromViewX) * t;
        const vy = fromViewY + (viewY - fromViewY) * t;
        canvas.zoom = z;
        flick.contentX = Math.max(0, Math.min(Math.max(0, flick.contentWidth - flick.width), anchorX * z - vx));
        flick.contentY = Math.max(0, Math.min(Math.max(0, flick.contentHeight - flick.height), anchorY * z - vy));
    }
    // Zooms to newZoom while moving workspace point (ax, ay) to viewport
    // point (vx, vy). With smooth, it glides there, over ms if given.
    function zoomTo(ax, ay, vx, vy, newZoom, smooth, ms) {
        glide.stop();
        scroll.stop();
        anchorX = ax;
        anchorY = ay;
        fromViewX = ax * canvas.zoom - flick.contentX;
        fromViewY = ay * canvas.zoom - flick.contentY;
        viewX = vx;
        viewY = vy;
        fromZoom = canvas.zoom;
        toZoom = newZoom;
        if (!smooth || !Motion.enabled) {
            apply(1);
            return;
        }
        glide.duration = ms !== undefined ? Motion.dur(ms) : Motion.scroll;
        progress = 0;
        glide.start();
    }
    // Zoom around a viewport point (vx, vy in Flickable viewport pixels) so
    // that point stays visually still.
    function zoomAt(vx, vy, newZoom, smooth, ms) {
        newZoom = Math.max(0.5, Math.min(1.8, newZoom));
        if (!isFinite(vx) || !isFinite(vy))
            return;
        if (newZoom === target)
            return;
        zoomTo((flick.contentX + vx) / canvas.zoom, (flick.contentY + vy) / canvas.zoom, vx, vy, newZoom, smooth, ms);
    }
}
