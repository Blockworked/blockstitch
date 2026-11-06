import QtQuick
import QtQuick.Controls

// A block's right-click menu: edit, copy, cut, comment, details, delete, plus
// the host's own items (BlockRegistry.blockMenu) or a palette block's extraMenu.
BwMenu {
    id: menu
    // The InstructionBlock this menu acts on.
    required property Item block

    BwMenuItem {
        visible: !block.paletteMode && block.isCustomBlock && block.type === "BlockHeader"
        iconName: "blocks"
        text: qsTr("Edit block")
        onTriggered: block.menuActionRequested("edit_block", block.strandId, block.path, block.instruction)
    }
    BwMenuItem {
        visible: !block.paletteMode
        iconName: "copy"
        text: qsTr("Copy block")
        onTriggered: block.menuActionRequested("copy", block.strandId, block.path, block.instruction)
    }
    BwMenuItem {
        visible: !block.paletteMode
        iconName: "layers"
        text: qsTr("Copy all")
        onTriggered: block.menuActionRequested("copy_all", block.strandId, block.path, block.instruction)
    }
    BwMenuItem {
        visible: !block.paletteMode
        iconName: "corner-down-right"
        text: qsTr("Duplicate block")
        onTriggered: block.duplicateRequested(block.strandId, block.path, block.instruction)
    }
    BwMenuItem {
        visible: !block.paletteMode
        iconName: "scissors"
        text: qsTr("Cut block")
        onTriggered: block.menuActionRequested("cut", block.strandId, block.path, block.instruction)
    }
    BwMenuItem {
        visible: !block.paletteMode
        iconName: "message-square"
        text: block.hasComment ? qsTr("Comment") : qsTr("Add Comment")
        onTriggered: block.commentRequested(block.instruction)
    }
    BwMenuItem {
        visible: !block.paletteMode || !block.extraMenu || block.extraMenu.length === 0
        iconName: "info"
        text: qsTr("Details")
        onTriggered: block.detailsRequested(block.isCustomBlock && block.instruction ? block.instruction.block_id : block.type)
    }
    BwMenuItem {
        id: deleteItem
        visible: !block.paletteMode
        iconName: "trash"
        danger: true
        text: qsTr("Delete block")
        onTriggered: block.removeRequested(block.strandId, block.path)
    }
    Instantiator {
        model: block.paletteMode ? block.extraMenu : BlockRegistry.blockMenu
        delegate: BwMenuItem {
            required property var modelData
            iconName: modelData.icon || ""
            // A host item may name itself per block: text(instruction, strandId, path).
            text: typeof modelData.text === "function" ? modelData.text(block.instruction, block.strandId, block.path) : modelData.text
            danger: !!modelData.danger
            visible: block.paletteMode || typeof modelData.when !== "function" || !!modelData.when(block.instruction, block.strandId, block.path)
            onTriggered: !block.paletteMode ? block.menuActionRequested(modelData.id, block.strandId, block.path, block.instruction) : modelData.id === "details" ? block.detailsRequested(block.isCustomBlock && block.instruction ? block.instruction.block_id : block.type) : block.extraMenuTriggered(modelData.id)
        }
        onObjectAdded: (index, object) => block.paletteMode ? menu.addItem(object) : menu.insertItem(index, object)
        onObjectRemoved: (index, object) => menu.removeItem(object)
    }
}
