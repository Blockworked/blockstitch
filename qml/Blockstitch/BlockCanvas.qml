import QtQuick
import QtQuick.Controls
import QtQuick.Shapes

Rectangle {
    id: root
    readonly property bool isBlockCanvas: true
    readonly property var branchDragState: dragSession
    readonly property alias workspaceItem: workspace
    Accessible.role: Accessible.Grouping
    Accessible.name: qsTr("Block canvas")
    property var strands: []
    // A strand the host marks with a badge (BlockRegistry.strandMark).
    property string markedStrandId: ""
    property var comments: []
    property Component textMenu: null
    property var floatingValues: []
    property var variables: []
    property var lists: []
    property var pendingListFocus: null
    property var dicts: []
    property var pendingDictFocus: null
    property var blockDefinitions: []
    property var keyCapture: null
    property bool locked: false
    // Whether the canvas menu offers "Delete all blocks".
    property bool offerClear: true
    property string clearText: qsTr("Delete all blocks")
    property string clearIcon: "trash"
    property bool canPaste: false
    // Run and debug marks from the host: instruction ids its strands are on,
    // with a breakpoint, or paused at, and id -> message markers (an error
    // from the last run, say). Clicking a breakpoint dot or a marker emits
    // breakpointClicked / markClicked.
    property var runningIds: []
    property var breakpointIds: []
    property var pausedIds: []
    property var blockMarks: ({})
    signal markClicked(string instructionId)
    signal breakpointClicked(string instructionId)
    readonly property CanvasState canvasState: CanvasState {
        runningIds: root.runningIds
        breakpointIds: root.breakpointIds
        pausedIds: root.pausedIds
        blockMarks: root.blockMarks
        commentedIds: (root.comments || []).filter(c => c.attached_to).map(c => c.attached_to)
        onMarkClicked: id => root.markClicked(id)
        onBreakpointClicked: id => root.breakpointClicked(id)
    }
    property real zoom: 1.0
    signal strandMoved(string strandId, int x, int y)
    signal instructionSplit(string strandId, var path, int x, int y)
    signal strandsMerged(string draggedId, string targetId, var path, var targetY)
    signal tailMerged(string strandId, var path, string targetId, var targetPath, var targetY)
    signal blockDragOutside(string strandId, var path, int tailCount, real sceneX, real sceneY)
    signal instructionRemoved(string strandId, var path)
    signal instructionDuplicated(string strandId, var path, var instruction)
    signal instructionEdited(string strandId, var path, var instruction)
    signal runBranchRequested(string strandId, var path, string name)
    signal valueEdited(var location, string text)
    signal commentForInstructionRequested(var instruction)
    signal canvasNoteRequested(int x, int y)
    signal clearRequested
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
    signal paletteDragCanceled
    signal keyCaptureRequested(string strandId, var path)
    signal pieceActionRequested(string action, string strandId, var path, var instruction)
    signal detailsRequested(string type)
    signal valueTakeRequested(var location)
    signal valuePutRequested(var location, var value)
    signal valueCreateRequested(int x, int y, var value, string originBlockId)
    // Moves a value in one edit: into `to`, or parked at x/y when `to` is null.
    signal valueMoveRequested(var from, var to, int x, int y, string originBlockId)
    signal valueDragOutside(var location, var value, real sceneX, real sceneY)
    color: Theme.canvas
    clip: true
    // Reporter name dropdowns offer whatever this document declares.
    onListsChanged: {
        BlockRegistry.listNames = (lists || []).map(l => l.name);
        syncListEditors();
    }
    // Keep the popup and its pointer grab alive across host state updates.
    ListModel {
        id: listEditorModel
    }
    ListModel {
        id: dictEditorModel
    }
    function syncListEditors() {
        syncCollectionEditors(listEditorModel, root.lists || []);
    }
    function syncDictEditors() {
        syncCollectionEditors(dictEditorModel, root.dicts || []);
    }
    function syncCollectionEditors(model, list) {
        for (let i = model.count - 1; i >= 0; --i) {
            if (!list.some(entry => entry.name === model.get(i).editorName))
                model.remove(i);
        }
        for (let i = 0; i < list.length; ++i) {
            const entry = list[i];
            const data = {
                editorName: entry.name,
                editorX: entry.editor_x ?? 36,
                editorY: entry.editor_y ?? 36,
                payload: JSON.stringify(entry)
            };
            let at = -1;
            for (let j = 0; j < model.count; ++j)
                if (model.get(j).editorName === entry.name) {
                    at = j;
                    break;
                }
            if (at < 0)
                model.insert(i, data);
            else {
                if (at !== i)
                    model.move(at, i, 1);
                for (const role of ["editorX", "editorY", "payload"])
                    if (model.get(i)[role] !== data[role])
                        model.setProperty(i, role, data[role]);
            }
        }
    }
    onVariablesChanged: BlockRegistry.variableNames = variables || []
    onDictsChanged: {
        BlockRegistry.dictNames = (dicts || []).map(d => d.name);
        syncDictEditors();
    }
    // World coordinates have their origin at the center of the workspace:
    // world (0, 0) renders at workspace-local (originOffsetX, originOffsetY).
    // Strands, comments and floating values use world coordinates;
    // everything rendered inside `workspace` adds the offset, and every
    // coordinate emitted back to the backend subtracts it again.
    // The world grows to fit its content: a fixed-size world clips strands
    // placed far from the origin (and hides them from scroll), so expand it
    // beyond the minimum whenever strands/comments/values extend past it.
    readonly property real minWorldW: 2600
    readonly property real minWorldH: 1800
    // Horizontal gets extra trailing room so the canvas extends a good
    // distance past a strand's right edge (comfortable panning / drop
    // space), while vertical keeps the tighter bound.
    readonly property real canvasPadX: 800
    readonly property real canvasPadY: 400
    // Fallback width until a strand delegate reports its real implicitWidth.
    readonly property real strandEstW: 360
    // Live measured strand widths (sid -> implicitWidth), reported by the
    // strand delegates below. Reassigned as a whole on every report so
    // needX re-evaluates. Without this the world is sized from a fixed
    // estimate, so wide strands eat the padding and the canvas ends right
    // at (or inside) their right edge.
    property var _strandWidths: ({})
    function noteStrandWidth(sid, w) {
        if (!sid || !(w > 0))
            return;
        if (_strandWidths[sid] === w)
            return;
        var m = Object.assign({}, _strandWidths);
        m[sid] = w;
        _strandWidths = m;
    }
    function clearStrandWidth(sid) {
        if (!sid || !(_strandWidths && (sid in _strandWidths)))
            return;
        var m = Object.assign({}, _strandWidths);
        delete m[sid];
        _strandWidths = m;
    }
    function strandWidthFor(sid) {
        var w = _strandWidths && _strandWidths[sid];
        return (w > 0) ? w : root.strandEstW;
    }
    // How far content reaches left of / right of the origin.
    readonly property var needX: {
        var lo = 0, hi = 0;
        var sw = root._strandWidths;
        var sl = root.strands || [];
        for (var i = 0; i < sl.length; ++i) {
            var sx = (sl[i] && sl[i].x) || 0;
            var w = (sw && sw[sl[i].id] > 0) ? sw[sl[i].id] : root.strandEstW;
            lo = Math.min(lo, sx);
            hi = Math.max(hi, sx + w);
        }
        var fv = root.floatingValues || [];
        for (var j = 0; j < fv.length; ++j) {
            var fx = (fv[j] && fv[j].x) || 0;
            lo = Math.min(lo, fx);
            hi = Math.max(hi, fx + 160);
        }
        var cm = root.comments || [];
        for (var k = 0; k < cm.length; ++k) {
            var cx = (cm[k] && cm[k].x) || 0;
            lo = Math.min(lo, cx);
            hi = Math.max(hi, cx + 220);
        }
        return {
            before: -lo,
            after: hi
        };
    }
    // Use measured strand heights so layout changes do not search every control.
    property var _strandHeights: ({})
    function noteStrandHeight(sid, h) {
        if (!sid || !(h >= 0) || _strandHeights[sid] === h)
            return;
        const heights = Object.assign({}, _strandHeights);
        heights[sid] = h;
        _strandHeights = heights;
    }
    function clearStrandHeight(sid) {
        if (!(sid in _strandHeights))
            return;
        const heights = Object.assign({}, _strandHeights);
        delete heights[sid];
        _strandHeights = heights;
    }
    readonly property var needY: {
        var lo = 0, hi = 0;
        var sl = root.strands || [];
        for (var i = 0; i < sl.length; ++i) {
            var sy = (sl[i] && sl[i].y) || 0;
            var sh = root._strandHeights[sl[i].id] ?? 58;
            lo = Math.min(lo, sy);
            hi = Math.max(hi, sy + sh);
        }
        var fv = root.floatingValues || [];
        for (var j = 0; j < fv.length; ++j) {
            var fy = (fv[j] && fv[j].y) || 0;
            lo = Math.min(lo, fy);
            hi = Math.max(hi, fy + 40);
        }
        var cm = root.comments || [];
        for (var k = 0; k < cm.length; ++k) {
            var cy = (cm[k] && cm[k].y) || 0;
            var chh = (cm[k] && cm[k].collapsed) ? 38 : 280;
            lo = Math.min(lo, cy);
            hi = Math.max(hi, cy + chh);
        }
        return {
            before: -lo,
            after: hi
        };
    }
    readonly property real needRight: needX.after
    readonly property real needBottom: needY.after
    // Each side grows on its own. Growing right or down leaves the origin
    // where it is; moving it shifts every item, which Qt pays for per item.
    readonly property real worldLeft: Math.max(root.minWorldW / 2, root.needX.before + root.canvasPadX)
    readonly property real worldTop: Math.max(root.minWorldH / 2, root.needY.before + root.canvasPadY)
    readonly property real worldW: worldLeft + Math.max(root.minWorldW / 2, root.needX.after + root.canvasPadX)
    readonly property real worldH: worldTop + Math.max(root.minWorldH / 2, root.needY.after + root.canvasPadY)
    readonly property real originOffsetX: worldLeft
    readonly property real originOffsetY: worldTop
    // Growing left or up moves the origin, which shifts every item's
    // workspace position. Compensate the scroll by the same amount so the
    // view stays visually still instead of jumping.
    property real _prevWorldLeft: 0
    property real _prevWorldTop: 0
    property var _resizeViewX: null
    property var _resizeViewY: null
    property real _resizeScrollX: NaN
    property real _resizeScrollY: NaN
    property real _resizeSpeedX: 0
    property real _resizeSpeedY: 0
    function pauseResizeScroll() {
        // Keep the glide's speed so it carries on without a hitch.
        if (canvasScroll.glidingX) {
            _resizeScrollX = canvasScroll.targetX;
            _resizeSpeedX = canvasScroll.velocityX;
        }
        if (canvasScroll.glidingY) {
            _resizeScrollY = canvasScroll.targetY;
            _resizeSpeedY = canvasScroll.velocityY;
        }
        canvasScroll.stop();
    }
    // Apply after Flickable updates its bounds, including automatic clamping.
    function applyWorldResize() {
        if (_resizeViewX !== null) {
            flick.contentX = Math.max(0, Math.min(Math.max(0, flick.contentWidth - flick.width), _resizeViewX));
            _resizeViewX = null;
        }
        if (_resizeViewY !== null) {
            flick.contentY = Math.max(0, Math.min(Math.max(0, flick.contentHeight - flick.height), _resizeViewY));
            _resizeViewY = null;
        }
        const tx = _resizeScrollX, ty = _resizeScrollY;
        _resizeScrollX = NaN;
        _resizeScrollY = NaN;
        const vx = _resizeSpeedX, vy = _resizeSpeedY;
        _resizeSpeedX = 0;
        _resizeSpeedY = 0;
        if (!isNaN(tx) || !isNaN(ty))
            canvasScroll.scrollTo(tx, ty, true, vx, vy);
    }
    // Drag anchors share workspace coordinates with the moving world origin.
    function shiftDragAnchors(dx, dy) {
        if (dragSession.active) {
            dragSession.startX += dx;
            dragSession.startY += dy;
            dragSession.originX += dx;
            dragSession.originY += dy;
        }
        if (dragSession.snapValid) {
            dragSession.snapX += dx;
            dragSession.snapY += dy;
        }
        if (valueDrag.active) {
            valueDrag.startX += dx;
            valueDrag.startY += dy;
            valueDrag.originX += dx;
            valueDrag.originY += dy;
        }
        if (valueDrag.settling) {
            valueDrag.settleX += dx;
            valueDrag.settleY += dy;
        }
    }
    onWorldLeftChanged: {
        const shift = worldLeft - _prevWorldLeft;
        if (_prevWorldLeft > 0 && flick && shift !== 0) {
            shiftDragAnchors(shift, 0);
            pauseResizeScroll();
            _resizeScrollX += shift * root.zoom;
            zoomer.anchorX += shift;
            _resizeViewX = (_resizeViewX ?? flick.contentX) + shift * root.zoom;
            Qt.callLater(root.applyWorldResize);
        }
        _prevWorldLeft = worldLeft;
    }
    onWorldTopChanged: {
        const shift = worldTop - _prevWorldTop;
        if (_prevWorldTop > 0 && flick && shift !== 0) {
            shiftDragAnchors(0, shift);
            pauseResizeScroll();
            _resizeScrollY += shift * root.zoom;
            zoomer.anchorY += shift;
            _resizeViewY = (_resizeViewY ?? flick.contentY) + shift * root.zoom;
            Qt.callLater(root.applyWorldResize);
        }
        _prevWorldTop = worldTop;
    }
    property bool _centered: false
    CanvasZoom {
        id: zoomer
        canvas: root
        flick: flick
        scroll: canvasScroll
    }
    // Zoom around a viewport point (vx, vy in Flickable viewport pixels) so
    // that point stays visually still. With smooth, the zoom glides there
    // (over ms if given).
    function zoomAt(vx, vy, newZoom, smooth, ms) {
        zoomer.zoomAt(vx, vy, newZoom, smooth, ms);
    }
    // Scales the zoom by factor around a viewport point. Steps that land
    // mid-glide build on the glide's target, like wheel scrolling does.
    function zoomBy(vx, vy, factor, smooth, ms) {
        zoomAt(vx, vy, zoomer.target * factor, smooth, ms);
    }
    // Touchpad zoom (pinch, Ctrl+two-finger scroll) arrives as a stream of
    // small steps; a short glide per step smooths it without trailing behind.
    readonly property int _touchpadZoomMs: 80
    // Zoom around the middle of the view, by step (the zoom buttons).
    function stepZoom(step) {
        zoomAt(flick.width / 2, flick.height / 2, zoomer.target + step, true);
    }
    function setZoom(newZoom) {
        zoomAt(flick.width / 2, flick.height / 2, newZoom);
    }
    function centerOnOrigin() {
        zoomer.stop();
        canvasScroll.stop();
        flick.contentX = Math.max(0, Math.min(flick.contentWidth - flick.width, root.originOffsetX * root.zoom - flick.width / 2));
        flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, root.originOffsetY * root.zoom - flick.height / 2));
    }
    function tryInitialCenter() {
        if (_centered || flick.width <= 0 || flick.height <= 0)
            return;
        _centered = true;
        centerOnOrigin();
    }
    // Glides back to 100% with the workspace origin in the middle of the view.
    function resetView() {
        zoomer.zoomTo(root.originOffsetX, root.originOffsetY, flick.width / 2, flick.height / 2, 1, true);
    }
    // The block showing instruction `id` under `item`. Every non-palette
    // InstructionBlock indexes itself in BlockRegistry, so this checks a few
    // candidates' ancestry instead of walking the whole tree.
    function findBlockItem(item, id) {
        const indexed = BlockRegistry.blockItems[id];
        if (indexed) {
            let match = null, matches = 0;
            for (const k of indexed) {
                if (k.paletteMode !== false || !k.instruction || k.instruction.id !== id)
                    continue;
                let node = k.parent;
                while (node && node !== item)
                    node = node.parent;
                if (!node)
                    continue;
                match = k;
                if (++matches > 1)
                    break;
            }
            // Two live blocks with one id: the walk's tree order decides.
            if (matches === 1)
                return match;
            if (matches > 1)
                return walkBlockItem(item, id);
        }
        return null;
    }
    function walkBlockItem(item, id) {
        const kids = item.children || [];
        for (let i = 0; i < kids.length; ++i) {
            const k = kids[i];
            if (k.instruction && k.paletteMode === false && k.instruction.id === id)
                return k;
            const deep = walkBlockItem(k, id);
            if (deep)
                return deep;
        }
        return null;
    }
    function commentAnchor(item) {
        if (!item)
            return Qt.point(0, 0);
        // Track ancestor moves and drag transforms, including nested blocks.
        let node = item;
        let x = item.width / 2;
        let y = Math.min(item.height, item.headHeight) / 2;
        while (node && node !== workspace) {
            x += node.x;
            y += node.y;
            if (node.dragOffsetX !== undefined) {
                x += node.dragOffsetX;
                y += node.dragOffsetY + node.displayedSnapShift;
            }
            node = node.parent;
        }
        return Qt.point(x, y);
    }
    // Strands far from the view build their blocks later (see StrandBuilder.qml).
    property bool lazyStrands: true
    property int builtStrands: 0
    readonly property real _viewMargin: 400
    function nearView(x, y, w, h) {
        const z = root.zoom || 1;
        const left = flick.contentX / z - _viewMargin, top = flick.contentY / z - _viewMargin;
        const right = (flick.contentX + flick.width) / z + _viewMargin, bottom = (flick.contentY + flick.height) / z + _viewMargin;
        return x < right && x + w > left && y < bottom && y + h > top;
    }
    // Blocks well outside this band are hidden, so a frame doesn't draw a
    // whole long strand. The band moves in steps, not with every scroll.
    property bool cullBlocks: true
    property real cullLeft: -1e9
    property real cullTop: -1e9
    property real cullRight: 1e9
    property real cullBottom: 1e9
    property bool _cullSet: false
    function updateCull() {
        const z = root.zoom || 1;
        const w = flick.width / z, h = flick.height / z;
        if (w <= 0 || h <= 0)
            return;
        const left = flick.contentX / z, top = flick.contentY / z, right = left + w, bottom = top + h;
        const mx = Math.max(400, w / 2), my = Math.max(400, h / 2);
        if (_cullSet && left - mx / 2 >= cullLeft && right + mx / 2 <= cullRight && top - my / 2 >= cullTop && bottom + my / 2 <= cullBottom)
            return;
        _cullSet = true;
        cullLeft = left - mx;
        cullRight = right + mx;
        cullTop = top - my;
        cullBottom = bottom + my;
    }
    Connections {
        target: flick
        function onContentXChanged() {
            root.updateCull();
        }
        function onContentYChanged() {
            root.updateCull();
        }
        function onWidthChanged() {
            root.updateCull();
        }
        function onHeightChanged() {
            root.updateCull();
        }
    }
    onZoomChanged: updateCull()
    onOriginOffsetXChanged: updateCull()
    onOriginOffsetYChanged: updateCull()
    function inCullBand(x, y, w, h) {
        return !cullBlocks || (x < cullRight && x + w > cullLeft && y < cullBottom && y + h > cullTop);
    }
    StrandBuilder {
        id: builder
        canvas: root
        flick: flick
        strands: strandRepeater
    }
    function buildStrand(strand) { builder.buildStrand(strand); }
    function startStrandBuilder() { builder.start(); }
    function bulkInsert(strand, repeater, at, n) { builder.bulkInsert(strand, repeater, at, n); }
    function slotCreated(strand, slot, estH) { builder.slotCreated(strand, slot, estH); }
    // How many strands still wait for their blocks.
    function pendingStrands() { return builder.pendingStrands(); }
    // Strands and top-level blocks still waiting to be built.
    function pendingBuilds() { return builder.pendingBuilds(); }
    // Builds every strand now, for callers that need each block to exist.
    function buildAllStrands() { builder.buildAllStrands(); }
    // Scrolls the block with this instruction id into view and outlines it.
    function revealInstruction(id) {
        if (!findBlockItem(workspace, id))
            buildAllStrands();
        const item = findBlockItem(workspace, id);
        if (!item)
            return false;
        const p = item.mapToItem(workspace, 0, 0);
        const cx = (p.x + Math.min(item.width, flick.width / root.zoom) / 2) * root.zoom;
        const cy = (p.y + Math.min(item.height, 60) / 2) * root.zoom;
        zoomer.stop();
        canvasScroll.scrollTo(cx - flick.width / 2, cy - flick.height / 2, true);
        canvasState.flash(id);
        return true;
    }

    // Drag session for blocks picked up on the canvas. Blocks read this to follow the pointer.
    // After a drop we keep a "settle" offset so the dragged blocks stay at
    // the drop point until the host's next state confirms the move. Without
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
    BlockDrag {
        id: dragSession
        canvas: root
    }
    // A new delegate may wait a frame for Qt's hover event after a drop.
    // Retain its outline until the pointer actually moves or leaves the canvas.
    HoverHandler {
        onPointChanged: {
            if (dragSession.hoveredDropId && Math.hypot(point.scenePosition.x - dragSession.hoveredDropScene.x,
                    point.scenePosition.y - dragSession.hoveredDropScene.y) > 0.5)
                dragSession.hoveredDropId = "";
        }
        onHoveredChanged: if (!hovered) dragSession.hoveredDropId = ""
    }
    // A host overlay can draw active drags outside the clipped canvas.
    property bool externalDragPreview: false
    readonly property bool dragging: dragSession.active || valueDrag.active
    // Read access to the value-drag session (active/target/targetValid).
    // Blocks already receive dragSession the same way via dragState.
    readonly property alias valueDragState: valueDrag
    readonly property real dragSceneX: dragSession.active ? dragSession.sceneX : valueDrag.sceneX
    readonly property real dragSceneY: dragSession.active ? dragSession.sceneY : valueDrag.sceneY
    // Palette live preview reads these (same object as the canvas snap above).
    // What an overlay needs to redraw the dragged item outside this clipped canvas (scene coords).
    readonly property bool dragIsValue: valueDrag.active
    readonly property real dragGhostX: dragSession.active ? dragSession.sceneX - (dragSession.startX - dragSession.originX) * zoom : valueDrag.sceneX - (valueDrag.startX - valueDrag.originX) * zoom
    readonly property real dragGhostY: dragSession.active ? dragSession.sceneY - (dragSession.startY - dragSession.originY) * zoom : valueDrag.sceneY - (valueDrag.startY - valueDrag.originY) * zoom
    readonly property string dragValueOrigin: valueDrag.sourceOrigin
    readonly property var dragValue: valueDrag.sourceValue
    readonly property var dragInstructions: {
        if (!dragSession.active)
            return [];
        const strand = strandById(dragSession.strandId), p = dragSession.path || [];
        if (!strand || !p.length)
            return [];
        const list = listFor(strand, copyPath(p.slice(0, p.length - 1)));
        const idx = p[p.length - 1].index;
        return (list || []).slice(idx, idx + dragSession.tailCount);
    }
    readonly property bool paletteSnapValid: dragSession.snapValid
    readonly property string paletteSnapTargetId: dragSession.snapTargetId
    readonly property var paletteSnapPath: dragSession.snapPath
    readonly property var paletteSnapTargetY: dragSession.snapTargetY
    // ---- value (operator) drag session ----
    // Separate from the block/strand drag above: values can only land in
    // value slots (fields) or as new floating blocks, never in a strand.
    ValueDrag {
        id: valueDrag
        canvas: root
    }
    property string _lastDrop: ""
    // Highlight set by the sidebar while a fresh palette value hovers the
    // canvas (palette drags are owned by the editor, not by valueDrag).
    property var paletteValueTarget: null
    property var paletteHighlightItem: null
    function clearPaletteHighlight() {
        if (paletteHighlightItem && paletteHighlightItem.dropHighlighted !== undefined)
            paletteHighlightItem.dropHighlighted = false;
        paletteHighlightItem = null;
        paletteValueTarget = null;
    }
    function setPaletteHighlight(item, loc) {
        if (paletteHighlightItem && paletteHighlightItem !== item && paletteHighlightItem.dropHighlighted !== undefined)
            paletteHighlightItem.dropHighlighted = false;
        paletteHighlightItem = item;
        if (item && item.dropHighlighted !== undefined)
            item.dropHighlighted = true;
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
        if (sx === null || sx === undefined || sy === null || sy === undefined) {
            clearPaletteHighlight();
            return null;
        }
        return updatePaletteValueTargetRect(sx, sy, sx, sy, sx, sy);
    }
    function updatePaletteValueTargetRect(gsx, gsy, gex, gey, sx, sy) {
        if (sx === null || sx === undefined || sy === null || sy === undefined) {
            clearPaletteHighlight();
            return null;
        }
        if (!root.contains(root.mapFromItem(null, sx, sy))) {
            clearPaletteHighlight();
            return null;
        }
        const tl = workspace.mapFromItem(null, gsx, gsy);
        const br = workspace.mapFromItem(null, gex, gey);
        const gx = Math.min(tl.x, br.x), gy = Math.min(tl.y, br.y);
        const gw = Math.abs(br.x - tl.x), gh = Math.abs(br.y - tl.y);
        const wp = workspace.mapFromItem(null, sx, sy);
        const found = resolveValueSlot(gx, gy, gw, gh, wp.x, wp.y);
        if (!found) {
            clearPaletteHighlight();
            return null;
        }
        const loc = JSON.parse(JSON.stringify(found.loc));
        setPaletteHighlight(found.item, loc);
        return loc;
    }
    // Reporter branches under `node`, in tree order. They index themselves in
    // BlockRegistry, so only two or more need the walk to order them.
    function branchContainers(node, out) {
        if (!node || node.visible === false)
            return;
        const live = [];
        for (const b of BlockRegistry.branchItems) {
            if (!b.isReporterBranch || !b.visible)
                continue;
            let up = b.parent;
            while (up && up !== node)
                up = up.parent;
            if (up)
                live.push(b);
            if (live.length > 1)
                break;
        }
        if (live.length === 1)
            pushBranch(live[0], out);
        else if (live.length > 1)
            walkBranchContainers(node, out);
    }
    function pushBranch(node, out) {
        const p = node.mapToItem(workspace, 0, 0);
        const list = node.branchList;
        out.push({
            strandId: node.branchStrandId,
            basePath: [],
            x: p.x,
            y: p.y,
            list: list,
            heights: list.map(ins => blockHeight(ins)),
            owner: node.branchSource
        });
    }
    function walkBranchContainers(node, out) {
        if (!node || node.visible === false)
            return;
        if (node.isReporterBranch)
            pushBranch(node, out);
        for (const child of node.children || [])
            walkBranchContainers(child, out);
    }
    function strandById(id) {
        if (!id)
            return null;
        for (const strand of root.strands || [])
            if (strand.id === id)
                return strand;
        // Only reporter branch addresses can resolve outside the strand list.
        if (!id.startsWith("@reporter-branch:"))
            return null;
        const branches = [];
        branchContainers(workspace, branches);
        const branch = branches.find(b => b.strandId === id);
        return branch ? {
            id: id,
            x: branch.x - root.originOffsetX,
            y: branch.y - root.originOffsetY,
            instructions: branch.list
        } : null;
    }
    // Binds a block to the canvas and forwards every signal it raises.
    // Strand blocks and blocks inside branch values both come through here.
    function wireInstruction(item) {
        item.variables = Qt.binding(() => root.variables);
        item.lists = Qt.binding(() => root.lists);
        item.keyCapture = Qt.binding(() => root.keyCapture);
        item.locked = Qt.binding(() => root.locked);
        item.dragState = Qt.binding(() => dragSession);
        item.removeRequested.connect(root.instructionRemoved);
        item.duplicateRequested.connect(root.instructionDuplicated);
        item.commentRequested.connect(root.commentForInstructionRequested);
        item.instructionEdited.connect(root.instructionEdited);
        item.valueEdited.connect(root.valueEdited);
        item.valueDragBegan.connect(root.beginValueDrag);
        item.valueDragMoved.connect(root.moveValueDrag);
        item.valueDragEnded.connect(root.endValueDrag);
        item.valueDragCanceled.connect(root.cancelValueDrag);
        item.runBranchRequested.connect(root.runBranchRequested);
        item.keyCaptureRequested.connect(root.keyCaptureRequested);
        item.detailsRequested.connect(root.detailsRequested);
        item.menuActionRequested.connect(root.blockMenuAction);
        item.pieceActionRequested.connect(root.pieceActionRequested);
        item.paletteDragStarted.connect(root.paletteDragStarted);
        item.paletteDragMoved.connect(root.paletteDragMoved);
        item.paletteDragEnded.connect(root.paletteDragEnded);
        item.paletteDragCanceled.connect(root.paletteDragCanceled);
        item.dragBegan.connect(root.beginDrag);
        item.dragMoved.connect(root.moveDrag);
        item.dragEnded.connect(root.endDrag);
        item.dragCanceled.connect(root.cancelDrag);
    }
    // ---- snap geometry: SnapGeometry.qml; these forward for blocks, tests and hosts ----
    readonly property SnapGeometry snapGeometryHelper: SnapGeometry {
        canvas: root
    }
    readonly property real snapThreshold: snapGeometryHelper.snapThreshold
    function isHeaderType(t) {
        return snapGeometryHelper.isHeaderType(t);
    }
    function isCapBlock(ins) {
        return snapGeometryHelper.isCapBlock(ins);
    }
    function blockHeight(ins) {
        return snapGeometryHelper.blockHeight(ins);
    }
    function contentHeightFor(list) {
        return snapGeometryHelper.contentHeightFor(list);
    }
    function mouthHeightFor(list) {
        return snapGeometryHelper.mouthHeightFor(list);
    }
    function shapeInfoFor(ins) {
        return snapGeometryHelper.shapeInfoFor(ins);
    }
    function listFor(strand, basePath) {
        return snapGeometryHelper.listFor(strand, basePath);
    }
    function instructionAt(strand, path) {
        return snapGeometryHelper.instructionAt(strand, path);
    }
    function copyPath(p) {
        return snapGeometryHelper.copyPath(p);
    }
    function snapGeometry() {
        return snapGeometryHelper.snapGeometry();
    }
    function collectContainers() {
        return snapGeometryHelper.collectContainers();
    }
    function findSnap(ghostLeft, ghostTop, sourceId, sourcePath, isWhole, prevSnap, stackHeight, stackEndsCap) {
        return snapGeometryHelper.findSnap(ghostLeft, ghostTop, sourceId, sourcePath, isWhole, prevSnap, stackHeight, stackEndsCap);
    }
    function applySnap(best, w, h, droppedIsCap, stackHeight) { dragSession.applySnap(best, w, h, droppedIsCap, stackHeight); }
    function clearSnap() { dragSession.clearSnap(); }
    StrandModel {
        id: strandModel
    }
    function syncStrands() {
        const list = root.strands || [];
        const changing = () => {
            dragSession.applyingDocument = true;
        };
        const origins = {};
        let originsChanged = false;
        for (const s of list) {
            const header = (s.instructions || [])[0];
            origins[s.id] = header && header.type === "BlockHeader" ? header.block_id : "";
            if (root.strandOrigins[s.id] !== origins[s.id])
                originsChanged = true;
        }
        if (originsChanged || Object.keys(root.strandOrigins).length !== list.length)
            root.strandOrigins = origins;
        strandModel.sync(list, changing);
    }
    function beginDrag(strandId, path, tailCount, sx, sy, ox, oy, bw, bh) { dragSession.begin(strandId, path, tailCount, sx, sy, ox, oy, bw, bh); }
    function moveDrag(sx, sy) { dragSession.move(sx, sy); }
    function updateSnap() { dragSession.updateSnap(); }
    function updatePaletteSnap(ghostLeft, ghostTop, instruction, w, h) { dragSession.updatePaletteSnap(ghostLeft, ghostTop, instruction, w, h); }
    function endDrag(sx, sy) { dragSession.end(sx, sy); }
    // ---- drop settling: DropSettle.qml; these forward for the drags, hosts and tests ----
    readonly property DropSettle dropSettle: DropSettle {
        canvas: root
    }
    function settleTrashed() { dropSettle.settleTrashed(); }
    function settlePaletteDrop() { dropSettle.settlePaletteDrop(); }
    // Scene point where a palette drop will land (value slot or attach gap), or null.
    function paletteDropScenePoint() {
        if (paletteHighlightItem)
            return paletteHighlightItem.mapToItem(null, 0, 0);
        if (dragSession.snapValid)
            return workspace.mapToItem(null, dragSession.snapX, dragSession.snapY);
        return null;
    }
    function settleValue(source, x, y, hidden) { dropSettle.settleValue(source, x, y, hidden); }
    function endSettle() { dropSettle.endSettle(); }
    function armSettle() { dropSettle.armSettle(); }
    function cancelDrag() { dragSession.cancel(); }
    // ---- value (operator) drag: hit-testing in ValueDropTargets.qml, the session here ----
    readonly property ValueDropTargets valueTargets: ValueDropTargets {
        canvas: root
    }
    readonly property real valueDropRadius: valueTargets.dropRadius
    function valueLocationsEqual(a, b) {
        return valueTargets.locationsEqual(a, b);
    }
    function isValueDescendantOrSelf(target, source) {
        return valueTargets.isDescendantOrSelf(target, source);
    }
    function resolveValueSlot(gx, gy, gw, gh, px, py) {
        return valueTargets.resolve(gx, gy, gw, gh, px, py);
    }
    function clearValueTarget() { valueDrag.clearTarget(); }
    function setValueHighlight(item) { valueDrag.setHighlight(item); }
    function setPaletteValueTarget(loc) {
        paletteValueTarget = loc ? JSON.parse(JSON.stringify(loc)) : null;
    }
    // Fields use the definition heading their strand, including nested expressions.
    function branchColorForStrand(strandId) {
        const strand = strandById(strandId);
        const header = strand && (strand.instructions || [])[0];
        return branchColorForBlock(header && header.type === "BlockHeader" ? header.block_id : "");
    }
    function branchColorForBlock(blockId) {
        const definition = blockId ? blockDefinitions.find(d => d.id === blockId) : null;
        return definition && definition.color ? definition.color : Theme.accent;
    }
    // Strand id -> the custom block its header defines (or ""). Replaced
    // only when that changes, so blocks reading it skip unchanged pushes.
    property var strandOrigins: ({})
    readonly property color dragBranchColor: branchColorForStrand(dragSession.strandId)
    function parameterOrigin(location) {
        if (!location)
            return "";
        if (location.kind === "Floating") {
            const floating = (root.floatingValues || []).find(v => v.id === location.floating_id);
            return floating ? floating.origin_block_id || "" : "";
        }
        const origin = root.strandOrigins[location.strand_id];
        if (origin !== undefined)
            return origin;
        const strand = strandById(location.strand_id);
        const header = strand && (strand.instructions || [])[0];
        return header && header.type === "BlockHeader" ? header.block_id : "";
    }
    function beginValueDrag(location, value, sx, sy, ox, oy, w, h) { valueDrag.begin(location, value, sx, sy, ox, oy, w, h); }
    function updateValueTarget(sx, sy) { valueDrag.update(sx, sy); }
    function moveValueDrag(sx, sy) { valueDrag.update(sx, sy); }
    function endValueDrag(sx, sy) { valueDrag.end(sx, sy); }
    function cancelValueDrag() { valueDrag.cancel(); }
    onFloatingValuesChanged: dropSettle.settleOnDocChange()
    // The settling key lives in the shared registry; don't leave it naming a
    // location on whatever canvas comes next.
    Component.onDestruction: endSettle()
    onStrandsChanged: {
        // The document already includes the preview gap. Do not animate it
        // again. syncStrands raises applyingDocument only if anything changes,
        // since every block watches it.
        try {
            syncStrands();
            if (dragSession.settling || valueDrag.settling)
                dragSession.applyingDocument = true;
            dropSettle.settleOnDocChange();
            if (!dragSession.active && !dragSession.settling) {
                dragSession.sourceStrandId = "";
                dragSession.sourceBasePath = [];
                dragSession.sourceShrink = 0;
            }
        } finally {
            dragSession.applyingDocument = false;
        }
    }
    Component.onCompleted: {
        syncStrands();
        syncListEditors();
        syncDictEditors();
        tryInitialCenter();
        updateCull();
    }
    // Prefer free space in the view, then the closest free space around it.
    function findEmptyPosition(width, height) {
        applyWorldResize();
        const gap = 16 / root.zoom;
        const left = flick.contentX / root.zoom - root.originOffsetX + gap;
        const top = flick.contentY / root.zoom - root.originOffsetY + gap;
        const right = left + flick.width / root.zoom - 2 * gap;
        const bottom = top + flick.height / root.zoom - 2 * gap;
        const preferredX = Math.round((left + right - width) / 2);
        const preferredY = Math.round((top + bottom - height) / 2);
        const occupied = [];
        for (const item of workspace.children) {
            if (!item.sid && !(item.modelData && item.modelData.id))
                continue;
            occupied.push({
                left: item.x - root.originOffsetX - gap,
                top: item.y - root.originOffsetY - gap,
                right: item.x - root.originOffsetX + item.width + gap,
                bottom: item.y - root.originOffsetY + item.height + gap
            });
        }
        const xs = [preferredX, Math.ceil(left), Math.floor(right - width)];
        const ys = [preferredY, Math.ceil(top), Math.floor(bottom - height)];
        for (const rect of occupied) {
            xs.push(Math.floor(rect.left - width), Math.ceil(rect.right));
            ys.push(Math.floor(rect.top - height), Math.ceil(rect.bottom));
        }
        let best = null, bestScore = Infinity, bestInView = false;
        for (const x of xs)
            for (const y of ys) {
                const inView = x >= left && y >= top && x + width <= right && y + height <= bottom;
                if (bestInView && !inView)
                    continue;
                const score = (x - preferredX) ** 2 + (y - preferredY) ** 2;
                if (inView === bestInView && score >= bestScore)
                    continue;
                if (occupied.some(r => x < r.right && x + width > r.left && y < r.bottom && y + height > r.top))
                    continue;
                best = {
                    x: x,
                    y: y
                };
                bestScore = score;
                bestInView = inView;
            }
        return best || {
            x: preferredX,
            y: preferredY
        };
    }
    // World coordinates for a scene point, or null when it is outside the canvas.
    function workspacePoint(sx, sy) {
        if (!root.contains(root.mapFromItem(null, sx, sy)))
            return null;
        const p = workspace.mapFromItem(null, sx, sy);
        return {
            x: p.x - root.originOffsetX,
            y: p.y - root.originOffsetY
        };
    }

    Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: root.worldW * root.zoom
        contentHeight: root.worldH * root.zoom
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.horizontal: ScrollBar {}
        ScrollBar.vertical: ScrollBar {}
        onWidthChanged: root.tryInitialCenter()
        onHeightChanged: root.tryInitialCenter()
        // While a wheel gesture is active the Flickable must not run its own
        // wheel logic: it would process every event a second time (it
        // un-accepts wheel events) with a dominant-axis threshold and
        // momentum flicks, which read as straight-line priming before
        // diagonal kicked in - and slow diagonals died out entirely. The
        // WheelHandler below is then the single owner and pans 1:1.
        interactive: !wheelPan.active && textHolds === 0
        // Presses in text fields, which select rather than pan (TextSelectHold).
        property int textHolds: 0
        SmoothScroll {
            id: canvasScroll
            flickable: flick
        }
        // A drag or flick takes over from a zoom glide in progress.
        onMovementStarted: zoomer.stop()
        // Dragging the canvas with a mouse stops where it's let go: the
        // release fling read as the view sliding away on its own. Touch
        // screens keep their momentum.
        property bool touchDrag: false
        onFlickStarted: if (!touchDrag)
            cancelFlick()
        PointHandler {
            target: null
            acceptedDevices: PointerDevice.TouchScreen
            onActiveChanged: if (active)
                flick.touchDrag = true
        }
        PointHandler {
            target: null
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad | PointerDevice.Stylus
            onActiveChanged: if (active)
                flick.touchDrag = false
        }
        // A touchpad pinch zooms around the point between the fingers, like
        // Ctrl+scroll does around the pointer.
        PinchHandler {
            id: pinchZoom
            target: null
            acceptedDevices: PointerDevice.TouchPad
            onScaleChanged: delta => {
                if (!isFinite(delta) || delta <= 0 || delta === 1)
                    return;
                const sp = pinchZoom.centroid.scenePosition;
                const v = flick.mapFromItem(null, sp.x, sp.y);
                root.zoomBy(v.x, v.y, delta, true, root._touchpadZoomMs);
            }
        }
        // Two-finger touchpads emit one wheel event carrying both axes; pan
        // both from that same event so diagonal stays diagonal at any speed.
        WheelHandler {
            id: wheelPan
            target: null
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            orientation: Qt.Horizontal | Qt.Vertical
            onWheel: event => {
                if (event.modifiers & Qt.ControlModifier) {
                    // The handler sits on the Flickable's content item, so the
                    // event's own position is in (scrolled, scaled) content
                    // coordinates; zooming around that dragged the view right
                    // and down. Map the cursor into the viewport instead.
                    const sp = wheelPan.point.scenePosition;
                    const v = flick.mapFromItem(null, sp.x, sp.y);
                    // 12% per wheel notch (angleDelta 120), and in proportion
                    // for hi-res wheels. Touchpads send about 12 units per
                    // pixel, so 12% takes 20px of finger travel, with a
                    // shorter glide per step.
                    const delta = event.angleDelta.y !== 0 ? event.angleDelta.y : event.pixelDelta.y * 12;
                    const touchpad = canvasScroll.isTouchpad(event);
                    root.zoomBy(v.x, v.y, Math.pow(1.12, delta / (touchpad ? 240 : 120)), true, touchpad ? root._touchpadZoomMs : undefined);
                    event.accepted = true;
                    return;
                }
                zoomer.stop();
                const touchpad = canvasScroll.isTouchpad(event);
                const pan = (ad, pd) => canvasScroll.wheelStep(ad, pd, touchpad);
                // A wheel notch glides to its target; a touchpad pan trails its
                // fingers by a few frames.
                const px = pan(event.angleDelta.x, event.pixelDelta.x), py = pan(event.angleDelta.y, event.pixelDelta.y);
                if (touchpad)
                    canvasScroll.follow(px, py);
                else
                    canvasScroll.scrollBy(px, py, true);
                event.accepted = true;
            }
        }
        Item {
            id: workspace
            width: root.worldW
            height: root.worldH
            scale: root.zoom
            transformOrigin: Item.TopLeft
            // Keep new delegates in place before Flickable applies the new scroll bounds.
            transform: Translate {
                x: root._resizeViewX === null ? 0 : flick.contentX - root._resizeViewX
                y: root._resizeViewY === null ? 0 : flick.contentY - root._resizeViewY
            }
            // The dot grid lives in world space and moves with the content,
            // so scrolling and zooming never repaint it. Each 22px tile holds a
            // quarter dot in every corner, drawn at twice the size and scaled
            // down so zooming in stays sharp. It covers the cull band around
            // the view rather than the whole world, which can be huge for a
            // long strand, and moves only when the band does.
            Image {
                id: grid
                z: -200
                // Keep the tile phase tied to world coordinates as the origin moves.
                readonly property real phaseX: root.originOffsetX % 22
                readonly property real phaseY: root.originOffsetY % 22
                readonly property real tileLeft: Math.floor((Math.max(root.cullLeft, -root.worldW) - phaseX) / 22) * 22 + phaseX - 22
                readonly property real tileTop: Math.floor((Math.max(root.cullTop, -root.worldH) - phaseY) / 22) * 22 + phaseY - 22
                x: tileLeft
                y: tileTop
                width: 2 * (Math.min(root.cullRight, 2 * root.worldW) - tileLeft + 44)
                height: 2 * (Math.min(root.cullBottom, 2 * root.worldH) - tileTop + 44)
                scale: 0.5
                transformOrigin: Item.TopLeft
                fillMode: Image.Tile
                smooth: true
                // Tile from the top left so resizing cannot shift the pattern.
                horizontalAlignment: Image.AlignLeft
                verticalAlignment: Image.AlignTop
                sourceSize: Qt.size(44, 44)
                source: "data:image/svg+xml;utf8," + encodeURIComponent("<svg xmlns='http://www.w3.org/2000/svg' width='44' height='44'><g fill='" + Theme.grid + "'>" + "<circle cx='0' cy='0' r='2.3'/><circle cx='44' cy='0' r='2.3'/><circle cx='0' cy='44' r='2.3'/><circle cx='44' cy='44' r='2.3'/></g></svg>")
            }
            MouseArea {
                anchors.fill: parent
                z: -100
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: mouse => {
                    if (mouse.button === Qt.RightButton) {
                        canvasMenu.popupAt(mouse.x, mouse.y, Math.round(mouse.x - root.originOffsetX), Math.round(mouse.y - root.originOffsetY));
                    } else
                        flick.forceActiveFocus();
                }
                CanvasMenu {
                    id: canvasMenu
                    canvas: root
                }
            }
            Repeater {
                id: strandRepeater
                model: strandModel
                delegate: StrandView {
                    canvas: root
                }
            }
            Repeater {
                model: root.comments || []
                delegate: CommentCard {
                    canvas: root
                }
            }
            Repeater {
                model: root.floatingValues || []
                delegate: FloatingValue {
                    canvas: root
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
                objectName: "snapPreview"
                visible: dragSession.snapValid && !dragSession.settling
                x: dragSession.snapX
                y: dragSession.snapY
                width: Math.max(120, dragSession.snapWidth)
                height: Math.max(20, dragSession.snapHeight)
                z: 90
                enabled: false
                opacity: 0.55
                BlockSurface {
                    anchors.fill: parent
                    shape: dragSession.draggedShape
                    fill: Theme.accent
                    outline: Theme.accent
                    headHeight: 50
                    midHeight: 34
                    footHeight: 26
                    spine: 20
                    mouthHeights: dragSession.draggedMouths
                    flatEnds: dragSession.draggedFlat
                }
            }
            // Ghost following the pointer while an existing value is dragged.
            Item {
                id: valueGhost
                visible: (valueDrag.active && !root.externalDragPreview) || (valueDrag.settling && !valueDrag.settleHidden)
                x: valueDrag.active ? valueDrag.originX + valueDrag.dx : valueDrag.settleX
                y: valueDrag.active ? valueDrag.originY + valueDrag.dy : valueDrag.settleY
                width: Math.max(40, valueDrag.draggedWidth)
                height: Math.max(27, valueDrag.draggedHeight)
                z: 95
                enabled: false
                opacity: 0.9
                ValueChip {
                    anchors.fill: parent
                    valueData: valueDrag.sourceValue
                    boxed: true
                    editable: false
                    originBlockId: valueDrag.sourceOrigin
                    dragPreview: true
                    blockDefinitions: root.blockDefinitions
                    canvasState: root.canvasState
                }
            }
        }
    }
    Item {
        id: collectionOverlay
        anchors.fill: parent
        z: 12
        Repeater {
            model: listEditorModel
            delegate: ListEditorCard {
                canvas: root
                overlay: collectionOverlay
            }
        }
        Repeater {
            model: dictEditorModel
            delegate: DictEditorCard {
                canvas: root
                overlay: collectionOverlay
            }
        }
    }
    // Keeps the grab cursor while a block or value is dragged away from its source.
    MouseArea {
        anchors.fill: parent
        visible: root.dragging
        acceptedButtons: Qt.NoButton
        cursorShape: Qt.ClosedHandCursor
    }
    Column {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 18
        spacing: 8
        StitchButton {
            iconName: "zoom-in"
            text: ""
            implicitWidth: 40
            implicitHeight: 40
            radius: 20
            onClicked: root.stepZoom(.1)
        }
        StitchButton {
            iconName: "zoom-out"
            text: ""
            implicitWidth: 40
            implicitHeight: 40
            radius: 20
            onClicked: root.stepZoom(-.1)
        }
        StitchButton {
            iconName: "rotate-ccw"
            text: ""
            implicitWidth: 40
            implicitHeight: 40
            radius: 20
            onClicked: root.resetView()
        }
    }
}
