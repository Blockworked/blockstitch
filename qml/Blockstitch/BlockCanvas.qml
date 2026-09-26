import QtQuick
import QtQuick.Controls

Rectangle {
    id: root
    property var strands: []
    property var comments: []
    property var floatingValues: []
    property var variables: []
    property var lists: []
    property var dicts: []
    property var blockDefinitions: []
    property var keyCapture: null
    property bool locked: false
    // Whether the canvas menu offers "Delete all blocks".
    property bool offerClear: true
    property real zoom: 1.0
    signal strandMoved(string strandId, int x, int y)
    signal instructionSplit(string strandId, var path, int x, int y)
    signal strandsMerged(string draggedId, string targetId, var path)
    signal tailMerged(string strandId, var path, string targetId, var targetPath)
    signal blockDragOutside(string strandId, var path, int tailCount, real sceneX, real sceneY)
    signal instructionRemoved(string strandId, var path)
    signal instructionDuplicated(string strandId, var path, var instruction)
    signal instructionEdited(string strandId, var path, var instruction)
    signal runBranchRequested(string strandId, var path, string name)
    signal valueEdited(var location, string text)
    signal commentForInstructionRequested(var instruction)
    signal recordingTargetRequested(string strandId)
    signal canvasNoteRequested(int x, int y)
    signal clearRequested()
    signal commentMoved(string commentId, int x, int y)
    signal commentEdited(string commentId, string text)
    signal commentCollapseChanged(string commentId, bool collapsed)
    signal commentRemoved(string commentId)
    signal floatingValueMoved(string floatingId, int x, int y)
    signal floatingValueRemoved(string floatingId)
    signal listItemsEdited(string name, var items)
    signal listEditorStateChanged(string name, bool visible, int x, int y)
    signal dictEntriesEdited(string name, var entries)
    signal dictEditorStateChanged(string name, bool visible, int x, int y)
    signal blockMenuAction(string action, string strandId, var path, var instruction)
    signal canvasMenuAction(string action, int x, int y)
    // A parameter oval dragged out of a block header; the host runs it like a palette drag.
    signal paletteDragStarted(var spec, real sceneX, real sceneY, real offsetX, real offsetY)
    signal paletteDragMoved(real sceneX, real sceneY)
    signal paletteDragEnded(real sceneX, real sceneY)
    signal paletteDragCanceled()
    signal keyCaptureRequested(string strandId, var path)
    signal appPickerRequested(string strandId, var path, var instruction)
    signal detailsRequested(string type)
    signal valueTakeRequested(var location)
    signal valuePutRequested(var location, var value)
    signal valueCreateRequested(int x, int y, var value)
    signal valueDragOutside(var location, var value, real sceneX, real sceneY)
    color:Theme.canvas; clip:true
    // Reporter name dropdowns offer whatever this document declares.
    onListsChanged: BlockRegistry.listNames = (lists || []).map(l => l.name)
    onDictsChanged: BlockRegistry.dictNames = (dicts || []).map(d => d.name)
    // World coordinates have their origin at the center of the workspace:
    // world (0, 0) renders at workspace-local (originOffsetX, originOffsetY).
    // All model coordinates (strands, comments, values, lists) are world;
    // everything rendered inside `workspace` adds the offset, and every
    // coordinate emitted back to the backend subtracts it again.
    // The world grows symmetrically to fit its content: a fixed-size world
    // clips strands placed far from the origin (and hides them from scroll),
    // so expand it beyond the minimum whenever strands/comments/values or
    // collection editors extend past it.
    readonly property real minWorldW: 2600
    readonly property real minWorldH: 1800
    readonly property real canvasPad: 400
    // Conservative width for a strand card. Heights come from the same
    // deterministic block metrics the snap preview uses (contentHeightFor);
    // widths depend on text metrics, so estimate generously - canvasPad
    // absorbs the remainder.
    readonly property real strandEstW: 360
    readonly property real needHalfW: {
        var hw = 0;
        var sl = root.strands || [];
        for (var i = 0; i < sl.length; ++i) {
            var sx = (sl[i] && sl[i].x) || 0;
            hw = Math.max(hw, Math.abs(sx), Math.abs(sx + root.strandEstW));
        }
        var fv = root.floatingValues || [];
        for (var j = 0; j < fv.length; ++j) {
            var fx = (fv[j] && fv[j].x) || 0;
            hw = Math.max(hw, Math.abs(fx), Math.abs(fx + 160));
        }
        var cm = root.comments || [];
        for (var k = 0; k < cm.length; ++k) {
            var cx = (cm[k] && cm[k].x) || 0;
            hw = Math.max(hw, Math.abs(cx), Math.abs(cx + 220));
        }
        var li = root.lists || [];
        for (var m = 0; m < li.length; ++m) {
            var lx = (li[m] && (li[m].editor_x || 36)) || 36;
            hw = Math.max(hw, Math.abs(lx), Math.abs(lx + 300));
        }
        var di = root.dicts || [];
        for (var n = 0; n < di.length; ++n) {
            var dx = (di[n] && (di[n].editor_x || 36)) || 36;
            hw = Math.max(hw, Math.abs(dx), Math.abs(dx + 360));
        }
        return hw;
    }
    readonly property real needHalfH: {
        var hh = 0;
        var sl = root.strands || [];
        for (var i = 0; i < sl.length; ++i) {
            var sy = (sl[i] && sl[i].y) || 0;
            var sh = contentHeightFor((sl[i] && sl[i].instructions) || []);
            hh = Math.max(hh, Math.abs(sy), Math.abs(sy + sh));
        }
        var fv = root.floatingValues || [];
        for (var j = 0; j < fv.length; ++j) {
            var fy = (fv[j] && fv[j].y) || 0;
            hh = Math.max(hh, Math.abs(fy), Math.abs(fy + 40));
        }
        var cm = root.comments || [];
        for (var k = 0; k < cm.length; ++k) {
            var cy = (cm[k] && cm[k].y) || 0;
            var chh = (cm[k] && cm[k].collapsed) ? 38 : 280;
            hh = Math.max(hh, Math.abs(cy), Math.abs(cy + chh));
        }
        var li = root.lists || [];
        for (var m = 0; m < li.length; ++m) {
            var ly = (li[m] && (li[m].editor_y || 36)) || 36;
            var lh = Math.min(400, 78 + Math.max(38, ((li[m] && li[m].items) || []).length * 34));
            hh = Math.max(hh, Math.abs(ly), Math.abs(ly + lh));
        }
        var di = root.dicts || [];
        for (var n = 0; n < di.length; ++n) {
            var dy = (di[n] && (di[n].editor_y || 36)) || 36;
            var dh = Math.min(420, 78 + Math.max(38, ((di[n] && di[n].entries) || []).length * 34));
            hh = Math.max(hh, Math.abs(dy), Math.abs(dy + dh));
        }
        return hh;
    }
    readonly property real worldW: Math.max(root.minWorldW, 2 * (root.needHalfW + root.canvasPad))
    readonly property real worldH: Math.max(root.minWorldH, 2 * (root.needHalfH + root.canvasPad))
    readonly property real originOffsetX: worldW / 2
    readonly property real originOffsetY: worldH / 2
    // Growing the world moves the origin, which shifts every item's
    // workspace position by half the growth. Compensate the scroll by the
    // same amount so the view stays visually still instead of jumping.
    property real _prevWorldW: 0
    property real _prevWorldH: 0
    onWorldWChanged: {
        if (_prevWorldW > 0 && flick) {
            flick.contentX = Math.max(0, Math.min(Math.max(0, flick.contentWidth - flick.width), flick.contentX + (worldW - _prevWorldW) * root.zoom / 2));
        }
        _prevWorldW = worldW;
    }
    onWorldHChanged: {
        if (_prevWorldH > 0 && flick) {
            flick.contentY = Math.max(0, Math.min(Math.max(0, flick.contentHeight - flick.height), flick.contentY + (worldH - _prevWorldH) * root.zoom / 2));
        }
        _prevWorldH = worldH;
    }
    property bool _centered: false
    // Zoom around a viewport point (vx, vy in Flickable viewport pixels) so
    // that point stays visually still, instead of drifting to the top-left.
    function zoomAt(vx, vy, newZoom) {
        newZoom = Math.max(0.5, Math.min(1.8, newZoom));
        if (newZoom === root.zoom || !isFinite(vx) || !isFinite(vy)) return;
        const cx = flick.contentX + vx;
        const cy = flick.contentY + vy;
        const lx = cx / root.zoom;
        const ly = cy / root.zoom;
        root.zoom = newZoom;
        flick.contentX = Math.max(0, Math.min(Math.max(0, flick.contentWidth - flick.width), lx * newZoom - vx));
        flick.contentY = Math.max(0, Math.min(Math.max(0, flick.contentHeight - flick.height), ly * newZoom - vy));
    }
    function setZoom(newZoom) { zoomAt(flick.width / 2, flick.height / 2, newZoom); }
    function centerOnOrigin() {
        flick.contentX = Math.max(0, (flick.contentWidth - flick.width) / 2);
        flick.contentY = Math.max(0, (flick.contentHeight - flick.height) / 2);
    }
    function tryInitialCenter() {
        if (_centered || flick.width <= 0 || flick.height <= 0) return;
        _centered = true;
        centerOnOrigin();
    }
    function resetView() { root.zoom = 1; centerOnOrigin(); }

    // Drag session for blocks picked up on the canvas. Blocks read this to follow the pointer.
    // After a drop we keep a "settle" offset so the dragged blocks stay at
    // the drop point until the daemon round trip confirms the move. Without
    // this the transform snaps back to 0 on drop (visible revert) and the
    // block only teleports to its new position once the new state arrives.
    // snap* is the webapp-style attach preview: the nearest legal insertion
    // boundary within SNAP_THRESHOLD px, computed purely from the data model
    // (strand x/y + deterministic block heights, never live layout, so the
    // preview's own gap/shift can't feed back into the next measurement and
    // oscillate). Blocks shift/grow via transforms + effective mouth heights
    // to open a gap; the translucent snapPreview rect sits in that gap.
    // The same snap state doubles for palette drags (only one drag runs at a
    // time): updatePaletteSnap writes it while dragSession.active is false.
    QtObject {
        id: dragSession
        property bool active: false
        property string strandId: ""
        property var path: []
        property int tailCount: 1
        property real startX: 0    // pointer, workspace coordinates, at pick-up
        property real startY: 0
        property real originX: 0   // dragged block top-left, workspace coordinates, at pick-up
        property real originY: 0
        property real dx: 0
        property real dy: 0
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
        property bool snapValid: false
        property string snapTargetId: ""
        property var snapPath: []
        property real snapX: 0
        property real snapY: 0
        property real snapWidth: 200
        property real snapHeight: 58
        property real snapShiftAmt: 50
        property real snapGrowAmt: 50
        // Source collapse: the mouth the dragged tail is being pulled out of
        // renders as if the tail were already gone (the webapp splits the
        // strand on pickup; here the model only changes on drop). Shrink is
        // the mouth-height difference full-minus-prefix, computed from the
        // data model in beginDrag; cleared when the drag ends.
        property string sourceStrandId: ""
        property var sourceBasePath: []
        property real sourceShrink: 0
        // Set on drop, cleared once the new strands confirm the move (or on timeout).
        property bool settling: false
        property string settleStrandId: ""
        property var settlePath: []
        property real settleDx: 0
        property real settleDy: 0
    }
    readonly property bool dragging: dragSession.active || valueDrag.active
    // Read access to the value-drag session (active/target/targetValid).
    // Blocks already receive dragSession the same way via dragState.
    readonly property alias valueDragState: valueDrag
    readonly property real dragSceneX: dragSession.active ? dragSession.sceneX : valueDrag.sceneX
    readonly property real dragSceneY: dragSession.active ? dragSession.sceneY : valueDrag.sceneY
    // Palette live preview reads these (same object as the canvas snap above).
    readonly property bool paletteSnapValid: dragSession.snapValid
    readonly property string paletteSnapTargetId: dragSession.snapTargetId
    readonly property var paletteSnapPath: dragSession.snapPath
    // ---- value (operator) drag session ----
    // Separate from the block/strand drag above: values can only land in
    // value slots (fields) or as new floating blocks, never in a strand.
    QtObject {
        id: valueDrag
        property bool active: false
        property var sourceLocation: null
        property var sourceValue: null
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
    }
    // Highlight set by the sidebar while a fresh palette value hovers the
    // canvas (palette drags are owned by the editor, not by valueDrag).
    property var paletteValueTarget: null
    property var paletteHighlightItem: null
    function clearPaletteHighlight() {
        if (paletteHighlightItem && paletteHighlightItem.dropHighlighted !== undefined) paletteHighlightItem.dropHighlighted = false;
        paletteHighlightItem = null; paletteValueTarget = null;
    }
    function setPaletteHighlight(item, loc) {
        if (paletteHighlightItem && paletteHighlightItem !== item && paletteHighlightItem.dropHighlighted !== undefined) paletteHighlightItem.dropHighlighted = false;
        paletteHighlightItem = item;
        if (item && item.dropHighlighted !== undefined) item.dropHighlighted = true;
        paletteValueTarget = loc ? JSON.parse(JSON.stringify(loc)) : null;
    }
    // Returns the value-slot location under a scene point (for sidebar
    // palette drags), highlighting it. Pass null when the pointer leaves.
    // Targeting is proximity-based, not point-based: the nearest slot rect
    // to the dragged ghost rect within valueDropRadius wins (see
    // resolveValueSlot). The optional ghost scene rect (g-numbers) lets the
    // caller pass the dragged block's footprint; without it the pointer
    // alone is used as a zero-size ghost.
    function updatePaletteValueTarget(sx, sy) {
        if (sx === null || sx === undefined || sy === null || sy === undefined) { clearPaletteHighlight(); return null; }
        return updatePaletteValueTargetRect(sx, sy, sx, sy, sx, sy);
    }
    function updatePaletteValueTargetRect(gsx, gsy, gex, gey, sx, sy) {
        if (sx === null || sx === undefined || sy === null || sy === undefined) { clearPaletteHighlight(); return null; }
        if (!root.contains(root.mapFromItem(null, sx, sy))) { clearPaletteHighlight(); return null; }
        const tl = workspace.mapFromItem(null, gsx, gsy);
        const br = workspace.mapFromItem(null, gex, gey);
        const gx = Math.min(tl.x, br.x), gy = Math.min(tl.y, br.y);
        const gw = Math.abs(br.x - tl.x), gh = Math.abs(br.y - tl.y);
        const wp = workspace.mapFromItem(null, sx, sy);
        const found = resolveValueSlot(gx, gy, gw, gh, wp.x, wp.y);
        if (!found) { clearPaletteHighlight(); return null; }
        const loc = JSON.parse(JSON.stringify(found.loc));
        setPaletteHighlight(found.item, loc);
        return loc;
    }
    function strandById(id) { const list = root.strands || []; for (let i = 0; i < list.length; ++i) if (list[i].id === id) return list[i]; return null; }
    // ---- snap geometry (mirrors InstructionBlock row/wrap metrics) ----
    readonly property real snapThreshold: 36
    readonly property real snapSticky: 8
    function isWrapType(t) { return BlockRegistry.isWrap(t); }
    function isHeaderType(t) { return BlockRegistry.isHeader(t); }
    function isCapType(t) { return BlockRegistry.isCapType(t); }
    function isCapBlock(ins) { return BlockRegistry.isCap(ins, root.blockDefinitions); }
    function slotCountFor(ins) { return !ins ? 0 : ins.type === "BranchCallBlock" ? BlockRegistry.slotCount(ins) : Math.max(1, BlockRegistry.slotCount(ins)); }
    function bodyFor(ins, slot) { return BlockRegistry.body(ins, slot); }
    function blockHeight(ins) {
        if (!ins) return 58;
        if (!isWrapType(ins.type)) return 58;
        const n = slotCountFor(ins);
        let total = 0;
        for (let k = 0; k < n; ++k) total += mouthHeightFor(bodyFor(ins, k));
        return 50 + total + Math.max(0, n - 1) * 34 + 26 + 8;
    }
    function contentHeightFor(list) {
        if (!list || !list.length) return 0;
        let sum = 0;
        for (let i = 0; i < list.length; ++i) sum += blockHeight(list[i]);
        return sum - 8 * (list.length - 1);
    }
    function mouthHeightFor(list) {
        const ch = contentHeightFor(list);
        if (ch === 0) return 26;
        const last = list[list.length - 1];
        const cap = last && isCapBlock(last);
        return Math.max(26, ch - (cap ? 0 : 8));
    }
    // Block silhouette of an instruction for the attach preview: same shape
    // kind, mouth heights and flat (cap) ends a real InstructionBlock would
    // report, so the preview draws identical tabs/notches/C-shape.
    function shapeInfoFor(ins) {
        if (!ins) return { shape: "stack", mouths: [], flat: [] };
        const t = ins.type || "";
        if (isHeaderType(t)) return { shape: "header", mouths: [], flat: [] };
        if (isCapBlock(ins)) return { shape: "cap", mouths: [], flat: [] };
        if (!isWrapType(t)) return { shape: "stack", mouths: [], flat: [] };
        const n = slotCountFor(ins);
        const mouths = [], flat = [];
        for (let k = 0; k < n; ++k) {
            const body = bodyFor(ins, k);
            mouths.push(mouthHeightFor(body));
            flat.push(body.length > 0 && isCapBlock(body[body.length - 1]));
        }
        return { shape: "wrap", mouths: mouths, flat: flat };
    }
    function listFor(strand, basePath) {
        let list = (strand && strand.instructions) || [];
        const base = basePath || [];
        for (let i = 0; i < base.length; ++i) {
            const st = base[i] || {};
            const blk = list[st.index];
            if (!blk) return [];
            list = bodyFor(blk, st.slot || 0);
        }
        return list || [];
    }
    function instructionAt(strand, path) {
        if (!strand || !path || !path.length) return null;
        let list = strand.instructions || [];
        for (let i = 0; i < path.length; ++i) {
            const step = path[i];
            if (!list || step.index < 0 || step.index >= list.length) return null;
            const block = list[step.index];
            if (i === path.length - 1) return block;
            list = bodyFor(block, step.slot || 0);
        }
        return null;
    }
    function copyPath(p) {
        if (!p) return [];
        const out = [];
        for (let i = 0; i < p.length; ++i) {
            const s = p[i] || {};
            if (s.slot === undefined || s.slot === null) out.push({ index: s.index });
            else out.push({ index: s.index, slot: s.slot });
        }
        return out;
    }
    function stepsEqual(a, b) {
        if (a.index !== b.index) return false;
        const sa = (a.slot === undefined || a.slot === null) ? null : a.slot;
        const sb = (b.slot === undefined || b.slot === null) ? null : b.slot;
        return sa === sb;
    }
    function baseEqual(a, b) {
        const aa = a || [], bb = b || [];
        if (aa.length !== bb.length) return false;
        for (let i = 0; i < aa.length; ++i) if (!stepsEqual(aa[i], bb[i])) return false;
        return true;
    }
    function collectContainers() {
        const out = [];
        const strands = root.strands || [];
        for (let s = 0; s < strands.length; ++s) {
            const st = strands[s];
            const topList = st.instructions || [];
            const topHeights = [];
            for (let i = 0; i < topList.length; ++i) topHeights.push(blockHeight(topList[i]));
            const lx = st.x + root.originOffsetX, ly = st.y + root.originOffsetY;
            out.push({ strandId: st.id, basePath: [], x: lx, y: ly, list: topList, heights: topHeights });
            let top = ly;
            for (let j = 0; j < topList.length; ++j) {
                collectChildren(st.id, topList[j], [{ index: j }], lx, top, 1, out);
                top += topHeights[j] - 8;
            }
        }
        return out;
    }
    function collectChildren(strandId, ins, pathToBlock, blockX, blockY, depth, out) {
        if (!ins || !isWrapType(ins.type)) return;
        const n = slotCountFor(ins);
        const mouthHs = [];
        for (let k = 0; k < n; ++k) mouthHs.push(mouthHeightFor(bodyFor(ins, k)));
        let mTop = 50;
        for (let k = 0; k < n; ++k) {
            const cX = blockX + 20, cY = blockY + mTop;
            const body = bodyFor(ins, k);
            const base = copyPath(pathToBlock);
            base[base.length - 1].slot = k;
            const heights = [];
            for (let i = 0; i < body.length; ++i) heights.push(blockHeight(body[i]));
            out.push({ strandId: strandId, basePath: base, x: cX, y: cY, list: body, heights: heights });
            let childTop = cY;
            for (let ci = 0; ci < body.length; ++ci) {
                const childPath = copyPath(base);
                childPath.push({ index: ci });
                collectChildren(strandId, body[ci], childPath, cX, childTop, depth + 1, out);
                childTop += heights[ci] - 8;
            }
            mTop += mouthHs[k] + 34;
        }
    }
    function isBaseInsideTail(containerBase, srcParentBase, srcIdx) {
        const cb = containerBase || [], pb = srcParentBase || [];
        if (baseEqual(cb, pb)) return false;
        if (cb.length <= pb.length) return false;
        for (let i = 0; i < pb.length; ++i) if (!stepsEqual(cb[i], pb[i])) return false;
        const next = cb[pb.length];
        return next.index >= srcIdx;
    }
    // Stacked blocks interlock by the 8px connector tab (Column spacing
    // -8): a dropped block's top sits exactly on the old row top it replaces
    // (or 8px above the old bottom edge at the end / on the mouth origin when
    // empty), and everything after it moves by height-8, not height.
    function findSnap(ghostLeft, ghostTop, sourceId, sourcePath, isWhole, prevSnap) {
        const containers = collectContainers();
        let best = null, bestEff = 1e9;
        const srcParentBase = (sourceId && sourcePath && sourcePath.length) ? sourcePath.slice(0, sourcePath.length - 1) : null;
        const srcIdx = (sourceId && sourcePath && sourcePath.length) ? sourcePath[sourcePath.length - 1].index : -1;
        for (let ci = 0; ci < containers.length; ++ci) {
            const c = containers[ci];
            if (sourceId && isWhole && c.strandId === sourceId) continue;
            let list = c.list, heights = c.heights;
            if (sourceId && !isWhole && c.strandId === sourceId) {
                if (baseEqual(c.basePath, srcParentBase)) {
                    list = list.slice(0, Math.max(0, srcIdx));
                    heights = heights.slice(0, Math.max(0, srcIdx));
                } else if (isBaseInsideTail(c.basePath, srcParentBase, srcIdx)) {
                    continue;
                }
            }
            if (Math.abs(ghostLeft - c.x) > root.snapThreshold) continue;
            const isTop = c.basePath.length === 0;
            const headIsHeader = isTop && list.length > 0 && isHeaderType(list[0].type);
            const bounds = [];
            if (!list.length) {
                bounds.push({ index: 0, y: c.y });
            } else {
                let y = c.y;
                for (let i = 0; i < list.length; ++i) { bounds.push({ index: i, y: y }); y += heights[i] - 8; }
                bounds.push({ index: list.length, y: y });
            }
            for (let bi = 0; bi < bounds.length; ++bi) {
                const b = bounds[bi], idx = b.index;
                if (idx === 0 && headIsHeader) continue;
                if (idx > 0) {
                    const above = list[idx - 1];
                    if (!above || isCapBlock(above)) continue;
                }
                const dist = Math.abs(ghostTop - b.y);
                if (dist > root.snapThreshold) continue;
                const path = copyPath(c.basePath);
                path.push({ index: idx });
                const isCur = prevSnap && prevSnap.targetId === c.strandId && baseEqual(prevSnap.path, path);
                const eff = isCur ? Math.max(0, dist - root.snapSticky) : dist;
                if (best === null || eff < bestEff) {
                    best = { targetId: c.strandId, path: path, x: c.x, y: b.y, empty: list.length === 0, atEnd: idx === list.length };
                    bestEff = eff;
                }
            }
        }
        return best;
    }
    function applySnap(best, w, h, droppedIsCap) {
        if (!best) { clearSnap(); return; }
        dragSession.snapTargetId = best.targetId;
        dragSession.snapPath = best.path;
        dragSession.snapX = best.x;
        dragSession.snapY = best.y;
        dragSession.snapWidth = w;
        dragSession.snapHeight = h;
        // Siblings always shift by the interlocked amount; a mouth grows by
        // the same, except an empty mouth grows from its fixed 26px shell to
        // the single-block mouth, and appending a cap block keeps its full
        // height (no bottom tab to tuck).
        dragSession.snapShiftAmt = Math.max(0, h - 8);
        if (best.empty) dragSession.snapGrowAmt = Math.max(0, Math.max(26, h - (droppedIsCap ? 0 : 8)) - 26);
        else if (best.atEnd && droppedIsCap) dragSession.snapGrowAmt = Math.max(0, h);
        else dragSession.snapGrowAmt = Math.max(0, h - 8);
        dragSession.snapValid = true;
    }
    function clearSnap() {
        dragSession.snapValid = false;
        dragSession.snapTargetId = "";
        dragSession.snapPath = [];
    }
    function prevSnapObj() {
        if (!dragSession.snapValid) return null;
        return { targetId: dragSession.snapTargetId, path: dragSession.snapPath };
    }
    // Stable strand model: a plain `Repeater { model: root.strands }` over a
    // JS array destroys and recreates *every* strand delegate whenever the
    // array identity changes (which is every daemon state push, since
    // appState is re-parsed from JSON). That reads as all blocks flickering
    // at once. Syncing into a ListModel keyed by strand id instead keeps
    // untouched strands' delegates (and their nested blocks) alive: moves
    // only touch x/y roles, content changes only touch that strand.
    // NOTE: the instruction list is stored as a JSON *string* role. Storing
    // the raw JS array in a ListModel role does not round-trip: reads come
    // back as non-array sequences (no .length, Array.isArray false) and
    // setProperty with an array wipes the role, emptying every strand.
    ListModel { id: strandModel }
    function syncStrands() {
        const list = root.strands || [];
        for (let i = strandModel.count - 1; i >= 0; --i) {
            const sid = strandModel.get(i).sid;
            let alive = false;
            for (let j = 0; j < list.length; ++j) if (list[j].id === sid) { alive = true; break; }
            if (!alive) strandModel.remove(i);
        }
        for (let j = 0; j < list.length; ++j) {
            const s = list[j];
            const payload = JSON.stringify(s.instructions || []);
            let at = -1;
            for (let i = 0; i < strandModel.count; ++i) if (strandModel.get(i).sid === s.id) { at = i; break; }
            if (at === -1) {
                strandModel.insert(j, { sid: s.id, sx: s.x, sy: s.y, payload: payload });
            } else {
                if (at !== j) { strandModel.move(at, j, 1); at = j; }
                if (strandModel.get(at).sx !== s.x) strandModel.setProperty(at, "sx", s.x);
                if (strandModel.get(at).sy !== s.y) strandModel.setProperty(at, "sy", s.y);
                if (strandModel.get(at).payload !== payload)
                    strandModel.setProperty(at, "payload", payload);
            }
        }
        while (strandModel.count > list.length) strandModel.remove(strandModel.count - 1);
    }
    function beginDrag(strandId, path, tailCount, sx, sy, ox, oy, bw, bh) {
        cancelValueDrag(); clearPaletteHighlight();
        const p = workspace.mapFromItem(null, sx, sy);
        dragSession.settling = false;
        dragSession.strandId = strandId; dragSession.path = path; dragSession.tailCount = tailCount;
        dragSession.startX = p.x; dragSession.startY = p.y; dragSession.originX = p.x - ox; dragSession.originY = p.y - oy;
        dragSession.dx = 0; dragSession.dy = 0; dragSession.active = true;
        dragSession.draggedWidth = bw || 200; dragSession.draggedHeight = bh || 58;
        const si = shapeInfoFor(instructionAt(strandById(strandId), path));
        dragSession.draggedShape = si.shape; dragSession.draggedMouths = si.mouths; dragSession.draggedFlat = si.flat;
        const di = instructionAt(strandById(strandId), path);
        dragSession.draggedIsCap = !!(di && isCapBlock(di));
        // Shrink the home mouth for the drag's duration (see sourceShrink).
        // Top-level tails have no mouth shell, so only nested paths shrink.
        dragSession.sourceStrandId = strandId;
        dragSession.sourceBasePath = copyPath(path.slice(0, path.length - 1));
        let shrink = 0;
        if (path.length > 1) {
            const strand = strandById(strandId);
            if (strand) {
                const full = listFor(strand, dragSession.sourceBasePath);
                const idx = path[path.length - 1].index;
                shrink = mouthHeightFor(full) - mouthHeightFor(full.slice(0, Math.max(0, idx)));
            }
        }
        dragSession.sourceShrink = Math.max(0, shrink);
        clearSnap();
    }
    function moveDrag(sx, sy) {
        if (!dragSession.active) return;
        const p = workspace.mapFromItem(null, sx, sy);
        dragSession.dx = p.x - dragSession.startX; dragSession.dy = p.y - dragSession.startY;
        dragSession.sceneX = sx; dragSession.sceneY = sy;
        updateSnap();
    }
    function updateSnap() {
        if (!dragSession.active) return;
        const sourcePath = dragSession.path || [];
        if (!sourcePath.length) { clearSnap(); return; }
        const isWhole = sourcePath.length === 1 && sourcePath[0].index === 0;
        const srcStrand = strandById(dragSession.strandId);
        if (isWhole && srcStrand) {
            const first = (srcStrand.instructions || [])[0];
            if (first && isHeaderType(first.type)) { clearSnap(); return; }
        } else if (!isWhole && srcStrand) {
            const firstTail = instructionAt(srcStrand, sourcePath);
            if (firstTail && isHeaderType(firstTail.type)) { clearSnap(); return; }
        }
        const ghostLeft = dragSession.originX + dragSession.dx;
        const ghostTop = dragSession.originY + dragSession.dy;
        const best = findSnap(ghostLeft, ghostTop, dragSession.strandId, sourcePath, isWhole, prevSnapObj());
        applySnap(best, dragSession.draggedWidth, dragSession.draggedHeight, dragSession.draggedIsCap);
    }
    // Palette (new-block) drags share the same preview: a header prefab can
    // never snap into an existing strand, anything else uses the same
    // boundaries/rules as a canvas tail (excludeId none).
    function updatePaletteSnap(ghostLeft, ghostTop, instruction, w, h) {
        if (!instruction || isHeaderType(instruction.type)) { clearSnap(); return; }
        const si = shapeInfoFor(instruction);
        dragSession.draggedShape = si.shape; dragSession.draggedMouths = si.mouths; dragSession.draggedFlat = si.flat;
        dragSession.draggedIsCap = isCapBlock(instruction);
        dragSession.draggedWidth = w || 200; dragSession.draggedHeight = blockHeight(instruction) || h || 58;
        const best = findSnap(ghostLeft + root.originOffsetX, ghostTop + root.originOffsetY, null, [], false, prevSnapObj());
        applySnap(best, dragSession.draggedWidth, dragSession.draggedHeight, dragSession.draggedIsCap);
    }
    function endDrag(sx, sy) {
        if (!dragSession.active) return;
        moveDrag(sx, sy);
        const strandId = dragSession.strandId, path = dragSession.path, tail = dragSession.tailCount;
        const dx = dragSession.dx, dy = dragSession.dy, ox = dragSession.originX, oy = dragSession.originY;
        const snapValid = dragSession.snapValid, snapTargetId = dragSession.snapTargetId, snapPath = copyPath(dragSession.snapPath || []);
        const isWhole = path.length === 1 && path[0].index === 0;
        dragSession.active = false;
        if (!root.contains(root.mapFromItem(null, sx, sy))) { clearSnap(); dragSession.settling = false; root.blockDragOutside(strandId, path, tail, sx, sy); return; }
        if (snapValid && snapTargetId) {
            // Attach, just like the webapp: merge the whole strand, or move
            // the tail atomically (no split-then-merge round trip).
            clearSnap(); dragSession.settling = false;
            if (isWhole) root.strandsMerged(strandId, snapTargetId, snapPath);
            else root.tailMerged(strandId, path, snapTargetId, snapPath);
            return;
        }
        // Optimistic settle: keep rendering the dragged tail at the drop
        // point until the backend state confirms the move/split. Cleared in
        // onStrandsChanged or by settleTimer below.
        clearSnap();
        dragSession.settleStrandId = strandId;
        dragSession.settlePath = path;
        dragSession.settleDx = dx;
        dragSession.settleDy = dy;
        dragSession.settling = true;
        settleTimer.restart();
        const strand = strandById(strandId);
        if (isWhole && strand) root.strandMoved(strandId, Math.round(strand.x + dx), Math.round(strand.y + dy));
        else root.instructionSplit(strandId, path, Math.round(ox + dx - root.originOffsetX), Math.round(oy + dy - root.originOffsetY));
    }
    function cancelDrag() {
        dragSession.active = false; dragSession.settling = false; clearSnap();
        dragSession.sourceStrandId = ""; dragSession.sourceBasePath = []; dragSession.sourceShrink = 0;
    }
    // ---- value (operator) drag: hit-testing + session ----
    function valueLocationsEqual(a, b) {
        if (!a || !b) return false;
        if (a.kind !== b.kind) return false;
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
        } else {
            if (a.floating_id !== b.floating_id) return false;
        }
        const ap = a.path || [], bp = b.path || [];
        if (ap.length !== bp.length) return false;
        for (let i = 0; i < ap.length; ++i) if (ap[i] !== bp[i]) return false;
        return true;
    }
    function isFloatingRootLocation(loc) { return !!loc && loc.kind === "Floating" && !(loc.path && loc.path.length); }
    function isValueDescendantOrSelf(target, source) {
        if (!target || !source || target.kind !== source.kind) return false;
        if (target.kind === "Field") {
            if (target.strand_id !== source.strand_id || target.field_id !== source.field_id) return false;
            const ai = target.index || [], bi = source.index || [];
            if (ai.length !== bi.length) return false;
            for (let i = 0; i < ai.length; ++i) {
                if (ai[i].index !== bi[i].index) return false;
                const sa = (ai[i].slot === undefined || ai[i].slot === null) ? -1 : ai[i].slot;
                const sb = (bi[i].slot === undefined || bi[i].slot === null) ? -1 : bi[i].slot;
                if (sa !== sb) return false;
            }
        } else if (target.floating_id !== source.floating_id) return false;
        const tp = target.path || [], sp = source.path || [];
        if (tp.length < sp.length) return false;
        for (let i = 0; i < sp.length; ++i) if (tp[i] !== sp[i]) return false;
        return true;
    }
    // ---- value (operator) drop targeting: proximity, not point hits ----
    // Slots are small and the dragged ghost covers the pointer, so a pure
    // childAt(x, y) point query misses whenever the cursor sits just off a
    // slot edge. Instead we measure the gap between the dragged ghost rect
    // and every slot rect in workspace coordinates and take the nearest one
    // inside valueDropRadius (same idea as the block snapThreshold above).
    // Tie-breaks reproduce the old exact-hover behavior: among equidistant
    // slots the one actually containing the pointer wins, then the smallest
    // (deepest nested), then the one whose center is nearest the ghost.
    readonly property real valueDropRadius: 32
    function workspaceRectOf(item) {
        try {
            const tl = item.mapToItem(workspace, 0, 0);
            const br = item.mapToItem(workspace, item.width, item.height);
            return { x: Math.min(tl.x, br.x), y: Math.min(tl.y, br.y), w: Math.abs(br.x - tl.x), h: Math.abs(br.y - tl.y) };
        } catch (e) { return null; }
    }
    function rectGap(ax, ay, aw, ah, bx, by, bw, bh) {
        const dx = Math.max(bx - (ax + aw), ax - (bx + bw), 0);
        const dy = Math.max(by - (ay + ah), ay - (by + bh), 0);
        return Math.hypot(dx, dy);
    }
    function collectValueSlots(node, out) {
        if (!node || node.visible === false) return;
        const kids = node.children;
        if (kids) for (let i = 0; i < kids.length; ++i) collectValueSlots(kids[i], out);
        if (node.isValueChip && node.valueLocation && !isFloatingRootLocation(node.valueLocation)) {
            const r = workspaceRectOf(node);
            if (r) out.push({ item: node, loc: node.valueLocation, rect: r });
        }
    }
    // gx/gy/gw/gh: dragged ghost rect in workspace coordinates (gw/gh 0 =
    // unknown: pointer used as a zero-size ghost). px/py: pointer workspace
    // point, used for tie-breaks. Returns { item, loc, rect } or null.
    function resolveValueSlot(gx, gy, gw, gh, px, py) {
        const slots = [];
        collectValueSlots(workspace, slots);
        const gcx = gx + gw / 2, gcy = gy + gh / 2;
        let best = null, bestGap = 1e9, bestInside = false, bestArea = 1e9, bestCenter = 1e9;
        for (let i = 0; i < slots.length; ++i) {
            const s = slots[i], r = s.rect;
            const gap = rectGap(gx, gy, gw, gh, r.x, r.y, r.w, r.h);
            if (gap > valueDropRadius) continue;
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
    function findValueChip(item, x, y) {
        let child = null;
        try { child = item.childAt(x, y); } catch (e) { child = null; }
        if (!child) return item.isValueChip ? item : null;
        const cp = item.mapToItem(child, x, y);
        const deep = findValueChip(child, cp.x, cp.y);
        if (deep) return deep;
        return item.isValueChip ? item : null;
    }
    // Deepest value slot under a scene point, or null. Floating roots are
    // never slots (only their nested inputs are). `exclude` marks the drag
    // source: dropping back onto it is a no-op, dropping into its own
    // descendant is invalid - both still return the location so the caller
    // can tell "cancel" apart from "open canvas".
    function findValueTarget(sx, sy, exclude) {
        if (!root.contains(root.mapFromItem(null, sx, sy))) return null;
        const wp = workspace.mapFromItem(null, sx, sy);
        const found = resolveValueSlot(wp.x, wp.y, 0, 0, wp.x, wp.y);
        if (!found) return null;
        return JSON.parse(JSON.stringify(found.loc));
    }
    function clearValueTarget() { valueDrag.target = null; valueDrag.targetValid = false; setValueHighlight(null); }
    function setValueHighlight(item) {
        if (valueDrag.highlightItem && valueDrag.highlightItem !== item && valueDrag.highlightItem.dropHighlighted !== undefined) valueDrag.highlightItem.dropHighlighted = false;
        valueDrag.highlightItem = item;
        if (item && item.dropHighlighted !== undefined) item.dropHighlighted = true;
    }
    function setPaletteValueTarget(loc) { paletteValueTarget = loc ? JSON.parse(JSON.stringify(loc)) : null; }
    function beginValueDrag(location, value, sx, sy, ox, oy, w, h) {
        if (root.locked) return;
        cancelDrag();
        const p = workspace.mapFromItem(null, sx, sy);
        valueDrag.sourceLocation = JSON.parse(JSON.stringify(location));
        valueDrag.sourceValue = JSON.parse(JSON.stringify(value));
        valueDrag.startX = p.x; valueDrag.startY = p.y;
        valueDrag.originX = p.x - ox; valueDrag.originY = p.y - oy;
        valueDrag.dx = 0; valueDrag.dy = 0;
        valueDrag.sceneX = sx; valueDrag.sceneY = sy;
        valueDrag.draggedWidth = w || 120; valueDrag.draggedHeight = h || 32;
        valueDrag.active = true;
        clearValueTarget();
        clearPaletteHighlight();
        updateValueTarget(sx, sy);
    }
    function updateValueTarget(sx, sy) {
        if (!valueDrag.active) return;
        valueDrag.sceneX = sx; valueDrag.sceneY = sy;
        const p = workspace.mapFromItem(null, sx, sy);
        valueDrag.dx = p.x - valueDrag.startX; valueDrag.dy = p.y - valueDrag.startY;
        if (!root.contains(root.mapFromItem(null, sx, sy))) { clearValueTarget(); return; }
        // Ghost rect in workspace coordinates (draggedWidth/Height are item
        // pixels, so normalize by zoom); the drop target is the nearest slot
        // to this rect, not the item exactly under the cursor.
        const z = Math.max(0.01, root.zoom);
        const gx = valueDrag.originX + valueDrag.dx, gy = valueDrag.originY + valueDrag.dy;
        const gw = (valueDrag.draggedWidth || 0) / z, gh = (valueDrag.draggedHeight || 0) / z;
        const found = resolveValueSlot(gx, gy, gw, gh, p.x, p.y);
        if (!found) { clearValueTarget(); return; }
        const t = JSON.parse(JSON.stringify(found.loc));
        // Dropping back onto the exact source slot, or into its own
        // descendant, is never a move - keep the highlight for the
        // exact-source no-op, clear it for a true self-nesting.
        if (valueLocationsEqual(t, valueDrag.sourceLocation)) { valueDrag.target = t; valueDrag.targetValid = true; setValueHighlight(found.item); return; }
        if (isValueDescendantOrSelf(t, valueDrag.sourceLocation)) { clearValueTarget(); return; }
        valueDrag.target = t; valueDrag.targetValid = true; setValueHighlight(found.item);
    }
    function moveValueDrag(sx, sy) { updateValueTarget(sx, sy); }
    function endValueDrag(sx, sy) {
        if (!valueDrag.active) return;
        updateValueTarget(sx, sy);
        const source = valueDrag.sourceLocation ? JSON.parse(JSON.stringify(valueDrag.sourceLocation)) : null;
        const value = valueDrag.sourceValue ? JSON.parse(JSON.stringify(valueDrag.sourceValue)) : null;
        const target = valueDrag.targetValid && valueDrag.target ? JSON.parse(JSON.stringify(valueDrag.target)) : null;
        valueDrag.active = false;
        clearValueTarget();
        if (!source || !value) return;
        if (!root.contains(root.mapFromItem(null, sx, sy))) { root.valueDragOutside(source, value, sx, sy); return; }
        if (target) {
            if (valueLocationsEqual(target, source)) return; // no-op put-back
            root.valueTakeRequested(source);
            root.valuePutRequested(target, value);
            return;
        }
        // Open canvas: a whole floating block just moves; anything pulled
        // out of a field becomes a new floating block.
        if (source.kind === "Floating" && !(source.path && source.path.length)) {
            const at = workspacePoint(sx, sy);
            // Center the block under the pointer like a fresh drop.
            const fx = at ? Math.round(at.x - valueDrag.draggedWidth / 2) : 0;
            const fy = at ? Math.round(at.y - valueDrag.draggedHeight / 2) : 0;
            root.floatingValueMoved(source.floating_id, fx, fy);
            return;
        }
        const at = workspacePoint(sx, sy);
        if (!at) return;
        const fx = Math.round(at.x - valueDrag.draggedWidth / 2);
        const fy = Math.round(at.y - valueDrag.draggedHeight / 2);
        root.valueTakeRequested(source);
        root.valueCreateRequested(fx, fy, value);
    }
    function cancelValueDrag() { valueDrag.active = false; clearValueTarget(); }
    Timer { id: settleTimer; interval: 1500; onTriggered: dragSession.settling = false }
    onStrandsChanged: {
        syncStrands();
        if (dragSession.settling) dragSession.settling = false;
        if (!dragSession.active && !dragSession.settling) {
            dragSession.sourceStrandId = ""; dragSession.sourceBasePath = []; dragSession.sourceShrink = 0;
        }
    }
    Component.onCompleted: { syncStrands(); tryInitialCenter(); }
    // World coordinates for a scene point, or null when it is outside the canvas.
    function workspacePoint(sx, sy) {
        if (!root.contains(root.mapFromItem(null, sx, sy))) return null;
        const p = workspace.mapFromItem(null, sx, sy);
        return { x: p.x - root.originOffsetX, y: p.y - root.originOffsetY };
    }

    Flickable {
        id:flick; anchors.fill:parent; contentWidth:root.worldW*root.zoom; contentHeight:root.worldH*root.zoom; boundsBehavior:Flickable.StopAtBounds
        ScrollBar.horizontal:ScrollBar{}
        ScrollBar.vertical:ScrollBar{}
        onWidthChanged: root.tryInitialCenter()
        onHeightChanged: root.tryInitialCenter()
        // While a wheel gesture is active the Flickable must not run its own
        // wheel logic: it would process every event a second time (it
        // un-accepts wheel events) with a dominant-axis threshold and
        // momentum flicks, which read as straight-line priming before
        // diagonal kicked in - and slow diagonals died out entirely. The
        // WheelHandler below is then the single owner and pans 1:1.
        interactive: !wheelPan.active
        // Two-finger touchpads emit one wheel event carrying both axes; pan
        // both from that same event so diagonal stays diagonal at any speed.
        WheelHandler {
            id: wheelPan
            target: null
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            orientation: Qt.Horizontal | Qt.Vertical
            onWheel: event => {
                if (event.modifiers & Qt.ControlModifier) {
                    const delta = event.angleDelta.y !== 0 ? event.angleDelta.y : event.pixelDelta.y;
                    const factor = delta > 0 ? 1.12 : 1 / 1.12;
                    const vx = (event.x !== undefined && isFinite(event.x)) ? event.x : flick.width / 2;
                    const vy = (event.y !== undefined && isFinite(event.y)) ? event.y : flick.height / 2;
                    root.zoomAt(vx, vy, root.zoom * factor);
                    event.accepted = true;
                    return;
                }
                let dx = event.pixelDelta.x, dy = event.pixelDelta.y;
                if (dx === 0 && dy === 0) { dx = event.angleDelta.x / 2; dy = event.angleDelta.y / 2; }
                if (event.inverted) { dx = -dx; dy = -dy; }
                flick.contentX = Math.max(0, Math.min(flick.contentWidth - flick.width, flick.contentX - dx));
                flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, flick.contentY - dy));
                event.accepted = true;
            }
        }
        Item {
            id:workspace; width:root.worldW;height:root.worldH; scale:root.zoom; transformOrigin:Item.TopLeft
            // The dot grid lives in world space and moves with the content,
            // so scrolling and zooming never repaint it. Each 22px tile holds a
            // quarter dot in every corner, drawn at twice the size and scaled
            // down so zooming in stays sharp; the margin covers a zoomed-out view.
            Image {
                id:grid; z:-200
                readonly property int margin: 22 * 100
                x:-margin; y:-margin; width:2*(root.worldW+2*margin); height:2*(root.worldH+2*margin)
                scale:0.5; transformOrigin:Item.TopLeft
                fillMode:Image.Tile; smooth:true
                sourceSize: Qt.size(44, 44)
                source: "data:image/svg+xml;utf8," + encodeURIComponent("<svg xmlns='http://www.w3.org/2000/svg' width='44' height='44'><g fill='#46474d'>"
                    + "<circle cx='0' cy='0' r='2.3'/><circle cx='44' cy='0' r='2.3'/><circle cx='0' cy='44' r='2.3'/><circle cx='44' cy='44' r='2.3'/></g></svg>")
            }
            MouseArea {
                anchors.fill:parent; z:-100; acceptedButtons:Qt.LeftButton|Qt.RightButton
                onClicked: mouse => { if (mouse.button === Qt.RightButton) { canvasMenu.canvasX = Math.round(mouse.x - root.originOffsetX); canvasMenu.canvasY = Math.round(mouse.y - root.originOffsetY); canvasMenu.popup(mouse.x, mouse.y); } else flick.forceActiveFocus(); }
                BwMenu { id:canvasMenu;property int canvasX:0;property int canvasY:0
                    BwMenuItem{iconName:"message-square";text:"Add Note";onTriggered:root.canvasNoteRequested(canvasMenu.canvasX,canvasMenu.canvasY)}
                    BwMenuItem{visible:root.offerClear;iconName:"trash";danger:true;text:"Delete all blocks";onTriggered:root.clearRequested()}
                }
                Instantiator {
                    model: BlockRegistry.canvasMenu
                    delegate: BwMenuItem {
                        required property var modelData
                        iconName: modelData.icon || ""; text: modelData.text; danger: !!modelData.danger
                        onTriggered: root.canvasMenuAction(modelData.id, canvasMenu.canvasX, canvasMenu.canvasY)
                    }
                    onObjectAdded: (index, object) => canvasMenu.insertItem(index, object)
                    onObjectRemoved: (index, object) => canvasMenu.removeItem(object)
                }
            }
            Repeater {
                model: strandModel
                delegate:Column {
                    id:strand
                    required property string sid
                    required property real sx
                    required property real sy
                    required property string payload
                    required property int index
                    readonly property var blockList: JSON.parse(payload || "[]")
                    x:sx + root.originOffsetX; y:sy + root.originOffsetY; spacing:-8
                    z: (dragSession.active && dragSession.strandId === sid) || (dragSession.settling && dragSession.settleStrandId === sid) ? 100 : 0
                    InstructionList { id:strandBlocks; instructions:strand.blockList }
                    Repeater {
                        model:strandBlocks
                        delegate:InstructionBlock {
                            id:block; required property string payload; required property int index
                            instruction:JSON.parse(payload); strandId:strand.sid; path:[{index:index}]; tailCount:strandBlocks.count-index; dragState:dragSession
                            variables:root.variables; lists:root.lists; blockDefinitions:root.blockDefinitions; keyCapture:root.keyCapture; locked:root.locked
                            onRemoveRequested:(sid,p)=>root.instructionRemoved(sid,p)
                            onDuplicateRequested:(sid,p,i)=>root.instructionDuplicated(sid,p,i)
                            onCommentRequested:i=>root.commentForInstructionRequested(i)
                            onRecordingTargetRequested:sid=>root.recordingTargetRequested(sid)
                            onKeyCaptureRequested:(sid,p)=>root.keyCaptureRequested(sid,p)
                            onAppPickerRequested:(sid,p,i)=>root.appPickerRequested(sid,p,i)
                            onDetailsRequested:type=>root.detailsRequested(type)
                            onMenuActionRequested:(a,sid,p,i)=>root.blockMenuAction(a,sid,p,i)
                            onPaletteDragStarted:(sp,sx,sy,ox,oy)=>root.paletteDragStarted(sp,sx,sy,ox,oy)
                            onPaletteDragMoved:(sx,sy)=>root.paletteDragMoved(sx,sy)
                            onPaletteDragEnded:(sx,sy)=>root.paletteDragEnded(sx,sy)
                            onPaletteDragCanceled:root.paletteDragCanceled()
                            onInstructionEdited:(sid,p,i)=>root.instructionEdited(sid,p,i)
                            onRunBranchRequested:(sid,p,n)=>root.runBranchRequested(sid,p,n)
                            onValueEdited:(l,t)=>root.valueEdited(l,t)
                            onValueDragBegan:(loc,val,sx,sy,ox,oy,w,h)=>root.beginValueDrag(loc,val,sx,sy,ox,oy,w,h)
                            onValueDragMoved:(sx,sy)=>root.moveValueDrag(sx,sy)
                            onValueDragEnded:(sx,sy)=>root.endValueDrag(sx,sy)
                            onValueDragCanceled:root.cancelValueDrag()
                            onDragBegan:(sid,p,tail,sx,sy,ox,oy,bw,bh)=>root.beginDrag(sid,p,tail,sx,sy,ox,oy,bw,bh)
                            onDragMoved:(sx,sy)=>root.moveDrag(sx,sy)
                            onDragEnded:(sx,sy)=>root.endDrag(sx,sy)
                            onDragCanceled:root.cancelDrag()
                        }
                    }
                }
            }
            Repeater {
                model:root.comments||[]
                delegate:Rectangle {
                    id:commentCard; required property var modelData
                    readonly property real headerH: 38
                    readonly property real bodyMinH: 74
                    readonly property real bodyMaxH: 240
                    x:modelData.x + root.originOffsetX;y:modelData.y + root.originOffsetY;z:4;width:220
                    height:modelData.collapsed ? headerH : headerH + 1 + Math.min(bodyMaxH, Math.max(bodyMinH, bodyArea.implicitHeight + 14))
                    radius:Theme.radius;color:Theme.panelRaised;border.color:Theme.border;clip:true
                    Row {
                        id:headerRow;anchors.left:parent.left;anchors.right:parent.right;anchors.top:parent.top;anchors.leftMargin:8;anchors.rightMargin:4;height:commentCard.headerH;spacing:7
                        LucideIcon { name:"message-square";color:Theme.textDim;width:14;height:14;anchors.verticalCenter:parent.verticalCenter }
                        Text { id:noteLabel;text:"NOTE";color:Theme.textDim;font.pixelSize:10;font.weight:Font.Bold;anchors.verticalCenter:parent.verticalCenter }
                        Item { width:Math.max(0,parent.width-14-noteLabel.width-collapseBtn.width-parent.spacing*3);height:1 }
                        BwButton { id:collapseBtn;iconName:commentCard.modelData.collapsed?"chevron-down":"chevron-up";text:"";flat:true;implicitWidth:24;implicitHeight:24;anchors.verticalCenter:parent.verticalCenter;onClicked:root.commentCollapseChanged(commentCard.modelData.id,!commentCard.modelData.collapsed) }
                    }
                    Rectangle { id:noteDivider;visible:!commentCard.modelData.collapsed;anchors.left:parent.left;anchors.right:parent.right;anchors.top:headerRow.bottom;height:1;color:Theme.borderSoft }
                    TextArea {
                        id:bodyArea;visible:!commentCard.modelData.collapsed
                        anchors.left:parent.left;anchors.right:parent.right;anchors.top:noteDivider.bottom;anchors.bottom:parent.bottom
                        anchors.leftMargin:7;anchors.rightMargin:7;anchors.topMargin:7;anchors.bottomMargin:7
                        text:commentCard.modelData.text;color:Theme.text;wrapMode:TextEdit.Wrap;background:null
                        onActiveFocusChanged:if(!activeFocus&&text!==commentCard.modelData.text)root.commentEdited(commentCard.modelData.id,text)
                    }
                    DragHandler { enabled:!root.locked;target:commentCard;onActiveChanged:if(!active)root.commentMoved(commentCard.modelData.id,Math.round(commentCard.x - root.originOffsetX),Math.round(commentCard.y - root.originOffsetY)) }
                    TapHandler { acceptedButtons:Qt.RightButton;gesturePolicy:TapHandler.ReleaseWithinBounds;onTapped:commentMenu.popup() }
                    BwMenu { id:commentMenu;BwMenuItem{iconName:"trash";danger:true;text:"Delete note";onTriggered:root.commentRemoved(commentCard.modelData.id)} }
                }
            }
            Repeater {
                model:root.floatingValues||[]
                delegate:Item {
                    id:floatingItem;required property var modelData;x:modelData.x + root.originOffsetX;y:modelData.y + root.originOffsetY;z:5;width:floatingChip.implicitWidth;height:floatingChip.implicitHeight
                    ValueChip { id:floatingChip;valueData:floatingItem.modelData.value;location:({kind:"Floating",floating_id:floatingItem.modelData.id,path:[]});boxed:true;blockDefinitions:root.blockDefinitions;onEditRequested:(l,t)=>root.valueEdited(l,t);onDetailsRequested:kind=>root.detailsRequested(kind);onValueDragBegan:(loc,val,sx,sy,ox,oy,w,h)=>root.beginValueDrag(loc,val,sx,sy,ox,oy,w,h);onValueDragMoved:(sx,sy)=>root.moveValueDrag(sx,sy);onValueDragEnded:(sx,sy)=>root.endValueDrag(sx,sy);onValueDragCanceled:root.cancelValueDrag() }
                    TapHandler { acceptedButtons:Qt.RightButton;gesturePolicy:TapHandler.ReleaseWithinBounds;onTapped:floatingMenu.popup() }
                    BwMenu { id:floatingMenu;BwMenuItem{iconName:"info";text:"Details";onTriggered:root.detailsRequested(floatingItem.modelData.value.op||floatingItem.modelData.value.kind)}BwMenuItem{iconName:"trash";danger:true;text:"Delete value";onTriggered:root.floatingValueRemoved(floatingItem.modelData.id)} }
                }
            }
            Repeater {
                model:root.lists||[]
                delegate:Rectangle {
                    id:listCard;required property var modelData
                    visible:modelData.editor_visible;x:(modelData.editor_x || 36) + root.originOffsetX;y:(modelData.editor_y || 36) + root.originOffsetY;z:12
                    width:300;height:Math.min(400,78+Math.max(38,(modelData.items||[]).length*34));radius:8;color:Theme.panelRaised;border.color:Theme.border;clip:true
                    function itemFromText(value){const trimmed=value.trim();const number=Number(value);return trimmed.length&&Number.isFinite(number)?{kind:"Number",value:number}:{kind:"Text",value:value};}
                    function editItem(index,value){const next=JSON.parse(JSON.stringify(modelData.items||[]));next[index]=itemFromText(value);root.listItemsEdited(modelData.name,next);}
                    function removeItem(index){const next=JSON.parse(JSON.stringify(modelData.items||[]));next.splice(index,1);root.listItemsEdited(modelData.name,next);}
                    function addItem(){const next=JSON.parse(JSON.stringify(modelData.items||[]));next.push({kind:"Text",value:""});root.listItemsEdited(modelData.name,next);}
                    Rectangle { id:listHead;anchors.left:parent.left;anchors.right:parent.right;anchors.top:parent.top;height:38;color:"#393a3e";border.color:Theme.borderSoft
                        Row { anchors.fill:parent;anchors.margins:6;spacing:6
                            LucideIcon{name:"layers";color:Theme.textDim;width:16;height:16;anchors.verticalCenter:parent.verticalCenter}
                            Text{text:listCard.modelData.name;color:Theme.text;font.pixelSize:13;font.weight:Font.Bold;width:220;elide:Text.ElideRight;anchors.verticalCenter:parent.verticalCenter}
                            BwButton{iconName:"x";text:"";implicitWidth:25;implicitHeight:25;onClicked:root.listEditorStateChanged(listCard.modelData.name,false,Math.round(listCard.x - root.originOffsetX),Math.round(listCard.y - root.originOffsetY))}
                        }
                        DragHandler{id:listDrag;enabled:!root.locked;target:listCard;onActiveChanged:if(!active)root.listEditorStateChanged(listCard.modelData.name,true,Math.round(listCard.x - root.originOffsetX),Math.round(listCard.y - root.originOffsetY))}
                    }
                    Flickable { anchors.left:parent.left;anchors.right:parent.right;anchors.top:listHead.bottom;anchors.bottom:listFoot.top;contentHeight:listRows.implicitHeight;clip:true
                        Column { id:listRows;width:parent.width;spacing:2;padding:5
                            Text{visible:!(listCard.modelData.items||[]).length;text:"This list is empty.";color:Theme.textDim;font.pixelSize:12;padding:7}
                            Repeater{model:listCard.modelData.items||[];delegate:Row{
                                required property var modelData;required property int index;spacing:4;width:listRows.width-10;height:32
                                Text{text:String(index+1);color:Theme.textDim;font.pixelSize:11;font.weight:Font.Bold;width:22;horizontalAlignment:Text.AlignRight;anchors.verticalCenter:parent.verticalCenter}
                                BwTextField{text:String(modelData.value);color:modelData.kind==="Number"?Theme.accent:Theme.text;width:226;implicitHeight:29;font.pixelSize:12;onEditingFinished:listCard.editItem(index,text)}
                                BwButton{iconName:"x";text:"";danger:true;implicitWidth:27;implicitHeight:27;onClicked:listCard.removeItem(index)}
                            }}
                        }
                    }
                    Rectangle { id:listFoot;anchors.left:parent.left;anchors.right:parent.right;anchors.bottom:parent.bottom;height:40;color:Theme.panel;border.color:Theme.borderSoft
                        Row { anchors.fill:parent;anchors.margins:5
                            BwButton{iconName:"plus";text:"Add item";implicitHeight:29;onClicked:listCard.addItem()}
                            Item{width:Math.max(0,listFoot.width-170);height:1}
                            Text{text:String((listCard.modelData.items||[]).length)+((listCard.modelData.items||[]).length===1?" item":" items");color:Theme.textDim;font.pixelSize:11;anchors.verticalCenter:parent.verticalCenter}
                        }
                    }
                }
            }
            Repeater {
                model:root.dicts||[]
                delegate:Rectangle {
                    id:dictCard;required property var modelData
                    readonly property var entries: modelData.entries||[]
                    visible:modelData.editor_visible;x:(modelData.editor_x || 36) + root.originOffsetX;y:(modelData.editor_y || 36) + root.originOffsetY;z:12
                    width:360;height:Math.min(420,78+Math.max(38,entries.length*34));radius:8;color:Theme.panelRaised;border.color:Theme.border;clip:true
                    // A monitor edit is a literal: finite numbers stay numeric.
                    function itemFromText(value){const trimmed=value.trim();const number=Number(value);return trimmed.length&&Number.isFinite(number)?{kind:"Number",value:number}:{kind:"Text",value:value};}
                    function save(next){root.dictEntriesEdited(modelData.name,next);}
                    function copy(){return JSON.parse(JSON.stringify(entries));}
                    function editKey(index,key){const next=copy();next[index].key=key;save(next);}
                    function editValue(index,value){const next=copy();next[index].value=itemFromText(value);save(next);}
                    function removeEntry(index){const next=copy();next.splice(index,1);save(next);}
                    function addEntry(){const next=copy();next.push({key:"",value:{kind:"Text",value:""}});save(next);}
                    Rectangle { id:dictHead;anchors.left:parent.left;anchors.right:parent.right;anchors.top:parent.top;height:38;color:"#393a3e";border.color:Theme.borderSoft
                        Row { anchors.fill:parent;anchors.margins:6;spacing:6
                            LucideIcon{name:"book-key";color:Theme.textDim;width:16;height:16;anchors.verticalCenter:parent.verticalCenter}
                            Text{text:dictCard.modelData.name;color:Theme.text;font.pixelSize:13;font.weight:Font.Bold;width:280;elide:Text.ElideRight;anchors.verticalCenter:parent.verticalCenter}
                            BwButton{iconName:"x";text:"";implicitWidth:25;implicitHeight:25;onClicked:root.dictEditorStateChanged(dictCard.modelData.name,false,Math.round(dictCard.x - root.originOffsetX),Math.round(dictCard.y - root.originOffsetY))}
                        }
                        DragHandler{enabled:!root.locked;target:dictCard;onActiveChanged:if(!active)root.dictEditorStateChanged(dictCard.modelData.name,true,Math.round(dictCard.x - root.originOffsetX),Math.round(dictCard.y - root.originOffsetY))}
                    }
                    Flickable { anchors.left:parent.left;anchors.right:parent.right;anchors.top:dictHead.bottom;anchors.bottom:dictFoot.top;contentHeight:dictRows.implicitHeight;clip:true
                        Column { id:dictRows;width:parent.width;spacing:2;padding:5
                            Text{visible:!dictCard.entries.length;text:"This dict is empty.";color:Theme.textDim;font.pixelSize:12;padding:7}
                            Repeater{model:dictCard.entries;delegate:Row{
                                required property var modelData;required property int index;spacing:4;width:dictRows.width-10;height:32
                                BwTextField{text:modelData.key;placeholderText:"key";width:128;implicitHeight:29;font.pixelSize:12;onEditingFinished:if(text!==modelData.key)dictCard.editKey(index,text)}
                                LucideIcon{name:"arrow-right";color:Theme.textDim;width:13;height:13;anchors.verticalCenter:parent.verticalCenter}
                                BwTextField{text:String(modelData.value.value);placeholderText:"value";color:modelData.value.kind==="Number"?Theme.accent:Theme.text;width:162;implicitHeight:29;font.pixelSize:12;onEditingFinished:if(text!==String(modelData.value.value))dictCard.editValue(index,text)}
                                BwButton{iconName:"x";text:"";danger:true;implicitWidth:27;implicitHeight:27;onClicked:dictCard.removeEntry(index)}
                            }}
                        }
                    }
                    Rectangle { id:dictFoot;anchors.left:parent.left;anchors.right:parent.right;anchors.bottom:parent.bottom;height:40;color:Theme.panel;border.color:Theme.borderSoft
                        Row { anchors.fill:parent;anchors.margins:5
                            BwButton{iconName:"plus";text:"Add entry";implicitHeight:29;onClicked:dictCard.addEntry()}
                            Item{width:Math.max(0,dictFoot.width-180);height:1}
                            Text{text:String(dictCard.entries.length)+(dictCard.entries.length===1?" entry":" entries");color:Theme.textDim;font.pixelSize:11;anchors.verticalCenter:parent.verticalCenter}
                        }
                    }
                }
            }
            // Attach preview: the dragged first block's own silhouette (same
            // tabs/notches/C-shape as a real block, like the webapp's
            // translucent clone) exactly where the drop will land. Siblings
            // after it shift down and wrap mouths grow around it (see
            // InstructionBlock snapShift/effMouths), so the gap it sits in is
            // real layout room, not an overlay on top.
            Item {
                id: snapPreview
                visible: dragSession.snapValid
                x: dragSession.snapX; y: dragSession.snapY
                width: Math.max(120, dragSession.snapWidth); height: Math.max(20, dragSession.snapHeight)
                z: 90; enabled: false; opacity: 0.55
                BlockSurface {
                    anchors.fill: parent
                    shape: dragSession.draggedShape
                    fill: Theme.accent
                    outline: Theme.accent
                    headHeight: 50; midHeight: 34; footHeight: 26; spine: 20
                    mouthHeights: dragSession.draggedMouths
                    flatEnds: dragSession.draggedFlat
                }
            }
            // Ghost following the pointer while an existing value is dragged.
            Item {
                id: valueGhost
                visible: valueDrag.active
                x: valueDrag.originX + valueDrag.dx; y: valueDrag.originY + valueDrag.dy
                width: Math.max(40, valueDrag.draggedWidth); height: Math.max(27, valueDrag.draggedHeight)
                z: 95; enabled: false; opacity: 0.9
                ValueChip {
                    anchors.fill: parent
                    valueData: valueDrag.sourceValue; boxed: true; editable: false
                    blockDefinitions: root.blockDefinitions
                }
            }
        }
    }
    Column {
        anchors.right:parent.right;anchors.bottom:parent.bottom;anchors.margins:18;spacing:8
        BwButton { iconName:"zoom-in";text:"";implicitWidth:40;implicitHeight:40;radius:20;onClicked:root.setZoom(root.zoom+.1) }
        BwButton { iconName:"zoom-out";text:"";implicitWidth:40;implicitHeight:40;radius:20;onClicked:root.setZoom(root.zoom-.1) }
        BwButton { iconName:"rotate-ccw";text:"";implicitWidth:40;implicitHeight:40;radius:20;onClicked:root.resetView() }
    }
}
