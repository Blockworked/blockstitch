import QtQuick

// Which value slot a dragged value would land in, for a BlockCanvas. Slots
// are small and the ghost covers the pointer, so a point query misses when
// the cursor sits just off a slot edge. Instead this measures the gap
// between the ghost rect and every slot rect in workspace coordinates and
// takes the nearest within dropRadius (like the blocks' snap threshold).
// Ties go to the slot holding the pointer, then the smallest (deepest
// nested), then the one whose center is nearest the ghost.
QtObject {
    required property Item canvas
    readonly property real dropRadius: 12

    // Same field or floating root, same nested index; `prefix` allows the
    // first location's path to continue past the second's.
    function sameSlot(a, b, prefix) {
        if (!a || !b || a.kind !== b.kind) return false;
        if (a.kind === "Field") {
            if (a.strand_id !== b.strand_id || a.field_id !== b.field_id) return false;
            const ai = a.index || [], bi = b.index || [];
            if (ai.length !== bi.length) return false;
            for (let i = 0; i < ai.length; ++i) {
                if (ai[i].index !== bi[i].index) return false;
                const sa = (ai[i].slot === undefined || ai[i].slot === null) ? -1 : ai[i].slot;
                const sb = (bi[i].slot === undefined || bi[i].slot === null) ? -1 : bi[i].slot;
                if (sa !== sb) return false;
            }
        } else if (a.floating_id !== b.floating_id) return false;
        const ap = a.path || [], bp = b.path || [];
        if (prefix ? ap.length < bp.length : ap.length !== bp.length) return false;
        for (let i = 0; i < bp.length; ++i) if (ap[i] !== bp[i]) return false;
        return true;
    }
    function locationsEqual(a, b) { return sameSlot(a, b, false); }
    function isDescendantOrSelf(target, source) { return sameSlot(target, source, true); }
    function isFloatingRoot(loc) { return !!loc && loc.kind === "Floating" && !(loc.path && loc.path.length); }

    function workspaceRectOf(item) {
        try {
            const tl = item.mapToItem(canvas.workspaceItem, 0, 0);
            const br = item.mapToItem(canvas.workspaceItem, item.width, item.height);
            return { x: Math.min(tl.x, br.x), y: Math.min(tl.y, br.y), w: Math.abs(br.x - tl.x), h: Math.abs(br.y - tl.y) };
        } catch (e) { return null; }
    }
    function rectGap(ax, ay, aw, ah, bx, by, bw, bh) {
        const dx = Math.max(bx - (ax + aw), ax - (bx + bw), 0);
        const dy = Math.max(by - (ay + ah), ay - (by + bh), 0);
        return Math.hypot(dx, dy);
    }
    function collectSlots(node, out) {
        if (!node || node.visible === false) return;
        const kids = node.children;
        if (kids) for (let i = 0; i < kids.length; ++i) collectSlots(kids[i], out);
        if (node.isValueChip && node.valueLocation && !isFloatingRoot(node.valueLocation)) {
            const r = workspaceRectOf(node);
            if (r) out.push({ item: node, loc: node.valueLocation, rect: r });
        }
    }
    // gx/gy/gw/gh: dragged ghost rect in workspace coordinates (gw/gh 0 =
    // unknown: pointer used as a zero-size ghost). px/py: pointer workspace
    // point, used for tie-breaks. Returns { item, loc, rect } or null.
    function resolve(gx, gy, gw, gh, px, py) {
        const slots = [];
        collectSlots(canvas.workspaceItem, slots);
        const gcx = gx + gw / 2, gcy = gy + gh / 2;
        let best = null, bestGap = 1e9, bestInside = false, bestArea = 1e9, bestCenter = 1e9;
        for (let i = 0; i < slots.length; ++i) {
            const s = slots[i], r = s.rect;
            const gap = rectGap(gx, gy, gw, gh, r.x, r.y, r.w, r.h);
            if (gap > dropRadius) continue;
            const inside = px >= r.x && px <= r.x + r.w && py >= r.y && py <= r.y + r.h;
            const area = Math.max(1, r.w) * Math.max(1, r.h);
            const cd = Math.hypot(gcx - (r.x + r.w / 2), gcy - (r.y + r.h / 2));
            let take = false;
            if (!best || gap < bestGap - 1e-6) take = true;
            else if (Math.abs(gap - bestGap) <= 1e-6) {
                if (inside && !bestInside) take = true;
                else if (inside === bestInside) {
                    if (area < bestArea - 1e-6) take = true;
                    else if (Math.abs(area - bestArea) <= 1e-6 && cd < bestCenter) take = true;
                }
            }
            if (take) { best = s; bestGap = gap; bestInside = inside; bestArea = area; bestCenter = cd; }
        }
        return best;
    }
}
