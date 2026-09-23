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
    signal blockDropped(string type, int x, int y)
    signal valueDropped(var value, int x, int y)
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
    signal detailsRequested(string type)
    color:Theme.canvas; clip:true

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
            MouseArea { anchors.fill:parent; z:-100; acceptedButtons:Qt.LeftButton; onClicked:flick.forceActiveFocus() }
            Repeater {
                model:root.strands||[]
                delegate:Column {
                    id:strand; required property var modelData; required property int index
                    x:modelData.x; y:modelData.y; spacing:-8
                    Repeater {
                        model:strand.modelData.instructions||[]
                        delegate:InstructionBlock {
                            id:block; required property var modelData; required property int index
                            instruction:modelData; strandId:strand.modelData.id; path:[{index:index}]
                            variables:root.variables; lists:root.lists; blockDefinitions:root.blockDefinitions; keyCapture:root.keyCapture; locked:root.locked
                            onRemoveRequested:(sid,p)=>root.instructionRemoved(sid,p)
                            onDuplicateRequested:(sid,p,i)=>root.instructionDuplicated(sid,p,i)
                            onCommentRequested:i=>root.commentForInstructionRequested(i)
                            onRecordingTargetRequested:sid=>root.recordingTargetRequested(sid)
                            onKeyCaptureRequested:(sid,p)=>root.keyCaptureRequested(sid,p)
                            onDetailsRequested:type=>root.detailsRequested(type)
                            onInstructionEdited:(sid,p,i)=>root.instructionEdited(sid,p,i)
                            onRunBranchRequested:(sid,p,n)=>root.runBranchRequested(sid,p,n)
                            onValueEdited:(l,t)=>root.valueEdited(l,t)
                            onDragFinished:(sid,p,dx,dy)=>{
                                if(p.length===1&&p[0].index===0) root.strandMoved(sid,Math.round(strand.modelData.x+dx),Math.round(strand.modelData.y+dy));
                                else { const pos=block.mapToItem(workspace,0,0); root.instructionSplit(sid,p,Math.round(pos.x+dx),Math.round(pos.y+dy)); }
                            }
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
                    TapHandler { acceptedButtons:Qt.RightButton;onTapped:commentMenu.popup() }
                    Menu { id:commentMenu;background:Rectangle{radius:7;color:Theme.panelRaised;border.color:Theme.border}BwMenuItem{iconName:"trash";danger:true;text:"Delete note";onTriggered:root.commentRemoved(commentCard.modelData.id)} }
                }
            }
            Repeater {
                model:root.floatingValues||[]
                delegate:Item {
                    id:floatingItem;required property var modelData;x:modelData.x;y:modelData.y;z:5;width:floatingChip.implicitWidth;height:floatingChip.implicitHeight
                    ValueChip { id:floatingChip;valueData:floatingItem.modelData.value;location:({kind:"Floating",floating_id:floatingItem.modelData.id,path:[]});boxed:true;onEditRequested:(l,t)=>root.valueEdited(l,t) }
                    DragHandler { enabled:!root.locked;target:floatingItem;onActiveChanged:if(!active)root.floatingValueMoved(floatingItem.modelData.id,Math.round(floatingItem.x),Math.round(floatingItem.y)) }
                    TapHandler { acceptedButtons:Qt.RightButton;onTapped:floatingMenu.popup() }
                    Menu { id:floatingMenu;background:Rectangle{radius:7;color:Theme.panelRaised;border.color:Theme.border}BwMenuItem{iconName:"info";text:"Details";onTriggered:root.detailsRequested(floatingItem.modelData.value.op||floatingItem.modelData.value.kind)}BwMenuItem{iconName:"trash";danger:true;text:"Delete value";onTriggered:root.floatingValueRemoved(floatingItem.modelData.id)} }
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
        DropArea { anchors.fill:parent;keys:["blockwork-instruction","blockwork-value"];onDropped:drop=>{if(root.locked||!drop.source)return;const x=Math.round((drop.x+flick.contentX)/root.zoom),y=Math.round((drop.y+flick.contentY)/root.zoom);if(drop.source.valueData)root.valueDropped(drop.source.valueData,x,y);else if(drop.source.instructionType)root.blockDropped(drop.source.instructionType,x,y);} }
        TapHandler { acceptedButtons:Qt.RightButton;onTapped:event=>{ canvasMenu.canvasX=Math.round((event.position.x+flick.contentX)/root.zoom);canvasMenu.canvasY=Math.round((event.position.y+flick.contentY)/root.zoom);canvasMenu.popup();} }
        Menu { id:canvasMenu;property int canvasX:0;property int canvasY:0;background:Rectangle{radius:7;color:Theme.panelRaised;border.color:Theme.border}
            BwMenuItem{iconName:"message-square";text:"Add Note";onTriggered:root.canvasNoteRequested(canvasMenu.canvasX,canvasMenu.canvasY)}
            BwMenuItem{iconName:"trash";danger:true;text:"Delete all blocks";onTriggered:root.clearRequested()}
        }
    }
    Column {
        anchors.right:parent.right;anchors.bottom:parent.bottom;anchors.margins:18;spacing:8
        BwButton { iconName:"zoom-in";text:"";implicitWidth:40;implicitHeight:40;onClicked:root.zoom=Math.min(1.8,root.zoom+.1) }
        BwButton { iconName:"zoom-out";text:"";implicitWidth:40;implicitHeight:40;onClicked:root.zoom=Math.max(.5,root.zoom-.1) }
        BwButton { iconName:"rotate-ccw";text:"";implicitWidth:40;implicitHeight:40;onClicked:root.zoom=1 }
    }
}
