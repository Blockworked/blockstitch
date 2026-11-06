import QtQuick
import QtQuick.Controls
import QtQuick.Shapes

// A dict's floating editor card on the canvas: its keys and values, editable
// in place. BlockCanvas makes one per open dict editor.
Rectangle {
    id: dictCard
    required property Item canvas
    // The layer the card floats in; it stays inside it.
    required property Item overlay
    required property string editorName
    required property string payload
    required property real editorX
    required property real editorY
    readonly property var modelData: JSON.parse(payload)
    objectName: "dictEditor_" + modelData.name
    readonly property real maxX: Math.max(0, overlay.width - width)
    readonly property real maxY: Math.max(0, overlay.height - height)
    function keepInView() {
        if (x < 0 || x > maxX)
            x = Math.max(0, Math.min(x, maxX));
        if (y < 0 || y > maxY)
            y = Math.max(0, Math.min(y, maxY));
    }
    onMaxXChanged: keepInView()
    onMaxYChanged: keepInView()
    readonly property var entries: modelData.entries || []
    visible: modelData.editor_visible
    x: Math.max(0, Math.min(editorX, maxX))
    y: Math.max(0, Math.min(editorY, maxY))
    z: 12
    width: 360
    height: Math.min(420, 90 + Math.max(64, entries.length * 40 + 14))
    radius: 12
    color: Theme.panel
    border.color: Theme.borderSoft
    clip: true
    // A monitor edit is a literal: finite numbers stay numeric.
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
    function save(next) {
        canvas.dictEntriesEdited(modelData.name, next);
    }
    function copy() {
        return JSON.parse(JSON.stringify(entries));
    }
    function editKey(index, key) {
        const next = copy();
        next[index].key = key;
        save(next);
    }
    function editValue(index, value) {
        const next = copy();
        next[index].value = itemFromText(value);
        save(next);
    }
    function removeEntry(index) {
        const next = copy();
        next.splice(index, 1);
        save(next);
    }
    function addEntry() {
        const next = copy();
        for (let i = 0; i < dictRepeater.count; ++i) {
            const row = dictRepeater.itemAt(i);
            if (!row)
                continue;
            next[i].key = row.keyField.text;
            if (row.valueField.text !== String(next[i].value.value))
                next[i].value = itemFromText(row.valueField.text);
            row.submitting = true;
        }
        canvas.pendingDictFocus = {
            name: modelData.name,
            index: next.length
        };
        next.push({
            key: "",
            value: {
                kind: "Text",
                value: ""
            }
        });
        save(next);
    }
    Rectangle {
        id: dictHead
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
            id: dictHeaderDrag
            objectName: "dictHeaderDrag"
            anchors.fill: parent
            enabled: !canvas.locked
            acceptedButtons: Qt.LeftButton
            preventStealing: true
            drag.target: dictCard
            drag.minimumX: 0
            drag.maximumX: dictCard.maxX
            drag.minimumY: 0
            drag.maximumY: dictCard.maxY
            cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
            onReleased: if (drag.active)
                canvas.dictEditorStateChanged(dictCard.modelData.name, true, Math.round(dictCard.x), Math.round(dictCard.y))
        }
        Row {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 8
            LucideIcon {
                name: "book-key"
                color: Theme.textDim
                width: 16
                height: 16
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: dictCard.modelData.name
                color: Theme.text
                font.pixelSize: 13
                font.weight: Font.DemiBold
                width: parent.width - 16 - 28 - 16
                elide: Text.ElideRight
                anchors.verticalCenter: parent.verticalCenter
            }
            BwButton {
                iconName: "x"
                text: ""
                flat: true
                implicitWidth: 28
                implicitHeight: 28
                anchors.verticalCenter: parent.verticalCenter
                onClicked: canvas.dictEditorStateChanged(dictCard.modelData.name, false, Math.round(dictCard.x), Math.round(dictCard.y))
            }
        }
    }
    Flickable {
        id: dictScroll
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: dictHead.bottom
        anchors.bottom: dictFoot.top
        contentHeight: dictRows.implicitHeight
        clip: true
        Column {
            id: dictRows
            width: parent.width
            spacing: 6
            padding: 10
            Text {
                visible: !dictCard.entries.length
                text: qsTr("This dict is empty.")
                color: Theme.textDim
                font.pixelSize: 12
                width: parent.width - 20
                height: 44
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            Repeater {
                id: dictRepeater
                model: dictCard.entries
                delegate: Row {
                    id: entryRow
                    property alias keyField: dictKey
                    property alias valueField: dictValue
                    property bool submitting: false
                    function appendEntry(event) {
                        event.accepted = true;
                        dictCard.addEntry();
                    }
                    required property var modelData
                    required property int index
                    spacing: 6
                    width: dictRows.width - 20
                    height: 34
                    BwTextField {
                        id: dictKey
                        objectName: "dictKey_" + index
                        Keys.onReturnPressed: event => entryRow.appendEntry(event)
                        Keys.onEnterPressed: event => entryRow.appendEntry(event)
                        Component.onCompleted: Qt.callLater(function () {
                            const pending = canvas.pendingDictFocus;
                            if (!pending || pending.name !== dictCard.modelData.name || pending.index !== index)
                                return;
                            canvas.pendingDictFocus = null;
                            dictKey.forceActiveFocus();
                            dictKey.selectAll();
                            dictRows.forceLayout();
                            const position = dictKey.mapToItem(dictRows, 0, 0);
                            dictScroll.contentY = Math.max(0, Math.min(position.y, dictScroll.contentHeight - dictScroll.height));
                        })
                        text: modelData.key
                        placeholderText: qsTr("key")
                        width: 128
                        implicitHeight: 34
                        font.pixelSize: 13
                        onEditingFinished: if (!entryRow.submitting && text !== modelData.key)
                            dictCard.editKey(index, text)
                    }
                    LucideIcon {
                        name: "arrow-right"
                        color: Theme.textDim
                        width: 13
                        height: 13
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    BwTextField {
                        id: dictValue
                        objectName: "dictValue_" + index
                        Keys.onReturnPressed: event => entryRow.appendEntry(event)
                        Keys.onEnterPressed: event => entryRow.appendEntry(event)
                        text: String(modelData.value.value)
                        placeholderText: qsTr("value")
                        color: modelData.value.kind === "Number" ? Theme.accent : Theme.text
                        width: parent.width - 128 - 13 - 28 - 18
                        implicitHeight: 34
                        font.pixelSize: 13
                        onEditingFinished: if (!entryRow.submitting && text !== String(modelData.value.value))
                            dictCard.editValue(index, text)
                    }
                    BwButton {
                        iconName: "trash-2"
                        text: ""
                        flat: true
                        danger: hovered
                        implicitWidth: 28
                        implicitHeight: 28
                        anchors.verticalCenter: parent.verticalCenter
                        onClicked: dictCard.removeEntry(index)
                    }
                }
            }
        }
    }
    Rectangle {
        id: dictFoot
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
        BwButton {
            objectName: "addDictEntry"
            iconName: "plus"
            text: qsTr("Add entry")
            implicitHeight: 30
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            onClicked: dictCard.addEntry()
        }
        Text {
            text: qsTr("%n entry(s)", "", dictCard.entries.length)
            color: Theme.textDim
            font.pixelSize: 11
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
