import QtQuick
import QtQuick.Controls

// A slot filled by the host's picker (a button and the chosen value). A leaf of ValueChip.
Rectangle {
    required property Item chip
    id: pickChip
    readonly property bool live: chip.editable && !!chip.location && !chip.paletteMode
    implicitHeight: 27
    implicitWidth: Math.max(36, pickRow.implicitWidth + 18)
    radius: 5
    color: pickHover.hovered && live ? Theme.hover : (chip.flatLeaf ? "transparent" : Theme.field)
    border.color: chip.flatLeaf ? "transparent" : (pickHover.hovered && live ? Theme.accent : Theme.border)
    Behavior on color {
        enabled: Motion.enabled
        ColorAnimation {
            duration: Motion.quick
        }
    }
    Behavior on border.color {
        enabled: Motion.enabled
        ColorAnimation {
            duration: Motion.quick
        }
    }
    Row {
        id: pickRow
        anchors.centerIn: parent
        spacing: 6
        LucideIcon {
            visible: !!chip.activePick.icon
            name: chip.activePick.icon || ""
            width: 13
            height: 13
            color: Theme.text
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            textFormat: Text.PlainText
            text: chip.pickLabel
            color: Theme.text
            font.pixelSize: Theme.blockText
            anchors.verticalCenter: parent.verticalCenter
        }
    }
    HoverHandler {
        id: pickHover
        enabled: pickChip.live
        cursorShape: Qt.PointingHandCursor
    }
    TapHandler {
        enabled: pickChip.live
        onTapped: BlockRegistry.requestPick(chip.activePick.action || "", chip.location, chip.valueData, pickChip)
    }
    ToolTip.visible: pickHover.hovered && !!chip.activePick.tip
    ToolTip.delay: 500
    ToolTip.text: chip.activePick.tip || ""
    Accessible.role: Accessible.Button
    Accessible.name: chip.pickLabel
}
