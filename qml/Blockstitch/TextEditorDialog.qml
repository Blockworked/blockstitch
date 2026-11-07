import QtQuick
import QtQuick.Controls

// A bigger editor for a text slot, for text with line breaks. Enter adds a
// line; Ctrl+Enter or Done saves, through `textAccepted`.
StitchDialog {
    id: root
    property string text: ""
    property bool monospace: false
    signal textAccepted(string text)
    title: qsTr("Edit text")
    width: Math.min(parent ? parent.width - 48 : 640, 640)
    standardButtons: Dialog.Cancel | Dialog.Ok
    Component.onCompleted: {
        const ok = standardButton(Dialog.Ok);
        if (ok) ok.text = qsTr("Done");
    }
    onOpened: { area.text = root.text; area.cursorPosition = area.length; area.forceActiveFocus(); }
    onAccepted: root.textAccepted(area.text)

    contentItem: Column {
        spacing: 8
        Rectangle {
            width: parent.width
            height: Math.min(360, Math.max(140, area.contentHeight + 20))
            radius: 6
            color: Theme.field
            border.color: area.activeFocus ? Theme.accent : Theme.border
            StitchScrollView {
                id: scroll
                anchors.fill: parent; anchors.margins: 1
                clip: true
                TextArea {
                    id: area
                    objectName: "textEditorArea"
                    color: Theme.text; selectionColor: Theme.accent; selectByMouse: true
                    font.pixelSize: 13; font.family: root.monospace ? "monospace" : font.family
                    wrapMode: root.monospace ? TextEdit.NoWrap : TextEdit.Wrap
                    padding: 9; background: null
                    Keys.onPressed: event => {
                        if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && (event.modifiers & Qt.ControlModifier)) {
                            event.accepted = true;
                            root.accept();
                        }
                    }
                }
            }
        }
        Text {
            text: qsTr("Enter adds a line. Ctrl+Enter saves.")
            color: Theme.textDim; font.pixelSize: 11
        }
    }
}
