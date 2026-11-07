import QtQuick
import QtQuick.Controls

// A key slot drawn as keycaps; a click asks the host to record a key. A leaf of ValueChip.
Item {
    required property Item chip
    id: keycaps
    readonly property var parts: chip.keyParts(chip.valueData && chip.valueData.value !== undefined ? chip.valueData.value : "")
    readonly property bool showHint: chip.keyCapturing || parts.length === 0
    implicitHeight: 30
    implicitWidth: showHint ? Math.max(36, hint.implicitWidth + 24) : Math.max(36, capRow.implicitWidth + 24)
    Rectangle {
        anchors.fill: parent
        radius: 5
        color: chip.keyCapturing ? Theme.accent : (capHover.hovered ? Theme.hover : Theme.field)
        border.color: chip.keyCapturing ? Theme.accentHover : Theme.border
    }
    Text {
        id: hint
        anchors.centerIn: parent
        font.pixelSize: Theme.blockText
        visible: keycaps.showHint
        text: chip.keyCapturing ? qsTr("Press keys...") : qsTr("Click to set key")
        color: chip.keyCapturing ? "white" : Theme.text
    }
    Row {
        id: capRow
        spacing: 4
        visible: !keycaps.showHint
        anchors.centerIn: parent
        Repeater {
            model: keycaps.parts
            delegate: Row {
                id: capPart
                required property var modelData
                required property int index
                spacing: 4
                anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                Text {
                    visible: capPart.index > 0
                    text: "+"
                    color: Theme.text
                    font.pixelSize: Theme.blockText - 1
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: chip.keyPartLabel(capPart.modelData)
                    color: Theme.text
                    font.pixelSize: Theme.blockText
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }
    HoverHandler {
        id: capHover
        enabled: chip.editable
        cursorShape: Qt.PointingHandCursor
    }
    // Hold the press so dragging a key input cannot pan a surrounding view.
    MouseArea {
        anchors.fill: parent
        enabled: chip.editable
        acceptedButtons: Qt.LeftButton
        preventStealing: true
        cursorShape: Qt.PointingHandCursor
        TapHandler {
            onTapped: chip.keyCaptureRequested()
        }
    }
    ToolTip.visible: capHover.hovered && !chip.keyCapturing
    ToolTip.delay: 500
    ToolTip.text: qsTr("Click to set key, or drop a variable here")
}
