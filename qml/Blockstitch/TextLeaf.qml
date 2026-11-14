import QtQuick
import QtQuick.Controls

// A one-line number or text slot, typed in place. A leaf of ValueChip.
Item {
    required property Item chip
    implicitWidth: leafInput.implicitWidth
    implicitHeight: leafInput.implicitHeight
    StitchTextField {
        id: leafInput
        readOnly: !chip.editable
        text: chip.leafText
        selectByMouse: true
        font.pixelSize: Theme.blockText
        color: Theme.text
        implicitHeight: 27
        // Only a text slot can hold lines; a number slot never gets the bigger box.
        readonly property bool canExpand: chip.editable && !!chip.valueData && chip.valueData.kind === "Text"
        // Room on the right for the expand button while editing.
        readonly property bool expandShown: activeFocus && canExpand
        implicitWidth: Math.max(36, Math.min(600, contentWidth + 18 + (expandShown ? 20 : 0)))
        leftPadding: 7
        rightPadding: expandShown ? 27 : 7
        topPadding: 2
        bottomPadding: 2
        background: Rectangle {
            radius: 5
            color: chip.flatLeaf ? "transparent" : Theme.field
            border.color: chip.flatLeaf ? "transparent" : (leafInput.activeFocus ? Theme.accent : Theme.border)
        }
        onEditingFinished: chip.commitText(text)
        // Shift+Enter starts a second line, in the bigger editor.
        Keys.onPressed: event => {
            if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && (event.modifiers & Qt.ShiftModifier) && leafInput.canExpand) {
                event.accepted = true;
                const at = leafInput.cursorPosition;
                chip.openTextEditor(leafInput.text.slice(0, at) + "\n" + leafInput.text.slice(at));
            }
        }
        Item {
            objectName: "expandTextButton"
            visible: leafInput.expandShown
            anchors.right: parent.right
            anchors.rightMargin: 3
            anchors.verticalCenter: parent.verticalCenter
            width: 21
            height: 21
            LucideIcon {
                anchors.centerIn: parent
                name: "maximize"
                width: 12
                height: 12
                color: expandMouse.containsMouse ? Theme.accent : Theme.textDim
            }
            ToolTip.visible: expandMouse.containsMouse
            ToolTip.delay: 400
            ToolTip.text: qsTr("Edit in a bigger box (Shift+Enter adds a line)")
            MouseArea {
                id: expandMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: chip.openTextEditor(leafInput.text)
            }
        }
    }
}
