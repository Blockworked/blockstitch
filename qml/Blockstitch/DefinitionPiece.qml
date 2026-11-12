import QtQuick
import QtQuick.Controls

// One label, input or branch name in the definition editor's preview; a
// click edits it in place.
Item {
    id: piece
    required property Item editor
    required property int index
    required property int pieceIndex
    required property string pieceKind
    required property string pieceName
    required property string valueType
    readonly property bool isComponent: pieceIndex >= 0 && pieceIndex < editor.pieceModel.count && !!editor.pieceModel.get(pieceIndex).component
    readonly property bool isInput: pieceKind === "Input"
    readonly property bool isBranch: pieceKind === "Branch"
    readonly property bool isBool: isInput && valueType === "Bool" && !isComponent
    readonly property bool selected: editor.selectedPiece === pieceIndex
    readonly property bool editing: editor.editingPiece === pieceIndex
    implicitWidth: Math.max(isInput ? 48 : isBranch ? 42 : 30, measure.implicitWidth + (isBool ? 24 : isInput || isBranch ? 20 : 12))
    implicitHeight: 29
    z: selected ? 20 : 1

    function startEdit() {
        editor.beginEdit(pieceIndex, pieceEditor);
    }

    Rectangle {
        anchors.fill: parent
        visible: !piece.isBool
        radius: 5
        color: piece.isInput ? Theme.field : piece.selected ? Theme.hover : "transparent"
        border.width: piece.selected ? 2 : piece.isInput ? 1 : 0
        border.color: piece.selected ? Theme.accent : Theme.border
    }
    Canvas {
        id: boolCanvas
        anchors.fill: parent
        visible: piece.isBool
        antialiasing: true
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        Connections { target: Theme; function onDarkChanged() { boolCanvas.requestPaint(); } }
        Connections {
            target: piece
            function onSelectedChanged() {
                boolCanvas.requestPaint();
            }
        }
        onPaint: {
            const c = getContext("2d");
            c.reset();
            const n = Math.min(height * .32, width / 2);
            c.beginPath();
            c.moveTo(n, .5);
            c.lineTo(width - n, .5);
            c.lineTo(width - .5, height / 2);
            c.lineTo(width - n, height - .5);
            c.lineTo(n, height - .5);
            c.lineTo(.5, height / 2);
            c.closePath();
            c.fillStyle = Theme.field;
            c.fill();
            c.strokeStyle = piece.selected ? Theme.accent : Theme.border;
            c.lineWidth = piece.selected ? 2 : 1;
            c.stroke();
        }
    }
    Text {
        id: measure
        textFormat: Text.PlainText
        anchors.centerIn: parent
        text: piece.editing ? (pieceEditor.text || " ") : (piece.pieceName || (piece.isInput ? qsTr("value") : qsTr("Add label")))
        color: piece.isInput ? Theme.accent : Theme.text
        font.pixelSize: 13
        font.weight: piece.isInput ? Font.DemiBold : Font.Normal
        visible: !piece.editing
    }
    TextInput {
        id: pieceEditor
        ContextMenu.menu: editor.textMenu ? editor.textMenu.createObject(pieceEditor, { editor: pieceEditor }) : null
        anchors.centerIn: parent
        width: Math.max(20, measure.implicitWidth + 2)
        height: parent.height
        verticalAlignment: TextInput.AlignVCenter
        horizontalAlignment: TextInput.AlignHCenter
        text: piece.pieceName
        visible: piece.editing
        selectByMouse: true
        color: piece.isInput ? Theme.accent : Theme.text
        font.pixelSize: 13
        font.weight: piece.isInput ? Font.DemiBold : Font.Normal
        onActiveFocusChanged: if (!activeFocus && piece.editing)
            editor.commitPiece()
        onAccepted: editor.commitPiece()
        Keys.onEscapePressed: {
            editor.activeEditor = null;
            editor.editingPiece = -1;
        }
    }
    TapHandler {
        enabled: !piece.editing
        onTapped: piece.startEdit()
    }

    Rectangle {
        visible: piece.selected && !piece.isBranch && editor.pieceModel.count > 0
        x: (piece.width - width) / 2
        y: -39
        z: 30
        width: actions.implicitWidth + 6
        height: 30
        radius: 6
        color: Theme.panelRaised
        border.color: Theme.border
        Row {
            id: actions
            anchors.centerIn: parent
            spacing: 2
            Repeater {
                model: [
                    {
                        icon: "chevron-down",
                        tip: qsTr("Move left"),
                        direction: -1
                    },
                    {
                        icon: "x",
                        tip: qsTr("Remove"),
                        direction: 0
                    },
                    {
                        icon: "chevron-down",
                        tip: qsTr("Move right"),
                        direction: 1
                    }
                ]
                delegate: Button {
                    id: actionButton
                    required property var modelData
                    width: 22
                    height: 22
                    padding: 0
                    enabled: modelData.direction === 0 || (modelData.direction < 0 ? piece.pieceIndex > 0 : piece.pieceIndex < editor.pieceModel.count - 1)
                    ToolTip.visible: hovered
                    ToolTip.text: modelData.tip
                    onClicked: modelData.direction === 0 ? editor.removeSelected() : editor.moveSelected(modelData.direction)
                    contentItem: LucideIcon {
                        name: modelData.icon
                        rotation: modelData.direction < 0 ? 90 : modelData.direction > 0 ? -90 : 0
                        color: modelData.direction === 0 ? Theme.danger : Theme.textDim
                        width: 14
                        height: 14
                        anchors.centerIn: parent
                    }
                    background: Rectangle {
                        radius: 4
                        color: actionButton.hovered ? Theme.hover : "transparent"
                        Behavior on color { enabled: Motion.enabled; ColorAnimation { duration: Motion.quick } }
                    }
                }
            }
        }
    }
}
