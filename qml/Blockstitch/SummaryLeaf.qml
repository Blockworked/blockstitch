import QtQuick
import QtQuick.Controls

// Text with line breaks: its first line and how many follow. A click opens the bigger editor. A leaf of ValueChip.
Rectangle {
    required property Item chip
    id: summaryLeaf
    objectName: "multilineSummary"
    implicitHeight: 27
    implicitWidth: summaryRow.implicitWidth + 16
    radius: 5
    color: chip.flatLeaf ? "transparent" : (summaryHover.hovered && chip.editable ? Theme.hover : Theme.field)
    border.color: chip.flatLeaf ? "transparent" : (summaryHover.hovered && chip.editable ? Theme.accent : Theme.border)
    Row {
        id: summaryRow
        anchors.centerIn: parent
        spacing: 6
        Text {
            text: chip.leafText.split("\n")[0]
            color: Theme.text
            font.pixelSize: Theme.blockText
            width: Math.min(implicitWidth, 260)
            elide: Text.ElideRight
            anchors.verticalCenter: parent.verticalCenter
        }
        Rectangle {
            objectName: "multilineBadge"
            anchors.verticalCenter: parent.verticalCenter
            implicitWidth: badgeText.implicitWidth + 10
            implicitHeight: 17
            radius: 8.5
            color: Theme.panelRaised
            border.color: Theme.border
            Text {
                id: badgeText
                anchors.centerIn: parent
                text: chip.leafLines === 2 ? qsTr("+1 line") : qsTr("+%1 lines").arg(chip.leafLines - 1)
                color: Theme.textDim
                font.pixelSize: 10
            }
        }
    }
    HoverHandler {
        id: summaryHover
        enabled: chip.editable
        cursorShape: Qt.PointingHandCursor
    }
    TapHandler {
        enabled: chip.editable
        onTapped: chip.openTextEditor(chip.leafText)
    }
    ToolTip.visible: summaryHover.hovered
    ToolTip.delay: 500
    ToolTip.text: chip.leafText
    Accessible.role: Accessible.Button
    Accessible.name: qsTr("Text, %1 lines. Click to edit.").arg(chip.leafLines)
}
