import QtQuick

// What one canvas shows about its blocks beyond the document: run and debug
// marks, the comment dots, a reveal flash and a value being dropped. Each
// BlockCanvas owns one and hands it to its blocks as `canvasState`.
QtObject {
    id: state
    property string documentId: ""
    property var runningIds: []
    property var breakpointIds: []
    property var pausedIds: []
    property var commentedIds: []
    // Instruction id -> message, shown as a marker on the block.
    property var blockMarks: ({})
    signal markClicked(string instructionId)
    signal breakpointClicked(string instructionId)

    // Id lookups the blocks read. A host republishes equal lists on every
    // state push; these only change when the ids do, so thousands of blocks
    // don't re-evaluate for nothing.
    property var runningSet: ({})
    property var breakpointSet: ({})
    property var pausedSet: ({})
    property var commentedSet: ({})
    property var marks: ({})
    function _idSet(ids, old) {
        const set = {};
        for (const id of ids || []) set[id] = true;
        const keys = Object.keys(set);
        if (keys.length === Object.keys(old).length && keys.every(k => old[k] === true)) return old;
        return set;
    }
    onRunningIdsChanged: runningSet = _idSet(runningIds, runningSet)
    onBreakpointIdsChanged: breakpointSet = _idSet(breakpointIds, breakpointSet)
    onPausedIdsChanged: pausedSet = _idSet(pausedIds, pausedSet)
    onCommentedIdsChanged: commentedSet = _idSet(commentedIds, commentedSet)
    onBlockMarksChanged: {
        const next = blockMarks || {};
        const keys = Object.keys(next);
        if (keys.length !== Object.keys(marks).length || keys.some(k => marks[k] !== next[k])) marks = Object.assign({}, next);
    }

    // BlockRegistry.locationKey of the value just dropped elsewhere; that chip
    // stays blank until the new document arrives.
    property string settlingValueKey: ""

    // Outlined for a moment after BlockCanvas.revealInstruction.
    property string flashId: ""
    function flash(id) { flashId = id; flashTimer.restart(); }
    property var flashTimer: Timer { interval: 1600; onTriggered: state.flashId = "" }
}
