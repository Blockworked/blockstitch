import QtQuick
import QtQuick.Controls
import QtQuick.Shapes

// One mouth of a wrap block (If, Repeat, a branch call): the blocks inside it
// and the bar under it. A delegate of InstructionBlock's mouth Repeater.
Item {
    id: slotDelegate
    required property Item block
    required property int index
    property real adjustment: block.mouthAdjustment(index)
    Behavior on adjustment {
        enabled: block.animateLayout
        NumberAnimation {
            duration: Motion.dur(140)
            easing.type: Easing.OutCubic
        }
    }
    readonly property real contentHeight: slotBody.implicitHeight
    readonly property bool capEnd: block.lastIsCap(index)
    // the block sitting last in a mouth overlaps the bar below by its connector tab
    readonly property real mouthHeight: Math.max(block.emptyMouth, contentHeight - (capEnd || contentHeight === 0 ? 0 : block.tabDepth))
    // Measure the remaining children and the incoming snap preview live.
    readonly property real contentWidth: {
        let widest = 0;
        for (let i = 0; i < childBlocks.count; ++i) {
            const child = childBlocks.itemAt(i);
            if (child && child.item && child.item.dragRole !== 1)
                widest = Math.max(widest, child.item.implicitWidth);
        }
        const preview = block.snapLayout();
        if (block.isSnapMouth(index) && preview)
            widest = Math.max(widest, preview.snapWidth || 0);
        return widest;
    }
    function report() {
        block.setMouth(index, mouthHeight, contentWidth, capEnd);
    }
    onMouthHeightChanged: report()
    onContentWidthChanged: report()
    onCapEndChanged: report()
    Component.onCompleted: report()
    x: 0
    y: block.mouthTop(index)
    width: block.width
    height: mouthHeight
    Column {
        id: slotBody
        x: block.spine
        spacing: -8
        InstructionList {
            id: slotBlocks
            instructions: block.body(slotDelegate.index)
        }
        Repeater {
            id: childBlocks
            model: slotBlocks
            delegate: Loader {
                id: child
                required property string payload
                required property int index
                readonly property var blockData: JSON.parse(payload)
                width: item ? item.implicitWidth : 0
                height: item ? item.implicitHeight : 0
                // A hovered or dragged block stacks over the next one.
                z: item ? item.z : 0
                // Supply bindings at creation to avoid rebuilding controls for each property.
                Component.onCompleted: setSource("InstructionBlock.qml", {
                    instruction: Qt.binding(() => child.blockData),
                    strandId: Qt.binding(() => block.strandId),
                    path: Qt.binding(() => block.childPath(slotDelegate.index, child.index)),
                    tailCount: Qt.binding(() => slotBlocks.count - child.index),
                    variables: Qt.binding(() => block.variables),
                    lists: Qt.binding(() => block.lists),
                    blockDefinitions: Qt.binding(() => block.blockDefinitions),
                    canvasState: Qt.binding(() => block.canvasState),
                    branchColor: Qt.binding(() => block.branchColor),
                    keyCapture: Qt.binding(() => block.keyCapture),
                    locked: Qt.binding(() => block.locked),
                    dragState: Qt.binding(() => block.dragState)
                })
                onLoaded: {
                    item.removeRequested.connect((s, p) => block.removeRequested(s, p));
                    item.duplicateRequested.connect((s, p, i) => block.duplicateRequested(s, p, i));
                    item.commentRequested.connect(i => block.commentRequested(i));
                    item.instructionEdited.connect((s, p, i) => block.instructionEdited(s, p, i));
                    item.valueEdited.connect((l, t) => block.valueEdited(l, t));
                    item.valueDragBegan.connect((loc, val, sx, sy, ox, oy, w, h) => block.valueDragBegan(loc, val, sx, sy, ox, oy, w, h));
                    item.valueDragMoved.connect((sx, sy) => block.valueDragMoved(sx, sy));
                    item.valueDragEnded.connect((sx, sy) => block.valueDragEnded(sx, sy));
                    item.valueDragCanceled.connect(() => block.valueDragCanceled());
                    item.runBranchRequested.connect((s, p, n) => block.runBranchRequested(s, p, n));
                    item.keyCaptureRequested.connect((s, p) => block.keyCaptureRequested(s, p));
                    item.detailsRequested.connect(t => block.detailsRequested(t));
                    item.menuActionRequested.connect((a, s, p, i) => block.menuActionRequested(a, s, p, i));
                    item.pieceActionRequested.connect((a, s, p, i) => block.pieceActionRequested(a, s, p, i));
                    item.paletteDragStarted.connect((sp, sx, sy, ox, oy) => block.paletteDragStarted(sp, sx, sy, ox, oy));
                    item.paletteDragMoved.connect((sx, sy) => block.paletteDragMoved(sx, sy));
                    item.paletteDragEnded.connect((sx, sy) => block.paletteDragEnded(sx, sy));
                    item.paletteDragCanceled.connect(() => block.paletteDragCanceled());
                    item.dragBegan.connect(block.dragBegan);
                    item.dragMoved.connect(block.dragMoved);
                    item.dragEnded.connect(block.dragEnded);
                    item.dragCanceled.connect(block.dragCanceled);
                }
            }
        }
    }
    // separator bar below this mouth (not for the last: that is the foot bar)
    Text {
        visible: slotDelegate.index < block.slotCount() - 1
        x: block.spine + 8
        y: block.effMouthHeights[slotDelegate.index] + Math.round((block.midHeight - height) / 2)
        text: block.type === "BranchCallBlock" ? block.branchSeparator(slotDelegate.index) : BlockRegistry.separator(block.type, slotDelegate.index)
        color: Theme.text
        font.pixelSize: Theme.blockText
    }
}
