import QtQuick
import QtQuick.Layouts

// One edge of a docked window: a tab stack of panels that folds away and is
// resized by dragging its inner edge. The panels are its children, one per
// entry of `tabs` ({title, iconName}), in the same order.
Rectangle {
    id: root
    // "left", "right" or "bottom".
    property string edge: "bottom"
    property var tabs: []
    property int currentIndex: 0
    property bool open: true
    // Width (left, right) or height (bottom) while open.
    property real size: 200
    property real minSize: 120
    property real maxSize: 640
    // Drawn at the strip's trailing end, for the current panel's own tools.
    property Component trailing: null
    default property alias panels: stack.data
    // An open region with one tab may leave the strip to the panel's own header.
    property bool hideSingleTab: false
    readonly property bool stripShown: !(open && hideSingleTab && tabs.length <= 1)
    readonly property bool vertical: edge !== "bottom"
    readonly property real stripSize: vertical ? 34 : 30
    signal openRequested(bool open)
    signal resizeRequested(real size)
    signal tabRequested(int index)

    color: Theme.panel
    implicitWidth: vertical ? (open ? size : stripSize) : 0
    implicitHeight: vertical ? 0 : (open ? size : stripSize)

    // Clicking the open tab folds the region; any other tab opens it there.
    function pick(index) {
        if (index === root.currentIndex && root.open) root.openRequested(false);
        else { root.tabRequested(index); if (!root.open) root.openRequested(true); }
    }

    Rectangle {
        anchors.fill: parent; color: "transparent"; border.color: Theme.borderSoft
    }

    // A strip of tabs: along the top when open or along the bottom edge,
    // a rail of icons when a side region is folded.
    Item {
        id: strip
        visible: root.stripShown
        x: 0; y: 0
        width: root.vertical && !root.open ? root.stripSize : root.width
        height: root.vertical && !root.open ? root.height : root.stripSize
        Rectangle { visible: root.open; anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.borderSoft }
        Flow {
            id: tabFlow
            x: 4; y: root.vertical && !root.open ? 6 : 0
            width: parent.width - 8 - (trailingLoader.item ? trailingLoader.width + 4 : 0)
            height: parent.height
            flow: root.vertical && !root.open ? Flow.TopToBottom : Flow.LeftToRight
            spacing: 2
            Repeater {
                model: root.tabs
                delegate: Rectangle {
                    id: tab
                    required property var modelData
                    required property int index
                    readonly property bool current: root.open && root.currentIndex === index
                    readonly property bool rail: root.vertical && !root.open
                    objectName: "dock-tab-" + (modelData.title || index)
                    width: rail ? 26 : tabRow.implicitWidth + 18
                    height: rail ? 26 : root.stripSize
                    radius: rail ? 5 : 0
                    color: tabMouse.containsMouse && !current ? Theme.panelRaised : "transparent"
                    Row {
                        id: tabRow
                        anchors.centerIn: parent; spacing: 6
                        LucideIcon { name: tab.modelData.iconName || "square"; width: 14; height: 14; anchors.verticalCenter: parent.verticalCenter; color: tab.current ? Theme.text : Theme.textDim }
                        Text {
                            visible: !tab.rail
                            text: tab.modelData.title + (tab.modelData.badge ? "  " + tab.modelData.badge : "")
                            color: tab.current ? Theme.text : Theme.textDim; font.pixelSize: 12
                            font.weight: tab.current ? Font.DemiBold : Font.Normal
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    Rectangle { visible: tab.current; anchors.bottom: parent.bottom; width: parent.width; height: 2; color: Theme.accent }
                    MouseArea { id: tabMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.pick(tab.index) }
                }
            }
        }
        Loader {
            id: trailingLoader
            visible: root.open
            active: root.open && root.trailing !== null
            sourceComponent: root.trailing
            anchors.right: parent.right; anchors.rightMargin: 4
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    StackLayout {
        id: stack
        visible: root.open
        x: 1; y: root.stripShown ? root.stripSize : 1
        width: root.width - 2; height: root.height - y - (root.vertical ? 0 : 1)
        currentIndex: root.currentIndex
    }

    // The inner edge drags to resize.
    MouseArea {
        id: resizer
        visible: root.open
        hoverEnabled: true
        cursorShape: root.vertical ? Qt.SizeHorCursor : Qt.SizeVerCursor
        width: root.vertical ? 6 : root.width
        height: root.vertical ? root.height : 6
        x: root.edge === "left" ? root.width - 3 : (root.edge === "right" ? -3 : 0)
        y: root.vertical ? 0 : -3
        z: 10
        property real start: 0
        property real from: 0
        function along(mouse) { const p = mapToItem(null, mouse.x, mouse.y); return root.vertical ? p.x : p.y; }
        onPressed: mouse => { start = along(mouse); from = root.size; }
        onPositionChanged: mouse => {
            if (!pressed) return;
            const moved = along(mouse) - start;
            const next = root.edge === "left" ? from + moved : from - moved;
            root.resizeRequested(Math.max(root.minSize, Math.min(root.maxSize, next)));
        }
        Rectangle { anchors.centerIn: parent; width: root.vertical ? 2 : parent.width; height: root.vertical ? parent.height : 2; color: Theme.accent; visible: resizer.containsMouse || resizer.pressed }
    }
}
