import QtQuick

// A block (or tail of blocks) being dragged on a BlockCanvas: the pick-up,
// the attach preview it would snap into (palette drags share it), and the
// settle after a drop. SnapGeometry.qml finds where it would snap.
QtObject {
    id: drag
    required property Item canvas
    readonly property bool externalPreview: canvas.externalDragPreview
    property bool active: false
    // Carry the outline across replacement of a detached block's delegate.
    property string hoveredDropId: ""
    property point hoveredDropScene: Qt.point(0, 0)
    function rememberDropHover(sx, sy) {
        const instruction = canvas.instructionAt(canvas.strandById(drag.strandId), drag.path);
        const item = instruction ? canvas.findBlockItem(canvas.workspaceItem, instruction.id) : null;
        if (item && item.contains(item.mapFromItem(null, sx, sy))) {
            drag.hoveredDropScene = Qt.point(sx, sy);
            drag.hoveredDropId = instruction.id;
        }
    }
    property string strandId: ""
    property var path: []
    property int tailCount: 1
    property real startX: 0    // pointer, workspace coordinates, at pick-up
    property real startY: 0
    property real originX: 0   // dragged block top-left, workspace coordinates, at pick-up
    property real originY: 0
    property real dx: 0
    property real dy: 0
    // Pickup positions in document coordinates, independent of preview layout.
    property var pickupPositions: ({})
    property real sceneX: 0    // pointer, scene coordinates
    property real sceneY: 0
    property real draggedWidth: 200
    property real draggedHeight: 58
    // Silhouette of the dragged first block, so the preview is drawn
    // with the same tabs/notches/C-shape as a real block.
    property string draggedShape: "stack"
    property var draggedMouths: []
    property var draggedFlat: []
    property bool draggedIsCap: false
    // Attach preview (canvas drags and palette drags share it).
    // snapHeight is the preview block's own height; snapShiftAmt is how
    // far siblings after it move (height minus the 8px tab overlap that
    // interlocks stacked blocks); snapGrowAmt is how much a target wrap
    // mouth grows (same overlap logic, plus the empty-mouth fixed size).
    property var snapTargetY: null
    property bool snapValid: false
    property string snapTargetId: ""
    property var snapPath: []
    property real snapX: 0
    property real snapY: 0
    property real snapWidth: 200
    property real snapHeight: 58
    property real snapShiftAmt: 50
    property real snapGrowAmt: 50
    // Publish animation inputs together so a new mouth never uses the old gap size.
    property var snapLayout: null
    // Source collapse: the mouth the dragged tail is being pulled out of
    // renders as if the tail were already gone (the webapp splits the
    // strand on pickup; here the model only changes on drop). Shrink is
    // the mouth-height difference full-minus-prefix, computed from the
    // data model in beginDrag; cleared when the drag ends.
    property string sourceStrandId: ""
    property var sourceBasePath: []
    property real sourceShrink: 0
    // Set on drop, cleared once the new strands confirm the move (or on timeout).
    // An attach keeps the snap gap open while settling; a trash hides the tail.
    property bool settling: false
    property bool applyingDocument: false
    property bool settleHidden: false
    property string settleStrandId: ""
    property var settlePath: []
    property real settleDx: 0
    property real settleDy: 0
    function applySnap(best, w, h, droppedIsCap, stackHeight) {
        if (!best) {
            clearSnap();
            return;
        }
        drag.snapTargetId = best.targetId;
        drag.snapTargetY = best.targetY === undefined ? null : best.targetY;
        drag.snapPath = best.path;
        drag.snapX = best.x;
        drag.snapY = best.y;
        drag.snapWidth = w;
        drag.snapHeight = h;
        const gapHeight = stackHeight === undefined ? h : stackHeight;
        // Prepending keeps the target fixed; other insertions open a gap.
        // Empty mouths start at 26px, and cap blocks have no bottom overlap.
        drag.snapShiftAmt = drag.snapTargetY !== null ? 0 : Math.max(0, gapHeight - 8);
        if (best.empty)
            drag.snapGrowAmt = Math.max(0, Math.max(26, gapHeight - (droppedIsCap ? 0 : 8)) - 26);
        else if (best.atEnd && droppedIsCap)
            drag.snapGrowAmt = Math.max(0, gapHeight);
        else
            drag.snapGrowAmt = Math.max(0, gapHeight - 8);
        drag.snapValid = true;
        drag.snapLayout = {
            snapValid: true,
            snapTargetId: best.targetId,
            snapPath: best.path,
            snapShiftAmt: drag.snapShiftAmt,
            snapGrowAmt: drag.snapGrowAmt,
            snapWidth: w
        };
    }
    function clearSnap() {
        drag.snapLayout = null;
        drag.snapValid = false;
        drag.snapTargetY = null;
        drag.snapTargetId = "";
        drag.snapPath = [];
    }
    function prevSnapObj() {
        if (!drag.snapValid)
            return null;
        return {
            targetId: drag.snapTargetId,
            path: drag.snapPath
        };
    }
    function begin(strandId, path, tailCount, sx, sy, ox, oy, bw, bh) {
        drag.hoveredDropId = "";
        canvas.cancelValueDrag();
        canvas.clearPaletteHighlight();
        canvas.endSettle();
        const p = canvas.workspaceItem.mapFromItem(null, sx, sy);
        drag.strandId = strandId;
        drag.path = path;
        drag.tailCount = tailCount;
        drag.startX = p.x;
        drag.startY = p.y;
        drag.originX = p.x - ox;
        drag.originY = p.y - oy;
        drag.sceneX = sx;
        drag.sceneY = sy;
        drag.dx = 0;
        drag.dy = 0;
        const positions = {};
        const strand = canvas.strandById(strandId);
        const list = canvas.listFor(strand, path.slice(0, -1));
        for (const instruction of list.slice(path[path.length - 1].index)) {
            const item = canvas.findBlockItem(canvas.workspaceItem, instruction.id);
            if (item) {
                const at = item.mapToItem(canvas.workspaceItem, 0, 0);
                positions[instruction.id] = {x: at.x - canvas.originOffsetX, y: at.y - canvas.originOffsetY};
            }
        }
        drag.pickupPositions = positions;
        drag.active = true;
        drag.draggedWidth = bw || 200;
        drag.draggedHeight = bh || 58;
        const si = canvas.shapeInfoFor(canvas.instructionAt(canvas.strandById(strandId), path));
        drag.draggedShape = si.shape;
        drag.draggedMouths = si.mouths;
        drag.draggedFlat = si.flat;
        const di = canvas.instructionAt(canvas.strandById(strandId), path);
        drag.draggedIsCap = !!(di && canvas.isCapBlock(di));
        // Shrink the home mouth for the drag's duration (see sourceShrink).
        // Top-level tails have no mouth shell, so only nested paths shrink.
        drag.sourceStrandId = strandId;
        drag.sourceBasePath = canvas.copyPath(path.slice(0, path.length - 1));
        let shrink = 0;
        if (path.length > 1) {
            const strand = canvas.strandById(strandId);
            if (strand) {
                const full = canvas.listFor(strand, drag.sourceBasePath);
                const idx = path[path.length - 1].index;
                shrink = canvas.mouthHeightFor(full) - canvas.mouthHeightFor(full.slice(0, Math.max(0, idx)));
            }
        }
        drag.sourceShrink = Math.max(0, shrink);
        clearSnap();
    }
    function move(sx, sy) {
        if (!drag.active)
            return;
        const p = canvas.workspaceItem.mapFromItem(null, sx, sy);
        drag.dx = p.x - drag.startX;
        drag.dy = p.y - drag.startY;
        drag.sceneX = sx;
        drag.sceneY = sy;
        updateSnap();
    }
    function updateSnap() {
        if (!drag.active)
            return;
        const sourcePath = drag.path || [];
        if (!sourcePath.length) {
            clearSnap();
            return;
        }
        const isWhole = sourcePath.length === 1 && sourcePath[0].index === 0;
        const srcStrand = canvas.strandById(drag.strandId);
        if (isWhole && srcStrand) {
            const first = (srcStrand.instructions || [])[0];
            if (first && canvas.isHeaderType(first.type)) {
                clearSnap();
                return;
            }
        } else if (!isWhole && srcStrand) {
            const firstTail = canvas.instructionAt(srcStrand, sourcePath);
            if (firstTail && canvas.isHeaderType(firstTail.type)) {
                clearSnap();
                return;
            }
        }
        const ghostLeft = drag.originX + drag.dx;
        const ghostTop = drag.originY + drag.dy;
        const geometry = canvas.snapGeometry();
        if (!geometry.tail) {
            const tail = canvas.listFor(srcStrand, sourcePath.slice(0, -1)).slice(sourcePath[sourcePath.length - 1].index);
            let width = drag.draggedWidth;
            for (const instruction of tail) {
                const item = canvas.findBlockItem(canvas.workspaceItem, instruction.id);
                if (item)
                    width = Math.max(width, item.implicitWidth);
            }
            geometry.tail = {
                endsCap: tail.length > 0 && canvas.isCapBlock(tail[tail.length - 1]),
                height: canvas.contentHeightFor(tail),
                width: width
            };
        }
        const t = geometry.tail;
        const best = canvas.findSnap(ghostLeft, ghostTop, drag.strandId, sourcePath, isWhole, prevSnapObj(), t.height, t.endsCap);
        applySnap(best, t.width, drag.draggedHeight, t.endsCap, t.height);
    }
    // Palette (new-block) drags share the same preview: a header prefab can
    // never snap into an existing strand, anything else uses the same
    // boundaries/rules as a canvas tail (excludeId none).
    function updatePaletteSnap(ghostLeft, ghostTop, instruction, w, h) {
        canvas.endSettle();
        if (!instruction || canvas.isHeaderType(instruction.type)) {
            clearSnap();
            return;
        }
        const si = canvas.shapeInfoFor(instruction);
        drag.draggedShape = si.shape;
        drag.draggedMouths = si.mouths;
        drag.draggedFlat = si.flat;
        drag.draggedIsCap = canvas.isCapBlock(instruction);
        // The ghost's measured height wins: blockHeight only estimates blocks
        // that aren't on the canvas, and calls every plain block one row.
        drag.draggedWidth = w || 200;
        drag.draggedHeight = h > 0 ? h : (canvas.blockHeight(instruction) || 58);
        const best = canvas.findSnap(ghostLeft + canvas.originOffsetX, ghostTop + canvas.originOffsetY, null, [], false, prevSnapObj(), drag.draggedHeight, drag.draggedIsCap);
        applySnap(best, drag.draggedWidth, drag.draggedHeight, drag.draggedIsCap);
    }
    function end(sx, sy) {
        if (!drag.active)
            return;
        move(sx, sy);
        const strandId = drag.strandId, path = drag.path, tail = drag.tailCount;
        const dx = drag.dx, dy = drag.dy, ox = drag.originX, oy = drag.originY;
        const snapValid = drag.snapValid, snapTargetId = drag.snapTargetId, snapPath = canvas.copyPath(drag.snapPath || []);
        const isWhole = path.length === 1 && path[0].index === 0;
        // Keep the drag active until settling preserves the source collapse.
        drag.settleStrandId = strandId;
        drag.settlePath = path;
        drag.settleHidden = false;
        canvas._lastDrop = "block";
        if (!canvas.contains(canvas.mapFromItem(null, sx, sy))) {
            // The host calls settleTrashed() if it actually deletes the tail.
            drag.active = false;
            clearSnap();
            drag.settling = false;
            canvas.blockDragOutside(strandId, path, tail, sx, sy);
            return;
        }
        if (snapValid && snapTargetId) {
            // Attach, just like the webapp: merge the whole strand, or move
            // the tail atomically (no split-then-merge round trip). Settle on
            // the preview spot, keeping the gap open, until the merge lands.
            drag.settleDx = drag.snapX - ox;
            drag.settleDy = drag.snapY - oy;
            drag.settling = true;
            drag.active = false;
            rememberDropHover(sx, sy);
            canvas.armSettle();
            if (isWhole)
                canvas.strandsMerged(strandId, snapTargetId, snapPath, drag.snapTargetY);
            else
                canvas.tailMerged(strandId, path, snapTargetId, snapPath, drag.snapTargetY);
            return;
        }
        // Optimistic settle: keep rendering the dragged tail at the drop
        // point until the backend state confirms the move/split. Cleared in
        // onStrandsChanged or by settleTimer below.
        clearSnap();
        drag.settleDx = dx;
        drag.settleDy = dy;
        drag.settling = true;
        drag.active = false;
        rememberDropHover(sx, sy);
        canvas.armSettle();
        const strand = canvas.strandById(strandId);
        if (isWhole && strand)
            canvas.strandMoved(strandId, Math.round(strand.x + dx), Math.round(strand.y + dy));
        else
            canvas.instructionSplit(strandId, path, Math.round(ox + dx - canvas.originOffsetX), Math.round(oy + dy - canvas.originOffsetY));
    }
    function cancel() {
        drag.hoveredDropId = "";
        drag.active = false;
        drag.settling = false;
        drag.settleHidden = false;
        clearSnap();
        drag.sourceStrandId = "";
        drag.sourceBasePath = [];
        drag.sourceShrink = 0;
    }
}
