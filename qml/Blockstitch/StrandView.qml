import QtQuick

// One strand on the canvas: its blocks once it comes near the view (or the
// background builder reaches it), a placeholder of about its size before.
Column {
    id: strand
    required property Item canvas
    Accessible.role: Accessible.Grouping
    Accessible.name: qsTr("Block strand")
    required property string sid
    required property real sx
    required property real sy
    required property string payload
    required property int index
    readonly property var blockList: JSON.parse(payload || "[]")
    readonly property color branchColor: canvas.branchColorForBlock(canvas.strandOrigins[sid] || "")
    // Blocks are built once the strand comes near the view, or
    // by the background builder; until then a placeholder of
    // about the right size stands in.
    property bool built: false
    property bool loading: false
    property real estY: 0
    readonly property bool nearView: canvas.nearView(x, y, Math.max(width, canvas.strandEstW), Math.max(height, 58))
    onNearViewChanged: if (nearView)
        canvas.buildStrand(strand)
    x: sx + canvas.originOffsetX
    y: sy + canvas.originOffsetY
    spacing: -8
    z: (canvas.branchDragState.active && canvas.branchDragState.strandId === sid) || (canvas.branchDragState.settling && canvas.branchDragState.settleStrandId === sid) ? 100 : 0
    // Report the real card width so the world extends past
    // actual strand content, not a fixed estimate.
    // (InstructionList below is a non-visual ListModel, so the
    // Column's implicitWidth is still the widest block.)
    onImplicitWidthChanged: canvas.noteStrandWidth(sid, implicitWidth)
    onImplicitHeightChanged: canvas.noteStrandHeight(sid, implicitHeight)
    Component.onCompleted: {
        if (nearView || !canvas.lazyStrands)
            canvas.buildStrand(strand);
        else
            canvas.startStrandBuilder();
        canvas.noteStrandWidth(sid, implicitWidth);
        canvas.noteStrandHeight(sid, implicitHeight);
    }
    Component.onDestruction: {
        canvas.clearStrandWidth(sid);
        canvas.clearStrandHeight(sid);
    }
    InstructionList {
        id: strandBlocks
        instructions: strand.built ? strand.blockList : []
        onAboutToInsert: (at, n) => canvas.bulkInsert(strand, blockRepeater, at, n)
    }
    Item {
        visible: !strand.built
        width: canvas.strandEstW
        height: Math.max(58, strand.blockList.length * 50)
    }
    Repeater {
        id: blockRepeater
        model: strandBlocks
        // Far blocks of a long strand stand in as a placeholder
        // of their estimated size until the builder reaches them.
        delegate: Loader {
            id: slot
            required property string payload
            required property int index
            property bool built: false
            readonly property Item strandItem: strand
            // Blocks stack among their siblings (a hovered or dragged
            // block over the next one), so the slot carries their z.
            z: item ? item.z : 0
            sourceComponent: built ? blockComponent : placeholderComponent
            Component.onCompleted: canvas.slotCreated(strand, slot, canvas.blockHeight(JSON.parse(payload)))
            Component {
                id: placeholderComponent
                Item {
                    width: canvas.strandEstW
                    height: canvas.blockHeight(JSON.parse(slot.payload))
                }
            }
            Component {
                id: blockComponent
                InstructionBlock {
                    id: block
                    readonly property string payload: slot.payload
                    readonly property int index: slot.index
                    visible: dragRole !== 0 || canvas.inCullBand(strand.x + slot.x, strand.y + slot.y + snapShift, Math.max(slot.width, 1), Math.max(slot.height, 1))
                    instruction: JSON.parse(payload)
                    strandId: strand.sid
                    path: [
                        {
                            index: index
                        }
                    ]
                    tailCount: strandBlocks.count - index
                    strandMarked: index === 0 && canvas.markedStrandId === strand.sid
                    dragState: canvas.branchDragState
                    variables: canvas.variables
                    lists: canvas.lists
                    blockDefinitions: canvas.blockDefinitions
                    canvasState: canvas.canvasState
                    keyCapture: canvas.keyCapture
                    locked: canvas.locked
                    branchColor: strand.branchColor
                    // Signals go through wireInstruction, the one list branch blocks use too.
                    Component.onCompleted: canvas.wireInstruction(this)
                }
            }
        }
    }
}
