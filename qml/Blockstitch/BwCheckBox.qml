import QtQuick
import QtQuick.Controls

CheckBox {
    id: control
    implicitHeight: 28
    spacing: 8
    font.pixelSize: 12
    indicator: Rectangle {
        implicitWidth: 17; implicitHeight: 17
        x: control.leftPadding; y: Math.round((control.height-height)/2)
        radius: 4
        color: control.checked ? Theme.accent : Theme.field
        border.color: control.checked ? Theme.accentHover : (control.activeFocus ? Theme.accent : Theme.border)
        LucideIcon { anchors.centerIn: parent; width: 12; height: 12; name: "check"; color: "white"; strokeWidth: 2.6; visible: control.checked }
    }
    contentItem: Text {
        leftPadding: control.indicator.width + control.spacing
        text: control.text; font: control.font; color: Theme.textDim; opacity: control.enabled ? 1 : .45
        verticalAlignment: Text.AlignVCenter
    }
}
