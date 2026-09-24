import QtQuick
import QtQuick.Controls

Button {
    id: control
    property bool primary: false
    property bool danger: false
    property string iconName: ""
    property bool iconFilled: false
    // Raster image (e.g. an application icon as a data: URI) shown to the
    // left of the label, mirroring the web frontend's <img> inside its
    // chooser buttons. Takes precedence over the LucideIcon glyph.
    property url iconSource: ""
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
            readonly property bool hasGlyph: control.iconName.length > 0 && control.iconSource.toString().length === 0
            readonly property bool hasImage: control.iconSource.toString().length > 0
            spacing: ((hasGlyph || hasImage) && control.text.length > 0) ? 8 : 0
            anchors.centerIn: parent
            Image { visible: contentRow.hasImage; source: control.iconSource; width: 16; height: 16; fillMode: Image.PreserveAspectFit; smooth: true; mipmap: true; anchors.verticalCenter: parent.verticalCenter }
            LucideIcon { visible: contentRow.hasGlyph; name: control.iconName; filled: control.iconFilled; color: control.danger ? Theme.danger : (control.flat ? Theme.textDim : Theme.text); width: 16; height: 16; anchors.verticalCenter: parent.verticalCenter }
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
