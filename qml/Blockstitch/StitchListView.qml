import QtQuick
import QtQuick.Controls

ListView {
    id: control
    clip: true
    readonly property alias wheelHandler: wheel
    readonly property bool wheelScrolling: wheel.active || wheel.smooth.glidingX || wheel.smooth.glidingY || wheel.smooth.following
    ScrollBar.vertical: ScrollBar {}
    WheelPan { id: wheel; flickable: control }
}
