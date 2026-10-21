import QtQuick
import QtQuick.Controls

// A popup for picking a time of day: tap an hour and a minute, or nudge
// either with the arrows or the mouse wheel. Opens under the item it's
// given and reports the choice with `picked`; Escape or a click outside
// leaves the time as it was.
Popup {
    id: control
    property int hour: 9
    property int minute: 0
    property string title: qsTr("Time")
    signal picked(int hour, int minute)

    function pad(n) { return String(n).padStart(2, "0"); }
    // Opens below `item` (above it when there's no room), with the time set.
    function openAt(item, h, m) {
        hour = Math.max(0, Math.min(23, h | 0)); minute = Math.max(0, Math.min(59, m | 0));
        const host = parent || Overlay.overlay;
        const p = item.mapToItem(host, 0, 0);
        const below = p.y + item.height + 6;
        x = Math.max(8, Math.min(p.x, host.width - implicitWidth - 8));
        y = below + implicitHeight + 8 <= host.height ? below : Math.max(8, p.y - implicitHeight - 6);
        transformOrigin = below + implicitHeight + 8 <= host.height ? Popup.TopLeft : Popup.BottomLeft;
        open();
    }
    function step(part, by) {
        if (part === "hour") hour = (hour + by + 24) % 24;
        else minute = (minute + by + 60) % 60;
    }
    function accept() { picked(hour, minute); close(); }

    parent: Overlay.overlay
    modal: false; focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    padding: 14
    topInset: 0; bottomInset: 0; leftInset: 0; rightInset: 0
    background: Rectangle { radius: 10; color: Theme.panelRaised; border.color: Theme.border }
    enter: Transition {
        enabled: Motion.enabled
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Motion.normal; easing.type: Easing.OutCubic }
            NumberAnimation { property: "scale"; from: 0.92; to: 1; duration: Motion.normal; easing.type: Easing.OutCubic }
        }
    }
    exit: Transition {
        enabled: Motion.enabled
        NumberAnimation { property: "opacity"; from: 1; to: 0; duration: Motion.quick; easing.type: Easing.InCubic }
    }

    contentItem: Column {
        spacing: 12
        Keys.onReturnPressed: control.accept()
        Keys.onEnterPressed: control.accept()

        // The time as it stands, each half with its own arrows.
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 6
            Repeater {
                model: ["hour", "minute"]
                delegate: Row {
                    id: part
                    required property string modelData
                    required property int index
                    spacing: 6
                    Text {
                        visible: part.index > 0; text: ":"; color: Theme.textDim
                        font.pixelSize: 30; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter
                    }
                    Rectangle {
                        width: 64; height: 52; radius: 8
                        color: Theme.field; border.color: partWheel.hovered ? Theme.accent : Theme.border
                        Behavior on border.color { enabled: Motion.enabled; ColorAnimation { duration: Motion.quick } }
                        Text {
                            anchors.centerIn: parent
                            text: control.pad(part.modelData === "hour" ? control.hour : control.minute)
                            color: Theme.text; font.pixelSize: 30; font.weight: Font.DemiBold
                        }
                        HoverHandler { id: partWheel }
                        WheelHandler {
                            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                            property real rest: 0
                            onWheel: event => {
                                rest += event.angleDelta.y / 120;
                                const notches = rest > 0 ? Math.floor(rest) : Math.ceil(rest);
                                if (notches !== 0) { control.step(part.modelData, notches); rest -= notches; }
                            }
                        }
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4
                        Repeater {
                            model: [{ icon: "chevron-up", by: 1 }, { icon: "chevron-down", by: -1 }]
                            delegate: Rectangle {
                                required property var modelData
                                width: 24; height: 24; radius: 5
                                color: nudge.pressed ? Theme.field : nudge.containsMouse ? "#3b3c40" : "transparent"
                                Behavior on color { enabled: Motion.enabled; ColorAnimation { duration: Motion.quick } }
                                LucideIcon { anchors.centerIn: parent; name: modelData.icon; width: 15; height: 15; color: Theme.textDim }
                                MouseArea {
                                    id: nudge
                                    anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                    onClicked: control.step(part.modelData, modelData.by)
                                    // Held down, it keeps counting.
                                    onPressAndHold: repeatTimer.start()
                                    onReleased: repeatTimer.stop()
                                    onCanceled: repeatTimer.stop()
                                    Timer { id: repeatTimer; interval: 70; repeat: true; onTriggered: control.step(part.modelData, modelData.by) }
                                }
                                Accessible.role: Accessible.Button
                                Accessible.name: (modelData.by > 0 ? qsTr("Later") : qsTr("Earlier")) + " " + (part.modelData === "hour" ? qsTr("hour") : qsTr("minute"))
                            }
                        }
                    }
                }
            }
        }

        Text { text: qsTr("Hour"); color: Theme.textDim; font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 0.5 }
        ChoiceGrid {
            values: Array.from({ length: 24 }, (_, i) => i)
            current: control.hour
            onChosen: v => control.hour = v
        }
        Text { text: qsTr("Minute"); color: Theme.textDim; font.pixelSize: 11; font.weight: Font.DemiBold; font.letterSpacing: 0.5 }
        ChoiceGrid {
            values: Array.from({ length: 12 }, (_, i) => i * 5)
            current: control.minute
            onChosen: v => control.minute = v
        }

        Row {
            width: parent.width
            spacing: 8
            BwButton { id: nowButton; text: qsTr("Now"); flat: true; implicitHeight: 32; onClicked: { const d = new Date(); control.hour = d.getHours(); control.minute = d.getMinutes(); } }
            Item { width: parent.width - nowButton.width - cancelButton.width - setButton.width - 3 * parent.spacing; height: 1 }
            BwButton { id: cancelButton; text: qsTr("Cancel"); implicitHeight: 32; onClicked: control.close() }
            BwButton { id: setButton; text: qsTr("Set"); primary: true; implicitHeight: 32; onClicked: control.accept() }
        }
    }

    // Six to a row; the chosen cell's highlight glides to the next choice.
    component ChoiceGrid: Item {
        id: grid
        property var values: []
        property int current: -1
        signal chosen(int value)
        readonly property int columns: 6
        readonly property real cell: 38
        readonly property real gap: 4
        readonly property int chosenIndex: values.indexOf(current)
        width: columns * cell + (columns - 1) * gap
        height: Math.ceil(values.length / columns) * (30 + gap) - gap
        Rectangle {
            visible: grid.chosenIndex >= 0
            width: grid.cell; height: 30; radius: 6; color: Theme.accent
            x: (Math.max(0, grid.chosenIndex) % grid.columns) * (grid.cell + grid.gap)
            y: Math.floor(Math.max(0, grid.chosenIndex) / grid.columns) * (30 + grid.gap)
            Behavior on x { enabled: Motion.enabled; NumberAnimation { duration: Motion.normal; easing.type: Easing.OutCubic } }
            Behavior on y { enabled: Motion.enabled; NumberAnimation { duration: Motion.normal; easing.type: Easing.OutCubic } }
        }
        Repeater {
            model: grid.values
            delegate: Rectangle {
                required property int modelData
                required property int index
                readonly property bool isChosen: index === grid.chosenIndex
                x: (index % grid.columns) * (grid.cell + grid.gap)
                y: Math.floor(index / grid.columns) * (30 + grid.gap)
                width: grid.cell; height: 30; radius: 6
                color: isChosen ? "transparent" : cellMouse.containsMouse ? "#3b3c40" : Theme.field
                Behavior on color { enabled: Motion.enabled; ColorAnimation { duration: Motion.quick } }
                Text {
                    anchors.centerIn: parent; text: control.pad(modelData)
                    color: isChosen ? "white" : Theme.text; font.pixelSize: 13
                    font.weight: isChosen ? Font.DemiBold : Font.Normal
                }
                MouseArea { id: cellMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: grid.chosen(modelData) }
            }
        }
    }
}
