import QtQuick

// Press-and-drag surface for blocks. Reports the pointer in *scene*
// coordinates so callers can map it into whatever (scaled, scrolled) space they
// need, and never relies on Qt's DragHandler translation, which is reset by the
// time a drag ends.
MouseArea {
    id: area
    property bool dragEnabled: true
    property real threshold: 5
    readonly property bool dragging: internal.dragging
    readonly property bool hovered: hover.hovered

    signal dragBegan(real sceneX, real sceneY, real offsetX, real offsetY)
    signal dragMoved(real sceneX, real sceneY)
    signal dragEnded(real sceneX, real sceneY)
    signal dragCanceled()
    signal contextRequested(real x, real y)
    signal activated()

    acceptedButtons: Qt.LeftButton | Qt.RightButton
    preventStealing: true

    QtObject {
        id: internal
        property bool armed: false
        property bool dragging: false
        property point pressScene
        property point pressLocal
    }
    HoverHandler {
        id: hover
        cursorShape: internal.dragging ? Qt.ClosedHandCursor : (area.dragEnabled ? Qt.OpenHandCursor : Qt.ArrowCursor)
    }

    onPressed: mouse => {
        if (mouse.button === Qt.RightButton) { area.contextRequested(mouse.x, mouse.y); return; }
        internal.pressScene = area.mapToItem(null, mouse.x, mouse.y);
        internal.pressLocal = Qt.point(mouse.x, mouse.y);
        internal.armed = area.dragEnabled;
    }
    onPositionChanged: mouse => {
        if (!internal.armed) return;
        const p = area.mapToItem(null, mouse.x, mouse.y);
        if (!internal.dragging) {
            if (Math.hypot(p.x - internal.pressScene.x, p.y - internal.pressScene.y) < area.threshold) return;
            internal.dragging = true;
            area.dragBegan(internal.pressScene.x, internal.pressScene.y, internal.pressLocal.x, internal.pressLocal.y);
        }
        area.dragMoved(p.x, p.y);
    }
    onReleased: mouse => {
        if (!internal.armed) return;
        internal.armed = false;
        if (!internal.dragging) return;
        internal.dragging = false;
        const p = area.mapToItem(null, mouse.x, mouse.y);
        area.dragEnded(p.x, p.y);
    }
    onCanceled: {
        internal.armed = false;
        if (internal.dragging) { internal.dragging = false; area.dragCanceled(); }
    }
    onDoubleClicked: mouse => { if (mouse.button === Qt.LeftButton) area.activated(); }
    Component.onDestruction: if (internal.dragging) area.dragCanceled()
}
