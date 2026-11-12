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
                ? qsTr("Starting values for new blocks added from the sidebar (existing blocks keep their values), dropdown choices, settings buttons and text boxes.")
                : qsTr("Which inputs get a text box of their own, for text with several lines.")
            wrapMode: Text.WordWrap
            color: Theme.textDim
        }
        StitchScrollView {
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
                        required property string pieceJson
                        readonly property var saved: pieceJson ? JSON.parse(pieceJson) : ({})
                        readonly property var ui: saved.ui || ({})
                        // With no default, a multi-line input starts as empty text.
                        readonly property string kind: defaultKind || (valueType === "Bool" ? "Bool" : multiline ? "Text" : "Number")
                        readonly property string value: defaultKind ? defaultText : (valueType === "Bool" ? "false" : multiline ? "" : "0")
                        objectName: "defaultParameterRow" + index
                        visible: pieceKind === "Input" || pieceKind === "Button"
                        Layout.fillWidth: true
                        spacing: 6
                        Label { textFormat: Text.PlainText; text: defaultRow.pieceName; color: Theme.text; font.bold: true }
                        StitchCheckBox {
                            objectName: "multilineInput"
                            visible: defaultRow.pieceKind === "Input" && defaultRow.valueType !== "Bool" && !(defaultRow.ui.choices || []).length
                            text: qsTr("Multi-line text box under the block")
                            checked: defaultRow.multiline
                            onToggled: editor.pieceModel.setProperty(defaultRow.index, "multiline", checked)
                        }
                        ColumnLayout {
                            visible: defaultRow.pieceKind === "Input" && defaultRow.valueType !== "Bool"
                            Layout.fillWidth: true
                            Label { text: qsTr("Dropdown choices (one per line; label | value)"); color: Theme.textDim; wrapMode: Text.WordWrap; Layout.fillWidth: true }
                            TextArea {
                                objectName: "inputChoices"
                                Layout.fillWidth: true
                                Layout.preferredHeight: 90
                                Component.onCompleted: text = (defaultRow.ui.choices || []).map(c => c.label === c.value ? c.label : c.label + " | " + c.value).join("\n")
                                color: Theme.text
                                wrapMode: TextEdit.Wrap
                                selectByMouse: true
                                background: Rectangle { color: Theme.field; border.color: Theme.border; radius: 6 }
                                onTextChanged: if (activeFocus) editor.setChoices(defaultRow.index, text)
                            }
                        }
                        StitchCheckBox {
                            objectName: "screenOnlyInput"
                            visible: defaultRow.pieceKind === "Input"
                            text: qsTr("Show only in a settings screen")
                            checked: !!defaultRow.ui.screen_only
                            onToggled: editor.updatePieceUi(defaultRow.index, {screen_only: checked})
                        }
                        ColumnLayout {
                            visible: defaultRow.pieceKind === "Button"
                            Layout.fillWidth: true
                            StitchTextField {
                                objectName: "settingsScreenTitle"
                                Layout.fillWidth: true
                                placeholderText: qsTr("Screen title")
                                text: defaultRow.saved.title || defaultRow.pieceName
                                onTextEdited: editor.updateButton(defaultRow.index, {title: text})
                            }
                            Label { text: qsTr("Inputs on this screen"); color: Theme.textDim }
                            Repeater {
                                model: editor.screenInputChoices()
                                delegate: StitchCheckBox {
                                    required property var modelData
                                    text: modelData.label
                                    checked: (defaultRow.saved.inputs || []).includes(modelData.id)
                                    onToggled: {
                                        let selected = (defaultRow.saved.inputs || []).filter(id => id !== modelData.id);
                                        if (checked) selected.push(modelData.id);
                                        editor.updateButton(defaultRow.index, {inputs: selected});
                                    }
                                }
                            }
                        }
                        StitchComboBox {
                            objectName: "defaultChoiceValue"
                            visible: defaultRow.pieceKind === "Input" && editor.allowDefaults && (defaultRow.ui.choices || []).length > 0
                            Layout.fillWidth: true
                            model: defaultRow.ui.choices || []
                            textRole: "label"
                            currentIndex: model.findIndex(c => c.value === defaultRow.defaultText)
                            onActivated: index => editor.setInputDefault(defaultRow.index, "Text", model[index].value)
                        }
                        RowLayout {
                            visible: defaultRow.pieceKind === "Input" && editor.allowDefaults && !(defaultRow.ui.choices || []).length
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
                        StitchScrollView {
                            visible: defaultRow.pieceKind === "Input" && editor.allowDefaults && !(defaultRow.ui.choices || []).length && defaultRow.kind === "Text"
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
                            visible: defaultRow.pieceKind === "Input" && editor.allowDefaults && defaultRow.kind === "Number" && (!defaultRow.value.trim().length || !isFinite(Number(defaultRow.value)))
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
