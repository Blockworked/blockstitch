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
    signal dragBegan(string strandId, var path, int tailCount, real sceneX, real sceneY, real offsetX, real offsetY)
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
    signal runBranchRequested(string strandId, var path, string name)
    signal keyCaptureRequested(string strandId, var path)
    signal detailsRequested(string type)

    readonly property string type: instruction ? instruction.type : ""
    readonly property bool isWrap: ["If","IfElse","Repeat","Forever","While","BranchCallBlock"].indexOf(type) >= 0
    readonly property bool isHeader: type.indexOf("When") === 0 || type === "BlockHeader"
    readonly property bool isCap: ["Return","EscapeLoop","ContinueLoop"].indexOf(type) >= 0
    readonly property int rowHeight: 58
    readonly property real tabDepth: 8
    readonly property real spine: 20
    readonly property real headHeight: 50
    readonly property real midHeight: 34
    readonly property real footHeight: 26
    readonly property real emptyMouth: 26
    readonly property bool hovered: grab.hovered && !grab.dragging
    // 0: unaffected, 1: moves with the dragged block (it or a later sibling), 2: contains the dragged block
    readonly property int dragRole: {
        const d = dragState;
        if (!d || !d.active || d.strandId !== strandId) return 0;
        const a = d.path, b = path;
        if (b.length > a.length) return 0;
        for (let i = 0; i < b.length - 1; ++i)
            if (b[i].index !== a[i].index || (b[i].slot || 0) !== (a[i].slot || 0)) return 0;
        if (b.length < a.length) return b[b.length - 1].index === a[b.length - 1].index ? 2 : 0;
        return b[b.length - 1].index >= a[a.length - 1].index ? 1 : 0;
    }
    readonly property color displayColor: {
        if (instruction && ["CallBlock","BranchCallBlock","BlockHeader"].indexOf(type) >= 0) {
            const d = defFor(instruction.block_id); if (d && d.color) return d.color;
        }
        return blockColor;
    }
    implicitWidth: isWrap ? Math.max(218, headContent.implicitWidth + 42, spine + bodyWidth + 24) : Math.max(isHeader ? 108 : 132, fields.implicitWidth + (isHeader ? 24 : 36))
    implicitHeight: isWrap ? headHeight + mouthTotal + Math.max(0, slotCount() - 1) * midHeight + footHeight + tabDepth : rowHeight
    z: dragRole > 0 ? 50 : hovered ? 2 : 1
    transform: Translate { x: root.dragRole === 1 ? root.dragState.dx : 0; y: root.dragRole === 1 ? root.dragState.dy : 0 }

    // Heights/widths of each mouth's nested content, reported by the mouth delegates.
    property var mouthHeights: []
    property var mouthWidths: []
    property var flatEnds: []
    readonly property real mouthTotal: { let sum = 0; for (let k = 0; k < slotCount(); ++k) sum += mouthHeights[k] || emptyMouth; return sum; }
    readonly property real bodyWidth: mouthWidths.reduce((m, w) => Math.max(m, w), 0)
    function setMouth(i, height, width, flat) {
        if (mouthHeights[i] === height && mouthWidths[i] === width && flatEnds[i] === flat) return;
        const h = mouthHeights.slice(), w = mouthWidths.slice(), f = flatEnds.slice();
        h[i] = height; w[i] = width; f[i] = flat;
        mouthHeights = h; mouthWidths = w; flatEnds = f;
    }
    function mouthTop(k) { let y = headHeight; for (let i = 0; i < k; ++i) y += (mouthHeights[i] || emptyMouth) + midHeight; return y; }
    function isCapType(t) { return ["Return","EscapeLoop","ContinueLoop"].indexOf(t) >= 0; }
    function lastIsCap(slot) { const b = body(slot); return b.length > 0 && isCapType(b[b.length - 1].type); }

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

    function iconFor(t) {
        const p={WhenRan:"play",WhenBatteryDischargedTo:"battery-warning",WhenBatteryChargedTo:"battery-charging",WhenTime:"clock",WhenPowerPluggedIn:"plug-zap",WhenPowerUnplugged:"unplug",WhenClipboardChanged:"clipboard-check",Wait:"clock",Text:"text-cursor",Key:"keyboard",Button:"mouse-pointer-click",MoveMouse:"move",Scroll:"mouse",Command:"terminal",OpenApp:"app-window",CloseApp:"square-x",SetVariable:"equal",ChangeVariable:"trending-up",SetClipboard:"clipboard",AddToList:"plus",DeleteOfList:"trash",DeleteAllOfList:"trash",ShiftList:"arrow-left",InsertIntoList:"plus",ReplaceItemOfList:"repeat",ReverseList:"rotate",Return:"undo",If:"git-branch",IfElse:"git-fork",Repeat:"repeat",Forever:"infinity",While:"rotate",EscapeLoop:"log-out",ContinueLoop:"skip-forward",BlockHeader:"blocks",CallBlock:"blocks",BranchCallBlock:"blocks",RunBranch:"git-branch"};
        return p[t] || "blocks";
    }
    function fieldLocation(fieldId) { return {kind:"Field",strand_id:strandId,index:path,field_id:fieldId,path:[]}; }
    function cloneInstruction() { return JSON.parse(JSON.stringify(instruction)); }
    function setField(name,value) { const n=cloneInstruction(); n[name]=value; instructionEdited(strandId,path,n); }
    function childPath(slot,index) { const p=JSON.parse(JSON.stringify(path)); if(p.length) p[p.length-1].slot=slot; p.push({index:index}); return p; }
    function body(slot) { if(!instruction) return []; if(type==="BranchCallBlock")return (instruction.branches||[])[slot]||[];if(type==="IfElse") return slot===0?(instruction.then_body||[]):(instruction.else_body||[]); return instruction.body||[]; }
    function slotCount(){if(type==="BranchCallBlock")return instruction&&instruction.branches?instruction.branches.length:0;return type==="IfElse"?2:1;}
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
    function headerBranches(){const d=instruction?defFor(instruction.block_id):null;return d?(d.pieces||[]).filter(p=>p.kind==="Branch"):[];}

    BlockSurface {
        anchors.fill: parent
        shape: root.isWrap ? "wrap" : root.isHeader ? "header" : root.isCap ? "cap" : "stack"
        fill: root.displayColor; hovered: root.hovered || root.dragRole === 1
        headHeight: root.headHeight; midHeight: root.midHeight; footHeight: root.footHeight; spine: root.spine
        mouthHeights: root.isWrap ? Array.from({ length: root.slotCount() }, (_, k) => root.mouthHeights[k] || root.emptyMouth) : []
        flatEnds: root.flatEnds
    }
    QtObject { id: hitMask; function contains(point) { return root.hitTest(point.x, point.y); } }
    BlockDragArea {
        id: grab
        anchors.fill: parent
        containmentMask: hitMask
        dragEnabled: root.paletteMode || !root.locked
        onDragBegan: (sx, sy, ox, oy) => root.dragBegan(root.strandId, root.path, root.tailCount, sx, sy, ox, oy)
        onDragMoved: (sx, sy) => root.dragMoved(sx, sy)
        onDragEnded: (sx, sy) => root.dragEnded(sx, sy)
        onDragCanceled: root.dragCanceled()
        onActivated: root.activated()
        onContextRequested: (x, y) => blockMenu.popup(x, y)
        BwMenu {
            id: blockMenu
            BwMenuItem { visible: !root.paletteMode; iconName: "target"; text: "Set Recording Target"; onTriggered: root.recordingTargetRequested(root.strandId) }
            BwMenuItem { visible: !root.paletteMode; iconName: "corner-down-right"; text: "Duplicate block"; onTriggered: root.duplicateRequested(root.strandId, root.path, root.instruction) }
            BwMenuItem { visible: !root.paletteMode; iconName: "message-square"; text: "Add Comment"; onTriggered: root.commentRequested(root.instruction) }
            BwMenuItem { iconName: "info"; text: "Details"; onTriggered: root.detailsRequested(root.type) }
            BwMenuItem { visible: !root.paletteMode; iconName: "trash"; danger: true; text: "Delete block"; onTriggered: root.removeRequested(root.strandId, root.path) }
        }
    }
    Row {
        id: fields; visible: !root.isWrap; x: 14; y: Math.round((root.rowHeight-height-8)/2); spacing: 7
        LucideIcon { visible: !root.isHeader; name: root.iconFor(root.type); color: Theme.textDim; width: 16; height: 16; anchors.verticalCenter: parent.verticalCenter }
        LucideIcon { visible: root.isHeader; name: root.iconFor(root.type); color: Theme.accent; width: 16; height: 16; anchors.verticalCenter: parent.verticalCenter }
        Text { visible: root.type==="WhenRan"; text:"WHEN RAN"; color:Theme.textDim; font.pixelSize:12; font.weight:Font.DemiBold; font.letterSpacing:1; anchors.verticalCenter:parent.verticalCenter }
        Text { visible: root.type==="WhenBatteryDischargedTo"; text:"WHEN BATTERY DISCHARGED TO"; color:Theme.textDim; font.pixelSize:11; font.weight:Font.DemiBold; anchors.verticalCenter:parent.verticalCenter }
        ValueChip { visible: root.type==="WhenBatteryDischargedTo"; valueData:instruction?instruction.threshold:null; location:root.fieldLocation("BatteryDischargeThreshold"); boxed:false; onEditRequested:(l,t)=>root.valueEdited(l,t) }
        Text { visible: root.type==="WhenBatteryDischargedTo"; text:"%"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
        Text { visible: root.type==="WhenBatteryChargedTo"; text:"WHEN BATTERY CHARGED TO"; color:Theme.textDim; font.pixelSize:11; font.weight:Font.DemiBold; anchors.verticalCenter:parent.verticalCenter }
        ValueChip { visible: root.type==="WhenBatteryChargedTo"; valueData:instruction?instruction.threshold:null; location:root.fieldLocation("BatteryChargeThreshold"); boxed:false; onEditRequested:(l,t)=>root.valueEdited(l,t) }
        Text { visible: root.type==="WhenBatteryChargedTo"; text:"%"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
        Text { visible: root.type==="WhenTime"; text:"WHEN"; color:Theme.textDim; font.pixelSize:11; font.weight:Font.DemiBold; anchors.verticalCenter:parent.verticalCenter }
        BwComboBox { visible:root.type==="WhenTime"; model:["every day","weekly","monthly","yearly"]; implicitWidth:104; implicitHeight:30; font.pixelSize:12 }
        Text { visible:root.type==="WhenTime"; text:"at"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
        BwTextField { visible:root.type==="WhenTime"; text: instruction&&instruction.schedule ? String(instruction.schedule.hour).padStart(2,"0")+":"+String(instruction.schedule.minute).padStart(2,"0") : "09:00"; implicitWidth:72; implicitHeight:30; font.pixelSize:12 }
        Text { visible:root.type==="WhenPowerPluggedIn"; text:"WHEN POWER PLUGGED IN"; color:Theme.textDim; font.pixelSize:11; font.weight:Font.DemiBold; anchors.verticalCenter:parent.verticalCenter }
        Text { visible:root.type==="WhenPowerUnplugged"; text:"WHEN POWER UNPLUGGED"; color:Theme.textDim; font.pixelSize:11; font.weight:Font.DemiBold; anchors.verticalCenter:parent.verticalCenter }
        Text { visible:root.type==="WhenClipboardChanged"; text:"WHEN CLIPBOARD CHANGES"; color:Theme.textDim; font.pixelSize:11; font.weight:Font.DemiBold; anchors.verticalCenter:parent.verticalCenter }
        Text { visible:root.type==="Wait"; text:"Wait (ms):"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
        ValueChip { visible:root.type==="Wait"; valueData:instruction?instruction.duration:null; location:root.fieldLocation("WaitDuration"); boxed:false; onEditRequested:(l,t)=>root.valueEdited(l,t) }
        Text { visible:root.type==="Text"; text:"Text:"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
        ValueChip { visible:root.type==="Text"; valueData:instruction?instruction.text:null; location:root.fieldLocation("TextValue"); boxed:false; onEditRequested:(l,t)=>root.valueEdited(l,t) }
        Text { visible:root.type==="Key"; text:"Key:"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
        BwButton { visible:root.type==="Key"; text:root.isCapturingKey()?"Press any key…":(instruction&&instruction.key?instruction.key:"a"); primary:root.isCapturingKey(); implicitHeight:30; font.pixelSize:12; onClicked:root.keyCaptureRequested(root.strandId,root.path) }
        BwComboBox { visible:root.type==="Key"; model:["Click","Press","Release"]; currentIndex: instruction?["Click","Press","Release"].indexOf(instruction.direction):0; implicitWidth:88; implicitHeight:30; font.pixelSize:12; onActivated:index=>root.setField("direction",currentText) }
        Text { visible:root.type==="Button"; text:"Mouse button:"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
        BwComboBox { visible:root.type==="Button"; model:["Left","Right","Middle","Side","Extra"]; currentIndex:instruction?["Left","Right","Middle","Side","Extra"].indexOf(instruction.button):0; implicitWidth:82; implicitHeight:30; font.pixelSize:12; onActivated:index=>root.setField("button",currentText) }
        BwComboBox { visible:root.type==="Button"; model:["Click","Press","Release"]; currentIndex:instruction?["Click","Press","Release"].indexOf(instruction.direction):0; implicitWidth:88; implicitHeight:30; font.pixelSize:12; onActivated:index=>root.setField("direction",currentText) }
        Text { visible:root.type==="MoveMouse"; text:"Move mouse"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
        BwComboBox { visible:root.type==="MoveMouse"; model:["Relative","Absolute"]; currentIndex:instruction&&instruction.coordinate==="Absolute"?1:0; implicitWidth:88; implicitHeight:30; font.pixelSize:12; onActivated:index=>root.setField("coordinate",currentText) }
        Text { visible:root.type==="MoveMouse"; text:"x"; color:Theme.textDim; anchors.verticalCenter:parent.verticalCenter }
        ValueChip { visible:root.type==="MoveMouse"; valueData:instruction?instruction.x:null; location:root.fieldLocation("MoveMouseX"); boxed:false; onEditRequested:(l,t)=>root.valueEdited(l,t) }
        Text { visible:root.type==="MoveMouse"; text:"y"; color:Theme.textDim; anchors.verticalCenter:parent.verticalCenter }
        ValueChip { visible:root.type==="MoveMouse"; valueData:instruction?instruction.y:null; location:root.fieldLocation("MoveMouseY"); boxed:false; onEditRequested:(l,t)=>root.valueEdited(l,t) }
        Text { visible:root.type==="Scroll"; text:"Scroll"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
        ValueChip { visible:root.type==="Scroll"; valueData:instruction?instruction.amount:null; location:root.fieldLocation("ScrollAmount"); boxed:false; onEditRequested:(l,t)=>root.valueEdited(l,t) }
        BwComboBox { visible:root.type==="Scroll"; model:["Vertical","Horizontal"]; currentIndex:instruction&&instruction.axis==="Horizontal"?1:0; implicitWidth:92; implicitHeight:30; font.pixelSize:12; onActivated:index=>root.setField("axis",currentText) }
        Text { visible:root.type==="Command"; text:"Run command:"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
        BwTextField { visible:root.type==="Command"; text:instruction&&instruction.command?instruction.command:""; placeholderText:"command"; implicitWidth:150; implicitHeight:30; font.pixelSize:12; onEditingFinished:root.setField("command",text) }
        Text { visible:root.type==="OpenApp"; text:"Open app:"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
        BwButton { visible:root.type==="OpenApp"; text:instruction&&instruction.name?instruction.name:"Choose app…"; implicitHeight:30; font.pixelSize:12 }
        Text { visible:root.type==="CloseApp"; text:"Close app:"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
        BwButton { visible:root.type==="CloseApp"; text:instruction&&instruction.name?instruction.name:"Choose app…"; implicitHeight:30; font.pixelSize:12 }
        Text { visible:root.type==="SetVariable"; text:"set"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
        BwComboBox { visible:root.type==="SetVariable"; model:Array.from(root.variables||[]); currentIndex:instruction?Array.from(root.variables||[]).indexOf(instruction.name):-1; displayText:currentIndex>=0?currentText:(instruction&&instruction.name?instruction.name:"Choose variable"); implicitWidth:106; implicitHeight:30; font.pixelSize:12; onActivated:index=>root.setField("name",currentText) }
        Text { visible:root.type==="SetVariable"; text:"to"; color:Theme.textDim; anchors.verticalCenter:parent.verticalCenter }
        ValueChip { visible:root.type==="SetVariable"; valueData:instruction?instruction.value:null; location:root.fieldLocation("SetVariableValue"); boxed:false; onEditRequested:(l,t)=>root.valueEdited(l,t) }
        Text { visible:root.type==="ChangeVariable"; text:"change"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
        BwComboBox { visible:root.type==="ChangeVariable"; model:Array.from(root.variables||[]); currentIndex:instruction?Array.from(root.variables||[]).indexOf(instruction.name):-1; displayText:currentIndex>=0?currentText:(instruction&&instruction.name?instruction.name:"Choose variable"); implicitWidth:106; implicitHeight:30; font.pixelSize:12; onActivated:index=>root.setField("name",currentText) }
        Text { visible:root.type==="ChangeVariable"; text:"by"; color:Theme.textDim; anchors.verticalCenter:parent.verticalCenter }
        ValueChip { visible:root.type==="ChangeVariable"; valueData:instruction?instruction.value:null; location:root.fieldLocation("ChangeVariableValue"); boxed:false; onEditRequested:(l,t)=>root.valueEdited(l,t) }
        Text { visible:root.type==="SetClipboard"; text:"set clipboard to"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
        ValueChip { visible:root.type==="SetClipboard"; valueData:instruction?instruction.value:null; location:root.fieldLocation("SetClipboardValue"); boxed:false; onEditRequested:(l,t)=>root.valueEdited(l,t) }
        Text { visible:root.type==="AddToList"; text:"add"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
        ValueChip { visible:root.type==="AddToList"; valueData:instruction?instruction.value:null; location:root.fieldLocation("AddToListValue"); boxed:false; onEditRequested:(l,t)=>root.valueEdited(l,t) }
        Text { visible:root.type==="AddToList"; text:"to"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
        Text { visible:root.type==="DeleteOfList"; text:"delete"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
        ValueChip { visible:root.type==="DeleteOfList"; valueData:instruction?instruction.index:null; location:root.fieldLocation("DeleteOfListIndex"); boxed:false; onEditRequested:(l,t)=>root.valueEdited(l,t) }
        Text { visible:root.type==="DeleteOfList"; text:"of"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
        Text { visible:root.type==="DeleteAllOfList"; text:"delete all of"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
        Text { visible:root.type==="ShiftList"; text:"shift"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
        BwComboBox { visible:["AddToList","DeleteOfList","DeleteAllOfList","ShiftList"].indexOf(root.type)>=0; model:root.listNames(); currentIndex:instruction?root.listNames().indexOf(instruction.name):-1; displayText:currentIndex>=0?currentText:(instruction&&instruction.name?instruction.name:"Choose list"); implicitWidth:98; implicitHeight:30; font.pixelSize:12; onActivated:index=>root.setField("name",currentText) }
        Text { visible:root.type==="ShiftList"; text:"by"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
        ValueChip { visible:root.type==="ShiftList"; valueData:instruction?instruction.amount:null; location:root.fieldLocation("ShiftListAmount"); boxed:false; onEditRequested:(l,t)=>root.valueEdited(l,t) }
        Text { visible:root.type==="InsertIntoList"; text:"insert"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
        ValueChip { visible:root.type==="InsertIntoList"; valueData:instruction?instruction.value:null; location:root.fieldLocation("InsertIntoListValue"); boxed:false; onEditRequested:(l,t)=>root.valueEdited(l,t) }
        Text { visible:root.type==="InsertIntoList"; text:"at"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
        ValueChip { visible:root.type==="InsertIntoList"; valueData:instruction?instruction.index:null; location:root.fieldLocation("InsertIntoListIndex"); boxed:false; onEditRequested:(l,t)=>root.valueEdited(l,t) }
        Text { visible:root.type==="InsertIntoList"; text:"of"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
        BwComboBox { visible:root.type==="InsertIntoList"; model:root.listNames(); currentIndex:instruction?root.listNames().indexOf(instruction.name):-1; displayText:currentIndex>=0?currentText:(instruction&&instruction.name?instruction.name:"Choose list"); implicitWidth:98; implicitHeight:30; font.pixelSize:12; onActivated:index=>root.setField("name",currentText) }
        Text { visible:root.type==="ReplaceItemOfList"; text:"replace item"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
        ValueChip { visible:root.type==="ReplaceItemOfList"; valueData:instruction?instruction.index:null; location:root.fieldLocation("ReplaceItemOfListIndex"); boxed:false; onEditRequested:(l,t)=>root.valueEdited(l,t) }
        Text { visible:root.type==="ReplaceItemOfList"; text:"of"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
        BwComboBox { visible:root.type==="ReplaceItemOfList"; model:root.listNames(); currentIndex:instruction?root.listNames().indexOf(instruction.name):-1; displayText:currentIndex>=0?currentText:(instruction&&instruction.name?instruction.name:"Choose list"); implicitWidth:98; implicitHeight:30; font.pixelSize:12; onActivated:index=>root.setField("name",currentText) }
        Text { visible:root.type==="ReplaceItemOfList"; text:"with"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
        ValueChip { visible:root.type==="ReplaceItemOfList"; valueData:instruction?instruction.value:null; location:root.fieldLocation("ReplaceItemOfListValue"); boxed:false; onEditRequested:(l,t)=>root.valueEdited(l,t) }
        Text { visible:root.type==="ReverseList"; text:"reverse"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
        BwComboBox { visible:root.type==="ReverseList"; model:root.listNames(); currentIndex:instruction?root.listNames().indexOf(instruction.name):-1; displayText:currentIndex>=0?currentText:(instruction&&instruction.name?instruction.name:"Choose list"); implicitWidth:98; implicitHeight:30; font.pixelSize:12; onActivated:index=>root.setField("name",currentText) }
        Text { visible:root.type==="Return"; text:"return"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
        ValueChip { visible:root.type==="Return"; valueData:instruction?instruction.value:null; location:root.fieldLocation("ReturnValue"); boxed:false; onEditRequested:(l,t)=>root.valueEdited(l,t) }
        Text { visible:root.type==="EscapeLoop"; text:"break loop"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
        Text { visible:root.type==="ContinueLoop"; text:"continue loop"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
        Repeater { model:root.type==="CallBlock"?root.callHeadPieces():[];delegate:Item {
            required property var modelData;width:modelData.kind==="Label"?callPieceText.implicitWidth:callPieceValue.implicitWidth;height:30
            Text{id:callPieceText;visible:modelData.kind==="Label";text:modelData.text;color:Theme.text;font.pixelSize:12;font.weight:Font.DemiBold;anchors.centerIn:parent}
            ValueChip{id:callPieceValue;visible:modelData.kind==="Input";valueData:instruction&&(instruction.args||[])[modelData.argIndex]?(instruction.args||[])[modelData.argIndex]:(modelData.bool?{kind:"Bool"}:{kind:"Number",value:0});location:root.fieldLocation("CallArg:"+modelData.argIndex);boxed:modelData.bool;anchors.centerIn:parent;onEditRequested:(l,t)=>root.valueEdited(l,t)}
        }}
        Text { visible:root.type==="BlockHeader"; text:root.callLabel(); color:Theme.text; font.pixelSize:12; font.weight:Font.DemiBold; anchors.verticalCenter:parent.verticalCenter }
        Repeater { model:root.type==="BlockHeader"?root.headerBranches():[];delegate:BwButton { required property var modelData;text:"run "+modelData.name;iconName:"git-branch";implicitHeight:30;font.pixelSize:11;onClicked:root.runBranchRequested(root.strandId,root.path,modelData.name) } }
        Text { visible:root.type==="RunBranch"; text:"run branch "+(instruction?instruction.name:""); color:Theme.text; font.pixelSize:12; font.weight:Font.DemiBold; anchors.verticalCenter:parent.verticalCenter }
    }

    // Head bar content, then one mouth per body (nested blocks) with separator bars between them.
    Row {
        id:headContent; visible:root.isWrap; x:14; y:Math.round((root.headHeight-height)/2); spacing:7
        LucideIcon { name:root.iconFor(root.type); color:Theme.textDim; width:16;height:16; anchors.verticalCenter:parent.verticalCenter }
        Text { visible:root.type==="If"||root.type==="IfElse"; text:"if"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
        ValueChip { visible:root.type==="If"||root.type==="IfElse"||root.type==="While"; valueData:instruction?instruction.condition:null; location:root.fieldLocation("Condition"); boxed:true; onEditRequested:(l,t)=>root.valueEdited(l,t) }
        Text { visible:root.type==="If"||root.type==="IfElse"; text:"then"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
        Text { visible:root.type==="Repeat"; text:"repeat"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
        ValueChip { visible:root.type==="Repeat"; valueData:instruction?instruction.count:null; location:root.fieldLocation("RepeatCount"); boxed:false; onEditRequested:(l,t)=>root.valueEdited(l,t) }
        Text { visible:root.type==="Forever"; text:"forever"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
        Text { visible:root.type==="While"; text:"while"; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
        Repeater { model:root.type==="BranchCallBlock"?root.callHeadPieces():[];delegate:Item {
            required property var modelData;width:modelData.kind==="Label"?branchPieceText.implicitWidth:branchPieceValue.implicitWidth;height:30
            Text{id:branchPieceText;visible:modelData.kind==="Label";text:modelData.text;color:Theme.text;font.pixelSize:12;font.weight:Font.DemiBold;anchors.centerIn:parent}
            ValueChip{id:branchPieceValue;visible:modelData.kind==="Input";valueData:instruction&&(instruction.args||[])[modelData.argIndex]?(instruction.args||[])[modelData.argIndex]:(modelData.bool?{kind:"Bool"}:{kind:"Number",value:0});location:root.fieldLocation("CallArg:"+modelData.argIndex);boxed:modelData.bool;anchors.centerIn:parent;onEditRequested:(l,t)=>root.valueEdited(l,t)}
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
                            item.runBranchRequested.connect((s, p, n) => root.runBranchRequested(s, p, n));
                            item.keyCaptureRequested.connect((s, p) => root.keyCaptureRequested(s, p));
                            item.detailsRequested.connect(t => root.detailsRequested(t));
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
                text: root.type === "IfElse" ? "else" : root.branchSeparator(slotDelegate.index)
                color: root.type === "IfElse" ? Theme.textDim : Theme.text; font.pixelSize: 12
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
