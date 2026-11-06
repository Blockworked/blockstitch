import QtQuick

// Keeps a dropped block or value where it landed until the host's new
// document arrives (or a timeout), so a drop doesn't flash back first.
Item {
    id: helper
    required property Item canvas
    // Hides the block or value just dropped outside the canvas until its removal lands.
    function settleTrashed() {
        if (canvas._lastDrop === "value") {
            if (canvas.valueDragState.active || !canvas.valueDragState.settleSource)
                return;
            settleValue(canvas.valueDragState.settleSource, 0, 0, true);
            return;
        }
        if (canvas.branchDragState.active)
            return;
        canvas.branchDragState.settleHidden = true;
        canvas.branchDragState.settling = true;
        armSettle();
    }
    // Keeps a palette drop's attach gap open until the new block lands.
    function settlePaletteDrop() {
        if (canvas.branchDragState.active || !canvas.branchDragState.snapValid)
            return;
        canvas.branchDragState.settleStrandId = "";
        canvas.branchDragState.settlePath = [];
        canvas.branchDragState.settling = true;
        armSettle();
    }
    function settleValue(source, x, y, hidden) {
        canvas.valueDragState.settleX = x;
        canvas.valueDragState.settleY = y;
        canvas.valueDragState.settleHidden = hidden;
        canvas.valueDragState.settling = true;
        BlockRegistry.settlingValueKey = BlockRegistry.locationKey(source);
        armSettle();
    }
    function endSettle() {
        if (canvas.valueDragState.settling) {
            canvas.valueDragState.settling = false;
            canvas.valueDragState.settleHidden = false;
            BlockRegistry.settlingValueKey = "";
        }
        if (!canvas.branchDragState.settling)
            return;
        canvas.branchDragState.settling = false;
        canvas.branchDragState.settleHidden = false;
        canvas.clearSnap();
    }
    // A settle ends once the document differs from the drop moment; other
    // state pushes (run log, debugger) reassign it unchanged and must not.
    property string _settleDoc: ""
    function docKey() {
        return JSON.stringify([canvas.strands, canvas.floatingValues]);
    }
    function armSettle() {
        _settleDoc = docKey();
        settleTimer.restart();
    }
    function settleOnDocChange() {
        if ((canvas.branchDragState.settling || canvas.valueDragState.settling) && docKey() === _settleDoc)
            return;
        endSettle();
    }
    Timer {
        id: settleTimer
        interval: 1500
        onTriggered: helper.endSettle()
    }
}
