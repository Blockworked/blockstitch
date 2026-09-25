import QtQuick

// One draggable value/operator chip in the palette.
Item {
    id: root
    property var valueData
    property var spec: ({})
    property bool editable: true
    property bool forceBoolean: false
    property string callLabel: "custom block"
    property var blockDefinitions: []
    signal dragStarted(var spec, real sceneX, real sceneY, real offsetX, real offsetY)
    signal dragMoved(real sceneX, real sceneY)
    signal dragEnded(real sceneX, real sceneY)
    signal dragCanceled()
    signal activated()
    signal detailsRequested(string kind)
    // The prefab was edited in place (a typed number, a chosen dropdown entry).
    signal valueEdited(var value)
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
        blockDefinitions: root.blockDefinitions; paletteMode: true
        onDetailsRequested: kind => root.detailsRequested(kind)
        onLeafEdited: (path, leaf) => {
            if (!path.length) { root.valueData = leaf; root.valueEdited(leaf); return; }
            const next = JSON.parse(JSON.stringify(root.valueData));
            let v = next;
            for (let i = 0; i < path.length - 1; ++i) v = v.args[path[i]];
            v.args[path[path.length - 1]] = leaf;
            root.valueData = next;
            root.valueEdited(next);
        }
    }
}
