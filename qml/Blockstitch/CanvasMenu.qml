import QtQuick

// The canvas background's right-click menu: the host's BlockRegistry.canvasMenu
// entries first, then delete all, paste and add a comment.
Item {
    id: menuHost
    required property Item canvas
    // Opens at (x, y) in the parent's coordinates for canvas point (cx, cy).
    function popupAt(x, y, cx, cy) {
        canvasMenu.canvasX = cx;
        canvasMenu.canvasY = cy;
        canvasMenu.popup(x, y);
    }
    StitchMenu {
        id: canvasMenu
        property int canvasX: 0
        property int canvasY: 0
        StitchMenuItem {
            visible: canvas.offerClear
            iconName: canvas.clearIcon
            danger: true
            text: canvas.clearText
            onTriggered: canvas.clearRequested()
        }
        StitchMenuItem {
            iconName: "clipboard-paste"
            enabled: canvas.canPaste
            text: qsTr("Paste")
            onTriggered: canvas.canvasMenuAction("paste", canvasMenu.canvasX, canvasMenu.canvasY)
        }
        StitchMenuItem {
            iconName: "message-square"
            text: qsTr("Add Comment")
            onTriggered: canvas.canvasNoteRequested(canvasMenu.canvasX, canvasMenu.canvasY)
        }
    }
    Instantiator {
        model: BlockRegistry.canvasMenu
        delegate: StitchMenuItem {
            required property var modelData
            iconName: modelData.icon || ""
            text: modelData.text
            danger: !!modelData.danger
            onTriggered: canvas.canvasMenuAction(modelData.id, canvasMenu.canvasX, canvasMenu.canvasY)
        }
        onObjectAdded: (index, object) => canvasMenu.insertItem(index, object)
        onObjectRemoved: (index, object) => canvasMenu.removeItem(object)
    }
}
