import QtQuick

// One draggable value/operator chip in the palette.
Item {
    id: root
    property var valueData
    property var spec: ({})
    property bool editable: true
    property bool forceBoolean: false
    property string callLabel: "custom block"
    signal dragStarted(var spec, real sceneX, real sceneY, real offsetX, real offsetY)
    signal dragMoved(real sceneX, real sceneY)
    signal dragEnded(real sceneX, real sceneY)
    signal dragCanceled()
    signal activated()
    signal detailsRequested(string kind)
    implicitWidth: chip.implicitWidth
    implicitHeight: chip.implicitHeight
    width: implicitWidth; height: implicitHeight

    BlockDragArea {
        anchors.fill: parent
        onDragBegan: (sx, sy, ox, oy) => root.dragStarted(root.spec, sx, sy, ox, oy)
        onDragMoved: (sx, sy) => root.dragMoved(sx, sy)
        onDragEnded: (sx, sy) => root.dragEnded(sx, sy)
        onDragCanceled: root.dragCanceled()
        onActivated: root.activated()
    }
    ValueChip {
        id: chip
        valueData: root.valueData; editable: root.editable; boxed: true
        forceBoolean: root.forceBoolean; callDisplayLabel: root.callLabel
        onDetailsRequested: kind => root.detailsRequested(kind)
    }
}
