import QtQuick
import QtQuick.Controls

// A block's text box: every line shows, typed in place. A leaf of ValueChip.
Rectangle {
    required property Item chip
    id: boxLeaf
    objectName: "multilineBox"
    readonly property real lineHeight: boxMetrics.height
    readonly property int shownLines: Math.max(1, Math.min(10, boxArea.lineCount))
    implicitWidth: Math.max(260, Math.min(600, boxArea.contentWidth + 44))
    implicitHeight: shownLines * lineHeight + 14
    radius: 5
    color: Theme.field
    border.color: boxArea.activeFocus ? Theme.accent : Theme.border
    FontMetrics {
        id: boxMetrics
        font: boxArea.font
    }
    Flickable {
        id: boxFlick
        anchors.fill: parent
        anchors.margins: 1
        anchors.rightMargin: 24
        contentWidth: boxArea.contentWidth + 14
        contentHeight: boxArea.contentHeight + 12
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: (contentHeight > height || contentWidth > width) && textHolds === 0
        property int textHolds: 0
        TextEdit {
            id: boxArea
            objectName: "multilineBoxArea"
            x: 7
            y: 6
            // Fill the box, so a click anywhere in it starts typing.
            width: Math.max(contentWidth, boxFlick.width - 14)
            height: Math.max(contentHeight, boxFlick.height - 12)
            readOnly: !chip.editable
            text: chip.leafText
            selectByMouse: true
            font.pixelSize: Theme.blockText
            font.family: chip.monospace ? "monospace" : font.family
            color: Theme.text
            selectionColor: Theme.accent
            selectedTextColor: "white"
            onEditingFinished: chip.commitText(text)
            TextSelectHold {}
            onCursorRectangleChanged: {
                const r = cursorRectangle;
                if (r.y < boxFlick.contentY)
                    boxFlick.contentY = r.y;
                else if (r.y + r.height + 12 > boxFlick.contentY + boxFlick.height)
                    boxFlick.contentY = r.y + r.height + 12 - boxFlick.height;
            }
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    event.accepted = true;
                    boxArea.focus = false;
                }
            }
        }
    }
    Item {
        visible: chip.editable
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 3
        width: 21
        height: 21
        LucideIcon {
            anchors.centerIn: parent
            name: "maximize"
            width: 12
            height: 12
            color: boxExpandMouse.containsMouse ? Theme.accent : Theme.textDim
        }
        ToolTip.visible: boxExpandMouse.containsMouse
        ToolTip.delay: 400
        ToolTip.text: qsTr("Edit in a bigger box")
        MouseArea {
            id: boxExpandMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: chip.openTextEditor(boxArea.text)
        }
    }
}
