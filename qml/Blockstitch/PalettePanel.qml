import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Rectangle {
    id: root
    property var instructionTypes: []
    property var listInstructionTypes: []
    property var variables: []
    property var lists: []
    property var blockDefinitions: []
    property var keyCapture: null
    property string standaloneKey: ""
    property bool trashArmed: false   // a canvas block is being dragged over the panel
    signal blockActivated(string type)
    signal dragStarted(var spec, real sceneX, real sceneY, real offsetX, real offsetY)
    signal dragMoved(real sceneX, real sceneY)
    signal dragEnded(real sceneX, real sceneY)
    signal dragCanceled()
    signal resizeRequested(real width)
    signal customBlockActivated(var definition)
    signal valueActivated(var value)
    signal makeVariableRequested()
    signal makeListRequested()
    signal listEditorStateRequested(string name, bool visible, int x, int y)
    signal renameListRequested(string name)
    signal deleteListRequested(string name)
    signal makeBlockRequested()
    signal standaloneKeyCaptureRequested()
    signal detailsRequested(string name, string identifier, string explainer)
    implicitWidth: 318
    color: Theme.panel
    border.color: Theme.borderSoft

    function n(v) { return {kind:"Number",value:v}; }
    function t(v) { return {kind:"Text",value:v}; }
    function prefab(type) {
        const i={id:"palette-"+type,type:type};
        if(type==="WhenBatteryDischargedTo") i.threshold=n(20); else if(type==="WhenBatteryChargedTo") i.threshold=n(100);
        else if(type==="WhenTime") i.schedule={kind:"Daily",hour:9,minute:0}; else if(type==="Wait") i.duration=n(1000);
        else if(type==="Text") i.text=t("text"); else if(type==="Key"){i.key=standaloneKey||"a";i.direction="Click";} else if(type==="Button"){i.button="Left";i.direction="Click";}
        else if(type==="MoveMouse"){i.x=n(0);i.y=n(0);i.coordinate="Relative";} else if(type==="Scroll"){i.amount=n(4);i.axis="Vertical";}
        else if(type==="Command") i.command=""; else if(type==="OpenApp"||type==="CloseApp"){i.name="";i.command="";i.icon=null;}
        else if(type==="SetClipboard") i.value=t("text");
        else if(type==="AddToList"){i.name=firstListName();i.value=t("thing");}
        else if(type==="DeleteOfList"){i.name=firstListName();i.index=n(1);}
        else if(type==="DeleteAllOfList"||type==="ReverseList")i.name=firstListName();
        else if(type==="ShiftList"){i.name=firstListName();i.amount=n(1);}
        else if(type==="InsertIntoList"){i.name=firstListName();i.value=t("thing");i.index=n(1);}
        else if(type==="ReplaceItemOfList"){i.name=firstListName();i.index=n(1);i.value=t("thing");}
        else if(type==="If"){i.condition={kind:"Bool"};i.body=[];} else if(type==="IfElse"){i.condition={kind:"Bool"};i.then_body=[];i.else_body=[];}
        else if(type==="Repeat"){i.count=n(10);i.body=[];} else if(type==="Forever"){i.body=[];} else if(type==="While"){i.condition={kind:"Bool"};i.body=[];}
        else if(type==="Return")i.value=n(0); else if(type==="SetVariable"){i.name=(variables||[])[0]||"variable";i.value=n(0);} else if(type==="ChangeVariable"){i.name=(variables||[])[0]||"variable";i.value=n(1);}
        return i;
    }
    function firstListName(){return lists&&lists.length?lists[0].name:"";}
    readonly property var operators: [
        ["Add","number",2],["Sub","number",2],["Mul","number",2],["Div","number",2],["Mod","number",2],["Round","number",1],["Math","number",2],["Random","number",2],
        ["Join","text",2],["Join3","text",3],["NewLine","text",0],["Tab","text",0],["IndexOf","text",2],["LastIndexOf","text",2],["LetterOf","text",2],["Length","text",1],["Case","text",2],
        ["Eq","bool",2],["Neq","bool",2],["Gt","bool",2],["Lt","bool",2],["Gte","bool",2],["Lte","bool",2],["And","bool",2],["Or","bool",2],["Not","bool",1],["True","bool",0],["False","bool",0],["PluggedIn","bool",0],["BatteryPercentage","number",0],["CurrentTime","number",1],
        ["ClipboardText","text",0],["ClipboardHasImage","bool",0],["ClipboardHasFiles","bool",0]
    ]
    readonly property var listOperators: [["ListItem","text",2],["ListItemNumber","number",2],["ListAmount","number",2],["ListLength","number",1],["ListContains","bool",2],["ListItemExists","bool",2],["ListIsEmpty","bool",1]]
    function operatorValue(spec) {
        const listName=firstListName();
        if(spec[0]==="ListItem")return {kind:"Op",op:spec[0],args:[n(1),t(listName)],saved:n(0)};
        if(spec[0]==="ListItemNumber"||spec[0]==="ListAmount")return {kind:"Op",op:spec[0],args:[t("thing"),t(listName)],saved:n(0)};
        if(spec[0]==="ListLength"||spec[0]==="ListIsEmpty")return {kind:"Op",op:spec[0],args:[t(listName)],saved:n(0)};
        if(spec[0]==="ListContains")return {kind:"Op",op:spec[0],args:[t(listName),t("thing")],saved:n(0)};
        if(spec[0]==="ListItemExists")return {kind:"Op",op:spec[0],args:[n(1),t(listName)],saved:n(0)};
        let args=[]; for(let i=0;i<spec[2];i++) args.push(spec[1]==="text"?t(""):spec[0]==="And"||spec[0]==="Or"||spec[0]==="Not"?{kind:"Bool"}:n(0));
        return {kind:"Op",op:spec[0]==="Join3"?"Join":spec[0],args:args,saved:n(0)};
    }
    function customInstruction(definition){
        const args=(definition.pieces||[]).filter(p=>p.kind==="Input").map(p=>p.value_type==="Bool"?{kind:"Bool"}:n(0));
        const count=(definition.pieces||[]).filter(p=>p.kind==="Branch").length;
        const i={id:"palette-call",type:count?"BranchCallBlock":"CallBlock",block_id:definition.id,args:args};
        if(count)i.branches=Array.from({length:count},()=>[]);
        return i;
    }
    function isReporter(definition){return definition.shape==="ReturnsValue"||definition.shape==="ReturnsBool";}
    function customValue(definition){
        const args=(definition.pieces||[]).filter(p=>p.kind==="Input").map(p=>p.value_type==="Bool"?{kind:"Bool"}:n(0));
        return {kind:"Call",block_id:definition.id,args:args,branches:[],saved:n(0)};
    }
    function customLabel(definition){return (definition.pieces||[]).filter(p=>p.kind!=="Branch").map(p=>p.kind==="Label"?p.text:"("+p.name+")").join(" ");}

    ColumnLayout {
        anchors.fill:parent; spacing:0
        Rectangle {
            Layout.fillWidth:true; Layout.preferredHeight:76
            color: root.trashArmed ? "#33ff4848" : "transparent"
            Column { anchors.centerIn:parent; spacing:5
                LucideIcon { anchors.horizontalCenter:parent.horizontalCenter; name:"trash"; color:root.trashArmed?Theme.danger:Theme.textDim; width:20;height:20; opacity:root.trashArmed?1:.65 }
                Text { text:root.trashArmed?"Release to delete":"Drag a block here to delete it"; color:root.trashArmed?Theme.danger:Theme.textDim; font.pixelSize:11 }
            }
        }
        Rectangle { Layout.fillWidth:true; height:1; color:Theme.borderSoft }
        ScrollView {
            id:paletteScroll
            Layout.fillWidth:true; Layout.fillHeight:true; clip:true
            ScrollBar.horizontal.policy: ScrollBar.AsNeeded
            WheelHandler { target:null; onWheel:event=>{const f=paletteScroll.contentItem;f.contentY=Math.max(0,Math.min(f.contentHeight-f.height,f.contentY-event.angleDelta.y*.9));event.accepted=true;} }
            Column {
                width:Math.max(root.width-12, childrenRect.width); spacing:8; padding:8
                Repeater {
                    model:root.instructionTypes
                    delegate:PaletteBlock {
                        required property string modelData
                        instruction:root.prefab(modelData); spec:({kind:"instruction",type:modelData,instruction:instruction})
                        variables:Array.from(root.variables||[]); lists:Array.from(root.lists||[]); blockDefinitions:root.blockDefinitions; keyCapture:root.keyCapture
                        onDragStarted:(sp,sx,sy,ox,oy)=>root.dragStarted(sp,sx,sy,ox,oy); onDragMoved:(sx,sy)=>root.dragMoved(sx,sy); onDragEnded:(sx,sy)=>root.dragEnded(sx,sy); onDragCanceled:root.dragCanceled()
                        onActivated:root.blockActivated(modelData); onKeyCaptureRequested:root.standaloneKeyCaptureRequested()
                        onDetailsRequested:type=>root.detailsRequested(type,type,"See what this block does and where it can be used.")
                    }
                }
                Text { text:"OPERATORS"; color:Theme.textDim; font.pixelSize:10; font.weight:Font.Bold; font.letterSpacing:1; topPadding:8 }
                Repeater {
                    model:root.operators
                    delegate:PaletteValue {
                        required property var modelData
                        valueData:root.operatorValue(modelData); spec:({kind:"value",value:valueData})
                        onDragStarted:(sp,sx,sy,ox,oy)=>root.dragStarted(sp,sx,sy,ox,oy); onDragMoved:(sx,sy)=>root.dragMoved(sx,sy); onDragEnded:(sx,sy)=>root.dragEnded(sx,sy); onDragCanceled:root.dragCanceled()
                        onActivated:root.valueActivated(valueData)
                        onDetailsRequested:kind=>root.detailsRequested(kind,kind,"A value or operator block that can be placed in an input.")
                    }
                }
                Row {
                    spacing:8; topPadding:8
                    Text { text:"VARIABLES"; color:Theme.textDim; font.pixelSize:10; font.weight:Font.Bold; font.letterSpacing:1; anchors.verticalCenter:parent.verticalCenter }
                    BwButton { text:"Make a Variable"; implicitHeight:28; font.pixelSize:11; onClicked:root.makeVariableRequested() }
                }
                Repeater {
                    model:root.variables||[]
                    delegate:PaletteValue {
                        required property string modelData
                        valueData:({kind:"Var",name:modelData}); editable:false; spec:({kind:"value",value:valueData})
                        onDragStarted:(sp,sx,sy,ox,oy)=>root.dragStarted(sp,sx,sy,ox,oy); onDragMoved:(sx,sy)=>root.dragMoved(sx,sy); onDragEnded:(sx,sy)=>root.dragEnded(sx,sy); onDragCanceled:root.dragCanceled()
                        onActivated:root.valueActivated(valueData)
                    }
                }
                Row {
                    spacing:8; topPadding:8
                    Text { text:"LISTS"; color:Theme.textDim; font.pixelSize:10; font.weight:Font.Bold; font.letterSpacing:1; anchors.verticalCenter:parent.verticalCenter }
                    BwButton { text:"Make a List"; implicitHeight:28; font.pixelSize:11; onClicked:root.makeListRequested() }
                }
                Text { visible:!(root.lists&&root.lists.length); text:"Make a list, then check it to open its editor on the canvas."; width:Math.max(200,root.width-32); wrapMode:Text.WordWrap; color:Theme.textDim; font.pixelSize:11 }
                Repeater {
                    model:root.lists||[]
                    delegate:Rectangle {
                        id:listRow; required property var modelData; width:Math.max(230,root.width-28); height:30; radius:Theme.radius; color:listHover.hovered?"#303134":"transparent"
                        Row {
                            anchors.fill:parent; anchors.leftMargin:6; anchors.rightMargin:6; spacing:7
                            BwCheckBox {
                                anchors.verticalCenter:parent.verticalCenter; checked:listRow.modelData.editor_visible
                                Accessible.name:"Show "+listRow.modelData.name+" on canvas"
                                onToggled:root.listEditorStateRequested(listRow.modelData.name,checked,listRow.modelData.editor_x||36,listRow.modelData.editor_y||36)
                            }
                            Text { anchors.verticalCenter:parent.verticalCenter; text:listRow.modelData.name; color:Theme.text; font.pixelSize:12; width:Math.max(80,listRow.width-100); elide:Text.ElideRight }
                            Text { anchors.verticalCenter:parent.verticalCenter; text:String((listRow.modelData.items||[]).length); color:Theme.textDim; font.pixelSize:11 }
                        }
                        HoverHandler{id:listHover}
                        TapHandler{acceptedButtons:Qt.RightButton;gesturePolicy:TapHandler.ReleaseWithinBounds;onTapped:listMenu.popup()}
                        BwMenu{id:listMenu;BwMenuItem{iconName:"equal";text:"Rename list";onTriggered:root.renameListRequested(listRow.modelData.name)}BwMenuItem{iconName:"info";text:"Details";onTriggered:root.detailsRequested(listRow.modelData.name,"List","A macro-wide ordered collection of text and number items.")}BwMenuItem{iconName:"trash";danger:true;text:"Delete list";onTriggered:root.deleteListRequested(listRow.modelData.name)}}
                    }
                }
                Repeater {
                    model:root.listOperators
                    delegate:PaletteValue {
                        required property var modelData
                        valueData:root.operatorValue(modelData); spec:({kind:"value",value:valueData})
                        onDragStarted:(sp,sx,sy,ox,oy)=>root.dragStarted(sp,sx,sy,ox,oy); onDragMoved:(sx,sy)=>root.dragMoved(sx,sy); onDragEnded:(sx,sy)=>root.dragEnded(sx,sy); onDragCanceled:root.dragCanceled()
                        onActivated:root.valueActivated(valueData)
                        onDetailsRequested:kind=>root.detailsRequested(kind,kind,"A list reporter block that reads data without changing the list.")
                    }
                }
                Repeater {
                    model:root.listInstructionTypes
                    delegate:PaletteBlock {
                        required property string modelData
                        instruction:root.prefab(modelData); spec:({kind:"instruction",type:modelData,instruction:instruction})
                        variables:Array.from(root.variables||[]); lists:Array.from(root.lists||[]); blockDefinitions:root.blockDefinitions; keyCapture:root.keyCapture
                        onDragStarted:(sp,sx,sy,ox,oy)=>root.dragStarted(sp,sx,sy,ox,oy); onDragMoved:(sx,sy)=>root.dragMoved(sx,sy); onDragEnded:(sx,sy)=>root.dragEnded(sx,sy); onDragCanceled:root.dragCanceled()
                        onActivated:root.blockActivated(modelData)
                        onDetailsRequested:type=>root.detailsRequested(type,type,"See what this block does and where it can be used.")
                    }
                }
                Row {
                    spacing:8; topPadding:8
                    Text { text:"MY BLOCKS"; color:Theme.textDim; font.pixelSize:10; font.weight:Font.Bold; font.letterSpacing:1; anchors.verticalCenter:parent.verticalCenter }
                    BwButton { text:"Make a Block"; implicitHeight:28; font.pixelSize:11; onClicked:root.makeBlockRequested() }
                }
                Repeater {
                    model:root.blockDefinitions||[]
                    delegate:Loader {
                        id:customItem; required property var modelData
                        sourceComponent:root.isReporter(modelData)?customReporter:customCall
                        Component {
                            id:customCall
                            PaletteBlock {
                                instruction:root.customInstruction(customItem.modelData); spec:({kind:"custom",definition:customItem.modelData,instruction:instruction,color:blockColor})
                                variables:Array.from(root.variables||[]); lists:Array.from(root.lists||[]); blockDefinitions:root.blockDefinitions; keyCapture:root.keyCapture; blockColor:customItem.modelData.color||Theme.block
                                onDragStarted:(sp,sx,sy,ox,oy)=>root.dragStarted(sp,sx,sy,ox,oy); onDragMoved:(sx,sy)=>root.dragMoved(sx,sy); onDragEnded:(sx,sy)=>root.dragEnded(sx,sy); onDragCanceled:root.dragCanceled()
                                onActivated:root.customBlockActivated(customItem.modelData)
                                onDetailsRequested:root.detailsRequested(root.customLabel(customItem.modelData),customItem.modelData.id,"A custom block defined in this macro.")
                            }
                        }
                        Component {
                            id:customReporter
                            PaletteValue {
                                valueData:root.customValue(customItem.modelData); editable:false; forceBoolean:customItem.modelData.shape==="ReturnsBool"; callLabel:root.customLabel(customItem.modelData)
                                spec:({kind:"value",value:valueData,forceBoolean:forceBoolean,label:callLabel})
                                onDragStarted:(sp,sx,sy,ox,oy)=>root.dragStarted(sp,sx,sy,ox,oy); onDragMoved:(sx,sy)=>root.dragMoved(sx,sy); onDragEnded:(sx,sy)=>root.dragEnded(sx,sy); onDragCanceled:root.dragCanceled()
                                onActivated:root.valueActivated(valueData)
                                onDetailsRequested:root.detailsRequested(root.customLabel(customItem.modelData),customItem.modelData.id,"A custom reporter block defined in this macro.")
                            }
                        }
                    }
                }
                Item { width:1;height:8 }
            }
        }
    }

    // Drag the right edge to resize the panel.
    Rectangle {
        anchors.top: parent.top; anchors.bottom: parent.bottom; anchors.right: parent.right
        width: 6; z: 5
        color: Theme.accent; opacity: resizeArea.pressed || resizeArea.containsMouse ? 0.5 : 0
        MouseArea {
            id: resizeArea
            anchors.fill: parent; hoverEnabled: true; preventStealing: true; cursorShape: Qt.SizeHorCursor
            property real startWidth: 0
            property real startX: 0
            onPressed: mouse => { startWidth = root.width; startX = mapToItem(null, mouse.x, 0).x; }
            onPositionChanged: mouse => { if (pressed) root.resizeRequested(startWidth + mapToItem(null, mouse.x, 0).x - startX); }
        }
    }
}
