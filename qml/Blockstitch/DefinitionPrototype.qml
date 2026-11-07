import QtQuick
import QtQuick.Controls

// The definition's pieces in their groups, drawn as the block will look.
Row {
    id: proto
    required property Item editor
    spacing: 8
    Repeater {
        model: editor.previewGroups
        delegate: Rectangle {
            id: group
            required property var modelData
            objectName: modelData.component ? "prototypeComponentGroup" : "prototypeBasePiece"
            width: groupRow.implicitWidth + (modelData.component ? 16 : 0)
            height: modelData.component ? 41 : 29
            anchors.verticalCenter: parent.verticalCenter
            radius: 7
            color: modelData.component ? Theme.panelRaised : "transparent"
            border.width: modelData.component ? 1 : 0
            border.color: Theme.border
            Row {
                id: groupRow
                anchors.centerIn: parent
                spacing: 5
                Repeater {
                    model: group.modelData.indices
                    delegate: DefinitionPiece {
                        editor: proto.editor
                        required property int modelData
                        index: modelData
                        pieceIndex: modelData
                        pieceKind: editor.pieceModel.get(modelData).pieceKind
                        pieceName: editor.pieceModel.get(modelData).pieceName
                        valueType: editor.pieceModel.get(modelData).valueType
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }
    }
}
