import QtQuick
import QtQuick.Controls

// General-purpose scroll area. Content keeps Qt's normal ScrollView sizing.
ScrollView {
    id: control
    clip: true
    readonly property alias wheelHandler: wheel
    WheelPan { id: wheel; flickable: control.contentItem }
}
