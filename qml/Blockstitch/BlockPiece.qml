import QtQuick
import QtQuick.Controls

// One piece of a block's row: a label, a value slot, a dropdown, a text
// field, a button or a component capsule. Only the control the piece needs
// is built.
Loader {
    id: piece
    // The InstructionBlock this piece belongs to.
    required property Item block
    required property var modelData
    readonly property string kind: modelData.kind
    anchors.verticalCenter: parent ? parent.verticalCenter : undefined
    sourceComponent: kind === "label" ? labelPiece : kind === "value" ? (modelData.unit ? unitValuePiece : valuePiece) : kind === "dropdown" ? dropdownPiece : kind === "button" ? buttonPiece : kind === "component" ? componentPiece : kind === "addComponent" ? addComponentPiece : kind === "removeComponent" ? removeComponentPiece : textPiece
    Component {
        id: componentPiece
        Rectangle {
            objectName: "componentCapsule"
            readonly property var componentSpec: piece.modelData.component
            implicitWidth: componentRow.implicitWidth + 16
            implicitHeight: componentRow.implicitHeight + 8
            radius: 7
            color: Theme.panelRaised
            border.color: Theme.border
            Accessible.role: Accessible.Grouping
            Accessible.name: qsTr("Component: %1").arg(componentSpec.label || "")
            Row {
                id: componentRow
                anchors.centerIn: parent
                spacing: 7
                Repeater {
                    model: piece.modelData.pieces
                    delegate: block.pieceDelegate
                }
            }
        }
    }
    Component {
        id: labelPiece
        // Event (header) labels use the same caption style as the
        // built-in event blocks above, so every hat reads alike.
        Text {
            text: piece.modelData.text || ""
            color: Theme.text
            font.pixelSize: block.isHeader ? Theme.blockText - 1 : Theme.blockText
            font.weight: block.isHeader ? Font.DemiBold : Font.Normal
            height: 30
            verticalAlignment: Text.AlignVCenter
        }
    }
    Component {
        id: valuePiece
        ValueChip {
            valueData: block.instruction ? (block.slotValue(piece.modelData) || (piece.modelData.bool ? {
                        kind: "Bool"
                    } : {
                        kind: "Number",
                        value: 0
                    })) : null
            location: block.paletteMode ? null : block.fieldLocation(piece.modelData.field)
            leafOptions: piece.modelData.options ? BlockRegistry.choices(piece.modelData.options, block.instruction) : null
            leafPlaceholder: piece.modelData.placeholder || qsTr("choose")
            multiline: !!piece.modelData.box && !!piece.parent && piece.parent.objectName === "blockBoxLine"
            monospace: !!piece.modelData.monospace
            pickAction: piece.modelData.pickAction || ""
            pickOnClick: !piece.modelData.expression || !block.instruction || !block.instruction[piece.modelData.expression]
            boxed: !!piece.modelData.bool
            forceBoolean: !!piece.modelData.bool && (!valueData || valueData.kind === "Bool")
            pick: piece.modelData.pick || null
            flatLeaf: !!piece.modelData.unit
            keyMode: !!piece.modelData.keyCapture
            keyCapturing: !!piece.modelData.keyCapture && block.isCapturingKey()
            onKeyCaptureRequested: block.keyCaptureRequested(block.strandId, block.path)
            blockDefinitions: block.blockDefinitions
            canvasState: block.canvasState
            onEditRequested: (l, t) => block.valueEdited(l, t)
            onLeafEdited: (p, leaf) => block.setLeaf(piece.modelData.key, p, leaf, piece.modelData.index)
            onDetailsRequested: kind => block.detailsRequested(kind)
            onValueDragBegan: (loc, val, sx, sy, ox, oy, w, h) => block.valueDragBegan(loc, val, sx, sy, ox, oy, w, h)
            onValueDragMoved: (sx, sy) => block.valueDragMoved(sx, sy)
            onValueDragEnded: (sx, sy) => block.valueDragEnded(sx, sy)
            onValueDragCanceled: block.valueDragCanceled()
        }
    }
    // { kind: "value", unit: "ms" }: the slot inside a field box with its unit in front.
    Component {
        id: unitValuePiece
        Rectangle {
            implicitHeight: Math.max(27, unitChip.implicitHeight + 4)
            implicitWidth: unitLabel.implicitWidth + unitChip.implicitWidth + 21
            width: implicitWidth
            height: implicitHeight
            radius: 5
            color: Theme.field
            border.color: unitChip.item && unitChip.item.dropHighlighted ? Theme.accent : Theme.border
            Text {
                id: unitLabel
                x: 7
                text: piece.modelData.unit
                color: Theme.textDim
                font.pixelSize: Theme.blockText
                anchors.verticalCenter: parent.verticalCenter
            }
            Loader {
                id: unitChip
                x: unitLabel.width + 14
                anchors.verticalCenter: parent.verticalCenter
                sourceComponent: valuePiece
            }
        }
    }
    Component {
        id: dropdownPiece
        StitchComboBox {
            id: pieceDrop
            readonly property var choices: block.pieceOptions(piece.modelData)
            readonly property string current: block.pieceValue(piece.modelData)
            readonly property int chosen: {
                for (let i = 0; i < choices.length; ++i)
                    if (choices[i].value === current)
                        return i;
                return -1;
            }
            model: choices
            textRole: "label"
            currentIndex: chosen
            displayText: chosen >= 0 ? choices[chosen].label : (current.length ? current : (piece.modelData.placeholder || "choose"))
            implicitWidth: Math.min(190, Math.max(56, dropMetrics.advanceWidth + 36))
            implicitHeight: 28
            font.pixelSize: Theme.blockText
            leftPadding: 8
            rightPadding: 26
            TextMetrics {
                id: dropMetrics
                font: pieceDrop.font
                text: pieceDrop.displayText
            }
            onActivated: index => {
                const choice = pieceDrop.choices[index];
                if (choice.action)
                    choice.action(value => block.setPiece(piece.modelData, value));
                else
                    block.setPiece(piece.modelData, choice.value);
            }
        }
    }
    // { kind: "button", action, text, icon, image: key, palette } - with
    // `image`, shows that field's picture (a data: URI) as a thumbnail;
    // with `palette`, it can also be clicked in the palette.
    Component {
        id: buttonPiece
        Rectangle {
            id: pieceButton
            readonly property string picture: piece.modelData.image && block.instruction ? (block.instruction[piece.modelData.image] || "") : ""
            readonly property string label: typeof piece.modelData.text === "function" ? piece.modelData.text(block.instruction) : (piece.modelData.text || "")
            readonly property bool clickable: !block.paletteMode || !!piece.modelData.palette
            implicitWidth: buttonRow.implicitWidth + 14
            implicitHeight: picture ? 34 : 28
            radius: 6
            color: buttonMouse.containsMouse && clickable ? Theme.panelRaised : Theme.field
            border.color: buttonMouse.containsMouse && clickable ? Theme.accent : Theme.border
            Row {
                id: buttonRow
                anchors.centerIn: parent
                spacing: 6
                Image {
                    visible: pieceButton.picture.length > 0
                    source: pieceButton.picture
                    readonly property real aspect: implicitHeight > 0 ? implicitWidth / implicitHeight : 1
                    height: 26
                    width: Math.min(110, Math.max(14, height * aspect))
                    fillMode: Image.PreserveAspectFit
                    smooth: false
                    anchors.verticalCenter: parent.verticalCenter
                }
                LucideIcon {
                    visible: !pieceButton.picture && !!piece.modelData.icon
                    name: piece.modelData.icon || "info"
                    width: 14
                    height: 14
                    color: Theme.text
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    visible: pieceButton.label.length > 0
                    text: pieceButton.label
                    color: Theme.text
                    font.pixelSize: Theme.blockText
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
            MouseArea {
                id: buttonMouse
                anchors.fill: parent
                hoverEnabled: true
                enabled: pieceButton.clickable
                cursorShape: Qt.PointingHandCursor
                onClicked: block.pieceActionRequested(piece.modelData.action || "", block.strandId, block.path, block.instruction)
            }
        }
    }
    // The row's "+": a menu of the components the block doesn't have yet.
    Component {
        id: addComponentPiece
        Rectangle {
            id: addButton
            objectName: "addComponentButton"
            implicitWidth: 22
            implicitHeight: 22
            radius: 11
            color: addMouse.containsMouse ? Theme.panelRaised : "transparent"
            border.color: addMouse.containsMouse ? Theme.accent : Theme.border
            LucideIcon {
                anchors.centerIn: parent
                name: "plus"
                width: 13
                height: 13
                color: addMouse.containsMouse ? Theme.accent : Theme.textDim
            }
            ToolTip.visible: addMouse.containsMouse
            ToolTip.delay: 400
            ToolTip.text: qsTr("Add an option")
            MouseArea {
                id: addMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: addMenu.popup(0, addButton.height + 2)
            }
            StitchMenu {
                id: addMenu
                objectName: "addComponentMenu"
                Instantiator {
                    model: BlockRegistry.missingComponents(block.rowSpec, block.instruction)
                    delegate: StitchMenuItem {
                        required property var modelData
                        iconName: modelData.icon || "plus"
                        text: modelData.label
                        onTriggered: block.addComponent(modelData)
                    }
                    onObjectAdded: (index, object) => addMenu.insertItem(index, object)
                    onObjectRemoved: (index, object) => addMenu.removeItem(object)
                }
            }
        }
    }
    // The "x" that ends a component's pieces.
    Component {
        id: removeComponentPiece
        Item {
            objectName: "removeComponentButton"
            implicitWidth: 24
            implicitHeight: 22
            Rectangle {
                width: 1
                height: parent.height
                color: Theme.border
            }
            LucideIcon {
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: 3
                name: "x"
                width: 12
                height: 12
                color: removeMouse.containsMouse ? Theme.danger : Theme.textDim
            }
            ToolTip.visible: removeMouse.containsMouse
            ToolTip.delay: 400
            ToolTip.text: qsTr("Remove %1").arg(piece.modelData.component.label || "")
            MouseArea {
                id: removeMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: block.removeComponent(piece.modelData.component)
            }
        }
    }
    Component {
        id: textPiece
        StitchTextField {
            text: block.pieceValue(piece.modelData)
            placeholderText: piece.modelData.placeholder || ""
            implicitWidth: Math.min(piece.modelData.maxWidth || 200, Math.max(piece.modelData.minWidth || 64, contentWidth + 20))
            implicitHeight: 28
            font.pixelSize: Theme.blockText
            leftPadding: 7
            rightPadding: 7
            topPadding: 2
            bottomPadding: 2
            onEditingFinished: if (text !== block.pieceValue(piece.modelData))
                block.setPieceField(piece.modelData, text)
        }
    }
}
