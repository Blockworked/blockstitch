import QtQuick
import QtQuick.Controls

MenuItem {
    id: control
    property string iconName: ""
    property bool danger: false
    // Keys shown at the right edge, e.g. "Ctrl+S".
    property string shortcutText: ""
    implicitWidth: Math.max(210, label.implicitWidth + keys.implicitWidth + leftPadding + rightPadding + 28)
    implicitHeight: 34
    height: visible ? implicitHeight : 0
    leftPadding: 10; rightPadding: 12
    HoverHandler { cursorShape: Qt.PointingHandCursor }
    contentItem: Item {
        opacity: control.enabled ? 1 : 0.45
        Row {
            id: label
            anchors.verticalCenter: parent.verticalCenter
            spacing: 9
            LucideIcon { name: control.iconName; visible: control.iconName.length>0; width: 15; height: 15; color: control.danger?Theme.danger:Theme.textDim; anchors.verticalCenter: parent.verticalCenter }
            Text { text: control.text; color: control.danger?Theme.danger:Theme.text; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter; verticalAlignment: Text.AlignVCenter }
        }
        Text {
            id: keys
            anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
            text: control.shortcutText; visible: text.length > 0
            color: Theme.textDim; font.pixelSize: 11
        }
    }
    background: Rectangle {
        radius: 5; color: control.highlighted ? Theme.hover : "transparent"
        Behavior on color { enabled: Motion.enabled; ColorAnimation { duration: Motion.quick } }
    }
}
