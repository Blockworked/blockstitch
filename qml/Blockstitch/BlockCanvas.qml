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
    property string recordingTargetId: ""
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
    Binding {
        target: BlockRegistry
        property: "recordingTargetId"
        value: root.recordingTargetId
    }
    Binding {
        target: BlockRegistry
        property: "commentedIds"
        value: (root.comments || []).filter(c => c.attached_to).map(c => c.attached_to)
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
    signal recordingTargetRequested(string strandId)
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
    // Keep the popup and its pointer grab alive across daemon updates.
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
        BlockRegistry.flash(id);
        return true;
    }

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
        readonly property bool externalPreview: root.externalDragPreview
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
    QtObject {
        id: valueDrag
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
    function wireBranchInstruction(item) {
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
    function applySnap(best, w, h, droppedIsCap, stackHeight) {
        if (!best) {
            clearSnap();
            return;
        }
        dragSession.snapTargetId = best.targetId;
        dragSession.snapTargetY = best.targetY === undefined ? null : best.targetY;
        dragSession.snapPath = best.path;
        dragSession.snapX = best.x;
        dragSession.snapY = best.y;
        dragSession.snapWidth = w;
        dragSession.snapHeight = h;
        const gapHeight = stackHeight === undefined ? h : stackHeight;
        // Prepending keeps the target fixed; other insertions open a gap.
        // Empty mouths start at 26px, and cap blocks have no bottom overlap.
        dragSession.snapShiftAmt = dragSession.snapTargetY !== null ? 0 : Math.max(0, gapHeight - 8);
        if (best.empty)
            dragSession.snapGrowAmt = Math.max(0, Math.max(26, gapHeight - (droppedIsCap ? 0 : 8)) - 26);
        else if (best.atEnd && droppedIsCap)
            dragSession.snapGrowAmt = Math.max(0, gapHeight);
        else
            dragSession.snapGrowAmt = Math.max(0, gapHeight - 8);
        dragSession.snapValid = true;
        dragSession.snapLayout = {
            snapValid: true,
            snapTargetId: best.targetId,
            snapPath: best.path,
            snapShiftAmt: dragSession.snapShiftAmt,
            snapGrowAmt: dragSession.snapGrowAmt,
            snapWidth: w
        };
    }
    function clearSnap() {
        dragSession.snapLayout = null;
        dragSession.snapValid = false;
        dragSession.snapTargetY = null;
        dragSession.snapTargetId = "";
        dragSession.snapPath = [];
    }
    function prevSnapObj() {
        if (!dragSession.snapValid)
            return null;
        return {
            targetId: dragSession.snapTargetId,
            path: dragSession.snapPath
        };
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
    ListModel {
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
        for (let i = strandModel.count - 1; i >= 0; --i) {
            const sid = strandModel.get(i).sid;
            let alive = false;
            for (let j = 0; j < list.length; ++j)
                if (list[j].id === sid) {
                    alive = true;
                    break;
                }
            if (!alive) {
                changing();
                strandModel.remove(i);
            }
        }
        for (let j = 0; j < list.length; ++j) {
            const s = list[j];
            const payload = JSON.stringify(s.instructions || []);
            let at = -1;
            for (let i = 0; i < strandModel.count; ++i)
                if (strandModel.get(i).sid === s.id) {
                    at = i;
                    break;
                }
            if (at === -1) {
                changing();
                strandModel.insert(j, {
                    sid: s.id,
                    sx: s.x,
                    sy: s.y,
                    payload: payload
                });
            } else {
                if (at !== j) {
                    changing();
                    strandModel.move(at, j, 1);
                    at = j;
                }
                const row = strandModel.get(at);
                if (row.sx !== s.x) {
                    changing();
                    strandModel.setProperty(at, "sx", s.x);
                }
                if (row.sy !== s.y) {
                    changing();
                    strandModel.setProperty(at, "sy", s.y);
                }
                if (row.payload !== payload) {
                    changing();
                    strandModel.setProperty(at, "payload", payload);
                }
            }
        }
        while (strandModel.count > list.length) {
            changing();
            strandModel.remove(strandModel.count - 1);
        }
    }
    function beginDrag(strandId, path, tailCount, sx, sy, ox, oy, bw, bh) {
        cancelValueDrag();
        clearPaletteHighlight();
        endSettle();
        const p = workspace.mapFromItem(null, sx, sy);
        dragSession.strandId = strandId;
        dragSession.path = path;
        dragSession.tailCount = tailCount;
        dragSession.startX = p.x;
        dragSession.startY = p.y;
        dragSession.originX = p.x - ox;
        dragSession.originY = p.y - oy;
        dragSession.sceneX = sx;
        dragSession.sceneY = sy;
        dragSession.dx = 0;
        dragSession.dy = 0;
        dragSession.active = true;
        dragSession.draggedWidth = bw || 200;
        dragSession.draggedHeight = bh || 58;
        const si = shapeInfoFor(instructionAt(strandById(strandId), path));
        dragSession.draggedShape = si.shape;
        dragSession.draggedMouths = si.mouths;
        dragSession.draggedFlat = si.flat;
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
        if (!dragSession.active)
            return;
        const p = workspace.mapFromItem(null, sx, sy);
        dragSession.dx = p.x - dragSession.startX;
        dragSession.dy = p.y - dragSession.startY;
        dragSession.sceneX = sx;
        dragSession.sceneY = sy;
        updateSnap();
    }
    function updateSnap() {
        if (!dragSession.active)
            return;
        const sourcePath = dragSession.path || [];
        if (!sourcePath.length) {
            clearSnap();
            return;
        }
        const isWhole = sourcePath.length === 1 && sourcePath[0].index === 0;
        const srcStrand = strandById(dragSession.strandId);
        if (isWhole && srcStrand) {
            const first = (srcStrand.instructions || [])[0];
            if (first && isHeaderType(first.type)) {
                clearSnap();
                return;
            }
        } else if (!isWhole && srcStrand) {
            const firstTail = instructionAt(srcStrand, sourcePath);
            if (firstTail && isHeaderType(firstTail.type)) {
                clearSnap();
                return;
            }
        }
        const ghostLeft = dragSession.originX + dragSession.dx;
        const ghostTop = dragSession.originY + dragSession.dy;
        const geometry = snapGeometry();
        if (!geometry.tail) {
            const tail = listFor(srcStrand, sourcePath.slice(0, -1)).slice(sourcePath[sourcePath.length - 1].index);
            let width = dragSession.draggedWidth;
            for (const instruction of tail) {
                const item = findBlockItem(workspace, instruction.id);
                if (item)
                    width = Math.max(width, item.implicitWidth);
            }
            geometry.tail = {
                endsCap: tail.length > 0 && isCapBlock(tail[tail.length - 1]),
                height: contentHeightFor(tail),
                width: width
            };
        }
        const t = geometry.tail;
        const best = findSnap(ghostLeft, ghostTop, dragSession.strandId, sourcePath, isWhole, prevSnapObj(), t.height, t.endsCap);
        applySnap(best, t.width, dragSession.draggedHeight, t.endsCap, t.height);
    }
    // Palette (new-block) drags share the same preview: a header prefab can
    // never snap into an existing strand, anything else uses the same
    // boundaries/rules as a canvas tail (excludeId none).
    function updatePaletteSnap(ghostLeft, ghostTop, instruction, w, h) {
        endSettle();
        if (!instruction || isHeaderType(instruction.type)) {
            clearSnap();
            return;
        }
        const si = shapeInfoFor(instruction);
        dragSession.draggedShape = si.shape;
        dragSession.draggedMouths = si.mouths;
        dragSession.draggedFlat = si.flat;
        dragSession.draggedIsCap = isCapBlock(instruction);
        // The ghost's measured height wins: blockHeight only estimates blocks
        // that aren't on the canvas, and calls every plain block one row.
        dragSession.draggedWidth = w || 200;
        dragSession.draggedHeight = h > 0 ? h : (blockHeight(instruction) || 58);
        const best = findSnap(ghostLeft + root.originOffsetX, ghostTop + root.originOffsetY, null, [], false, prevSnapObj(), dragSession.draggedHeight, dragSession.draggedIsCap);
        applySnap(best, dragSession.draggedWidth, dragSession.draggedHeight, dragSession.draggedIsCap);
    }
    function endDrag(sx, sy) {
        if (!dragSession.active)
            return;
        moveDrag(sx, sy);
        const strandId = dragSession.strandId, path = dragSession.path, tail = dragSession.tailCount;
        const dx = dragSession.dx, dy = dragSession.dy, ox = dragSession.originX, oy = dragSession.originY;
        const snapValid = dragSession.snapValid, snapTargetId = dragSession.snapTargetId, snapPath = copyPath(dragSession.snapPath || []);
        const isWhole = path.length === 1 && path[0].index === 0;
        dragSession.active = false;
        dragSession.settleStrandId = strandId;
        dragSession.settlePath = path;
        dragSession.settleHidden = false;
        root._lastDrop = "block";
        if (!root.contains(root.mapFromItem(null, sx, sy))) {
            // The host calls settleTrashed() if it actually deletes the tail.
            clearSnap();
            dragSession.settling = false;
            root.blockDragOutside(strandId, path, tail, sx, sy);
            return;
        }
        if (snapValid && snapTargetId) {
            // Attach, just like the webapp: merge the whole strand, or move
            // the tail atomically (no split-then-merge round trip). Settle on
            // the preview spot, keeping the gap open, until the merge lands.
            dragSession.settleDx = dragSession.snapX - ox;
            dragSession.settleDy = dragSession.snapY - oy;
            dragSession.settling = true;
            armSettle();
            if (isWhole)
                root.strandsMerged(strandId, snapTargetId, snapPath, dragSession.snapTargetY);
            else
                root.tailMerged(strandId, path, snapTargetId, snapPath, dragSession.snapTargetY);
            return;
        }
        // Optimistic settle: keep rendering the dragged tail at the drop
        // point until the backend state confirms the move/split. Cleared in
        // onStrandsChanged or by settleTimer below.
        clearSnap();
        dragSession.settleDx = dx;
        dragSession.settleDy = dy;
        dragSession.settling = true;
        armSettle();
        const strand = strandById(strandId);
        if (isWhole && strand)
            root.strandMoved(strandId, Math.round(strand.x + dx), Math.round(strand.y + dy));
        else
            root.instructionSplit(strandId, path, Math.round(ox + dx - root.originOffsetX), Math.round(oy + dy - root.originOffsetY));
    }
    // Hides the block or value just dropped outside the canvas until its removal lands.
    function settleTrashed() {
        if (root._lastDrop === "value") {
            if (valueDrag.active || !valueDrag.settleSource)
                return;
            settleValue(valueDrag.settleSource, 0, 0, true);
            return;
        }
        if (dragSession.active)
            return;
        dragSession.settleHidden = true;
        dragSession.settling = true;
        armSettle();
    }
    // Keeps a palette drop's attach gap open until the new block lands.
    function settlePaletteDrop() {
        if (dragSession.active || !dragSession.snapValid)
            return;
        dragSession.settleStrandId = "";
        dragSession.settlePath = [];
        dragSession.settling = true;
        armSettle();
    }
    // Scene point where a palette drop will land (value slot or attach gap), or null.
    function paletteDropScenePoint() {
        if (paletteHighlightItem)
            return paletteHighlightItem.mapToItem(null, 0, 0);
        if (dragSession.snapValid)
            return workspace.mapToItem(null, dragSession.snapX, dragSession.snapY);
        return null;
    }
    function settleValue(source, x, y, hidden) {
        valueDrag.settleX = x;
        valueDrag.settleY = y;
        valueDrag.settleHidden = hidden;
        valueDrag.settling = true;
        BlockRegistry.settlingValueKey = BlockRegistry.locationKey(source);
        armSettle();
    }
    function endSettle() {
        if (valueDrag.settling) {
            valueDrag.settling = false;
            valueDrag.settleHidden = false;
            BlockRegistry.settlingValueKey = "";
        }
        if (!dragSession.settling)
            return;
        dragSession.settling = false;
        dragSession.settleHidden = false;
        clearSnap();
    }
    function cancelDrag() {
        dragSession.active = false;
        dragSession.settling = false;
        dragSession.settleHidden = false;
        clearSnap();
        dragSession.sourceStrandId = "";
        dragSession.sourceBasePath = [];
        dragSession.sourceShrink = 0;
    }
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
    function clearValueTarget() {
        valueDrag.target = null;
        valueDrag.targetValid = false;
        setValueHighlight(null);
    }
    function setValueHighlight(item) {
        if (valueDrag.highlightItem && valueDrag.highlightItem !== item && valueDrag.highlightItem.dropHighlighted !== undefined)
            valueDrag.highlightItem.dropHighlighted = false;
        valueDrag.highlightItem = item;
        if (item && item.dropHighlighted !== undefined)
            item.dropHighlighted = true;
    }
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
    function beginValueDrag(location, value, sx, sy, ox, oy, w, h) {
        if (root.locked)
            return;
        cancelDrag();
        endSettle();
        const p = workspace.mapFromItem(null, sx, sy);
        valueDrag.sourceLocation = JSON.parse(JSON.stringify(location));
        valueDrag.sourceValue = JSON.parse(JSON.stringify(value));
        valueDrag.sourceOrigin = parameterOrigin(location);
        valueDrag.startX = p.x;
        valueDrag.startY = p.y;
        valueDrag.originX = p.x - ox;
        valueDrag.originY = p.y - oy;
        valueDrag.dx = 0;
        valueDrag.dy = 0;
        valueDrag.sceneX = sx;
        valueDrag.sceneY = sy;
        valueDrag.draggedWidth = w || 120;
        valueDrag.draggedHeight = h || 32;
        valueDrag.active = true;
        clearValueTarget();
        clearPaletteHighlight();
        updateValueTarget(sx, sy);
    }
    function updateValueTarget(sx, sy) {
        if (!valueDrag.active)
            return;
        valueDrag.sceneX = sx;
        valueDrag.sceneY = sy;
        const p = workspace.mapFromItem(null, sx, sy);
        valueDrag.dx = p.x - valueDrag.startX;
        valueDrag.dy = p.y - valueDrag.startY;
        if (!root.contains(root.mapFromItem(null, sx, sy))) {
            clearValueTarget();
            return;
        }
        // Ghost rect in workspace coordinates (draggedWidth/Height are item
        // pixels, so normalize by zoom); the drop target is the nearest slot
        // to this rect, not the item exactly under the cursor.
        const z = Math.max(0.01, root.zoom);
        const gx = valueDrag.originX + valueDrag.dx, gy = valueDrag.originY + valueDrag.dy;
        const gw = (valueDrag.draggedWidth || 0) / z, gh = (valueDrag.draggedHeight || 0) / z;
        const found = resolveValueSlot(gx, gy, gw, gh, p.x, p.y);
        if (!found) {
            clearValueTarget();
            return;
        }
        const t = JSON.parse(JSON.stringify(found.loc));
        // Dropping back onto the exact source slot, or into its own
        // descendant, is never a move - keep the highlight for the
        // exact-source no-op, clear it for a true self-nesting.
        if (valueLocationsEqual(t, valueDrag.sourceLocation)) {
            valueDrag.target = t;
            valueDrag.targetValid = true;
            setValueHighlight(found.item);
            return;
        }
        if (isValueDescendantOrSelf(t, valueDrag.sourceLocation)) {
            clearValueTarget();
            return;
        }
        valueDrag.target = t;
        valueDrag.targetValid = true;
        setValueHighlight(found.item);
    }
    function moveValueDrag(sx, sy) {
        updateValueTarget(sx, sy);
    }
    function endValueDrag(sx, sy) {
        if (!valueDrag.active)
            return;
        updateValueTarget(sx, sy);
        const source = valueDrag.sourceLocation ? JSON.parse(JSON.stringify(valueDrag.sourceLocation)) : null;
        const value = valueDrag.sourceValue ? JSON.parse(JSON.stringify(valueDrag.sourceValue)) : null;
        const target = valueDrag.targetValid && valueDrag.target ? JSON.parse(JSON.stringify(valueDrag.target)) : null;
        const targetItem = valueDrag.highlightItem;
        const gx = valueDrag.originX + valueDrag.dx, gy = valueDrag.originY + valueDrag.dy;
        valueDrag.active = false;
        clearValueTarget();
        root._lastDrop = "value";
        valueDrag.settleSource = source;
        if (!source || !value)
            return;
        if (!root.contains(root.mapFromItem(null, sx, sy))) {
            root.valueDragOutside(source, value, sx, sy);
            return;
        }
        if (target) {
            if (valueLocationsEqual(target, source))
                return; // no-op put-back
            const p = targetItem ? workspace.mapFromItem(targetItem, 0, 0) : Qt.point(gx, gy);
            settleValue(source, p.x, p.y, false);
            root.valueMoveRequested(source, target, 0, 0, "");
            return;
        }
        // Open canvas: lands where the ghost is. A whole floating block just
        // moves; anything pulled out of a field becomes a new floating block.
        const fx = Math.round(gx - root.originOffsetX), fy = Math.round(gy - root.originOffsetY);
        settleValue(source, gx, gy, false);
        if (source.kind === "Floating" && !(source.path && source.path.length))
            root.floatingValueMoved(source.floating_id, fx, fy);
        else
            root.valueMoveRequested(source, null, fx, fy, valueDrag.sourceOrigin);
    }
    function cancelValueDrag() {
        valueDrag.active = false;
        clearValueTarget();
    }
    // A settle ends once the document differs from the drop moment; other
    // state pushes (run log, debugger) reassign it unchanged and must not.
    property string _settleDoc: ""
    function docKey() {
        return JSON.stringify([root.strands, root.floatingValues]);
    }
    function armSettle() {
        _settleDoc = docKey();
        settleTimer.restart();
    }
    function settleOnDocChange() {
        if ((dragSession.settling || valueDrag.settling) && docKey() === _settleDoc)
            return;
        endSettle();
    }
    onFloatingValuesChanged: settleOnDocChange()
    Timer {
        id: settleTimer
        interval: 1500
        onTriggered: root.endSettle()
    }
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
            settleOnDocChange();
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
                // A mouse wheel gets Qt's own Flickable step per notch (angleDelta 120,
                // less on hi-res wheels) with no acceleration; a touchpad gets the
                // accelerated pan. pixelDelta is truncated to ints on touchpads;
                // angleDelta carries the real resolution (about 12 units per px).
                const touchpad = canvasScroll.isTouchpad(event);
                const pan = (ad, pd) => {
                    if (!touchpad)
                        return ad / 120 * Qt.styleHints.wheelScrollLines * 24;
                    const d = ad !== 0 ? ad / 12 : pd;
                    return d * Math.min(24, 6 + 1.5 * Math.abs(d));
                };
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
                        canvasMenu.canvasX = Math.round(mouse.x - root.originOffsetX);
                        canvasMenu.canvasY = Math.round(mouse.y - root.originOffsetY);
                        canvasMenu.popup(mouse.x, mouse.y);
                    } else
                        flick.forceActiveFocus();
                }
                BwMenu {
                    id: canvasMenu
                    property int canvasX: 0
                    property int canvasY: 0
                    BwMenuItem {
                        visible: root.offerClear
                        iconName: root.clearIcon
                        danger: true
                        text: root.clearText
                        onTriggered: root.clearRequested()
                    }
                    BwMenuItem {
                        iconName: "clipboard-paste"
                        enabled: root.canPaste
                        text: qsTr("Paste")
                        onTriggered: root.canvasMenuAction("paste", canvasMenu.canvasX, canvasMenu.canvasY)
                    }
                    BwMenuItem {
                        iconName: "message-square"
                        text: qsTr("Add Comment")
                        onTriggered: root.canvasNoteRequested(canvasMenu.canvasX, canvasMenu.canvasY)
                    }
                }
                Instantiator {
                    model: BlockRegistry.canvasMenu
                    delegate: BwMenuItem {
                        required property var modelData
                        iconName: modelData.icon || ""
                        text: modelData.text
                        danger: !!modelData.danger
                        onTriggered: root.canvasMenuAction(modelData.id, canvasMenu.canvasX, canvasMenu.canvasY)
                    }
                    onObjectAdded: (index, object) => canvasMenu.insertItem(index, object)
                    onObjectRemoved: (index, object) => canvasMenu.removeItem(object)
                }
            }
            Repeater {
                id: strandRepeater
                model: strandModel
                delegate: Column {
                    id: strand
                    Accessible.role: Accessible.Grouping
                    Accessible.name: qsTr("Block strand")
                    required property string sid
                    required property real sx
                    required property real sy
                    required property string payload
                    required property int index
                    readonly property var blockList: JSON.parse(payload || "[]")
                    readonly property color branchColor: root.branchColorForBlock(root.strandOrigins[sid] || "")
                    // Blocks are built once the strand comes near the view, or
                    // by the background builder; until then a placeholder of
                    // about the right size stands in.
                    property bool built: false
                    property bool loading: false
                    property real estY: 0
                    readonly property bool nearView: root.nearView(x, y, Math.max(width, root.strandEstW), Math.max(height, 58))
                    onNearViewChanged: if (nearView)
                        root.buildStrand(strand)
                    x: sx + root.originOffsetX
                    y: sy + root.originOffsetY
                    spacing: -8
                    z: (dragSession.active && dragSession.strandId === sid) || (dragSession.settling && dragSession.settleStrandId === sid) ? 100 : 0
                    // Report the real card width so the world extends past
                    // actual strand content, not a fixed estimate.
                    // (InstructionList below is a non-visual ListModel, so the
                    // Column's implicitWidth is still the widest block.)
                    onImplicitWidthChanged: root.noteStrandWidth(sid, implicitWidth)
                    onImplicitHeightChanged: root.noteStrandHeight(sid, implicitHeight)
                    Component.onCompleted: {
                        if (nearView || !root.lazyStrands)
                            root.buildStrand(strand);
                        else
                            builder.start();
                        root.noteStrandWidth(sid, implicitWidth);
                        root.noteStrandHeight(sid, implicitHeight);
                    }
                    Component.onDestruction: {
                        root.clearStrandWidth(sid);
                        root.clearStrandHeight(sid);
                    }
                    InstructionList {
                        id: strandBlocks
                        instructions: strand.built ? strand.blockList : []
                        onAboutToInsert: (at, n) => root.bulkInsert(strand, blockRepeater, at, n)
                    }
                    Item {
                        visible: !strand.built
                        width: root.strandEstW
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
                            Component.onCompleted: root.slotCreated(strand, slot, root.blockHeight(JSON.parse(payload)))
                            Component {
                                id: placeholderComponent
                                Item {
                                    width: root.strandEstW
                                    height: root.blockHeight(JSON.parse(slot.payload))
                                }
                            }
                            Component {
                                id: blockComponent
                                InstructionBlock {
                                    id: block
                                    readonly property string payload: slot.payload
                                    readonly property int index: slot.index
                                    visible: dragRole !== 0 || root.inCullBand(strand.x + slot.x, strand.y + slot.y + snapShift, Math.max(slot.width, 1), Math.max(slot.height, 1))
                                    instruction: JSON.parse(payload)
                                    strandId: strand.sid
                                    path: [
                                        {
                                            index: index
                                        }
                                    ]
                                    tailCount: strandBlocks.count - index
                                    recordingTarget: index === 0 && root.recordingTargetId === strand.sid
                                    dragState: dragSession
                                    variables: root.variables
                                    lists: root.lists
                                    blockDefinitions: root.blockDefinitions
                                    keyCapture: root.keyCapture
                                    locked: root.locked
                                    branchColor: strand.branchColor
                                    onRemoveRequested: (sid, p) => root.instructionRemoved(sid, p)
                                    onDuplicateRequested: (sid, p, i) => root.instructionDuplicated(sid, p, i)
                                    onCommentRequested: i => root.commentForInstructionRequested(i)
                                    onRecordingTargetRequested: sid => root.recordingTargetRequested(sid)
                                    onKeyCaptureRequested: (sid, p) => root.keyCaptureRequested(sid, p)
                                    onPieceActionRequested: (a, sid, p, i) => root.pieceActionRequested(a, sid, p, i)
                                    onDetailsRequested: type => root.detailsRequested(type)
                                    onMenuActionRequested: (a, sid, p, i) => root.blockMenuAction(a, sid, p, i)
                                    onPaletteDragStarted: (sp, sx, sy, ox, oy) => root.paletteDragStarted(sp, sx, sy, ox, oy)
                                    onPaletteDragMoved: (sx, sy) => root.paletteDragMoved(sx, sy)
                                    onPaletteDragEnded: (sx, sy) => root.paletteDragEnded(sx, sy)
                                    onPaletteDragCanceled: root.paletteDragCanceled()
                                    onInstructionEdited: (sid, p, i) => root.instructionEdited(sid, p, i)
                                    onRunBranchRequested: (sid, p, n) => root.runBranchRequested(sid, p, n)
                                    onValueEdited: (l, t) => root.valueEdited(l, t)
                                    onValueDragBegan: (loc, val, sx, sy, ox, oy, w, h) => root.beginValueDrag(loc, val, sx, sy, ox, oy, w, h)
                                    onValueDragMoved: (sx, sy) => root.moveValueDrag(sx, sy)
                                    onValueDragEnded: (sx, sy) => root.endValueDrag(sx, sy)
                                    onValueDragCanceled: root.cancelValueDrag()
                                    onDragBegan: (sid, p, tail, sx, sy, ox, oy, bw, bh) => root.beginDrag(sid, p, tail, sx, sy, ox, oy, bw, bh)
                                    onDragMoved: (sx, sy) => root.moveDrag(sx, sy)
                                    onDragEnded: (sx, sy) => root.endDrag(sx, sy)
                                    onDragCanceled: root.cancelDrag()
                                }
                            }
                        }
                    }
                }
            }
            Repeater {
                model: root.comments || []
                delegate: Rectangle {
                    id: commentCard
                    required property var modelData
                    objectName: "commentCard_" + modelData.id
                    readonly property var attachedBlock: modelData.attached_to && root.builtStrands >= 0 ? root.findBlockItem(workspace, modelData.attached_to) : null
                    readonly property point blockAnchor: root.commentAnchor(attachedBlock)
                    Shape {
                        parent: workspace
                        objectName: "commentConnector_" + commentCard.modelData.id
                        z: -2
                        visible: !!commentCard.attachedBlock
                        ShapePath {
                            strokeColor: Theme.textDim
                            strokeWidth: 1.5
                            fillColor: "transparent"
                            startX: commentCard.blockAnchor.x
                            startY: commentCard.blockAnchor.y
                            PathLine {
                                // End inside the card so its rounded surface masks the line.
                                x: commentCard.x + commentCard.width / 2
                                y: commentCard.y + commentCard.height / 2
                            }
                        }
                    }
                    readonly property real headerH: 38
                    readonly property real bodyMinH: 74
                    readonly property real bodyMaxH: 240
                    x: modelData.x + root.originOffsetX
                    y: modelData.y + root.originOffsetY
                    z: 4
                    width: 220
                    height: modelData.collapsed ? headerH : headerH + 1 + Math.min(bodyMaxH, Math.max(bodyMinH, bodyArea.implicitHeight + 14))
                    radius: Theme.radius
                    color: Theme.panelRaised
                    border.color: Theme.border
                    clip: true
                    Row {
                        id: headerRow
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.leftMargin: 8
                        anchors.rightMargin: 4
                        height: commentCard.headerH
                        spacing: 7
                        LucideIcon {
                            name: "message-square"
                            color: Theme.textDim
                            width: 14
                            height: 14
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            id: commentLabel
                            text: qsTr("Comment")
                            color: Theme.textDim
                            font.pixelSize: 12
                            font.weight: Font.Medium
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Item {
                            width: Math.max(0, parent.width - 14 - commentLabel.width - collapseBtn.width - parent.spacing * 3)
                            height: 1
                        }
                        BwButton {
                            id: collapseBtn
                            iconName: commentCard.modelData.collapsed ? "chevron-down" : "chevron-up"
                            text: ""
                            flat: true
                            implicitWidth: 24
                            implicitHeight: 24
                            anchors.verticalCenter: parent.verticalCenter
                            onClicked: root.commentCollapseChanged(commentCard.modelData.id, !commentCard.modelData.collapsed)
                        }
                    }
                    Rectangle {
                        id: commentDivider
                        visible: !commentCard.modelData.collapsed
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: headerRow.bottom
                        height: 1
                        color: Theme.borderSoft
                    }
                    ScrollView {
                        id: bodyScroll
                        objectName: "commentScroll_" + commentCard.modelData.id
                        visible: !commentCard.modelData.collapsed
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: commentDivider.bottom
                        anchors.bottom: parent.bottom
                        contentWidth: availableWidth
                        clip: true
                        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                        TextArea {
                            id: bodyArea
                            objectName: "commentText_" + commentCard.modelData.id
                            ContextMenu.menu: root.textMenu ? root.textMenu.createObject(bodyArea, {
                                editor: bodyArea
                            }) : null
                            text: commentCard.modelData.text
                            color: Theme.text
                            wrapMode: TextEdit.Wrap
                            padding: 7
                            background: null
                            TextSelectHold {}
                            onActiveFocusChanged: if (!activeFocus && text !== commentCard.modelData.text)
                                root.commentEdited(commentCard.modelData.id, text)
                        }
                    }
                    DragHandler {
                        parent: headerRow
                        enabled: !root.locked
                        target: commentCard
                        onActiveChanged: if (!active)
                            root.commentMoved(commentCard.modelData.id, Math.round(commentCard.x - root.originOffsetX), Math.round(commentCard.y - root.originOffsetY))
                    }
                    TapHandler {
                        acceptedButtons: Qt.RightButton
                        gesturePolicy: TapHandler.ReleaseWithinBounds
                        onTapped: commentMenu.popup()
                    }
                    BwMenu {
                        id: commentMenu
                        BwMenuItem {
                            iconName: "trash"
                            danger: true
                            text: qsTr("Delete comment")
                            onTriggered: root.commentRemoved(commentCard.modelData.id)
                        }
                    }
                }
            }
            Repeater {
                model: root.floatingValues || []
                delegate: Item {
                    id: floatingItem
                    required property var modelData
                    x: modelData.x + root.originOffsetX
                    y: modelData.y + root.originOffsetY
                    z: 5
                    width: floatingChip.implicitWidth
                    height: floatingChip.implicitHeight
                    ValueChip {
                        id: floatingChip
                        valueData: floatingItem.modelData.value
                        originBlockId: floatingItem.modelData.origin_block_id || ""
                        location: ({
                                kind: "Floating",
                                floating_id: floatingItem.modelData.id,
                                path: []
                            })
                        boxed: true
                        blockDefinitions: root.blockDefinitions
                        onEditRequested: (l, t) => root.valueEdited(l, t)
                        onDetailsRequested: kind => root.detailsRequested(kind)
                        onValueDragBegan: (loc, val, sx, sy, ox, oy, w, h) => root.beginValueDrag(loc, val, sx, sy, ox, oy, w, h)
                        onValueDragMoved: (sx, sy) => root.moveValueDrag(sx, sy)
                        onValueDragEnded: (sx, sy) => root.endValueDrag(sx, sy)
                        onValueDragCanceled: root.cancelValueDrag()
                        // The chip's own menu, so one right-click opens one menu.
                        extraMenu: [
                            {
                                id: "details",
                                text: qsTr("Details"),
                                icon: "info"
                            },
                            {
                                id: "delete",
                                text: qsTr("Delete value"),
                                icon: "trash",
                                danger: true
                            }
                        ]
                        onExtraMenuTriggered: id => {
                            if (id === "delete")
                                root.floatingValueRemoved(floatingItem.modelData.id);
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
            delegate: Rectangle {
                id: listCard
                required property string editorName
                required property string payload
                required property real editorX
                required property real editorY
                readonly property var modelData: JSON.parse(payload)
                objectName: "listEditor_" + modelData.name
                readonly property real maxX: Math.max(0, collectionOverlay.width - width)
                readonly property real maxY: Math.max(0, collectionOverlay.height - height)
                visible: modelData.editor_visible
                x: Math.max(0, Math.min(editorX, maxX))
                y: Math.max(0, Math.min(editorY, maxY))
                z: 12
                function keepInView() {
                    if (x < 0 || x > maxX)
                        x = Math.max(0, Math.min(x, maxX));
                    if (y < 0 || y > maxY)
                        y = Math.max(0, Math.min(y, maxY));
                }
                onMaxXChanged: keepInView()
                onMaxYChanged: keepInView()
                width: 300
                height: Math.min(400, 90 + Math.max(64, (modelData.items || []).length * 40 + 14))
                radius: 12
                color: Theme.panel
                border.color: Theme.borderSoft
                clip: true
                function itemFromText(value) {
                    const trimmed = value.trim();
                    const number = Number(value);
                    return trimmed.length && Number.isFinite(number) ? {
                        kind: "Number",
                        value: number
                    } : {
                        kind: "Text",
                        value: value
                    };
                }
                function editItem(index, value) {
                    const next = JSON.parse(JSON.stringify(modelData.items || []));
                    next[index] = itemFromText(value);
                    root.listItemsEdited(modelData.name, next);
                }
                function removeItem(index) {
                    const next = JSON.parse(JSON.stringify(modelData.items || []));
                    next.splice(index, 1);
                    root.listItemsEdited(modelData.name, next);
                }
                function addItem(index, value) {
                    const next = JSON.parse(JSON.stringify(modelData.items || []));
                    for (let i = 0; i < listRepeater.count; ++i) {
                        const row = listRepeater.itemAt(i);
                        if (row && row.field.text !== String(next[i].value))
                            next[i] = itemFromText(row.field.text);
                        if (row)
                            row.field.submitting = true;
                    }
                    if (index !== undefined)
                        next[index] = itemFromText(value);
                    root.pendingListFocus = {
                        name: modelData.name,
                        index: next.length
                    };
                    next.push({
                        kind: "Text",
                        value: ""
                    });
                    root.listItemsEdited(modelData.name, next);
                }
                Rectangle {
                    id: listHead
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    height: 44
                    color: "transparent"
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 1
                        color: Theme.borderSoft
                    }
                    // Accept the press before the canvas can start panning.
                    MouseArea {
                        id: listHeaderDrag
                        objectName: "listHeaderDrag"
                        anchors.fill: parent
                        enabled: !root.locked
                        acceptedButtons: Qt.LeftButton
                        preventStealing: true
                        drag.target: listCard
                        drag.minimumX: 0
                        drag.maximumX: listCard.maxX
                        drag.minimumY: 0
                        drag.maximumY: listCard.maxY
                        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                        onReleased: if (drag.active)
                            root.listEditorStateChanged(listCard.modelData.name, true, Math.round(listCard.x), Math.round(listCard.y))
                    }
                    Row {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 8
                        LucideIcon {
                            name: "layers"
                            color: Theme.textDim
                            width: 16
                            height: 16
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: listCard.modelData.name
                            color: Theme.text
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            width: parent.width - 16 - 28 - 16
                            elide: Text.ElideRight
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        BwButton {
                            iconName: "x"
                            text: ""
                            flat: true
                            implicitWidth: 28
                            implicitHeight: 28
                            anchors.verticalCenter: parent.verticalCenter
                            onClicked: root.listEditorStateChanged(listCard.modelData.name, false, Math.round(listCard.x), Math.round(listCard.y))
                        }
                    }
                }
                Flickable {
                    id: listScroll
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: listHead.bottom
                    anchors.bottom: listFoot.top
                    contentHeight: listRows.implicitHeight
                    clip: true
                    Column {
                        id: listRows
                        width: parent.width
                        spacing: 6
                        padding: 10
                        Text {
                            visible: !(listCard.modelData.items || []).length
                            text: qsTr("This list is empty.")
                            color: Theme.textDim
                            font.pixelSize: 12
                            width: parent.width - 20
                            height: 44
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        Repeater {
                            id: listRepeater
                            model: listCard.modelData.items || []
                            delegate: Row {
                                property alias field: itemField
                                required property var modelData
                                required property int index
                                spacing: 6
                                width: listRows.width - 20
                                height: 34
                                Text {
                                    text: String(index + 1)
                                    color: Theme.textDim
                                    font.pixelSize: 11
                                    width: 18
                                    horizontalAlignment: Text.AlignRight
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                BwTextField {
                                    id: itemField
                                    objectName: "listItem_" + index
                                    property bool submitting: false
                                    text: String(modelData.value)
                                    color: modelData.kind === "Number" ? Theme.accent : Theme.text
                                    width: parent.width - 18 - 28 - 12
                                    implicitHeight: 34
                                    font.pixelSize: 13
                                    function appendItem(event) {
                                        event.accepted = true;
                                        submitting = true;
                                        listCard.addItem(index, text);
                                    }
                                    Keys.onReturnPressed: event => appendItem(event)
                                    Keys.onEnterPressed: event => appendItem(event)
                                    onEditingFinished: if (!submitting && text !== String(modelData.value))
                                        listCard.editItem(index, text)
                                    Component.onCompleted: Qt.callLater(function () {
                                        const pending = root.pendingListFocus;
                                        if (!pending || pending.name !== listCard.modelData.name || pending.index !== index)
                                            return;
                                        root.pendingListFocus = null;
                                        itemField.forceActiveFocus();
                                        itemField.selectAll();
                                        listRows.forceLayout();
                                        const position = itemField.mapToItem(listRows, 0, 0);
                                        listScroll.contentY = Math.max(0, Math.min(position.y, listScroll.contentHeight - listScroll.height));
                                    })
                                }
                                BwButton {
                                    iconName: "trash-2"
                                    text: ""
                                    flat: true
                                    danger: hovered
                                    implicitWidth: 28
                                    implicitHeight: 28
                                    anchors.verticalCenter: parent.verticalCenter
                                    onClicked: listCard.removeItem(index)
                                }
                            }
                        }
                    }
                }
                Rectangle {
                    id: listFoot
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 46
                    color: "transparent"
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        height: 1
                        color: Theme.borderSoft
                    }
                    BwButton {
                        objectName: "addListItem"
                        iconName: "plus"
                        text: qsTr("Add item")
                        implicitHeight: 30
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        onClicked: listCard.addItem()
                    }
                    Text {
                        text: qsTr("%n item(s)", "", (listCard.modelData.items || []).length)
                        color: Theme.textDim
                        font.pixelSize: 11
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }
        Repeater {
            model: dictEditorModel
            delegate: Rectangle {
                id: dictCard
                required property string editorName
                required property string payload
                required property real editorX
                required property real editorY
                readonly property var modelData: JSON.parse(payload)
                objectName: "dictEditor_" + modelData.name
                readonly property real maxX: Math.max(0, collectionOverlay.width - width)
                readonly property real maxY: Math.max(0, collectionOverlay.height - height)
                function keepInView() {
                    if (x < 0 || x > maxX)
                        x = Math.max(0, Math.min(x, maxX));
                    if (y < 0 || y > maxY)
                        y = Math.max(0, Math.min(y, maxY));
                }
                onMaxXChanged: keepInView()
                onMaxYChanged: keepInView()
                readonly property var entries: modelData.entries || []
                visible: modelData.editor_visible
                x: Math.max(0, Math.min(editorX, maxX))
                y: Math.max(0, Math.min(editorY, maxY))
                z: 12
                width: 360
                height: Math.min(420, 90 + Math.max(64, entries.length * 40 + 14))
                radius: 12
                color: Theme.panel
                border.color: Theme.borderSoft
                clip: true
                // A monitor edit is a literal: finite numbers stay numeric.
                function itemFromText(value) {
                    const trimmed = value.trim();
                    const number = Number(value);
                    return trimmed.length && Number.isFinite(number) ? {
                        kind: "Number",
                        value: number
                    } : {
                        kind: "Text",
                        value: value
                    };
                }
                function save(next) {
                    root.dictEntriesEdited(modelData.name, next);
                }
                function copy() {
                    return JSON.parse(JSON.stringify(entries));
                }
                function editKey(index, key) {
                    const next = copy();
                    next[index].key = key;
                    save(next);
                }
                function editValue(index, value) {
                    const next = copy();
                    next[index].value = itemFromText(value);
                    save(next);
                }
                function removeEntry(index) {
                    const next = copy();
                    next.splice(index, 1);
                    save(next);
                }
                function addEntry() {
                    const next = copy();
                    for (let i = 0; i < dictRepeater.count; ++i) {
                        const row = dictRepeater.itemAt(i);
                        if (!row)
                            continue;
                        next[i].key = row.keyField.text;
                        if (row.valueField.text !== String(next[i].value.value))
                            next[i].value = itemFromText(row.valueField.text);
                        row.submitting = true;
                    }
                    root.pendingDictFocus = {
                        name: modelData.name,
                        index: next.length
                    };
                    next.push({
                        key: "",
                        value: {
                            kind: "Text",
                            value: ""
                        }
                    });
                    save(next);
                }
                Rectangle {
                    id: dictHead
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    height: 44
                    color: "transparent"
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 1
                        color: Theme.borderSoft
                    }
                    // Accept the press before the canvas can start panning.
                    MouseArea {
                        id: dictHeaderDrag
                        objectName: "dictHeaderDrag"
                        anchors.fill: parent
                        enabled: !root.locked
                        acceptedButtons: Qt.LeftButton
                        preventStealing: true
                        drag.target: dictCard
                        drag.minimumX: 0
                        drag.maximumX: dictCard.maxX
                        drag.minimumY: 0
                        drag.maximumY: dictCard.maxY
                        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                        onReleased: if (drag.active)
                            root.dictEditorStateChanged(dictCard.modelData.name, true, Math.round(dictCard.x), Math.round(dictCard.y))
                    }
                    Row {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 8
                        LucideIcon {
                            name: "book-key"
                            color: Theme.textDim
                            width: 16
                            height: 16
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: dictCard.modelData.name
                            color: Theme.text
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            width: parent.width - 16 - 28 - 16
                            elide: Text.ElideRight
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        BwButton {
                            iconName: "x"
                            text: ""
                            flat: true
                            implicitWidth: 28
                            implicitHeight: 28
                            anchors.verticalCenter: parent.verticalCenter
                            onClicked: root.dictEditorStateChanged(dictCard.modelData.name, false, Math.round(dictCard.x), Math.round(dictCard.y))
                        }
                    }
                }
                Flickable {
                    id: dictScroll
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: dictHead.bottom
                    anchors.bottom: dictFoot.top
                    contentHeight: dictRows.implicitHeight
                    clip: true
                    Column {
                        id: dictRows
                        width: parent.width
                        spacing: 6
                        padding: 10
                        Text {
                            visible: !dictCard.entries.length
                            text: qsTr("This dict is empty.")
                            color: Theme.textDim
                            font.pixelSize: 12
                            width: parent.width - 20
                            height: 44
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        Repeater {
                            id: dictRepeater
                            model: dictCard.entries
                            delegate: Row {
                                id: entryRow
                                property alias keyField: dictKey
                                property alias valueField: dictValue
                                property bool submitting: false
                                function appendEntry(event) {
                                    event.accepted = true;
                                    dictCard.addEntry();
                                }
                                required property var modelData
                                required property int index
                                spacing: 6
                                width: dictRows.width - 20
                                height: 34
                                BwTextField {
                                    id: dictKey
                                    objectName: "dictKey_" + index
                                    Keys.onReturnPressed: event => entryRow.appendEntry(event)
                                    Keys.onEnterPressed: event => entryRow.appendEntry(event)
                                    Component.onCompleted: Qt.callLater(function () {
                                        const pending = root.pendingDictFocus;
                                        if (!pending || pending.name !== dictCard.modelData.name || pending.index !== index)
                                            return;
                                        root.pendingDictFocus = null;
                                        dictKey.forceActiveFocus();
                                        dictKey.selectAll();
                                        dictRows.forceLayout();
                                        const position = dictKey.mapToItem(dictRows, 0, 0);
                                        dictScroll.contentY = Math.max(0, Math.min(position.y, dictScroll.contentHeight - dictScroll.height));
                                    })
                                    text: modelData.key
                                    placeholderText: qsTr("key")
                                    width: 128
                                    implicitHeight: 34
                                    font.pixelSize: 13
                                    onEditingFinished: if (!entryRow.submitting && text !== modelData.key)
                                        dictCard.editKey(index, text)
                                }
                                LucideIcon {
                                    name: "arrow-right"
                                    color: Theme.textDim
                                    width: 13
                                    height: 13
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                BwTextField {
                                    id: dictValue
                                    objectName: "dictValue_" + index
                                    Keys.onReturnPressed: event => entryRow.appendEntry(event)
                                    Keys.onEnterPressed: event => entryRow.appendEntry(event)
                                    text: String(modelData.value.value)
                                    placeholderText: qsTr("value")
                                    color: modelData.value.kind === "Number" ? Theme.accent : Theme.text
                                    width: parent.width - 128 - 13 - 28 - 18
                                    implicitHeight: 34
                                    font.pixelSize: 13
                                    onEditingFinished: if (!entryRow.submitting && text !== String(modelData.value.value))
                                        dictCard.editValue(index, text)
                                }
                                BwButton {
                                    iconName: "trash-2"
                                    text: ""
                                    flat: true
                                    danger: hovered
                                    implicitWidth: 28
                                    implicitHeight: 28
                                    anchors.verticalCenter: parent.verticalCenter
                                    onClicked: dictCard.removeEntry(index)
                                }
                            }
                        }
                    }
                }
                Rectangle {
                    id: dictFoot
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 46
                    color: "transparent"
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        height: 1
                        color: Theme.borderSoft
                    }
                    BwButton {
                        objectName: "addDictEntry"
                        iconName: "plus"
                        text: qsTr("Add entry")
                        implicitHeight: 30
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        onClicked: dictCard.addEntry()
                    }
                    Text {
                        text: qsTr("%n entry(s)", "", dictCard.entries.length)
                        color: Theme.textDim
                        font.pixelSize: 11
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
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
        BwButton {
            iconName: "zoom-in"
            text: ""
            implicitWidth: 40
            implicitHeight: 40
            radius: 20
            onClicked: root.stepZoom(.1)
        }
        BwButton {
            iconName: "zoom-out"
            text: ""
            implicitWidth: 40
            implicitHeight: 40
            radius: 20
            onClicked: root.stepZoom(-.1)
        }
        BwButton {
            iconName: "rotate-ccw"
            text: ""
            implicitWidth: 40
            implicitHeight: 40
            radius: 20
            onClicked: root.resetView()
        }
    }
}
