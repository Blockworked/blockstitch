import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// BlockDefinitionEditor's Inputs dialog: each input's starting value (when
// the host allows defaults) and whether it gets a multi-line text box.
Popup {
    id: defaultsPopup
    required property Item editor
    objectName: "defaultParametersPopup"
    parent: Overlay.overlay
    anchors.centerIn: parent
    width: Math.min(560, parent.width - 48)
    height: Math.min(560, parent.height - 48)
    padding: 20
    modal: true
    focus: true
    background: Rectangle { radius: Theme.radius; color: Theme.panel; border.color: Theme.border }
    contentItem: ColumnLayout {
        spacing: 12
        Label { text: qsTr("Inputs"); color: Theme.text; font.bold: true; font.pixelSize: 20 }
        Label {
            Layout.fillWidth: true
            text: editor.allowDefaults
                ? qsTr("Starting values for new blocks added from the sidebar (existing blocks keep their values), and which inputs get a text box of their own.")
                : qsTr("Which inputs get a text box of their own, for text with several lines.")
            wrapMode: Text.WordWrap
            color: Theme.textDim
        }
        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: availableWidth
            ColumnLayout {
                width: parent.width
                spacing: 14
                Label {
                    Layout.fillWidth: true
                    visible: !editor.resultPieces().some(p => p.kind === "Input")
                    text: qsTr("Add an input to the block to set its options.")
                    wrapMode: Text.WordWrap
                    color: Theme.textDim
                }
                Repeater {
                    objectName: "defaultParameterRows"
                    model: editor.pieceModel
                    delegate: ColumnLayout {
                        id: defaultRow
                        required property int index
                        required property string pieceKind
                        required property string pieceName
                        required property string valueType
                        required property string defaultKind
                        required property string defaultText
                        required property bool multiline
                        // With no default, a multi-line input starts as empty text.
                        readonly property string kind: defaultKind || (valueType === "Bool" ? "Bool" : multiline ? "Text" : "Number")
                        readonly property string value: defaultKind ? defaultText : (valueType === "Bool" ? "false" : multiline ? "" : "0")
                        objectName: "defaultParameterRow" + index
                        visible: pieceKind === "Input"
                        Layout.fillWidth: true
                        spacing: 6
                        Label { text: defaultRow.pieceName; color: Theme.text; font.bold: true }
                        StitchCheckBox {
                            objectName: "multilineInput"
                            visible: defaultRow.valueType !== "Bool"
                            text: qsTr("Multi-line text box under the block")
                            checked: defaultRow.multiline
                            onToggled: editor.pieceModel.setProperty(defaultRow.index, "multiline", checked)
                        }
                        RowLayout {
                            visible: editor.allowDefaults
                            Layout.fillWidth: true
                            StitchComboBox {
                                objectName: "defaultParameterType"
                                visible: defaultRow.valueType !== "Bool"
                                model: [qsTr("Number"), qsTr("Text")]
                                currentIndex: defaultRow.kind === "Text" ? 1 : 0
                                onActivated: editor.setInputDefault(defaultRow.index, currentIndex === 1 ? "Text" : "Number", currentIndex === 1 ? "" : "0")
                            }
                            StitchTextField {
                                objectName: "defaultNumberValue"
                                visible: defaultRow.kind === "Number"
                                Layout.fillWidth: true
                                text: defaultRow.value
                                onTextEdited: editor.setInputDefault(defaultRow.index, "Number", text)
                            }
                            StitchCheckBox {
                                objectName: "defaultBooleanValue"
                                visible: defaultRow.valueType === "Bool"
                                text: checked ? qsTr("True") : qsTr("False")
                                checked: defaultRow.value === "true"
                                onToggled: editor.setInputDefault(defaultRow.index, "Bool", checked)
                            }
                        }
                        ScrollView {
                            visible: editor.allowDefaults && defaultRow.kind === "Text"
                            Layout.fillWidth: true
                            Layout.preferredHeight: 80
                            contentWidth: availableWidth
                            TextArea {
                                objectName: "defaultTextValue"
                                text: defaultRow.value
                                color: Theme.text
                                wrapMode: TextEdit.Wrap
                                selectByMouse: true
                                background: Rectangle { color: Theme.field; radius: 6; border.color: Theme.border }
                                onTextChanged: {
                                    if (activeFocus)
                                        editor.setInputDefault(defaultRow.index, "Text", text);
                                }
                            }
                        }
                        Label {
                            visible: editor.allowDefaults && defaultRow.kind === "Number" && (!defaultRow.value.trim().length || !isFinite(Number(defaultRow.value)))
                            text: qsTr("Enter a finite number")
                            color: Theme.danger
                        }
                    }
                }
            }
        }
        StitchButton {
            Layout.alignment: Qt.AlignRight
            text: qsTr("Done")
            onClicked: { if (editor.defaultsValid()) defaultsPopup.close(); }
        }
    }
}
