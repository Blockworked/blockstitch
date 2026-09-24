import QtQuick
import QtQuick.Controls

Item {
    id: root
    property var valueData
    property var location: null
    property bool editable: true
    property bool forceBoolean: false
    property string callDisplayLabel: "custom block"
    property bool boxed: !!valueData && ["Op", "Var", "Param", "Call"].indexOf(valueData.kind) >= 0
    property var blockDefinitions: []
    property bool dropHighlighted: false
    property bool paletteMode: false
    // Marks this item for value-drop hit-testing (recursive childAt walk in BlockCanvas).
    readonly property bool isValueChip: true
    readonly property var valueLocation: location
    signal editRequested(var location, string text)
    signal detailsRequested(string kind)
    signal valueDragBegan(var location, var value, real sceneX, real sceneY, real offsetX, real offsetY, real w, real h)
    signal valueDragMoved(real sceneX, real sceneY)
    signal valueDragEnded(real sceneX, real sceneY)
    signal valueDragCanceled()

    readonly property bool booleanShape: forceBoolean || (!!valueData && (valueData.kind === "Bool" || (valueData.kind === "Op" && ["Eq","Neq","Gt","Lt","Gte","Lte","And","Or","Not","True","False","PluggedIn","ClipboardHasImage","ClipboardHasFiles","ListContains","ListItemExists","ListIsEmpty"].indexOf(valueData.op) >= 0)))
    // An operator / variable / param / call reference is always its own
    // distinct block, even when a field passes boxed:false (which is meant
    // for bare Number/Text leaves typed straight into the field).
    readonly property bool isRef: !!valueData && ["Op", "Var", "Param", "Call"].indexOf(valueData.kind) >= 0
    readonly property bool showBox: boxed || isRef || booleanShape
    function defFor(id) { for (let i = 0; i < (blockDefinitions || []).length; ++i) if (blockDefinitions[i].id === id) return blockDefinitions[i]; return null; }
    readonly property color refColor: {
        if (valueData && valueData.kind === "Call") { const d = defFor(valueData.block_id); if (d && d.color) return d.color; }
        return "#37383c";
    }
    readonly property bool hovered: (valueGrab.hovered && !valueGrab.dragging) || paletteHover.hovered
    // Sidebar prefabs have no location (so valueGrab never arms), but still
    // need the grab cursor + accent outline that blocks get from
    // InstructionBlock. A top HoverHandler does not consume presses, so the
    // palette's own drag surface behind it still receives them.
    HoverHandler { id: paletteHover; enabled: root.paletteMode; cursorShape: Qt.OpenHandCursor }
    readonly property string opPrefix: {
        if (!valueData || valueData.kind !== "Op") return "";
        const p={Round:"round",Random:"pick random from",Join:"join",NewLine:"new line",Tab:"tab character",IndexOf:"index of",LastIndexOf:"last index of",LetterOf:"letter",Length:"length of",Not:"not",True:"true",False:"false",BatteryPercentage:"battery percentage",PluggedIn:"plugged in?",CurrentTime:"current",ClipboardText:"clipboard text",ClipboardHasImage:"clipboard has image",ClipboardHasFiles:"clipboard has files",ListItem:"item",ListItemNumber:"item # of",ListAmount:"amount of",ListLength:"length of",ListItemExists:"item",ListIsEmpty:"is"};
        return p[valueData.op] || "";
    }
    readonly property string opInfix: {
        if (!valueData || valueData.kind !== "Op") return "";
        const p={Add:"+",Sub:"−",Mul:"×",Div:"/",Mod:"mod",Math:"of",Random:"to",IndexOf:"in",LastIndexOf:"in",LetterOf:"of",Case:"to",Eq:"=",Neq:"≠",Gt:">",Lt:"<",Gte:"≥",Lte:"≤",And:"and",Or:"or",ListItem:"of",ListItemNumber:"in",ListAmount:"in",ListContains:"contains",ListItemExists:"exists in"};
        return p[valueData.op] || "";
    }
    readonly property string opSuffix: valueData && valueData.kind === "Op" && valueData.op === "ListIsEmpty" ? "empty?" : ""
    implicitWidth: Math.max(booleanShape ? 48 : 36, content.implicitWidth + (booleanShape ? 22 : showBox ? 12 : 0))
    implicitHeight: Math.max(27, content.implicitHeight + (showBox ? 4 : 0))

    Canvas {
        id: chipCanvas
        // The box also renders while targeted as a drop preview, so even a
        // bare Number/Text leaf (showBox false) lights up when an operator
        // hovers it. Size stays untouched so the slot never shifts mid-drag.
        anchors.fill: parent; visible: root.showBox || root.dropHighlighted; antialiasing: true
        onWidthChanged: requestPaint(); onHeightChanged: requestPaint()
        // HoverHandler lives in the drag area behind the content (see
        // below), so request a repaint when its hover state changes.
        Connections { target: valueGrab; function onHoveredChanged() { chipCanvas.requestPaint(); } }
        Connections { target: paletteHover; function onHoveredChanged() { chipCanvas.requestPaint(); } }
        Connections { target: root; function onShowBoxChanged() { chipCanvas.requestPaint(); } }
        Connections { target: root; function onDropHighlightedChanged() { chipCanvas.requestPaint(); } }
        Connections { target: root; function onValueDataChanged() { chipCanvas.requestPaint(); } }
        onPaint: {
            const c=getContext("2d"); c.reset(); c.beginPath();
            if (root.booleanShape) { const n=Math.min(height*.32,width/2); c.moveTo(n,.5); c.lineTo(width-n,.5); c.lineTo(width-.5,height/2); c.lineTo(width-n,height-.5); c.lineTo(n,height-.5); c.lineTo(.5,height/2); c.closePath(); }
            else { c.roundedRect(.5,.5,width-1,height-1,5,5); }
            const g=c.createLinearGradient(0,0,width,height);
            if (root.valueData && root.valueData.kind === "Call" && root.defFor(root.valueData.block_id)) { const base=root.refColor; g.addColorStop(0,Qt.lighter(base,1.11)); g.addColorStop(1,base); }
            else { g.addColorStop(0,"#37383c"); g.addColorStop(1,"#292a2d"); }
            c.fillStyle=g; c.fill();
            // Drop preview reads stronger than hover: thicker line plus glow
            // so it stays visible next to the dragged ghost covering the slot.
            if (root.dropHighlighted) { c.shadowColor=Theme.accent; c.shadowBlur=9; }
            c.strokeStyle=(root.hovered || root.dropHighlighted) ? Theme.accent : Theme.border; c.lineWidth=root.dropHighlighted ? 2.4 : (root.hovered ? 1.6 : 1); c.stroke();
        }
    }
    // Press-and-drag surface for existing value blocks (fields + floating).
    // Sits behind the content so text inputs stay editable and nested value
    // blocks (on top, inside `content`) get first claim on presses inside
    // them. Only actual blocks (operators / refs / floating roots) arm a
    // drag - a bare Number/Text leaf typed into a field is just its input.
    BlockDragArea {
        id: valueGrab
        anchors.fill: parent
        dragEnabled: !!root.location && root.showBox
        // When this chip itself isn't draggable (sidebar prefab, or a bare
        // Number/Text leaf), stay fully out of press delivery so the press
        // falls through to the drag surface underneath: the palette
        // wrapper, or the enclosing operator block. `enabled` (not just
        // acceptedButtons) is load-bearing here: with its HoverHandler
        // child active, this MouseArea claims presses even for unaccepted
        // buttons, starving everything below it.
        enabled: dragEnabled
        onDragBegan: (sx, sy, ox, oy) => root.valueDragBegan(root.location, root.valueData, sx, sy, ox, oy, root.implicitWidth, root.implicitHeight)
        onDragMoved: (sx, sy) => root.valueDragMoved(sx, sy)
        onDragEnded: (sx, sy) => root.valueDragEnded(sx, sy)
        onDragCanceled: root.valueDragCanceled()
    }
    MouseArea {
        anchors.fill: parent; acceptedButtons: Qt.RightButton
        onPressed: mouse => valueMenu.popup(mouse.x, mouse.y)
        BwMenu {
            id: valueMenu
            BwMenuItem { iconName: "info"; text: "Details"; onTriggered: root.detailsRequested(root.valueData && root.valueData.kind === "Op" ? root.valueData.op : (root.valueData ? root.valueData.kind : "Value")) }
        }
    }
    Row {
        id: content; anchors.centerIn: parent; spacing: 3
        Text { visible: root.opPrefix.length > 0; text: root.opPrefix; color: Theme.textDim; font.pixelSize: 12; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter }
        Repeater {
            model: root.valueData && root.valueData.kind === "Op" ? (root.valueData.args || []) : []
            delegate: Row {
                required property var modelData; required property int index; spacing: 3
                Text { visible: index > 0 && root.opInfix.length > 0; text: root.opInfix; color: Theme.textDim; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
                Loader {
                    source:"ValueChip.qml"; width:item?item.implicitWidth:0; height:item?item.implicitHeight:0
                    onLoaded:{item.location=root.location?Object.assign({},root.location,{path:(root.location.path||[]).concat([index])}):null;item.editable=root.editable;item.boxed=!!modelData&&["Op","Var","Param","Call"].indexOf(modelData.kind)>=0;item.blockDefinitions=root.blockDefinitions;item.dropHighlighted=root.dropHighlighted;item.editRequested.connect((where,text)=>root.editRequested(where,text));item.detailsRequested.connect(kind=>root.detailsRequested(kind));item.valueDragBegan.connect((loc,val,sx,sy,ox,oy,w,h)=>root.valueDragBegan(loc,val,sx,sy,ox,oy,w,h));item.valueDragMoved.connect((sx,sy)=>root.valueDragMoved(sx,sy));item.valueDragEnded.connect((sx,sy)=>root.valueDragEnded(sx,sy));item.valueDragCanceled.connect(()=>root.valueDragCanceled());item.valueData=modelData;}
                }
            }
        }
        BwTextField {
            id: leafInput
            visible: !!root.valueData && (root.valueData.kind === "Number" || root.valueData.kind === "Text")
            readOnly: !root.editable; text: root.valueData ? String(root.valueData.value) : ""; selectByMouse: true
            font.pixelSize: 12; color: Theme.text; implicitWidth: Math.max(36, Math.min(150, contentWidth + 18)); implicitHeight: 27
            leftPadding: 7; rightPadding: 7; topPadding: 2; bottomPadding: 2
            background: Rectangle { radius: 5; color: Theme.field; border.color: leafInput.activeFocus ? Theme.accent : Theme.border }
            onEditingFinished: if (root.location && text !== String(root.valueData.value)) root.editRequested(root.location,text)
        }
        Text { visible: !!root.valueData && ["Var","Param"].indexOf(root.valueData.kind)>=0; text: root.valueData && root.valueData.name ? root.valueData.name : ""; color: Theme.accent; font.pixelSize: 12; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter }
        Text { visible: !!root.valueData && root.valueData.kind === "Call"; text: root.callDisplayLabel; color: Theme.text; font.pixelSize: 12; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter }
        Item { visible: !!root.valueData && root.valueData.kind === "Bool"; width: 24; height: 17 }
        Text { visible: !!root.valueData && root.valueData.kind === "Op" && root.opPrefix.length===0 && (root.valueData.args||[]).length===0; text: root.valueData && root.valueData.op ? root.valueData.op.toLowerCase() : ""; color: Theme.text; font.pixelSize: 12 }
        Text { visible: root.opSuffix.length>0; text:root.opSuffix; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
    }
}
