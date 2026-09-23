import QtQuick
import QtQuick.Controls

Button {
    id: control
    property bool primary: false
    property bool danger: false
    property string iconName: ""
    property bool iconFilled: false
    property real radius: Theme.radius
    implicitHeight: 38
    implicitWidth: Math.max(40, contentRow.implicitWidth + 24)
    leftPadding: 12
    rightPadding: 12
    font.pixelSize: 13

    HoverHandler { cursorShape: control.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }

    contentItem: Item {
        Row {
            id: contentRow
            spacing: (control.iconName.length > 0 && control.text.length > 0) ? 8 : 0
            anchors.centerIn: parent
            LucideIcon { visible: control.iconName.length > 0; name: control.iconName; filled: control.iconFilled; color: control.danger ? Theme.danger : (control.flat ? Theme.textDim : Theme.text); width: 16; height: 16; anchors.verticalCenter: parent.verticalCenter }
            Text { id: label; visible: control.text.length > 0; text: control.text; color: control.danger ? Theme.danger : Theme.text; font: control.font; elide: Text.ElideRight; anchors.verticalCenter: parent.verticalCenter; verticalAlignment: Text.AlignVCenter }
        }
    }
    background: Rectangle {
        radius: control.radius
        color: control.down ? (control.primary ? "#087bd4" : "#292a2d")
                            : control.hovered ? (control.primary ? Theme.accentHover : "#3b3c40")
                                              : (control.primary ? Theme.accent : (control.flat ? "transparent" : Theme.panelRaised))
        border.color: control.flat && !control.hovered ? "transparent" : (control.danger ? Theme.danger : (control.primary ? "#50b2ff" : Theme.border))
        opacity: control.enabled ? 1 : 0.42
    }
}
