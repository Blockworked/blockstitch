import QtQuick
import QtQuick.Controls

Item {
    id: root
    property var instruction
    property string strandId: ""
    property var path: []
    property var variables: []
    property var lists: []
    property var blockDefinitions: []
    property var keyCapture: null
    property bool paletteMode: false
    property bool locked: false
    property color blockColor: Theme.block
    // shared drag session owned by BlockCanvas (null for palette/preview blocks)
    property var dragState: null
    // number of instructions from this one to the end of its list (inclusive)
    property int tailCount: 1
    signal dragBegan(string strandId, var path, int tailCount, real sceneX, real sceneY, real offsetX, real offsetY, real blockW, real blockH)
    signal dragMoved(real sceneX, real sceneY)
    signal dragEnded(real sceneX, real sceneY)
    signal dragCanceled()
    signal activated()
    signal removeRequested(string strandId, var path)
    signal duplicateRequested(string strandId, var path, var instruction)
    signal commentRequested(var instruction)
    signal recordingTargetRequested(string strandId)
    signal instructionEdited(string strandId, var path, var instruction)
    signal valueEdited(var location, string text)
    signal valueDragBegan(var location, var value, real sceneX, real sceneY, real offsetX, real offsetY, real w, real h)
    signal valueDragMoved(real sceneX, real sceneY)
    signal valueDragEnded(real sceneX, real sceneY)
    signal valueDragCanceled()
    signal runBranchRequested(string strandId, var path, string name)
    signal keyCaptureRequested(string strandId, var path)
    signal appPickerRequested(string strandId, var path, var instruction)
    signal detailsRequested(string type)
    // A host menu entry from BlockRegistry.blockMenu was chosen.
    signal menuActionRequested(string action, string strandId, var path, var instruction)
    // A parameter oval dragged out of a custom block's header: the same drag
    // a palette value makes, with spec {kind:"value", value:{kind:"Param"}, originBlockId}.
    signal paletteDragStarted(var spec, real sceneX, real sceneY, real offsetX, real offsetY)
    signal paletteDragMoved(real sceneX, real sceneY)
    signal paletteDragEnded(real sceneX, real sceneY)
    signal paletteDragCanceled()

    readonly property string type: instruction ? instruction.type : ""
    readonly property bool isWrap: BlockRegistry.isWrap(type)
    readonly property bool isHeader: BlockRegistry.isHeader(type)
    readonly property bool isCap: BlockRegistry.isCap(instruction, blockDefinitions)
    // The host's declarative row for this type, if it registered one.
    readonly property var rowSpec: BlockRegistry.row(type)
    readonly property var headPieces: {
        BlockRegistry.revision;
        if (!rowSpec || !rowSpec.head) return [];
        return rowSpec.head.filter(p => !p.when || p.when(instruction));
    }
    readonly property int rowHeight: 58
    readonly property real tabDepth: 8
    readonly property real spine: 20
    readonly property real headHeight: 50
    readonly property real midHeight: 34
    readonly property real footHeight: 26
    readonly property real emptyMouth: 26
    readonly property bool hovered: grab.hovered && !grab.dragging
    // 0: unaffected, 1: moves with the dragged block (it or a later sibling), 2: contains the dragged block.
    // While `settling` (dropped, waiting for the daemon round trip) the tail
    // keeps its drop offset so it doesn't visibly snap back and teleport.
    readonly property int dragRole: {
        const d = dragState;
        if (!d) return 0;
        if (d.active && d.strandId === strandId) {
            const a = d.path, b = path;
            if (b.length > a.length) return 0;
            for (let i = 0; i < b.length - 1; ++i)
                if (b[i].index !== a[i].index || (b[i].slot || 0) !== (a[i].slot || 0)) return 0;
            if (b.length < a.length) return b[b.length - 1].index === a[b.length - 1].index ? 2 : 0;
            return b[b.length - 1].index >= a[a.length - 1].index ? 1 : 0;
        }
        if (d.settling && d.settleStrandId === strandId) {
            const a = d.settlePath || [], b = path;
            if (!a.length || b.length > a.length) return 0;
            for (let i = 0; i < b.length - 1; ++i)
                if (b[i].index !== a[i].index || (b[i].slot || 0) !== (a[i].slot || 0)) return 0;
            if (b.length < a.length) return b[b.length - 1].index === a[b.length - 1].index ? 2 : 0;
            return b[b.length - 1].index >= a[a.length - 1].index ? 1 : 0;
        }
        return 0;
    }
    readonly property bool isCustomBlock: ["CallBlock","BranchCallBlock","BlockHeader"].indexOf(type) >= 0
    readonly property color customColor: {
        if (instruction && isCustomBlock) {
            const d = defFor(instruction.block_id);
            if (d && d.color) return d.color;
        }
        return Theme.accent;
    }
    // Match the web canvas: the chosen color marks a custom block's icon and
    // hover outline, while the block body stays in the neutral canvas palette.
    readonly property color displayColor: isCustomBlock ? Theme.block : blockColor
    implicitWidth: isWrap ? Math.max(218, headContent.implicitWidth + 42, spine + bodyWidth + 24) : Math.max(isHeader ? 108 : 132, fields.implicitWidth + (isHeader ? 24 : 36))
    implicitHeight: isWrap ? headHeight + mouthTotal + Math.max(0, slotCount() - 1) * midHeight + footHeight + tabDepth : rowHeight
    z: dragRole > 0 ? 50 : hovered ? 2 : 1
    readonly property real dragOffsetX: {
        if (!dragState || dragRole !== 1) return 0;
        if (dragState.active) return dragState.dx;
        if (dragState.settling) return dragState.settleDx;
        return 0;
    }
    readonly property real dragOffsetY: {
        if (!dragState || dragRole !== 1) return 0;
        if (dragState.active) return dragState.dy;
        if (dragState.settling) return dragState.settleDy;
        return 0;
    }
    // Attach preview gap: stationary rows at/after the snap insertion point
    // shift down by exactly the dragged height, opening real room. Dragged
    // rows (dragRole 1) are excluded - they already follow the pointer.
    readonly property real snapShift: {
        const d = dragState;
        if (!d || !d.snapValid) return 0;
        if (d.snapTargetId !== strandId) return 0;
        if (dragRole === 1) return 0;
        const sp = d.snapPath || [];
        if (!sp.length || sp.length !== path.length) return 0;
        for (let i = 0; i < path.length - 1; ++i) {
            if (path[i].index !== sp[i].index) return 0;
            const a = (path[i].slot === undefined || path[i].slot === null) ? null : path[i].slot;
            const b = (sp[i].slot === undefined || sp[i].slot === null) ? null : sp[i].slot;
            if (a !== b) return 0;
        }
        if (path[path.length - 1].index < sp[sp.length - 1].index) return 0;
        return d.snapShiftAmt || Math.max(0, (d.snapHeight || 58) - 8);
    }
    transform: Translate { x: root.dragOffsetX; y: root.dragOffsetY + root.snapShift }

    // Heights/widths of each mouth's nested content, reported by the mouth delegates.
    property var mouthHeights: []
    property var mouthWidths: []
    property var flatEnds: []
    function isSnapMouth(k) {
        const d = dragState;
        if (!d || !d.snapValid) return false;
        if (d.snapTargetId !== strandId) return false;
        const sp = d.snapPath || [];
        if (sp.length !== path.length + 1) return false;
        for (let i = 0; i < path.length; ++i) {
            if (path[i].index !== sp[i].index) return false;
            if (i < path.length - 1) {
                const a = (path[i].slot === undefined || path[i].slot === null) ? null : path[i].slot;
                const b = (sp[i].slot === undefined || sp[i].slot === null) ? null : sp[i].slot;
                if (a !== b) return false;
            }
        }
        const mouthSlot = (sp[path.length - 1].slot === undefined || sp[path.length - 1].slot === null) ? null : sp[path.length - 1].slot;
        return mouthSlot === k;
    }
    // The mouth the dragged tail is being pulled out of (if this block's
    // mouth is it): mirrors isSnapMouth against the drag's source container
    // so the bracket shell collapses around the remaining prefix live.
    function isSourceMouth(k) {
        const d = dragState;
        if (!d || (!d.active && !d.settling)) return false;
        if (d.sourceStrandId !== strandId) return false;
        const sp = d.sourceBasePath || [];
        // NOTE: unlike a snap path (container + insertion step), the source
        // base path addresses the container itself, so it is the same length
        // as the owning wrap block's path.
        if (!sp.length || sp.length !== path.length) return false;
        for (let i = 0; i < path.length; ++i) {
            if (path[i].index !== sp[i].index) return false;
            if (i < path.length - 1) {
                const a = (path[i].slot === undefined || path[i].slot === null) ? null : path[i].slot;
                const b = (sp[i].slot === undefined || sp[i].slot === null) ? null : sp[i].slot;
                if (a !== b) return false;
            }
        }
        const mouthSlot = (sp[path.length - 1].slot === undefined || sp[path.length - 1].slot === null) ? null : sp[path.length - 1].slot;
        return mouthSlot === k;
    }
    readonly property var effMouthHeights: {
        const n = slotCount();
        const out = [];
        const grow = (dragState && dragState.snapGrowAmt !== undefined) ? dragState.snapGrowAmt : Math.max(0, ((dragState ? (dragState.snapHeight || 58) : 58) - 8));
        const shrink = (dragState && (dragState.active || dragState.settling) && typeof dragState.sourceShrink === "number") ? dragState.sourceShrink : 0;
        for (let k = 0; k < n; ++k) out.push(Math.max(emptyMouth, (mouthHeights[k] || emptyMouth) + (isSnapMouth(k) ? grow : 0) - (isSourceMouth(k) ? shrink : 0)));
        return out;
    }
    readonly property real mouthTotal: { let sum = 0; const e = effMouthHeights; for (let k = 0; k < slotCount(); ++k) sum += e[k] || emptyMouth; return sum; }
    readonly property real bodyWidth: mouthWidths.reduce((m, w) => Math.max(m, w), 0)
    function setMouth(i, height, width, flat) {
        if (mouthHeights[i] === height && mouthWidths[i] === width && flatEnds[i] === flat) return;
        const h = mouthHeights.slice(), w = mouthWidths.slice(), f = flatEnds.slice();
        h[i] = height; w[i] = width; f[i] = flat;
        mouthHeights = h; mouthWidths = w; flatEnds = f;
    }
    function mouthTop(k) { let y = headHeight; const e = effMouthHeights; for (let i = 0; i < k; ++i) y += (e[i] || emptyMouth) + midHeight; return y; }
    function lastIsCap(slot) { const b = body(slot); return b.length > 0 && BlockRegistry.isCap(b[b.length - 1], blockDefinitions); }

    // Where a press grabs this block: its own bars, spine and connector tabs, but
    // not the hollow mouths (those belong to the blocks nested in them or the canvas).
    function inRect(x, y, rx, ry, rw, rh) { return x >= rx && x < rx + rw && y >= ry && y < ry + rh; }
    function hitTest(x, y) {
        const w = width, t = tabDepth;
        if (!isWrap) {
            const bottomTab = !isCap, body = bottomTab ? height - t : height;
            if (inRect(x, y, 0, 0, w, body)) return !(!isHeader && inRect(x, y, 13, 0, 26, t));
            return bottomTab && inRect(x, y, 13, body, 26, t);
        }
        if (inRect(x, y, 0, 0, w, headHeight)) return !inRect(x, y, 13, 0, 26, t);
        if (inRect(x, y, spine + 13, headHeight, 26, t)) return true;
        const n = slotCount();
        let top = headHeight;
        for (let k = 0; k < n; ++k) {
            const mh = mouthHeights[k] || emptyMouth, barTop = top + mh, foot = k === n - 1;
            if (inRect(x, y, 0, top, spine, mh)) return true;
            const barH = foot ? footHeight : midHeight;
            if (inRect(x, y, 0, barTop, w, barH)) return !(inRect(x, y, spine + 13, barTop, 26, t) && !flatEnds[k]);
            if (inRect(x, y, foot ? 13 : spine + 13, barTop + barH, 26, t)) return true;
            top = barTop + barH;
        }
        return false;
    }

    function iconFor(t) { return BlockRegistry.iconFor(t); }
    function fieldLocation(fieldId) { return {kind:"Field",strand_id:strandId,index:path,field_id:fieldId,path:[]}; }
    function cloneInstruction() { return JSON.parse(JSON.stringify(instruction)); }
    function setField(name,value) { const n=cloneInstruction(); n[name]=value; instructionEdited(strandId,path,n); }
    function childPath(slot,index) { const p=JSON.parse(JSON.stringify(path)); if(p.length) p[p.length-1].slot=slot; p.push({index:index}); return p; }
    function body(slot) { return BlockRegistry.body(instruction, slot); }
    function slotCount() { return type === "BranchCallBlock" ? BlockRegistry.slotCount(instruction) : Math.max(1, BlockRegistry.slotCount(instruction)); }
    // Palette prefabs have no strand, so their slots edit the prefab itself.
    function setLeaf(key, path, leaf) {
        const n = cloneInstruction();
        if (!path.length) n[key] = leaf;
        else { let v = n[key]; for (let i = 0; i < path.length - 1; ++i) v = v.args[path[i]]; v.args[path[path.length - 1]] = leaf; }
        instructionEdited(strandId, root.path, n);
    }
    function pieceOptions(piece) { return BlockRegistry.choices(piece.options, instruction); }
    function pieceValue(piece) { const v = instruction ? instruction[piece.key] : undefined; return piece.decode ? piece.decode(v) : (typeof v === "string" ? v : (v === undefined || v === null ? "" : String(v))); }
    function setPiece(piece, chosen) { setField(piece.key, piece.encode ? piece.encode(chosen) : chosen); }
    function defFor(id) { for(let i=0;i<(blockDefinitions||[]).length;i++) if(blockDefinitions[i].id===id) return blockDefinitions[i]; return null; }
    function callLabel() { const d=instruction?defFor(instruction.block_id):null; if(!d) return "custom block"; return (d.pieces||[]).filter(p=>p.kind!=="Branch").map(p=>p.kind==="Label"?p.text:("("+p.name+")")).join(" "); }
    function callHeadPieces(){
        const d=instruction?defFor(instruction.block_id):null;if(!d)return [{kind:"Label",text:"(deleted block)",argIndex:-1}];
        const first=(d.pieces||[]).findIndex(p=>p.kind==="Branch");let arg=0;const out=[];
        for(let i=0;i<d.pieces.length;i++){const p=d.pieces[i];if(p.kind==="Input"){out.push({kind:"Input",text:p.name,argIndex:arg,bool:p.value_type==="Bool"});arg++;}else if(p.kind==="Label"&&(first<0||i<first))out.push({kind:"Label",text:p.text,argIndex:-1,bool:false});}
        return out;
    }
    function listNames(){return (lists||[]).map(l=>l.name);}
    function branchSeparator(slot){const d=instruction?defFor(instruction.block_id):null;if(!d)return "";let seen=-1;for(let i=0;i<(d.pieces||[]).length;i++){const p=d.pieces[i];if(p.kind!=="Branch")continue;seen++;if(seen===slot){for(let j=i+1;j<d.pieces.length;j++){if(d.pieces[j].kind==="Branch")break;if(d.pieces[j].kind==="Label")return d.pieces[j].text;}}}return "";}
    function headerPieces(){const d=instruction?defFor(instruction.block_id):null;if(!d)return [{kind:"Label",text:"(deleted block)"}];return (d.pieces||[]).filter(p=>p.kind!=="Branch");}
    function headerBranches(){const d=instruction?defFor(instruction.block_id):null;return d?(d.pieces||[]).filter(p=>p.kind==="Branch"):[];}

    BlockSurface {
        anchors.fill: parent
        shape: root.isWrap ? "wrap" : root.isHeader ? "header" : root.isCap ? "cap" : "stack"
        fill: root.displayColor; hovered: root.hovered || root.dragRole === 1
        hoverColor: root.isCustomBlock ? root.customColor : Theme.accent
        headHeight: root.headHeight; midHeight: root.midHeight; footHeight: root.footHeight; spine: root.spine
        mouthHeights: root.isWrap ? root.effMouthHeights : []
        flatEnds: root.flatEnds
    }
    QtObject { id: hitMask; function contains(point: point): bool { return root.hitTest(point.x, point.y); } }
    BlockDragArea {
        id: grab
        anchors.fill: parent
        containmentMask: hitMask
        dragEnabled: root.paletteMode || !root.locked
        onDragBegan: (sx, sy, ox, oy) => root.dragBegan(root.strandId, root.path, root.tailCount, sx, sy, ox, oy, root.implicitWidth, root.implicitHeight)
        onDragMoved: (sx, sy) => root.dragMoved(sx, sy)
        onDragEnded: (sx, sy) => root.dragEnded(sx, sy)
        onDragCanceled: root.dragCanceled()
        onActivated: root.activated()
        onContextRequested: (x, y) => blockMenu.popup(x, y)
        BwMenu {
            id: blockMenu
            BwMenuItem { visible: !root.paletteMode && BlockRegistry.recordingTargets; iconName: "target"; text: "Set Recording Target"; onTriggered: root.recordingTargetRequested(root.strandId) }
            BwMenuItem { visible: !root.paletteMode; iconName: "corner-down-right"; text: "Duplicate block"; onTriggered: root.duplicateRequested(root.strandId, root.path, root.instruction) }
            BwMenuItem { visible: !root.paletteMode; iconName: "message-square"; text: "Add Comment"; onTriggered: root.commentRequested(root.instruction) }
            BwMenuItem { iconName: "info"; text: "Details"; onTriggered: root.detailsRequested(root.type) }
            BwMenuItem { visible: !root.paletteMode; iconName: "trash"; danger: true; text: "Delete block"; onTriggered: root.removeRequested(root.strandId, root.path) }
        }
        Instantiator {
            model: root.paletteMode ? [] : BlockRegistry.blockMenu
            delegate: BwMenuItem {
                required property var modelData
                iconName: modelData.icon || ""; text: modelData.text; danger: !!modelData.danger
                onTriggered: root.menuActionRequested(modelData.id, root.strandId, root.path, root.instruction)
            }
            onObjectAdded: (index, object) => blockMenu.insertItem(index, object)
            onObjectRemoved: (index, object) => blockMenu.removeItem(object)
        }
    }
    Row {
        id: fields; visible: !root.isWrap; x: 14; y: Math.round((root.rowHeight-height-8)/2); spacing: 7
        LucideIcon { visible: !root.isHeader; name: root.iconFor(root.type); color: root.isCustomBlock ? root.customColor : Theme.textDim; width: 16; height: 16; anchors.verticalCenter: parent.verticalCenter }
        LucideIcon { visible: root.isHeader; name: root.iconFor(root.type); color: root.isCustomBlock ? root.customColor : Theme.accent; width: 16; height: 16; anchors.verticalCenter: parent.verticalCenter }
        Loader {
            active: !root.rowSpec; visible: active; anchors.verticalCenter: parent.verticalCenter
            sourceComponent: Row {
                spacing: 7
                Text { visible: root.type==="WhenRan"; text:"WHEN RAN"; color:Theme.textDim; font.pixelSize:12; font.weight:Font.DemiBold; font.letterSpacing:1; anchors.verticalCenter:parent.verticalCenter }
                Text { visible: root.type==="WhenBatteryDischargedTo"; text:"WHEN BATTERY DISCHARGED TO"; color:Theme.textDim; font.pixelSize:11; font.weight:Font.DemiBold; anchors.verticalCenter:parent.verticalCenter }
                ValueChip { visible: root.type==="WhenBatteryDischargedTo"; valueData:instruction?instruction.threshold:null; location:root.fieldLocation("BatteryDischargeThreshold"); boxed:false; onEditRequested:(l,t)=>root.valueEdited(l,t); blockDefinitions:root.blockDefinitions; onValueDragBegan:(loc,val,sx,sy,ox,oy,w,h)=>root.valueDragBegan(loc,val,sx,sy,ox,oy,w,h); onValueDragMoved:(sx,sy)=>root.valueDragMoved(sx,sy); onValueDragEnded:(sx,sy)=>root.valueDragEnded(sx,sy); onValueDragCanceled:()=>root.valueDragCanceled() }
                Text { visible: root.type==="WhenBatteryDischargedTo"; text:"%"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
                Text { visible: root.type==="WhenBatteryChargedTo"; text:"WHEN BATTERY CHARGED TO"; color:Theme.textDim; font.pixelSize:11; font.weight:Font.DemiBold; anchors.verticalCenter:parent.verticalCenter }
                ValueChip { visible: root.type==="WhenBatteryChargedTo"; valueData:instruction?instruction.threshold:null; location:root.fieldLocation("BatteryChargeThreshold"); boxed:false; onEditRequested:(l,t)=>root.valueEdited(l,t); blockDefinitions:root.blockDefinitions; onValueDragBegan:(loc,val,sx,sy,ox,oy,w,h)=>root.valueDragBegan(loc,val,sx,sy,ox,oy,w,h); onValueDragMoved:(sx,sy)=>root.valueDragMoved(sx,sy); onValueDragEnded:(sx,sy)=>root.valueDragEnded(sx,sy); onValueDragCanceled:()=>root.valueDragCanceled() }
                Text { visible: root.type==="WhenBatteryChargedTo"; text:"%"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
                Text { visible: root.type==="WhenTime"; text:"WHEN"; color:Theme.textDim; font.pixelSize:11; font.weight:Font.DemiBold; anchors.verticalCenter:parent.verticalCenter }
                BwComboBox { visible:root.type==="WhenTime"; model:["every day","weekly","monthly","yearly"]; implicitWidth:104; implicitHeight:30; font.pixelSize:12 }
                Text { visible:root.type==="WhenTime"; text:"at"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
                BwTextField { visible:root.type==="WhenTime"; text: instruction&&instruction.schedule ? String(instruction.schedule.hour).padStart(2,"0")+":"+String(instruction.schedule.minute).padStart(2,"0") : "09:00"; implicitWidth:72; implicitHeight:30; font.pixelSize:12 }
                Text { visible:root.type==="WhenPowerPluggedIn"; text:"WHEN POWER PLUGGED IN"; color:Theme.textDim; font.pixelSize:11; font.weight:Font.DemiBold; anchors.verticalCenter:parent.verticalCenter }
                Text { visible:root.type==="WhenPowerUnplugged"; text:"WHEN POWER UNPLUGGED"; color:Theme.textDim; font.pixelSize:11; font.weight:Font.DemiBold; anchors.verticalCenter:parent.verticalCenter }
                Text { visible:root.type==="WhenClipboardChanged"; text:"WHEN CLIPBOARD CHANGES"; color:Theme.textDim; font.pixelSize:11; font.weight:Font.DemiBold; anchors.verticalCenter:parent.verticalCenter }
                Text { visible:root.type==="Wait"; text:"Wait (ms):"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
                ValueChip { visible:root.type==="Wait"; valueData:instruction?instruction.duration:null; location:root.fieldLocation("WaitDuration"); boxed:false; onEditRequested:(l,t)=>root.valueEdited(l,t); blockDefinitions:root.blockDefinitions; onValueDragBegan:(loc,val,sx,sy,ox,oy,w,h)=>root.valueDragBegan(loc,val,sx,sy,ox,oy,w,h); onValueDragMoved:(sx,sy)=>root.valueDragMoved(sx,sy); onValueDragEnded:(sx,sy)=>root.valueDragEnded(sx,sy); onValueDragCanceled:()=>root.valueDragCanceled() }
                Text { visible:root.type==="Text"; text:"Text:"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
                ValueChip { visible:root.type==="Text"; valueData:instruction?instruction.text:null; location:root.fieldLocation("TextValue"); boxed:false; onEditRequested:(l,t)=>root.valueEdited(l,t); blockDefinitions:root.blockDefinitions; onValueDragBegan:(loc,val,sx,sy,ox,oy,w,h)=>root.valueDragBegan(loc,val,sx,sy,ox,oy,w,h); onValueDragMoved:(sx,sy)=>root.valueDragMoved(sx,sy); onValueDragEnded:(sx,sy)=>root.valueDragEnded(sx,sy); onValueDragCanceled:()=>root.valueDragCanceled() }
                Text { visible:root.type==="Key"; text:"Key:"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
                BwButton { visible:root.type==="Key"; text:root.type!=="Key"?"":root.isCapturingKey()?"Press any key…":(instruction&&instruction.key?String(instruction.key):"a"); primary:root.isCapturingKey(); implicitHeight:30; font.pixelSize:12; onClicked:root.keyCaptureRequested(root.strandId,root.path) }
                BwComboBox { visible:root.type==="Key"; model:["Click","Press","Release"]; currentIndex: instruction?["Click","Press","Release"].indexOf(instruction.direction):0; implicitWidth:88; implicitHeight:30; font.pixelSize:12; onActivated:index=>root.setField("direction",currentText) }
                Text { visible:root.type==="Button"; text:"Mouse button:"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
                BwComboBox { visible:root.type==="Button"; model:["Left","Right","Middle","Side","Extra"]; currentIndex:instruction?["Left","Right","Middle","Side","Extra"].indexOf(instruction.button):0; implicitWidth:82; implicitHeight:30; font.pixelSize:12; onActivated:index=>root.setField("button",currentText) }
                BwComboBox { visible:root.type==="Button"; model:["Click","Press","Release"]; currentIndex:instruction?["Click","Press","Release"].indexOf(instruction.direction):0; implicitWidth:88; implicitHeight:30; font.pixelSize:12; onActivated:index=>root.setField("direction",currentText) }
                Text { visible:root.type==="MoveMouse"; text:"Move mouse"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
                BwComboBox { visible:root.type==="MoveMouse"; model:["Relative","Absolute"]; currentIndex:instruction&&instruction.coordinate==="Absolute"?1:0; implicitWidth:88; implicitHeight:30; font.pixelSize:12; onActivated:index=>root.setField("coordinate",currentText) }
                Text { visible:root.type==="MoveMouse"; text:"x"; color:Theme.textDim; anchors.verticalCenter:parent.verticalCenter }
                ValueChip { visible:root.type==="MoveMouse"; valueData:instruction?instruction.x:null; location:root.fieldLocation("MoveMouseX"); boxed:false; onEditRequested:(l,t)=>root.valueEdited(l,t); blockDefinitions:root.blockDefinitions; onValueDragBegan:(loc,val,sx,sy,ox,oy,w,h)=>root.valueDragBegan(loc,val,sx,sy,ox,oy,w,h); onValueDragMoved:(sx,sy)=>root.valueDragMoved(sx,sy); onValueDragEnded:(sx,sy)=>root.valueDragEnded(sx,sy); onValueDragCanceled:()=>root.valueDragCanceled() }
                Text { visible:root.type==="MoveMouse"; text:"y"; color:Theme.textDim; anchors.verticalCenter:parent.verticalCenter }
                ValueChip { visible:root.type==="MoveMouse"; valueData:instruction?instruction.y:null; location:root.fieldLocation("MoveMouseY"); boxed:false; onEditRequested:(l,t)=>root.valueEdited(l,t); blockDefinitions:root.blockDefinitions; onValueDragBegan:(loc,val,sx,sy,ox,oy,w,h)=>root.valueDragBegan(loc,val,sx,sy,ox,oy,w,h); onValueDragMoved:(sx,sy)=>root.valueDragMoved(sx,sy); onValueDragEnded:(sx,sy)=>root.valueDragEnded(sx,sy); onValueDragCanceled:()=>root.valueDragCanceled() }
                Text { visible:root.type==="Scroll"; text:"Scroll"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
                ValueChip { visible:root.type==="Scroll"; valueData:instruction?instruction.amount:null; location:root.fieldLocation("ScrollAmount"); boxed:false; onEditRequested:(l,t)=>root.valueEdited(l,t); blockDefinitions:root.blockDefinitions; onValueDragBegan:(loc,val,sx,sy,ox,oy,w,h)=>root.valueDragBegan(loc,val,sx,sy,ox,oy,w,h); onValueDragMoved:(sx,sy)=>root.valueDragMoved(sx,sy); onValueDragEnded:(sx,sy)=>root.valueDragEnded(sx,sy); onValueDragCanceled:()=>root.valueDragCanceled() }
                BwComboBox { visible:root.type==="Scroll"; model:["Vertical","Horizontal"]; currentIndex:instruction&&instruction.axis==="Horizontal"?1:0; implicitWidth:92; implicitHeight:30; font.pixelSize:12; onActivated:index=>root.setField("axis",currentText) }
                Text { visible:root.type==="Command"; text:"Run command:"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
                BwTextField { visible:root.type==="Command"; text:instruction&&instruction.command?instruction.command:""; placeholderText:"command"; implicitWidth:150; implicitHeight:30; font.pixelSize:12; onEditingFinished:root.setField("command",text) }
                Text { visible:root.type==="OpenApp"; text:"Open app:"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
                BwButton { visible:root.type==="OpenApp"; text:instruction&&instruction.name?instruction.name:"Choose app…"; iconSource:instruction&&instruction.icon?instruction.icon:""; iconName:instruction&&!instruction.icon&&instruction.name?"app-window":""; implicitHeight:30; font.pixelSize:12; onClicked: root.appPickerRequested(root.strandId, root.path, root.instruction) }
                Text { visible:root.type==="CloseApp"; text:"Close app:"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
                BwButton { visible:root.type==="CloseApp"; text:instruction&&instruction.name?instruction.name:"Choose app…"; iconSource:instruction&&instruction.icon?instruction.icon:""; iconName:instruction&&!instruction.icon&&instruction.name?"app-window":""; implicitHeight:30; font.pixelSize:12; onClicked: root.appPickerRequested(root.strandId, root.path, root.instruction) }
                Text { visible:root.type==="SetVariable"; text:"set"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
                BwComboBox { visible:root.type==="SetVariable"; model:Array.from(root.variables||[]); currentIndex:instruction?Array.from(root.variables||[]).indexOf(instruction.name):-1; displayText:currentIndex>=0?currentText:(instruction&&instruction.name?instruction.name:"Choose variable"); implicitWidth:106; implicitHeight:30; font.pixelSize:12; onActivated:index=>root.setField("name",currentText) }
                Text { visible:root.type==="SetVariable"; text:"to"; color:Theme.textDim; anchors.verticalCenter:parent.verticalCenter }
                ValueChip { visible:root.type==="SetVariable"; valueData:instruction?instruction.value:null; location:root.fieldLocation("SetVariableValue"); boxed:false; onEditRequested:(l,t)=>root.valueEdited(l,t); blockDefinitions:root.blockDefinitions; onValueDragBegan:(loc,val,sx,sy,ox,oy,w,h)=>root.valueDragBegan(loc,val,sx,sy,ox,oy,w,h); onValueDragMoved:(sx,sy)=>root.valueDragMoved(sx,sy); onValueDragEnded:(sx,sy)=>root.valueDragEnded(sx,sy); onValueDragCanceled:()=>root.valueDragCanceled() }
                Text { visible:root.type==="ChangeVariable"; text:"change"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
                BwComboBox { visible:root.type==="ChangeVariable"; model:Array.from(root.variables||[]); currentIndex:instruction?Array.from(root.variables||[]).indexOf(instruction.name):-1; displayText:currentIndex>=0?currentText:(instruction&&instruction.name?instruction.name:"Choose variable"); implicitWidth:106; implicitHeight:30; font.pixelSize:12; onActivated:index=>root.setField("name",currentText) }
                Text { visible:root.type==="ChangeVariable"; text:"by"; color:Theme.textDim; anchors.verticalCenter:parent.verticalCenter }
                ValueChip { visible:root.type==="ChangeVariable"; valueData:instruction?instruction.value:null; location:root.fieldLocation("ChangeVariableValue"); boxed:false; onEditRequested:(l,t)=>root.valueEdited(l,t); blockDefinitions:root.blockDefinitions; onValueDragBegan:(loc,val,sx,sy,ox,oy,w,h)=>root.valueDragBegan(loc,val,sx,sy,ox,oy,w,h); onValueDragMoved:(sx,sy)=>root.valueDragMoved(sx,sy); onValueDragEnded:(sx,sy)=>root.valueDragEnded(sx,sy); onValueDragCanceled:()=>root.valueDragCanceled() }
                Text { visible:root.type==="SetClipboard"; text:"set clipboard to"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
                ValueChip { visible:root.type==="SetClipboard"; valueData:instruction?instruction.value:null; location:root.fieldLocation("SetClipboardValue"); boxed:false; onEditRequested:(l,t)=>root.valueEdited(l,t); blockDefinitions:root.blockDefinitions; onValueDragBegan:(loc,val,sx,sy,ox,oy,w,h)=>root.valueDragBegan(loc,val,sx,sy,ox,oy,w,h); onValueDragMoved:(sx,sy)=>root.valueDragMoved(sx,sy); onValueDragEnded:(sx,sy)=>root.valueDragEnded(sx,sy); onValueDragCanceled:()=>root.valueDragCanceled() }
                Text { visible:root.type==="AddToList"; text:"add"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
                ValueChip { visible:root.type==="AddToList"; valueData:instruction?instruction.value:null; location:root.fieldLocation("AddToListValue"); boxed:false; onEditRequested:(l,t)=>root.valueEdited(l,t); blockDefinitions:root.blockDefinitions; onValueDragBegan:(loc,val,sx,sy,ox,oy,w,h)=>root.valueDragBegan(loc,val,sx,sy,ox,oy,w,h); onValueDragMoved:(sx,sy)=>root.valueDragMoved(sx,sy); onValueDragEnded:(sx,sy)=>root.valueDragEnded(sx,sy); onValueDragCanceled:()=>root.valueDragCanceled() }
                Text { visible:root.type==="AddToList"; text:"to"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
                Text { visible:root.type==="DeleteOfList"; text:"delete"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
                ValueChip { visible:root.type==="DeleteOfList"; valueData:instruction?instruction.index:null; location:root.fieldLocation("DeleteOfListIndex"); boxed:false; onEditRequested:(l,t)=>root.valueEdited(l,t); blockDefinitions:root.blockDefinitions; onValueDragBegan:(loc,val,sx,sy,ox,oy,w,h)=>root.valueDragBegan(loc,val,sx,sy,ox,oy,w,h); onValueDragMoved:(sx,sy)=>root.valueDragMoved(sx,sy); onValueDragEnded:(sx,sy)=>root.valueDragEnded(sx,sy); onValueDragCanceled:()=>root.valueDragCanceled() }
                Text { visible:root.type==="DeleteOfList"; text:"of"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
                Text { visible:root.type==="DeleteAllOfList"; text:"delete all of"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
                Text { visible:root.type==="ShiftList"; text:"shift"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
                BwComboBox { visible:["AddToList","DeleteOfList","DeleteAllOfList","ShiftList"].indexOf(root.type)>=0; model:root.listNames(); currentIndex:instruction?root.listNames().indexOf(instruction.name):-1; displayText:currentIndex>=0?currentText:(instruction&&instruction.name?instruction.name:"Choose list"); implicitWidth:98; implicitHeight:30; font.pixelSize:12; onActivated:index=>root.setField("name",currentText) }
                Text { visible:root.type==="ShiftList"; text:"by"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
                ValueChip { visible:root.type==="ShiftList"; valueData:instruction?instruction.amount:null; location:root.fieldLocation("ShiftListAmount"); boxed:false; onEditRequested:(l,t)=>root.valueEdited(l,t); blockDefinitions:root.blockDefinitions; onValueDragBegan:(loc,val,sx,sy,ox,oy,w,h)=>root.valueDragBegan(loc,val,sx,sy,ox,oy,w,h); onValueDragMoved:(sx,sy)=>root.valueDragMoved(sx,sy); onValueDragEnded:(sx,sy)=>root.valueDragEnded(sx,sy); onValueDragCanceled:()=>root.valueDragCanceled() }
                Text { visible:root.type==="InsertIntoList"; text:"insert"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
                ValueChip { visible:root.type==="InsertIntoList"; valueData:instruction?instruction.value:null; location:root.fieldLocation("InsertIntoListValue"); boxed:false; onEditRequested:(l,t)=>root.valueEdited(l,t); blockDefinitions:root.blockDefinitions; onValueDragBegan:(loc,val,sx,sy,ox,oy,w,h)=>root.valueDragBegan(loc,val,sx,sy,ox,oy,w,h); onValueDragMoved:(sx,sy)=>root.valueDragMoved(sx,sy); onValueDragEnded:(sx,sy)=>root.valueDragEnded(sx,sy); onValueDragCanceled:()=>root.valueDragCanceled() }
                Text { visible:root.type==="InsertIntoList"; text:"at"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
                ValueChip { visible:root.type==="InsertIntoList"; valueData:instruction?instruction.index:null; location:root.fieldLocation("InsertIntoListIndex"); boxed:false; onEditRequested:(l,t)=>root.valueEdited(l,t); blockDefinitions:root.blockDefinitions; onValueDragBegan:(loc,val,sx,sy,ox,oy,w,h)=>root.valueDragBegan(loc,val,sx,sy,ox,oy,w,h); onValueDragMoved:(sx,sy)=>root.valueDragMoved(sx,sy); onValueDragEnded:(sx,sy)=>root.valueDragEnded(sx,sy); onValueDragCanceled:()=>root.valueDragCanceled() }
                Text { visible:root.type==="InsertIntoList"; text:"of"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
                BwComboBox { visible:root.type==="InsertIntoList"; model:root.listNames(); currentIndex:instruction?root.listNames().indexOf(instruction.name):-1; displayText:currentIndex>=0?currentText:(instruction&&instruction.name?instruction.name:"Choose list"); implicitWidth:98; implicitHeight:30; font.pixelSize:12; onActivated:index=>root.setField("name",currentText) }
                Text { visible:root.type==="ReplaceItemOfList"; text:"replace item"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
                ValueChip { visible:root.type==="ReplaceItemOfList"; valueData:instruction?instruction.index:null; location:root.fieldLocation("ReplaceItemOfListIndex"); boxed:false; onEditRequested:(l,t)=>root.valueEdited(l,t); blockDefinitions:root.blockDefinitions; onValueDragBegan:(loc,val,sx,sy,ox,oy,w,h)=>root.valueDragBegan(loc,val,sx,sy,ox,oy,w,h); onValueDragMoved:(sx,sy)=>root.valueDragMoved(sx,sy); onValueDragEnded:(sx,sy)=>root.valueDragEnded(sx,sy); onValueDragCanceled:()=>root.valueDragCanceled() }
                Text { visible:root.type==="ReplaceItemOfList"; text:"of"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
                BwComboBox { visible:root.type==="ReplaceItemOfList"; model:root.listNames(); currentIndex:instruction?root.listNames().indexOf(instruction.name):-1; displayText:currentIndex>=0?currentText:(instruction&&instruction.name?instruction.name:"Choose list"); implicitWidth:98; implicitHeight:30; font.pixelSize:12; onActivated:index=>root.setField("name",currentText) }
                Text { visible:root.type==="ReplaceItemOfList"; text:"with"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
                ValueChip { visible:root.type==="ReplaceItemOfList"; valueData:instruction?instruction.value:null; location:root.fieldLocation("ReplaceItemOfListValue"); boxed:false; onEditRequested:(l,t)=>root.valueEdited(l,t); blockDefinitions:root.blockDefinitions; onValueDragBegan:(loc,val,sx,sy,ox,oy,w,h)=>root.valueDragBegan(loc,val,sx,sy,ox,oy,w,h); onValueDragMoved:(sx,sy)=>root.valueDragMoved(sx,sy); onValueDragEnded:(sx,sy)=>root.valueDragEnded(sx,sy); onValueDragCanceled:()=>root.valueDragCanceled() }
                Text { visible:root.type==="ReverseList"; text:"reverse"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
                BwComboBox { visible:root.type==="ReverseList"; model:root.listNames(); currentIndex:instruction?root.listNames().indexOf(instruction.name):-1; displayText:currentIndex>=0?currentText:(instruction&&instruction.name?instruction.name:"Choose list"); implicitWidth:98; implicitHeight:30; font.pixelSize:12; onActivated:index=>root.setField("name",currentText) }
                Text { visible:root.type==="Return"; text:"return"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
                ValueChip { visible:root.type==="Return"; valueData:instruction?instruction.value:null; location:root.fieldLocation("ReturnValue"); boxed:false; onEditRequested:(l,t)=>root.valueEdited(l,t); blockDefinitions:root.blockDefinitions; onValueDragBegan:(loc,val,sx,sy,ox,oy,w,h)=>root.valueDragBegan(loc,val,sx,sy,ox,oy,w,h); onValueDragMoved:(sx,sy)=>root.valueDragMoved(sx,sy); onValueDragEnded:(sx,sy)=>root.valueDragEnded(sx,sy); onValueDragCanceled:()=>root.valueDragCanceled() }
                Text { visible:root.type==="EscapeLoop"; text:"break loop"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
                Text { visible:root.type==="ContinueLoop"; text:"continue loop"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
                Repeater { model:root.type==="CallBlock"?root.callHeadPieces():[];delegate:Item {
                    required property var modelData;width:modelData.kind==="Label"?callPieceText.implicitWidth:callPieceValue.implicitWidth;height:30
                    Text{id:callPieceText;visible:modelData.kind==="Label";text:modelData.text;color:Theme.text;font.pixelSize:12;font.weight:Font.DemiBold;anchors.centerIn:parent}
                    ValueChip{id:callPieceValue;visible:modelData.kind==="Input";valueData:instruction&&(instruction.args||[])[modelData.argIndex]?(instruction.args||[])[modelData.argIndex]:(modelData.bool?{kind:"Bool"}:{kind:"Number",value:0});location:root.fieldLocation("CallArg:"+modelData.argIndex);boxed:modelData.bool;anchors.centerIn:parent;onEditRequested:(l,t)=>root.valueEdited(l,t); blockDefinitions:root.blockDefinitions; onValueDragBegan:(loc,val,sx,sy,ox,oy,w,h)=>root.valueDragBegan(loc,val,sx,sy,ox,oy,w,h); onValueDragMoved:(sx,sy)=>root.valueDragMoved(sx,sy); onValueDragEnded:(sx,sy)=>root.valueDragEnded(sx,sy); onValueDragCanceled:()=>root.valueDragCanceled()}
                }}
                Repeater { model:root.type==="BlockHeader"?root.headerPieces():[];delegate:Item {
                    required property var modelData;width:modelData.kind==="Label"?headerText.implicitWidth:headerParam.implicitWidth;height:30
                    Text{id:headerText;visible:modelData.kind==="Label";text:modelData.text||"";color:Theme.text;font.pixelSize:12;font.weight:Font.DemiBold;anchors.centerIn:parent}
                    PaletteValue{id:headerParam;visible:modelData.kind==="Input";anchors.centerIn:parent;editable:false;valueData:({kind:"Param",name:modelData.name||""});forceBoolean:modelData.value_type==="Bool";blockDefinitions:root.blockDefinitions
                        spec:({kind:"value",value:valueData,forceBoolean:forceBoolean,originBlockId:root.instruction?root.instruction.block_id:null})
                        onDragStarted:(sp,sx,sy,ox,oy)=>root.paletteDragStarted(sp,sx,sy,ox,oy);onDragMoved:(sx,sy)=>root.paletteDragMoved(sx,sy);onDragEnded:(sx,sy)=>root.paletteDragEnded(sx,sy);onDragCanceled:root.paletteDragCanceled()}
                }}
                Repeater { model:root.type==="BlockHeader"?root.headerBranches():[];delegate:BwButton { required property var modelData;text:"run "+modelData.name;iconName:"git-branch";implicitHeight:30;font.pixelSize:11;onClicked:root.runBranchRequested(root.strandId,root.path,modelData.name) } }
                Text { visible:root.type==="RunBranch"; text:"run branch "+(instruction?instruction.name:""); color:Theme.text; font.pixelSize:12; font.weight:Font.DemiBold; anchors.verticalCenter:parent.verticalCenter }
            }
        }
        Repeater { model: root.isWrap ? [] : root.headPieces; delegate: pieceDelegate }
    }

    // Head bar content, then one mouth per body (nested blocks) with separator bars between them.
    Row {
        id:headContent; visible:root.isWrap; x:14; y:Math.round((root.headHeight-height)/2); spacing:7
        LucideIcon { name:root.iconFor(root.type); color:root.isCustomBlock?root.customColor:Theme.textDim; width:16;height:16; anchors.verticalCenter:parent.verticalCenter }
        Loader {
            active: !root.rowSpec; visible: active; anchors.verticalCenter: parent.verticalCenter
            sourceComponent: Row {
                spacing: 7
                Text { visible:root.type==="If"||root.type==="IfElse"; text:"if"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
                ValueChip { visible:root.type==="If"||root.type==="IfElse"||root.type==="While"; valueData:instruction?instruction.condition:null; location:root.fieldLocation("Condition"); boxed:true; onEditRequested:(l,t)=>root.valueEdited(l,t); blockDefinitions:root.blockDefinitions; onValueDragBegan:(loc,val,sx,sy,ox,oy,w,h)=>root.valueDragBegan(loc,val,sx,sy,ox,oy,w,h); onValueDragMoved:(sx,sy)=>root.valueDragMoved(sx,sy); onValueDragEnded:(sx,sy)=>root.valueDragEnded(sx,sy); onValueDragCanceled:()=>root.valueDragCanceled() }
                Text { visible:root.type==="If"||root.type==="IfElse"; text:"then"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
                Text { visible:root.type==="Repeat"; text:"repeat"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
                ValueChip { visible:root.type==="Repeat"; valueData:instruction?instruction.count:null; location:root.fieldLocation("RepeatCount"); boxed:false; onEditRequested:(l,t)=>root.valueEdited(l,t); blockDefinitions:root.blockDefinitions; onValueDragBegan:(loc,val,sx,sy,ox,oy,w,h)=>root.valueDragBegan(loc,val,sx,sy,ox,oy,w,h); onValueDragMoved:(sx,sy)=>root.valueDragMoved(sx,sy); onValueDragEnded:(sx,sy)=>root.valueDragEnded(sx,sy); onValueDragCanceled:()=>root.valueDragCanceled() }
                Text { visible:root.type==="Forever"; text:"forever"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
                Text { visible:root.type==="While"; text:"while"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
            }
        }
        Repeater { model: root.isWrap ? root.headPieces : []; delegate: pieceDelegate }
        Repeater { model:root.type==="BranchCallBlock"?root.callHeadPieces():[];delegate:Item {
            required property var modelData;width:modelData.kind==="Label"?branchPieceText.implicitWidth:branchPieceValue.implicitWidth;height:30
            Text{id:branchPieceText;visible:modelData.kind==="Label";text:modelData.text;color:Theme.text;font.pixelSize:12;font.weight:Font.DemiBold;anchors.centerIn:parent}
            ValueChip{id:branchPieceValue;visible:modelData.kind==="Input";valueData:instruction&&(instruction.args||[])[modelData.argIndex]?(instruction.args||[])[modelData.argIndex]:(modelData.bool?{kind:"Bool"}:{kind:"Number",value:0});location:root.fieldLocation("CallArg:"+modelData.argIndex);boxed:modelData.bool;anchors.centerIn:parent;onEditRequested:(l,t)=>root.valueEdited(l,t); blockDefinitions:root.blockDefinitions; onValueDragBegan:(loc,val,sx,sy,ox,oy,w,h)=>root.valueDragBegan(loc,val,sx,sy,ox,oy,w,h); onValueDragMoved:(sx,sy)=>root.valueDragMoved(sx,sy); onValueDragEnded:(sx,sy)=>root.valueDragEnded(sx,sy); onValueDragCanceled:()=>root.valueDragCanceled()}
        }}
    }

    Repeater {
        model: root.isWrap ? root.slotCount() : 0
        delegate: Item {
            id: slotDelegate; required property int index
            readonly property real contentHeight: slotBody.implicitHeight
            readonly property bool capEnd: root.lastIsCap(index)
            // the block sitting last in a mouth overlaps the bar below by its connector tab
            readonly property real mouthHeight: Math.max(root.emptyMouth, contentHeight - (capEnd || contentHeight === 0 ? 0 : root.tabDepth))
            readonly property real contentWidth: slotBody.implicitWidth
            function report() { root.setMouth(index, mouthHeight, contentWidth, capEnd); }
            onMouthHeightChanged: report()
            onContentWidthChanged: report()
            onCapEndChanged: report()
            Component.onCompleted: report()
            x: 0; y: root.mouthTop(index); width: root.width; height: mouthHeight
            Column {
                id: slotBody; x: root.spine; spacing: -8
                Repeater {
                    model: root.body(slotDelegate.index)
                    delegate: Loader {
                        required property var modelData; required property int index
                        source: "InstructionBlock.qml"; width: item ? item.implicitWidth : 0; height: item ? item.implicitHeight : 0
                        onLoaded: {
                            item.instruction = modelData; item.strandId = root.strandId; item.path = root.childPath(slotDelegate.index, index);
                            item.tailCount = root.body(slotDelegate.index).length - index;
                            item.variables = root.variables; item.lists = root.lists; item.blockDefinitions = root.blockDefinitions; item.keyCapture = root.keyCapture; item.locked = root.locked;
                            item.dragState = root.dragState;
                            item.removeRequested.connect((s, p) => root.removeRequested(s, p));
                            item.duplicateRequested.connect((s, p, i) => root.duplicateRequested(s, p, i));
                            item.commentRequested.connect(i => root.commentRequested(i));
                            item.recordingTargetRequested.connect(s => root.recordingTargetRequested(s));
                            item.instructionEdited.connect((s, p, i) => root.instructionEdited(s, p, i));
                            item.valueEdited.connect((l, t) => root.valueEdited(l, t));
                            item.valueDragBegan.connect((loc, val, sx, sy, ox, oy, w, h) => root.valueDragBegan(loc, val, sx, sy, ox, oy, w, h));
                            item.valueDragMoved.connect((sx, sy) => root.valueDragMoved(sx, sy));
                            item.valueDragEnded.connect((sx, sy) => root.valueDragEnded(sx, sy));
                            item.valueDragCanceled.connect(() => root.valueDragCanceled());
                            item.runBranchRequested.connect((s, p, n) => root.runBranchRequested(s, p, n));
                            item.keyCaptureRequested.connect((s, p) => root.keyCaptureRequested(s, p));
                            item.appPickerRequested.connect((s, p, i) => root.appPickerRequested(s, p, i));
                            item.detailsRequested.connect(t => root.detailsRequested(t));
                            item.menuActionRequested.connect((a, s, p, i) => root.menuActionRequested(a, s, p, i));
                            item.paletteDragStarted.connect((sp, sx, sy, ox, oy) => root.paletteDragStarted(sp, sx, sy, ox, oy));
                            item.paletteDragMoved.connect((sx, sy) => root.paletteDragMoved(sx, sy));
                            item.paletteDragEnded.connect((sx, sy) => root.paletteDragEnded(sx, sy));
                            item.paletteDragCanceled.connect(() => root.paletteDragCanceled());
                            item.dragBegan.connect(root.dragBegan); item.dragMoved.connect(root.dragMoved);
                            item.dragEnded.connect(root.dragEnded); item.dragCanceled.connect(root.dragCanceled);
                        }
                    }
                }
            }
            // separator bar below this mouth (not for the last: that is the foot bar)
            Text {
                visible: slotDelegate.index < root.slotCount() - 1
                x: root.spine + 8; y: slotDelegate.mouthHeight + Math.round((root.midHeight - height) / 2)
                text: root.type === "BranchCallBlock" ? root.branchSeparator(slotDelegate.index) : BlockRegistry.separator(root.type, slotDelegate.index)
                color: root.type === "BranchCallBlock" ? Theme.text : Theme.textDim; font.pixelSize: 12
            }
        }
    }

    // One piece of a registered row: a label, a value slot, a dropdown or a text field.
    Component {
        id: pieceDelegate
        Item {
            id: piece
            required property var modelData
            readonly property string kind: modelData.kind
            implicitWidth: kind === "label" ? pieceLabel.implicitWidth : kind === "value" ? (pieceValue.item ? pieceValue.item.implicitWidth : 0)
                         : kind === "dropdown" ? pieceDrop.implicitWidth : pieceText.implicitWidth
            implicitHeight: 30
            width: implicitWidth; height: implicitHeight
            anchors.verticalCenter: parent ? parent.verticalCenter : undefined
            Text { id: pieceLabel; visible: piece.kind === "label"; text: piece.modelData.text || ""; color: Theme.text; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
            Loader {
                id: pieceValue
                active: piece.kind === "value"
                anchors.verticalCenter: parent.verticalCenter
                sourceComponent: ValueChip {
                    valueData: root.instruction ? (root.instruction[piece.modelData.key] || (piece.modelData.bool ? { kind: "Bool" } : { kind: "Number", value: 0 })) : null
                    location: root.paletteMode ? null : root.fieldLocation(piece.modelData.field)
                    boxed: !!piece.modelData.bool; forceBoolean: !!piece.modelData.bool && (!valueData || valueData.kind === "Bool")
                    blockDefinitions: root.blockDefinitions
                    onEditRequested: (l, t) => root.valueEdited(l, t)
                    onLeafEdited: (p, leaf) => root.setLeaf(piece.modelData.key, p, leaf)
                    onDetailsRequested: kind => root.detailsRequested(kind)
                    onValueDragBegan: (loc, val, sx, sy, ox, oy, w, h) => root.valueDragBegan(loc, val, sx, sy, ox, oy, w, h)
                    onValueDragMoved: (sx, sy) => root.valueDragMoved(sx, sy)
                    onValueDragEnded: (sx, sy) => root.valueDragEnded(sx, sy)
                    onValueDragCanceled: root.valueDragCanceled()
                }
            }
            BwComboBox {
                id: pieceDrop
                visible: piece.kind === "dropdown"
                readonly property var choices: visible ? root.pieceOptions(piece.modelData) : []
                readonly property string current: visible ? root.pieceValue(piece.modelData) : ""
                readonly property int chosen: { for (let i = 0; i < choices.length; ++i) if (choices[i].value === current) return i; return -1; }
                model: choices; textRole: "label"; currentIndex: chosen
                displayText: chosen >= 0 ? choices[chosen].label : (current.length ? current : (piece.modelData.placeholder || "choose"))
                implicitWidth: Math.min(190, Math.max(56, dropMetrics.advanceWidth + 36)); implicitHeight: 28; font.pixelSize: 12
                leftPadding: 8; rightPadding: 26
                anchors.verticalCenter: parent.verticalCenter
                TextMetrics { id: dropMetrics; font: pieceDrop.font; text: pieceDrop.displayText }
                onActivated: index => root.setPiece(piece.modelData, pieceDrop.choices[index].value)
            }
            BwTextField {
                id: pieceText
                visible: piece.kind === "text"
                text: visible ? root.pieceValue(piece.modelData) : ""; placeholderText: piece.modelData.placeholder || ""
                implicitWidth: Math.min(200, Math.max(64, contentWidth + 20)); implicitHeight: 28; font.pixelSize: 12
                leftPadding: 7; rightPadding: 7; topPadding: 2; bottomPadding: 2
                anchors.verticalCenter: parent.verticalCenter
                onEditingFinished: if (text !== root.pieceValue(piece.modelData)) root.setField(piece.modelData.key, text)
            }
        }
    }

    function isCapturingKey() {
        if (type !== "Key" || !keyCapture) return false;
        if (paletteMode) return keyCapture.kind === "Standalone";
        return keyCapture.kind === "Strand" && keyCapture.strand_id === strandId && samePath(keyCapture.index, path);
    }
    // Paths from the daemon carry an explicit `slot: null` on every step; ours omit it.
    function samePath(a, b) {
        if (!a || !b || a.length !== b.length) return false;
        for (let i = 0; i < a.length; ++i)
            if (a[i].index !== b[i].index || (a[i].slot === undefined || a[i].slot === null ? -1 : a[i].slot) !== (b[i].slot === undefined || b[i].slot === null ? -1 : b[i].slot)) return false;
        return true;
    }
}
