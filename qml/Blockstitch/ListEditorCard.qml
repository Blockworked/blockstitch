import QtQuick
import QtQuick.Controls
import QtQuick.Shapes

// A list's floating editor card on the canvas: its items, editable in place,
// moved by its title bar. BlockCanvas makes one per open list editor.
Rectangle {
    id: listCard
    required property Item canvas
    // The layer the card floats in; it stays inside it.
    required property Item overlay
    required property string editorName
    required property string payload
    required property real editorX
    required property real editorY
    readonly property var modelData: JSON.parse(payload)
    objectName: "listEditor_" + modelData.name
    readonly property real maxX: Math.max(0, overlay.width - width)
    readonly property real maxY: Math.max(0, overlay.height - height)
    visible: !!modelData.editor_visible
    x: Math.max(0, Math.min(editorX, maxX))
    y: Math.max(0, Math.min(editorY, maxY))
    z: 12
    function keepInView() {
        if (x < 0 || x > maxX)
            x = Math.max(0, Math.min(x, maxX));
        if (y < 0 || y > maxY)
            y = Math.max(0, Math.min(y, maxY));
    }
    onMaxXChanged: keepInView()
    onMaxYChanged: keepInView()
    width: 300
    height: Math.min(400, 90 + Math.max(64, (modelData.items || []).length * 40 + 14))
    radius: 12
    color: Theme.panel
    border.color: Theme.borderSoft
    clip: true
    function itemFromText(value) {
        const trimmed = value.trim();
        const number = Number(value);
        return trimmed.length && Number.isFinite(number) ? {
            kind: "Number",
            value: number
        } : {
            kind: "Text",
            value: value
        };
    }
    function editItem(index, value) {
        const next = JSON.parse(JSON.stringify(modelData.items || []));
        next[index] = itemFromText(value);
        canvas.listItemsEdited(modelData.name, next);
    }
    function removeItem(index) {
        const next = JSON.parse(JSON.stringify(modelData.items || []));
        next.splice(index, 1);
        canvas.listItemsEdited(modelData.name, next);
    }
    function addItem(index, value) {
        const next = JSON.parse(JSON.stringify(modelData.items || []));
        for (let i = 0; i < listRepeater.count; ++i) {
            const row = listRepeater.itemAt(i);
            if (row && row.field.text !== String(next[i].value))
                next[i] = itemFromText(row.field.text);
            if (row)
                row.field.submitting = true;
        }
        if (index !== undefined)
            next[index] = itemFromText(value);
        canvas.pendingListFocus = {
            name: modelData.name,
            index: next.length
        };
        next.push({
            kind: "Text",
            value: ""
        });
        canvas.listItemsEdited(modelData.name, next);
    }
    Rectangle {
        id: listHead
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 44
        color: "transparent"
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 1
            color: Theme.borderSoft
        }
        // Accept the press before the canvas can start panning.
        MouseArea {
            id: listHeaderDrag
            objectName: "listHeaderDrag"
            anchors.fill: parent
            enabled: !canvas.locked
            acceptedButtons: Qt.LeftButton
            preventStealing: true
            drag.target: listCard
            drag.minimumX: 0
            drag.maximumX: listCard.maxX
            drag.minimumY: 0
            drag.maximumY: listCard.maxY
            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            onReleased: if (drag.active)
                canvas.listEditorStateChanged(listCard.modelData.name, true, Math.round(listCard.x), Math.round(listCard.y))
        }
        Row {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 8
            LucideIcon {
                name: "layers"
                color: Theme.textDim
                width: 16
                height: 16
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: listCard.modelData.name
                color: Theme.text
                font.pixelSize: 13
                font.weight: Font.DemiBold
                width: parent.width - 16 - 28 - 16
                elide: Text.ElideRight
                anchors.verticalCenter: parent.verticalCenter
            }
            StitchButton {
                iconName: "x"
                text: ""
                flat: true
                implicitWidth: 28
                implicitHeight: 28
                anchors.verticalCenter: parent.verticalCenter
                onClicked: canvas.listEditorStateChanged(listCard.modelData.name, false, Math.round(listCard.x), Math.round(listCard.y))
            }
        }
    }
    Flickable {
        id: listScroll
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: listHead.bottom
        anchors.bottom: listFoot.top
        contentHeight: listRows.implicitHeight
        clip: true
        Column {
            id: listRows
            width: parent.width
            spacing: 6
            padding: 10
            Text {
                visible: !(listCard.modelData.items || []).length
                text: qsTr("This list is empty.")
                color: Theme.textDim
                font.pixelSize: 12
                width: parent.width - 20
                height: 44
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            Repeater {
                id: listRepeater
                model: listCard.modelData.items || []
                delegate: Row {
                    property alias field: itemField
                    required property var modelData
                    required property int index
                    spacing: 6
                    width: listRows.width - 20
                    height: 34
                    Text {
                        text: String(index + 1)
                        color: Theme.textDim
                        font.pixelSize: 11
                        width: 18
                        horizontalAlignment: Text.AlignRight
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    StitchTextField {
                        id: itemField
                        objectName: "listItem_" + index
                        property bool submitting: false
                        text: String(modelData.value)
                        color: modelData.kind === "Number" ? Theme.accent : Theme.text
                        width: parent.width - 18 - 28 - 12
                        implicitHeight: 34
                        font.pixelSize: 13
                        function appendItem(event) {
                            event.accepted = true;
                            submitting = true;
                            listCard.addItem(index, text);
                        }
                        Keys.onReturnPressed: event => appendItem(event)
                        Keys.onEnterPressed: event => appendItem(event)
                        onEditingFinished: if (!submitting && text !== String(modelData.value))
                            listCard.editItem(index, text)
                        Component.onCompleted: Qt.callLater(function () {
                            const pending = canvas.pendingListFocus;
                            if (!pending || pending.name !== listCard.modelData.name || pending.index !== index)
                                return;
                            canvas.pendingListFocus = null;
                            itemField.forceActiveFocus();
                            itemField.selectAll();
                            listRows.forceLayout();
                            const position = itemField.mapToItem(listRows, 0, 0);
                            listScroll.contentY = Math.max(0, Math.min(position.y, listScroll.contentHeight - listScroll.height));
                        })
                    }
                    StitchButton {
                        iconName: "trash-2"
                        text: ""
                        flat: true
                        danger: hovered
                        implicitWidth: 28
                        implicitHeight: 28
                        anchors.verticalCenter: parent.verticalCenter
                        onClicked: listCard.removeItem(index)
                    }
                }
            }
        }
    }
    Rectangle {
        id: listFoot
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 46
        color: "transparent"
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: 1
            color: Theme.borderSoft
        }
        StitchButton {
            objectName: "addListItem"
            iconName: "plus"
            text: qsTr("Add item")
            implicitHeight: 30
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            onClicked: listCard.addItem()
        }
        Text {
            text: qsTr("%n item(s)", "", (listCard.modelData.items || []).length)
            color: Theme.textDim
            font.pixelSize: 11
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
