import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// A draft form over ordinary block values. Cancel never writes to the canvas.
StitchDialog {
    id: root
    objectName: "blockSettingsDialog"
    required property var fields
    required property var values
    property var changes: ({})
    property var blockDefinitions: []
    property string errorText: ""
    property var invalidFields: ({})
    readonly property bool valid: !Object.values(invalidFields).some(v => v)
    function validateNumber(id, invalid) { invalidFields = Object.assign({}, invalidFields, {[id]: invalid}); }
    signal applyRequested(var changes)
    width: Math.min(540, parent ? parent.width - 32 : 540)
    height: Math.min(600, parent ? parent.height - 32 : 600)
    standardButtons: Dialog.NoButton
    function setValue(id, value) {
        const next = Object.assign({}, changes);
        if (JSON.stringify(value) === JSON.stringify(values[id])) delete next[id];
        else next[id] = value;
        changes = next;
        errorText = "";
    }
    function setLeaf(id, path, leaf) {
        if (!path.length) { setValue(id, leaf); return; }
        const value = JSON.parse(JSON.stringify(current(id)));
        let parent = value;
        for (let i = 0; i < path.length - 1; ++i) parent = parent.args[path[i]];
        parent.args[path[path.length - 1]] = leaf;
        setValue(id, value);
    }
    function current(id) { return changes.hasOwnProperty(id) ? changes[id] : values[id]; }
    contentItem: ColumnLayout {
        spacing: 12
        StitchScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: availableWidth
            clip: true
            ColumnLayout {
                width: parent.width
                spacing: 14
                Repeater {
                    model: root.fields
                    delegate: ColumnLayout {
                        id: field
                        required property var modelData
                        readonly property var value: root.current(modelData.id)
                        readonly property bool expression: !!value && value.kind !== "Number" && value.kind !== "Text" && value.kind !== "Bool" && !(value.kind === "Op" && (value.op === "True" || value.op === "False"))
                        Layout.fillWidth: true
                        spacing: 5
                        Label { text: field.modelData.label; textFormat: Text.PlainText; color: Theme.text }
                        Label {
                            visible: field.expression
                            Layout.fillWidth: true
                            text: qsTr("Reporter inputs")
                            color: Theme.textDim
                            wrapMode: Text.WordWrap
                        }
                        ValueChip {
                            objectName: "blockSettingsReporter"
                            visible: field.expression
                            valueData: field.expression ? field.value : null
                            forceBoolean: !!field.modelData.bool
                            blockDefinitions: root.blockDefinitions
                            onLeafEdited: (path, leaf) => root.setLeaf(field.modelData.id, path, leaf)
                        }
                        StitchCheckBox {
                            objectName: "blockSettingsBoolean"
                            visible: !!field.modelData.bool && !field.expression
                            text: qsTr("Enabled")
                            checked: BlockRegistry.componentEnabled(field.value)
                            onToggled: root.setValue(field.modelData.id, BlockRegistry.componentValue(checked))
                        }
                        StitchComboBox {
                            objectName: "blockSettingsChoice"
                            visible: !field.modelData.bool && (field.modelData.choices || []).length > 0 && !field.expression
                            Layout.fillWidth: true
                            model: field.modelData.choices || []
                            textRole: "label"
                            currentIndex: model.findIndex(c => field.value && c.value === field.value.value)
                            onActivated: index => root.setValue(field.modelData.id, {kind: "Text", value: model[index].value})
                        }
                        StitchTextField {
                            objectName: "blockSettingsText"
                            visible: !field.modelData.bool && !(field.modelData.choices || []).length && !field.modelData.multiline && !field.expression
                            Layout.fillWidth: true
                            text: root.values[field.modelData.id] && root.values[field.modelData.id].value !== undefined ? String(root.values[field.modelData.id].value) : ""
                            onTextEdited: {
                                const numeric = field.value && field.value.kind === "Number";
                                if (numeric && (!text.trim().length || !isFinite(Number(text)))) {
                                    root.validateNumber(field.modelData.id, true);
                                    return;
                                }
                                root.validateNumber(field.modelData.id, false);
                                root.setValue(field.modelData.id, {kind: numeric ? "Number" : "Text", value: numeric ? Number(text) : text});
                            }
                        }
                        TextArea {
                            objectName: "blockSettingsMultiline"
                            visible: !!field.modelData.multiline && !field.expression
                            Layout.fillWidth: true
                            Layout.preferredHeight: 110
                            text: field.value && field.value.value !== undefined ? String(field.value.value) : ""
                            color: Theme.text
                            wrapMode: TextEdit.Wrap
                            selectByMouse: true
                            background: Rectangle { color: Theme.field; radius: 6; border.color: Theme.border }
                            onTextChanged: if (activeFocus) root.setValue(field.modelData.id, {kind: "Text", value: text})
                        }
                    }
                }
            }
        }
        Label { Layout.fillWidth: true; visible: text.length > 0; text: !root.valid ? qsTr("Enter a finite number") : root.errorText; color: Theme.danger; wrapMode: Text.WordWrap }
        RowLayout {
            Layout.alignment: Qt.AlignRight
            StitchButton { text: qsTr("Cancel"); onClicked: root.reject() }
            StitchButton { objectName: "applyBlockSettings"; text: qsTr("Apply"); primary: true; enabled: root.valid; onClicked: root.applyRequested(root.changes) }
        }
    }
}
