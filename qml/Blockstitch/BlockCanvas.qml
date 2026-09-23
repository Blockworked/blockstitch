import QtQuick
import QtQuick.Controls

Rectangle {
    id: root
    property var strands: []
    property var comments: []
    property var floatingValues: []
    property var variables: []
    property var lists: []
    property var blockDefinitions: []
    property var keyCapture: null
    property bool locked: false
    property real zoom: 1.0
    signal strandMoved(string strandId, int x, int y)
    signal instructionSplit(string strandId, var path, int x, int y)
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
    signal keyCaptureRequested(string strandId, var path)
    signal appPickerRequested(string strandId, var path, var instruction)
    signal detailsRequested(string type)
    color:Theme.canvas; clip:true

    // Drag session for blocks picked up on the canvas. Blocks read this to follow the pointer.
    // After a drop we keep a "settle" offset so the dragged blocks stay at
    // the drop point until the daemon round trip confirms the move. Without
    // this the transform snaps back to 0 on drop (visible revert) and the
    // block only teleports to its new position once the new state arrives.
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
        // Set on drop, cleared once the new strands confirm the move (or on timeout).
        property bool settling: false
        property string settleStrandId: ""
        property var settlePath: []
        property real settleDx: 0
        property real settleDy: 0
    }
    readonly property bool dragging: dragSession.active
    readonly property real dragSceneX: dragSession.sceneX
    readonly property real dragSceneY: dragSession.sceneY
    function strandById(id) { const list = root.strands || []; for (let i = 0; i < list.length; ++i) if (list[i].id === id) return list[i]; return null; }
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
    function beginDrag(strandId, path, tailCount, sx, sy, ox, oy) {
        const p = workspace.mapFromItem(null, sx, sy);
        dragSession.settling = false;
        dragSession.strandId = strandId; dragSession.path = path; dragSession.tailCount = tailCount;
        dragSession.startX = p.x; dragSession.startY = p.y; dragSession.originX = p.x - ox; dragSession.originY = p.y - oy;
        dragSession.dx = 0; dragSession.dy = 0; dragSession.active = true;
    }
    function moveDrag(sx, sy) {
        if (!dragSession.active) return;
        const p = workspace.mapFromItem(null, sx, sy);
        dragSession.dx = p.x - dragSession.startX; dragSession.dy = p.y - dragSession.startY;
        dragSession.sceneX = sx; dragSession.sceneY = sy;
    }
    function endDrag(sx, sy) {
        if (!dragSession.active) return;
        moveDrag(sx, sy);
        const strandId = dragSession.strandId, path = dragSession.path, tail = dragSession.tailCount;
        const dx = dragSession.dx, dy = dragSession.dy, ox = dragSession.originX, oy = dragSession.originY;
        dragSession.active = false;
        if (!root.contains(root.mapFromItem(null, sx, sy))) { dragSession.settling = false; root.blockDragOutside(strandId, path, tail, sx, sy); return; }
        // Optimistic settle: keep rendering the dragged tail at the drop
        // point until the backend state confirms the move/split. Cleared in
        // onStrandsChanged or by settleTimer below.
        dragSession.settleStrandId = strandId;
        dragSession.settlePath = path;
        dragSession.settleDx = dx;
        dragSession.settleDy = dy;
        dragSession.settling = true;
        settleTimer.restart();
        const strand = strandById(strandId);
        if (path.length === 1 && path[0].index === 0 && strand) root.strandMoved(strandId, Math.round(strand.x + dx), Math.round(strand.y + dy));
        else root.instructionSplit(strandId, path, Math.round(ox + dx), Math.round(oy + dy));
    }
    function cancelDrag() { dragSession.active = false; dragSession.settling = false; }
    Timer { id: settleTimer; interval: 1500; onTriggered: dragSession.settling = false }
    onStrandsChanged: { syncStrands(); if (dragSession.settling) dragSession.settling = false; }
    Component.onCompleted: syncStrands()
    // Workspace coordinates for a scene point, or null when it is outside the canvas.
    function workspacePoint(sx, sy) {
        if (!root.contains(root.mapFromItem(null, sx, sy))) return null;
        return workspace.mapFromItem(null, sx, sy);
    }

    Canvas {
        id:grid; anchors.fill:parent
        onPaint:{ const c=getContext("2d"); c.reset(); c.fillStyle="#3d3e43"; const gap=22*root.zoom; const ox=(-flick.contentX)%gap,oy=(-flick.contentY)%gap; for(let x=ox;x<width;x+=gap)for(let y=oy;y<height;y+=gap){c.beginPath();c.arc(x,y,1.05,0,Math.PI*2);c.fill();} }
    }
    Flickable {
        id:flick; anchors.fill:parent; contentWidth:2600*root.zoom; contentHeight:1800*root.zoom; boundsBehavior:Flickable.StopAtBounds
        ScrollBar.horizontal:ScrollBar{}
        ScrollBar.vertical:ScrollBar{}
        onContentXChanged:grid.requestPaint()
        onContentYChanged:grid.requestPaint()
        Item {
            id:workspace; width:2600;height:1800; scale:root.zoom; transformOrigin:Item.TopLeft
            MouseArea {
                anchors.fill:parent; z:-100; acceptedButtons:Qt.LeftButton|Qt.RightButton
                onClicked: mouse => { if (mouse.button === Qt.RightButton) { canvasMenu.canvasX = Math.round(mouse.x); canvasMenu.canvasY = Math.round(mouse.y); canvasMenu.popup(mouse.x, mouse.y); } else flick.forceActiveFocus(); }
                BwMenu { id:canvasMenu;property int canvasX:0;property int canvasY:0
                    BwMenuItem{iconName:"message-square";text:"Add Note";onTriggered:root.canvasNoteRequested(canvasMenu.canvasX,canvasMenu.canvasY)}
                    BwMenuItem{iconName:"trash";danger:true;text:"Delete all blocks";onTriggered:root.clearRequested()}
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
                    x:sx; y:sy; spacing:-8
                    z: (dragSession.active && dragSession.strandId === sid) || (dragSession.settling && dragSession.settleStrandId === sid) ? 100 : 0
                    Repeater {
                        model:strand.blockList||[]
                        delegate:InstructionBlock {
                            id:block; required property var modelData; required property int index
                            instruction:modelData; strandId:strand.sid; path:[{index:index}]; tailCount:(strand.blockList||[]).length-index; dragState:dragSession
                            variables:root.variables; lists:root.lists; blockDefinitions:root.blockDefinitions; keyCapture:root.keyCapture; locked:root.locked
                            onRemoveRequested:(sid,p)=>root.instructionRemoved(sid,p)
                            onDuplicateRequested:(sid,p,i)=>root.instructionDuplicated(sid,p,i)
                            onCommentRequested:i=>root.commentForInstructionRequested(i)
                            onRecordingTargetRequested:sid=>root.recordingTargetRequested(sid)
                            onKeyCaptureRequested:(sid,p)=>root.keyCaptureRequested(sid,p)
                            onAppPickerRequested:(sid,p,i)=>root.appPickerRequested(sid,p,i)
                            onDetailsRequested:type=>root.detailsRequested(type)
                            onInstructionEdited:(sid,p,i)=>root.instructionEdited(sid,p,i)
                            onRunBranchRequested:(sid,p,n)=>root.runBranchRequested(sid,p,n)
                            onValueEdited:(l,t)=>root.valueEdited(l,t)
                            onDragBegan:(sid,p,tail,sx,sy,ox,oy)=>root.beginDrag(sid,p,tail,sx,sy,ox,oy)
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
                    x:modelData.x;y:modelData.y;z:4;width:220;height:modelData.collapsed?38:112;radius:6;color:"#4a4328";border.color:"#8b7940"
                    Row { anchors.left:parent.left;anchors.right:parent.right;anchors.top:parent.top;anchors.margins:8;spacing:7
                        LucideIcon { name:"message-square";color:"#e7d991";width:14;height:14 }
                        Text { text:"NOTE";color:"#e7d991";font.pixelSize:10;font.weight:Font.Bold }
                        Item { width:Math.max(0,parent.width-94);height:1 }
                        BwButton { iconName:commentCard.modelData.collapsed?"plus":"x"; text:"";implicitWidth:22;implicitHeight:22;onClicked:root.commentCollapseChanged(commentCard.modelData.id,!commentCard.modelData.collapsed) }
                    }
                    TextArea { visible:!commentCard.modelData.collapsed;anchors.fill:parent;anchors.topMargin:30;anchors.margins:7;text:commentCard.modelData.text;color:Theme.text;wrapMode:TextEdit.Wrap;background:null;onActiveFocusChanged:if(!activeFocus&&text!==commentCard.modelData.text)root.commentEdited(commentCard.modelData.id,text) }
                    DragHandler { enabled:!root.locked;target:commentCard;onActiveChanged:if(!active)root.commentMoved(commentCard.modelData.id,Math.round(commentCard.x),Math.round(commentCard.y)) }
                    TapHandler { acceptedButtons:Qt.RightButton;gesturePolicy:TapHandler.ReleaseWithinBounds;onTapped:commentMenu.popup() }
                    BwMenu { id:commentMenu;BwMenuItem{iconName:"trash";danger:true;text:"Delete note";onTriggered:root.commentRemoved(commentCard.modelData.id)} }
                }
            }
            Repeater {
                model:root.floatingValues||[]
                delegate:Item {
                    id:floatingItem;required property var modelData;x:modelData.x;y:modelData.y;z:5;width:floatingChip.implicitWidth;height:floatingChip.implicitHeight
                    ValueChip { id:floatingChip;valueData:floatingItem.modelData.value;location:({kind:"Floating",floating_id:floatingItem.modelData.id,path:[]});boxed:true;onEditRequested:(l,t)=>root.valueEdited(l,t) }
                    DragHandler { enabled:!root.locked;target:floatingItem;onActiveChanged:if(!active)root.floatingValueMoved(floatingItem.modelData.id,Math.round(floatingItem.x),Math.round(floatingItem.y)) }
                    TapHandler { acceptedButtons:Qt.RightButton;gesturePolicy:TapHandler.ReleaseWithinBounds;onTapped:floatingMenu.popup() }
                    BwMenu { id:floatingMenu;BwMenuItem{iconName:"info";text:"Details";onTriggered:root.detailsRequested(floatingItem.modelData.value.op||floatingItem.modelData.value.kind)}BwMenuItem{iconName:"trash";danger:true;text:"Delete value";onTriggered:root.floatingValueRemoved(floatingItem.modelData.id)} }
                }
            }
            Repeater {
                model:root.lists||[]
                delegate:Rectangle {
                    id:listCard;required property var modelData
                    visible:modelData.editor_visible;x:modelData.editor_x||36;y:modelData.editor_y||36;z:12
                    width:300;height:Math.min(400,78+Math.max(38,(modelData.items||[]).length*34));radius:8;color:Theme.panelRaised;border.color:Theme.border;clip:true
                    function itemFromText(value){const trimmed=value.trim();const number=Number(value);return trimmed.length&&Number.isFinite(number)?{kind:"Number",value:number}:{kind:"Text",value:value};}
                    function editItem(index,value){const next=JSON.parse(JSON.stringify(modelData.items||[]));next[index]=itemFromText(value);root.listItemsEdited(modelData.name,next);}
                    function removeItem(index){const next=JSON.parse(JSON.stringify(modelData.items||[]));next.splice(index,1);root.listItemsEdited(modelData.name,next);}
                    function addItem(){const next=JSON.parse(JSON.stringify(modelData.items||[]));next.push({kind:"Text",value:""});root.listItemsEdited(modelData.name,next);}
                    Rectangle { id:listHead;anchors.left:parent.left;anchors.right:parent.right;anchors.top:parent.top;height:38;color:"#393a3e";border.color:Theme.borderSoft
                        Row { anchors.fill:parent;anchors.margins:6;spacing:6
                            LucideIcon{name:"layers";color:Theme.textDim;width:16;height:16;anchors.verticalCenter:parent.verticalCenter}
                            Text{text:listCard.modelData.name;color:Theme.text;font.pixelSize:13;font.weight:Font.Bold;width:220;elide:Text.ElideRight;anchors.verticalCenter:parent.verticalCenter}
                            BwButton{iconName:"x";text:"";implicitWidth:25;implicitHeight:25;onClicked:root.listEditorStateChanged(listCard.modelData.name,false,Math.round(listCard.x),Math.round(listCard.y))}
                        }
                        DragHandler{id:listDrag;enabled:!root.locked;target:listCard;onActiveChanged:if(!active)root.listEditorStateChanged(listCard.modelData.name,true,Math.round(listCard.x),Math.round(listCard.y))}
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
        }
    }
    Column {
        anchors.right:parent.right;anchors.bottom:parent.bottom;anchors.margins:18;spacing:8
        BwButton { iconName:"zoom-in";text:"";implicitWidth:40;implicitHeight:40;radius:20;onClicked:root.zoom=Math.min(1.8,root.zoom+.1) }
        BwButton { iconName:"zoom-out";text:"";implicitWidth:40;implicitHeight:40;radius:20;onClicked:root.zoom=Math.max(.5,root.zoom-.1) }
        BwButton { iconName:"rotate-ccw";text:"";implicitWidth:40;implicitHeight:40;radius:20;onClicked:root.zoom=1 }
    }
}
