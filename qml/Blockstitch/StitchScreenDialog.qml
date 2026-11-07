import QtQuick
import QtQuick.Controls

// A bounded form dialog. StitchDialog keeps its title and actions outside the scroll area.
StitchDialog {
    id: control
    default property alias content: page.content
    property alias description: page.description
    property alias contentSpacing: page.contentSpacing
    readonly property alias scrollView: page.scrollView
    property real preferredWidth: 560
    property real windowMargin: 16
    width: Math.max(0, Math.min(preferredWidth, parent ? parent.width - windowMargin * 2 : preferredWidth))
    height: Math.max(0, Math.min(implicitHeight, parent ? parent.height - windowMargin * 2 : implicitHeight))
    contentItem: StitchPage {
        id: page
        padding: 0
        background: null
    }
}
