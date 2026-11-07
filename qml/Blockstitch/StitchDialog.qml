import QtQuick
import QtQuick.Controls

// Themed modal dialog. Every part (header, footer, backdrop) is drawn from
// Theme so the dialog looks the same regardless of the system light/dark palette.
Dialog {
    id: control
    property bool showClose: true
    parent: Overlay.overlay
    anchors.centerIn: parent
    modal: true
    padding: 22
    topInset: 0; bottomInset: 0; leftInset: 0; rightInset: 0
    topPadding: 4
    bottomPadding: footer && footer.visible ? 6 : 22

    // The popup fades this dimmer in and out with its enter/exit transitions.
    Overlay.modal: Rectangle {
        color: "#a3101113"
        Behavior on opacity { enabled: Motion.enabled; NumberAnimation { duration: Motion.slow } }
    }
    enter: Transition {
        enabled: Motion.enabled
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Motion.slow; easing.type: Easing.OutCubic }
            NumberAnimation { property: "scale"; from: 0.94; to: 1; duration: Motion.slow; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
        }
    }
    exit: Transition {
        enabled: Motion.enabled
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Motion.normal; easing.type: Easing.InCubic }
            NumberAnimation { property: "scale"; from: 1; to: 0.96; duration: Motion.normal; easing.type: Easing.InCubic }
        }
    }
    background: Rectangle { radius: 12; color: Theme.panel; border.color: Theme.border }
    header: Item {
        visible: control.title.length > 0
        implicitHeight: visible ? Math.max(58, heading.implicitHeight + 28) : 0
        Text {
            id: heading
            x: 22; width: Math.max(0, parent.width - 44 - (control.showClose ? 38 : 0))
            anchors.verticalCenter: parent.verticalCenter
            text: control.title; textFormat: Text.PlainText
            color: Theme.text; font.pixelSize: 16; font.weight: Font.Bold
            wrapMode: Text.WordWrap
        }
        StitchButton {
            visible: control.showClose
            anchors.right: parent.right; anchors.rightMargin: 14; anchors.verticalCenter: parent.verticalCenter
            iconName: "x"; text: ""; flat: true; radius: 15; implicitWidth: 30; implicitHeight: 30
            onClicked: control.reject()
        }
    }
    footer: DialogButtonBox {
        visible: count > 0
        alignment: Qt.AlignRight
        spacing: 8
        padding: 18; topPadding: 8
        background: null
        delegate: StitchButton {
            primary: DialogButtonBox.buttonRole === DialogButtonBox.AcceptRole || DialogButtonBox.buttonRole === DialogButtonBox.YesRole
        }
    }
}
