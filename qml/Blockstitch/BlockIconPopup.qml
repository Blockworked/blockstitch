import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// The icon picker of BlockDefinitionEditor: searches Lucide icons and sets
// the editor's blockIcon.
Popup {
    id: iconPopup
    required property Item editor
    parent: Overlay.overlay
    enter: Transition {
        enabled: Motion.enabled
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Motion.slow; easing.type: Easing.OutCubic }
            NumberAnimation { property: "scale"; from: 0.94; to: 1; duration: Motion.slow; easing.type: Easing.OutCubic }
        }
    }
    exit: Transition {
        enabled: Motion.enabled
        NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Motion.normal; easing.type: Easing.InCubic }
    }
    anchors.centerIn: parent
    modal: true
    focus: true
    width: Math.min(520, parent.width - 48)
    height: Math.min(520, parent.height - 48)
    padding: 12
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    background: Rectangle {
        radius: 8
        color: Theme.block
        border.color: Theme.border
    }
    readonly property var shown: {
        const q = editor.iconSearch.trim().toLowerCase();
        return q.length ? editor.allIcons.filter(n => n.indexOf(q) >= 0) : editor.allIcons;
    }
    contentItem: ColumnLayout {
        spacing: 10
        BwTextField {
            id: iconSearchField
            Layout.fillWidth: true
            placeholderText: qsTr("Search icons")
            text: editor.iconSearch
            onTextChanged: editor.iconSearch = text
        }
        GridView {
            id: iconGrid
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            cellWidth: Math.floor(width / Math.max(1, Math.floor(width / 52)))
            cellHeight: 52
            model: iconPopup.shown
            ScrollBar.vertical: ScrollBar {}
            delegate: Item {
                required property string modelData
                width: iconGrid.cellWidth
                height: iconGrid.cellHeight
                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 3
                    radius: 6
                    color: tile.hovered ? Theme.hover : Theme.field
                    Behavior on color { enabled: Motion.enabled; ColorAnimation { duration: Motion.quick } }
                    border.color: editor.blockIcon === modelData ? Theme.accent : Theme.border
                    border.width: editor.blockIcon === modelData ? 2 : 1
                }
                LucideIcon {
                    anchors.centerIn: parent
                    width: 22
                    height: 22
                    name: modelData
                    color: Theme.text
                }
                HoverHandler {
                    id: tile
                    cursorShape: Qt.PointingHandCursor
                }
                TapHandler {
                    onTapped: {
                        editor.blockIcon = modelData;
                        iconPopup.close();
                    }
                }
                ToolTip.visible: tile.hovered
                ToolTip.delay: 400
                ToolTip.text: modelData
            }
        }
        Text {
            visible: iconPopup.shown.length === 0
            text: qsTr("No icons match")
            color: Theme.textDim
            Layout.alignment: Qt.AlignHCenter
        }
    }
}
