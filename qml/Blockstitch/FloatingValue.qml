import QtQuick

// A reporter left loose on the canvas, with its own Details/Delete menu.
Item {
    id: floatingItem
    required property Item canvas
    required property var modelData
    x: modelData.x + canvas.originOffsetX
    y: modelData.y + canvas.originOffsetY
    z: 5
    width: floatingChip.implicitWidth
    height: floatingChip.implicitHeight
    ValueChip {
        id: floatingChip
        valueData: floatingItem.modelData.value
        originBlockId: floatingItem.modelData.origin_block_id || ""
        location: ({
                kind: "Floating",
                floating_id: floatingItem.modelData.id,
                path: []
            })
        boxed: true
        blockDefinitions: canvas.blockDefinitions
        canvasState: canvas.canvasState
        onEditRequested: (l, t) => canvas.valueEdited(l, t)
        onDetailsRequested: kind => canvas.detailsRequested(kind)
        onValueDragBegan: (loc, val, sx, sy, ox, oy, w, h) => canvas.beginValueDrag(loc, val, sx, sy, ox, oy, w, h)
        onValueDragMoved: (sx, sy) => canvas.moveValueDrag(sx, sy)
        onValueDragEnded: (sx, sy) => canvas.endValueDrag(sx, sy)
        onValueDragCanceled: canvas.cancelValueDrag()
        // The chip's own menu, so one right-click opens one menu.
        extraMenu: [
            {
                id: "details",
                text: qsTr("Details"),
                icon: "info"
            },
            {
                id: "delete",
                text: qsTr("Delete value"),
                icon: "trash",
                danger: true
            }
        ]
        onExtraMenuTriggered: id => {
            if (id === "delete")
                canvas.floatingValueRemoved(floatingItem.modelData.id);
        }
    }
}
