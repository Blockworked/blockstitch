import QtQuick
import QtQuick.Controls

// A text slot with fixed choices: a dropdown. A leaf of ValueChip.
StitchComboBox {
    required property Item chip
    id: leafBox
    readonly property var choices: chip.leafOptions || []
    readonly property string current: chip.valueData ? String(chip.valueData.value || "") : ""
    readonly property int chosen: choices.findIndex(c => c.value === current)
    model: choices
    textRole: "label"
    currentIndex: chosen
    displayText: chosen >= 0 ? choices[chosen].label : (current || chip.leafPlaceholder)
    implicitWidth: Math.min(190, Math.max(56, leafMetrics.advanceWidth + 36))
    implicitHeight: 28
    font.pixelSize: Theme.blockText
    leftPadding: 8
    rightPadding: 26
    enabled: chip.editable
    TextMetrics {
        id: leafMetrics
        font: leafBox.font
        text: leafBox.displayText
    }
    onActivated: index => {
        const choice = choices[index];
        const select = v => chip.emitLeaf([], {
                kind: "Text",
                value: v
            }, v);
        if (choice.action)
            choice.action(select, chip.location);
        else
            select(choice.value);
    }
}
