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
    signal editRequested(var location, string text)
    signal detailsRequested(string kind)

    readonly property bool booleanShape: forceBoolean || (!!valueData && (valueData.kind === "Bool" || (valueData.kind === "Op" && ["Eq","Neq","Gt","Lt","Gte","Lte","And","Or","Not","True","False","PluggedIn","ClipboardHasImage","ClipboardHasFiles","ListContains","ListItemExists","ListIsEmpty"].indexOf(valueData.op) >= 0)))
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
    implicitWidth: Math.max(booleanShape ? 48 : 36, content.implicitWidth + (booleanShape ? 22 : boxed ? 12 : 0))
    implicitHeight: Math.max(27, content.implicitHeight + (boxed ? 4 : 0))

    Canvas {
        anchors.fill: parent; visible: root.boxed || root.booleanShape; antialiasing: true
        onWidthChanged: requestPaint(); onHeightChanged: requestPaint()
        onPaint: {
            const c=getContext("2d"); c.reset(); c.beginPath();
            if (root.booleanShape) { const n=Math.min(height*.32,width/2); c.moveTo(n,.5); c.lineTo(width-n,.5); c.lineTo(width-.5,height/2); c.lineTo(width-n,height-.5); c.lineTo(n,height-.5); c.lineTo(.5,height/2); c.closePath(); }
            else { c.roundedRect(.5,.5,width-1,height-1,5,5); }
            const g=c.createLinearGradient(0,0,width,height); g.addColorStop(0,"#37383c"); g.addColorStop(1,"#292a2d"); c.fillStyle=g; c.fill(); c.strokeStyle=Theme.border; c.lineWidth=1; c.stroke();
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
                    onLoaded:{item.valueData=modelData;item.location=root.location?Object.assign({},root.location,{path:(root.location.path||[]).concat([index])}):null;item.editable=root.editable;item.boxed=!!modelData&&["Op","Var","Param","Call"].indexOf(modelData.kind)>=0;item.editRequested.connect((where,text)=>root.editRequested(where,text));}
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
    TapHandler { acceptedButtons:Qt.RightButton; onTapped:valueMenu.popup() }
    Menu {
        id:valueMenu;background:Rectangle{radius:7;color:Theme.panelRaised;border.color:Theme.border}
        BwMenuItem{iconName:"info";text:"Details";onTriggered:root.detailsRequested(root.valueData&&root.valueData.kind==="Op"?root.valueData.op:(root.valueData?root.valueData.kind:"Value"))}
    }
}
