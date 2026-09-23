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
    signal blockActivated(string type)
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
        Item {
            Layout.fillWidth:true; Layout.preferredHeight:76
            Column { anchors.centerIn:parent; spacing:5
                LucideIcon { anchors.horizontalCenter:parent.horizontalCenter; name:"trash"; color:Theme.textDim; width:20;height:20; opacity:.65 }
                Text { text:"Drag a block here to delete it"; color:Theme.textDim; font.pixelSize:11 }
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
                    delegate:Item {
                        id:prefabItem; required property string modelData
                        property string instructionType:modelData
                        width:block.implicitWidth; height:block.implicitHeight
                        InstructionBlock { id:block; instruction:root.prefab(prefabItem.instructionType); variables:Array.from(root.variables||[]); lists:Array.from(root.lists||[]); blockDefinitions:root.blockDefinitions; keyCapture:root.keyCapture; paletteMode:true; locked:true; onKeyCaptureRequested:root.standaloneKeyCaptureRequested(); onDetailsRequested:type=>root.detailsRequested(type,type,"See what this block does and where it can be used.") }
                        Item{id:dragToken;width:prefabItem.width;height:prefabItem.height;property string instructionType:prefabItem.instructionType;Drag.active:paletteDrag.active;Drag.source:dragToken;Drag.keys:["blockwork-instruction"];Drag.hotSpot.x:prefabItem.width/2;Drag.hotSpot.y:prefabItem.height/2}
                        DragHandler { id:paletteDrag; target:dragToken; onActiveChanged:if(!active){dragToken.x=0;dragToken.y=0} }
                        TapHandler { acceptedButtons:Qt.LeftButton; onDoubleTapped:root.blockActivated(prefabItem.instructionType) }
                    }
                }
                Text { text:"OPERATORS"; color:Theme.textDim; font.pixelSize:10; font.weight:Font.Bold; font.letterSpacing:1; topPadding:8 }
                Repeater {
                    model:root.operators
                    delegate:Item {
                        id:opItem; required property var modelData
                        property var valueData:root.operatorValue(modelData)
                        width:opChip.implicitWidth; height:opChip.implicitHeight
                        ValueChip { id:opChip; valueData:opItem.valueData; editable:true; boxed:true; onDetailsRequested:kind=>root.detailsRequested(kind,kind,"A value or operator block that can be placed in an input.") }
                        Item{id:opDragToken;width:opItem.width;height:opItem.height;property var valueData:opItem.valueData;Drag.active:opPaletteDrag.active;Drag.source:opDragToken;Drag.keys:["blockwork-value"];Drag.hotSpot.x:opItem.width/2;Drag.hotSpot.y:opItem.height/2}
                        DragHandler{id:opPaletteDrag;target:opDragToken;onActiveChanged:if(!active){opDragToken.x=0;opDragToken.y=0}}
                        TapHandler { acceptedButtons:Qt.LeftButton; onDoubleTapped:root.valueActivated(opItem.valueData) }
                    }
                }
                Row {
                    spacing:8; topPadding:8
                    Text { text:"VARIABLES"; color:Theme.textDim; font.pixelSize:10; font.weight:Font.Bold; font.letterSpacing:1; anchors.verticalCenter:parent.verticalCenter }
                    BwButton { text:"Make a Variable"; implicitHeight:28; font.pixelSize:11; onClicked:root.makeVariableRequested() }
                }
                Repeater { model:root.variables||[]; delegate:Item {
                    id:varItem;required property string modelData;property var valueData:({kind:"Var",name:modelData});width:varChip.implicitWidth;height:varChip.implicitHeight
                    ValueChip{id:varChip;valueData:varItem.valueData;editable:false;boxed:true}
                    Item{id:varDragToken;width:varItem.width;height:varItem.height;property var valueData:varItem.valueData;Drag.active:varPaletteDrag.active;Drag.source:varDragToken;Drag.keys:["blockwork-value"];Drag.hotSpot.x:varItem.width/2;Drag.hotSpot.y:varItem.height/2}
                    DragHandler{id:varPaletteDrag;target:varDragToken;onActiveChanged:if(!active){varDragToken.x=0;varDragToken.y=0}}
                } }
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
                            CheckBox {
                                anchors.verticalCenter:parent.verticalCenter; checked:listRow.modelData.editor_visible
                                Accessible.name:"Show "+listRow.modelData.name+" on canvas"
                                onToggled:root.listEditorStateRequested(listRow.modelData.name,checked,listRow.modelData.editor_x||36,listRow.modelData.editor_y||36)
                            }
                            Text { anchors.verticalCenter:parent.verticalCenter; text:listRow.modelData.name; color:Theme.text; font.pixelSize:12; width:Math.max(80,listRow.width-100); elide:Text.ElideRight }
                            Text { anchors.verticalCenter:parent.verticalCenter; text:String((listRow.modelData.items||[]).length); color:Theme.textDim; font.pixelSize:11 }
                        }
                        HoverHandler{id:listHover}
                        TapHandler{acceptedButtons:Qt.RightButton;onTapped:listMenu.popup()}
                        Menu{id:listMenu;background:Rectangle{radius:7;color:Theme.panelRaised;border.color:Theme.border}BwMenuItem{iconName:"equal";text:"Rename list";onTriggered:root.renameListRequested(listRow.modelData.name)}BwMenuItem{iconName:"info";text:"Details";onTriggered:root.detailsRequested(listRow.modelData.name,"List","A macro-wide ordered collection of text and number items.")}BwMenuItem{iconName:"trash";danger:true;text:"Delete list";onTriggered:root.deleteListRequested(listRow.modelData.name)}}
                    }
                }
                Repeater {
                    model:root.listOperators
                    delegate:Item {
                        id:listOpItem; required property var modelData; property var valueData:root.operatorValue(modelData)
                        width:listOpChip.implicitWidth; height:listOpChip.implicitHeight
                        ValueChip{id:listOpChip;valueData:listOpItem.valueData;editable:true;boxed:true;onDetailsRequested:kind=>root.detailsRequested(kind,kind,"A list reporter block that reads data without changing the list.")}
                        Item{id:listOpDragToken;width:listOpItem.width;height:listOpItem.height;property var valueData:listOpItem.valueData;Drag.active:listOpPaletteDrag.active;Drag.source:listOpDragToken;Drag.keys:["blockwork-value"];Drag.hotSpot.x:listOpItem.width/2;Drag.hotSpot.y:listOpItem.height/2}
                        DragHandler{id:listOpPaletteDrag;target:listOpDragToken;onActiveChanged:if(!active){listOpDragToken.x=0;listOpDragToken.y=0}}
                        TapHandler{acceptedButtons:Qt.LeftButton;onDoubleTapped:root.valueActivated(listOpItem.valueData)}
                    }
                }
                Repeater {
                    model:root.listInstructionTypes
                    delegate:Item {
                        id:listPrefabItem;required property string modelData;property string instructionType:modelData
                        width:listBlock.implicitWidth;height:listBlock.implicitHeight
                        InstructionBlock{id:listBlock;instruction:root.prefab(listPrefabItem.instructionType);variables:Array.from(root.variables||[]);lists:Array.from(root.lists||[]);blockDefinitions:root.blockDefinitions;keyCapture:root.keyCapture;paletteMode:true;locked:true;onDetailsRequested:type=>root.detailsRequested(type,type,"See what this block does and where it can be used.")}
                        Item{id:listDragToken;width:listPrefabItem.width;height:listPrefabItem.height;property string instructionType:listPrefabItem.instructionType;Drag.active:listPaletteDrag.active;Drag.source:listDragToken;Drag.keys:["blockwork-instruction"];Drag.hotSpot.x:listPrefabItem.width/2;Drag.hotSpot.y:listPrefabItem.height/2}
                        DragHandler{id:listPaletteDrag;target:listDragToken;onActiveChanged:if(!active){listDragToken.x=0;listDragToken.y=0}}
                        TapHandler{acceptedButtons:Qt.LeftButton;onDoubleTapped:root.blockActivated(listPrefabItem.instructionType)}
                    }
                }
                Row {
                    spacing:8; topPadding:8
                    Text { text:"MY BLOCKS"; color:Theme.textDim; font.pixelSize:10; font.weight:Font.Bold; font.letterSpacing:1; anchors.verticalCenter:parent.verticalCenter }
                    BwButton { text:"Make a Block"; implicitHeight:28; font.pixelSize:11; onClicked:root.makeBlockRequested() }
                }
                Repeater {
                    model:root.blockDefinitions||[]
                    delegate:Item {
                        id:customItem; required property var modelData; width:root.isReporter(modelData)?customValue.implicitWidth:customBlock.implicitWidth; height:root.isReporter(modelData)?customValue.implicitHeight:customBlock.implicitHeight
                        InstructionBlock { id:customBlock; visible:!root.isReporter(customItem.modelData); instruction:root.customInstruction(customItem.modelData); variables:Array.from(root.variables||[]); lists:Array.from(root.lists||[]); blockDefinitions:root.blockDefinitions; keyCapture:root.keyCapture; paletteMode:true; locked:true; blockColor:customItem.modelData.color||Theme.block; onDetailsRequested:root.detailsRequested(root.customLabel(customItem.modelData),customItem.modelData.id,"A custom block defined in this macro.") }
                        ValueChip{id:customValue;visible:root.isReporter(customItem.modelData);valueData:root.customValue(customItem.modelData);editable:false;boxed:true;forceBoolean:customItem.modelData.shape==="ReturnsBool";callDisplayLabel:root.customLabel(customItem.modelData);onDetailsRequested:root.detailsRequested(root.customLabel(customItem.modelData),customItem.modelData.id,"A custom reporter block defined in this macro.")}
                        Item{id:customDragToken;width:customItem.width;height:customItem.height;property string instructionType:"__custom:"+customItem.modelData.id;property var valueData:root.isReporter(customItem.modelData)?root.customValue(customItem.modelData):null;Drag.active:customPaletteDrag.active;Drag.source:customDragToken;Drag.keys:[root.isReporter(customItem.modelData)?"blockwork-value":"blockwork-instruction"];Drag.hotSpot.x:customItem.width/2;Drag.hotSpot.y:customItem.height/2}
                        DragHandler{id:customPaletteDrag;target:customDragToken;onActiveChanged:if(!active){customDragToken.x=0;customDragToken.y=0}}
                        TapHandler { acceptedButtons:Qt.LeftButton; onDoubleTapped:{if(root.isReporter(customItem.modelData))root.valueActivated(root.customValue(customItem.modelData));else root.customBlockActivated(customItem.modelData);} }
                    }
                }
                Item { width:1;height:8 }
            }
        }
    }
}
