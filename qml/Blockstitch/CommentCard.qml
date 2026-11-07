import QtQuick
import QtQuick.Controls
import QtQuick.Shapes

// One comment on the canvas: a header that drags it, a collapsible text body,
// and a line to the block it's attached to.
Rectangle {
    id: commentCard
    required property var modelData
    // The BlockCanvas this card sits on.
    required property Item canvas
    objectName: "commentCard_" + modelData.id
    readonly property var attachedBlock: modelData.attached_to && canvas.builtStrands >= 0 ? canvas.findBlockItem(canvas.workspaceItem, modelData.attached_to) : null
    readonly property point blockAnchor: canvas.commentAnchor(attachedBlock)
    Shape {
        parent: commentCard.canvas.workspaceItem
        objectName: "commentConnector_" + commentCard.modelData.id
        z: -2
        visible: !!commentCard.attachedBlock
        ShapePath {
            strokeColor: Theme.textDim
            strokeWidth: 1.5
            fillColor: "transparent"
            startX: commentCard.blockAnchor.x
            startY: commentCard.blockAnchor.y
            PathLine {
                // End inside the card so its rounded surface masks the line.
                x: commentCard.x + commentCard.width / 2
                y: commentCard.y + commentCard.height / 2
            }
        }
    }
    readonly property real headerH: 38
    readonly property real bodyMinH: 74
    readonly property real bodyMaxH: 240
    x: modelData.x + canvas.originOffsetX
    y: modelData.y + canvas.originOffsetY
    z: 4
    width: 220
    height: modelData.collapsed ? headerH : headerH + 1 + Math.min(bodyMaxH, Math.max(bodyMinH, bodyArea.implicitHeight + 14))
    radius: Theme.radius
    color: Theme.panelRaised
    border.color: Theme.border
    clip: true
    Row {
        id: headerRow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: 8
        anchors.rightMargin: 4
        height: commentCard.headerH
        spacing: 7
        LucideIcon {
            name: "message-square"
            color: Theme.textDim
            width: 14
            height: 14
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            id: commentLabel
            text: qsTr("Comment")
            color: Theme.textDim
            font.pixelSize: 12
            font.weight: Font.Medium
            anchors.verticalCenter: parent.verticalCenter
        }
        Item {
            width: Math.max(0, parent.width - 14 - commentLabel.width - collapseBtn.width - parent.spacing * 3)
            height: 1
        }
        StitchButton {
            id: collapseBtn
            iconName: commentCard.modelData.collapsed ? "chevron-down" : "chevron-up"
            text: ""
            flat: true
            implicitWidth: 24
            implicitHeight: 24
            anchors.verticalCenter: parent.verticalCenter
            onClicked: canvas.commentCollapseChanged(commentCard.modelData.id, !commentCard.modelData.collapsed)
        }
    }
    Rectangle {
        id: commentDivider
        visible: !commentCard.modelData.collapsed
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: headerRow.bottom
        height: 1
        color: Theme.borderSoft
    }
    ScrollView {
        id: bodyScroll
        objectName: "commentScroll_" + commentCard.modelData.id
        visible: !commentCard.modelData.collapsed
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: commentDivider.bottom
        anchors.bottom: parent.bottom
        contentWidth: availableWidth
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        TextArea {
            id: bodyArea
            objectName: "commentText_" + commentCard.modelData.id
            ContextMenu.menu: canvas.textMenu ? canvas.textMenu.createObject(bodyArea, {
                editor: bodyArea
            }) : null
            text: commentCard.modelData.text
            color: Theme.text
            wrapMode: TextEdit.Wrap
            padding: 7
            background: null
            TextSelectHold {}
            onActiveFocusChanged: if (!activeFocus && text !== commentCard.modelData.text)
                canvas.commentEdited(commentCard.modelData.id, text)
        }
    }
    DragHandler {
        parent: headerRow
        enabled: !canvas.locked
        target: commentCard
        onActiveChanged: if (!active)
            canvas.commentMoved(commentCard.modelData.id, Math.round(commentCard.x - canvas.originOffsetX), Math.round(commentCard.y - canvas.originOffsetY))
    }
    TapHandler {
        acceptedButtons: Qt.RightButton
        gesturePolicy: TapHandler.ReleaseWithinBounds
        onTapped: commentMenu.popup()
    }
    StitchMenu {
        id: commentMenu
        StitchMenuItem {
            iconName: "trash"
            danger: true
            text: qsTr("Delete comment")
            onTriggered: canvas.commentRemoved(commentCard.modelData.id)
        }
    }
}
