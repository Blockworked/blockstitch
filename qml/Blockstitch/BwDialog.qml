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

    Overlay.modal: Rectangle { color: "#a3101113" }
    background: Rectangle { radius: 12; color: Theme.panel; border.color: Theme.border }
    header: Item {
        visible: control.title.length > 0
        implicitHeight: visible ? 58 : 0
        Text { x: 22; anchors.verticalCenter: parent.verticalCenter; text: control.title; color: Theme.text; font.pixelSize: 16; font.weight: Font.Bold }
        BwButton {
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
        delegate: BwButton {
            primary: DialogButtonBox.buttonRole === DialogButtonBox.AcceptRole || DialogButtonBox.buttonRole === DialogButtonBox.YesRole
        }
    }
}
