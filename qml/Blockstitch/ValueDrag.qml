import QtQuick

// A value (reporter) being dragged on a BlockCanvas: where it came from, the
// slot it would drop into, and the settle after a drop.
QtObject {
    id: drag
    required property Item canvas
    property bool active: false
    property var sourceLocation: null
    property var sourceValue: null
    property string sourceOrigin: ""
    property real startX: 0
    property real startY: 0
    property real originX: 0
    property real originY: 0
    property real dx: 0
    property real dy: 0
    property real sceneX: 0
    property real sceneY: 0
    property real draggedWidth: 120
    property real draggedHeight: 32
    property var target: null
    property bool targetValid: false
    property var highlightItem: null
    // After a drop the ghost stays at the landing spot (or hidden, for a
    // trash) and the source stays blank until the new state arrives.
    property bool settling: false
    property bool settleHidden: false
    property real settleX: 0
    property real settleY: 0
    property var settleSource: null

    function clearTarget() {
        drag.target = null;
        drag.targetValid = false;
        setHighlight(null);
    }
    function setHighlight(item) {
        if (drag.highlightItem && drag.highlightItem !== item && drag.highlightItem.dropHighlighted !== undefined)
            drag.highlightItem.dropHighlighted = false;
        drag.highlightItem = item;
        if (item && item.dropHighlighted !== undefined)
            item.dropHighlighted = true;
    }
    function begin(location, value, sx, sy, ox, oy, w, h) {
        if (canvas.locked)
            return;
        canvas.cancelDrag();
        canvas.endSettle();
        const p = canvas.workspaceItem.mapFromItem(null, sx, sy);
        drag.sourceLocation = JSON.parse(JSON.stringify(location));
        drag.sourceValue = JSON.parse(JSON.stringify(value));
        drag.sourceOrigin = canvas.parameterOrigin(location);
        drag.startX = p.x;
        drag.startY = p.y;
        drag.originX = p.x - ox;
        drag.originY = p.y - oy;
        drag.dx = 0;
        drag.dy = 0;
        drag.sceneX = sx;
        drag.sceneY = sy;
        drag.draggedWidth = w || 120;
        drag.draggedHeight = h || 32;
        drag.active = true;
        clearTarget();
        canvas.clearPaletteHighlight();
        update(sx, sy);
    }
    function update(sx, sy) {
        if (!drag.active)
            return;
        drag.sceneX = sx;
        drag.sceneY = sy;
        const p = canvas.workspaceItem.mapFromItem(null, sx, sy);
        drag.dx = p.x - drag.startX;
        drag.dy = p.y - drag.startY;
        if (!canvas.contains(canvas.mapFromItem(null, sx, sy))) {
            clearTarget();
            return;
        }
        // Ghost rect in workspace coordinates (draggedWidth/Height are item
        // pixels, so normalize by zoom); the drop target is the nearest slot
        // to this rect, not the item exactly under the cursor.
        const z = Math.max(0.01, canvas.zoom);
        const gx = drag.originX + drag.dx, gy = drag.originY + drag.dy;
        const gw = (drag.draggedWidth || 0) / z, gh = (drag.draggedHeight || 0) / z;
        const found = canvas.resolveValueSlot(gx, gy, gw, gh, p.x, p.y);
        if (!found) {
            clearTarget();
            return;
        }
        const t = JSON.parse(JSON.stringify(found.loc));
        // Dropping back onto the exact source slot, or into its own
        // descendant, is never a move - keep the highlight for the
        // exact-source no-op, clear it for a true self-nesting.
        if (canvas.valueLocationsEqual(t, drag.sourceLocation)) {
            drag.target = t;
            drag.targetValid = true;
            setHighlight(found.item);
            return;
        }
        if (canvas.isValueDescendantOrSelf(t, drag.sourceLocation)) {
            clearTarget();
            return;
        }
        drag.target = t;
        drag.targetValid = true;
        setHighlight(found.item);
    }
    function end(sx, sy) {
        if (!drag.active)
            return;
        update(sx, sy);
        const source = drag.sourceLocation ? JSON.parse(JSON.stringify(drag.sourceLocation)) : null;
        const value = drag.sourceValue ? JSON.parse(JSON.stringify(drag.sourceValue)) : null;
        const target = drag.targetValid && drag.target ? JSON.parse(JSON.stringify(drag.target)) : null;
        const targetItem = drag.highlightItem;
        const gx = drag.originX + drag.dx, gy = drag.originY + drag.dy;
        drag.active = false;
        clearTarget();
        canvas._lastDrop = "value";
        drag.settleSource = source;
        if (!source || !value)
            return;
        if (!canvas.contains(canvas.mapFromItem(null, sx, sy))) {
            canvas.valueDragOutside(source, value, sx, sy);
            return;
        }
        if (target) {
            if (canvas.valueLocationsEqual(target, source))
                return; // no-op put-back
            const p = targetItem ? canvas.workspaceItem.mapFromItem(targetItem, 0, 0) : Qt.point(gx, gy);
            canvas.settleValue(source, p.x, p.y, false);
            canvas.valueMoveRequested(source, target, 0, 0, "");
            return;
        }
        // Open canvas: lands where the ghost is. A whole floating block just
        // moves; anything pulled out of a field becomes a new floating block.
        const fx = Math.round(gx - canvas.originOffsetX), fy = Math.round(gy - canvas.originOffsetY);
        canvas.settleValue(source, gx, gy, false);
        if (source.kind === "Floating" && !(source.path && source.path.length))
            canvas.floatingValueMoved(source.floating_id, fx, fy);
        else
            canvas.valueMoveRequested(source, null, fx, fy, drag.sourceOrigin);
    }
    function cancel() {
        drag.active = false;
        clearTarget();
    }
}
