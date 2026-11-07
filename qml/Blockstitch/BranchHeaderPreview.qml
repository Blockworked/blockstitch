import QtQuick
import QtQuick.Controls
import QtQuick.Shapes

// A custom block definition's header drawn as its call (when the block has
// branches), so the definition shows what a call looks like.
Item {
    id: pvRoot
    required property Item block
    readonly property alias pieces: pvPieces
    visible: block.hasBranchHeader
    x: 14
    y: block.pvTop
    width: block.pvOuterWidth
    height: block.pvOuterHeight
    Shape {
        id: pvShell
        visible: block.pvReporter
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        readonly property string outline: {
            const w = width, h = height;
            if (w <= 0 || h <= 0)
                return "";
            if (block.pvBool) {
                const n = Math.min(w / 2, h / 2);
                return "M" + n + " .5 L" + (w - n) + " .5 L" + (w - .5) + " " + h / 2 + " L" + (w - n) + " " + (h - .5) + " L" + n + " " + (h - .5) + " L.5 " + h / 2 + " Z";
            }
            const r = Math.min(24, h / 2), R = w - .5, B = h - .5;
            return "M" + (.5 + r) + " .5 L" + (R - r) + " .5 Q" + R + " .5 " + R + " " + (.5 + r) + " L" + R + " " + (B - r) + " Q" + R + " " + B + " " + (R - r) + " " + B + " L" + (.5 + r) + " " + B + " Q.5 " + B + " .5 " + (B - r) + " L.5 " + (.5 + r) + " Q.5 .5 " + (.5 + r) + " .5 Z";
        }
        ShapePath {
            strokeColor: Qt.rgba(block.customColor.r * .3 + Theme.border.r * .7, block.customColor.g * .3 + Theme.border.g * .7, block.customColor.b * .3 + Theme.border.b * .7, 1)
            strokeWidth: 1.3
            joinStyle: ShapePath.RoundJoin
            fillColor: Theme.block
            PathSvg {
                path: pvShell.outline
            }
        }
    }
    Item {
        id: pvInner
        x: block.pvPadX
        y: block.pvPadY
        width: block.pvWidth
        height: block.pvHeight
        BlockSurface {
            anchors.fill: parent
            shape: "wrap"
            fill: Theme.block
            outline: Theme.border
            hoverColor: block.customColor
            headNotch: !block.pvReporter
            footTab: !block.pvNoTab
            headHeight: block.pvHead
            midHeight: block.pvMid
            footHeight: block.pvFoot
            spine: block.spine
            mouthHeights: block.branchModel.map(() => block.pvMouth)
        }
        Repeater {
            model: block.branchModel
            delegate: Text {
                required property var modelData
                required property int index
                visible: index < block.branchModel.length - 1 && modelData.s.length > 0
                x: block.spine + 8
                y: block.pvHead + index * (block.pvMouth + block.pvMid) + block.pvMouth + Math.round((block.pvMid - height) / 2)
                text: modelData.s
                color: Theme.text
                font.pixelSize: Theme.blockText
            }
        }
        Repeater {
            id: pvPieces
            model: block.branchModel
            delegate: Item {
                id: pv
                required property var modelData
                required property int index
                readonly property real pieceWidth: Math.max(150, pvRow.implicitWidth + 28)
                onPieceWidthChanged: block.recalcPieceMax()
                Component.onCompleted: block.recalcPieceMax()
                x: block.spine
                y: block.pvHead + index * (block.pvMouth + block.pvMid)
                width: pieceWidth
                height: block.pvMouth + block.tabDepth
                BlockSurface {
                    anchors.fill: parent
                    shape: "stack"
                    fill: Theme.panelRaised
                    outline: Theme.border
                    hoverColor: block.customColor
                    hovered: pvDrag.hovered
                }
                Row {
                    id: pvRow
                    x: 14
                    y: Math.round((block.pvMouth - height) / 2)
                    spacing: 6
                    LucideIcon {
                        name: "git-branch"
                        color: block.customColor
                        width: 16
                        height: 16
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: pv.modelData.n
                        color: Theme.text
                        font.pixelSize: Theme.blockText
                        font.weight: Font.DemiBold
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                BlockDragArea {
                    id: pvDrag
                    anchors.fill: parent
                    onDragBegan: (sx, sy, ox, oy) => block.paletteDragStarted({
                            kind: "branch",
                            color: block.customColor,
                            instruction: {
                                id: "palette-branch",
                                type: "RunBranch",
                                name: pv.modelData.n
                            }
                        }, sx, sy, ox, oy)
                    onDragMoved: (sx, sy) => block.paletteDragMoved(sx, sy)
                    onDragEnded: (sx, sy) => block.paletteDragEnded(sx, sy)
                    onDragCanceled: block.paletteDragCanceled()
                    onTapped: block.runBranchRequested(block.strandId, block.path, pv.modelData.n)
                }
            }
        }
    }
}
