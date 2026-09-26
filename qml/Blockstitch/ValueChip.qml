import QtQuick
import QtQuick.Controls
import QtQuick.Shapes

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
    // A leaf changed where there is no backend location to edit (a palette
    // prefab): `path` indexes args from this chip down, `leaf` is the new value.
    signal leafEdited(var path, var leaf)
    signal detailsRequested(string kind)
    signal valueDragBegan(var location, var value, real sceneX, real sceneY, real offsetX, real offsetY, real w, real h)
    signal valueDragMoved(real sceneX, real sceneY)
    signal valueDragEnded(real sceneX, real sceneY)
    signal valueDragCanceled()

    readonly property var opSpec: valueData && valueData.kind === "Op" ? BlockRegistry.operator(valueData.op) : null
    function defFor(id) { for (let i = 0; i < (blockDefinitions || []).length; ++i) if (blockDefinitions[i].id === id) return blockDefinitions[i]; return null; }
    readonly property var callDef: valueData && valueData.kind === "Call" ? defFor(valueData.block_id) : null
    readonly property bool booleanShape: forceBoolean || (!!valueData && (valueData.kind === "Bool"
        || (valueData.kind === "Op" && BlockRegistry.isBoolOp(valueData.op))
        || (valueData.kind === "Call" && !!callDef && callDef.shape === "ReturnsBool")))
    // An operator / variable / param / call reference is always its own
    // distinct block, even when a field passes boxed:false (which is meant
    // for bare Number/Text leaves typed straight into the field).
    readonly property bool isRef: !!valueData && ["Op", "Var", "Param", "Call"].indexOf(valueData.kind) >= 0
    readonly property bool showBox: boxed || isRef || booleanShape
    readonly property bool customCall: !!callDef
    readonly property color refColor: callDef && callDef.color ? callDef.color : Theme.accent
    readonly property color quietRefColor: Qt.rgba(
        refColor.r * .3 + Theme.border.r * .7,
        refColor.g * .3 + Theme.border.g * .7,
        refColor.b * .3 + Theme.border.b * .7, 1)
    readonly property bool hovered: (valueGrab.hovered && !valueGrab.dragging) || paletteHover.hovered
    // Sidebar prefabs have no location (so valueGrab never arms), but still
    // need the grab cursor + accent outline that blocks get from
    // InstructionBlock. A top HoverHandler does not consume presses, so the
    // palette's own drag surface behind it still receives them.
    HoverHandler { id: paletteHover; enabled: root.paletteMode; cursorShape: Qt.OpenHandCursor }
    readonly property string opPrefix: opSpec && opSpec.prefix ? opSpec.prefix : ""
    readonly property string opInfix: opSpec && opSpec.infix ? opSpec.infix : ""
    readonly property string opSuffix: opSpec && opSpec.suffix ? opSpec.suffix : ""
    readonly property int enumIndex: opSpec && opSpec.enumArg ? opSpec.enumArg.index : -1
    // What a Call renders: its definition's labels, and one slot per input.
    readonly property var callPieces: {
        if (!callDef) return [];
        const out = []; let arg = 0;
        for (const p of (callDef.pieces || [])) {
            if (p.kind === "Label") out.push({ label: p.text, arg: -1, bool: false });
            else if (p.kind === "Input") out.push({ label: "", arg: arg++, bool: p.value_type === "Bool" });
        }
        return out;
    }
    function childLocation(index) {
        return root.location ? Object.assign({}, root.location, { path: (root.location.path || []).concat([index]) }) : null;
    }
    function emitLeaf(path, leaf, text) {
        if (root.location) root.editRequested(Object.assign({}, root.location, { path: (root.location.path || []).concat(path) }), text);
        else root.leafEdited(path, leaf);
    }
    function leafFromText(old, text) {
        const num = Number(text);
        if (old && old.kind === "Number" && text.trim().length && Number.isFinite(num)) return { kind: "Number", value: num };
        return { kind: "Text", value: text };
    }
    function wireNested(item, index, data) {
        // Bound, not copied: a chip now outlives edits elsewhere on its block.
        item.location = Qt.binding(() => root.childLocation(index));
        item.editable = Qt.binding(() => root.editable);
        item.boxed = !!data && ["Op", "Var", "Param", "Call"].indexOf(data.kind) >= 0;
        item.blockDefinitions = Qt.binding(() => root.blockDefinitions);
        item.dropHighlighted = root.dropHighlighted;
        item.editRequested.connect((where, text) => root.editRequested(where, text));
        item.leafEdited.connect((path, leaf) => root.leafEdited([index].concat(path), leaf));
        item.detailsRequested.connect(kind => root.detailsRequested(kind));
        item.valueDragBegan.connect((loc, val, sx, sy, ox, oy, w, h) => root.valueDragBegan(loc, val, sx, sy, ox, oy, w, h));
        item.valueDragMoved.connect((sx, sy) => root.valueDragMoved(sx, sy));
        item.valueDragEnded.connect((sx, sy) => root.valueDragEnded(sx, sy));
        item.valueDragCanceled.connect(() => root.valueDragCanceled());
        item.valueData = data;
    }
    implicitWidth: Math.max(booleanShape ? 48 : 36, content.implicitWidth + (booleanShape ? 22 : showBox ? 12 : 0))
    implicitHeight: Math.max(27, content.implicitHeight + (showBox ? 4 : 0))

    // The box also renders while targeted as a drop preview, so even a
    // bare Number/Text leaf (showBox false) lights up when an operator
    // hovers it. Size stays untouched so the slot never shifts mid-drag.
    // A bare leaf has no box, so it doesn't pay for one until then.
    Loader {
        anchors.fill: parent
        active: root.showBox || root.dropHighlighted
        sourceComponent: chipBox
    }
    Component {
        id: chipBox
        Shape {
            id: chipShape
            preferredRendererType: Shape.CurveRenderer
            readonly property color edge: (root.hovered || root.dropHighlighted) ? (root.customCall ? root.refColor : Theme.accent) : (root.customCall ? root.quietRefColor : Theme.border)
            readonly property string outline: {
                const w = width, h = height;
                if (w <= 0 || h <= 0) return "";
                if (root.booleanShape) {
                    const n = Math.min(h * .32, w / 2);
                    return "M" + n + " .5 L" + (w - n) + " .5 L" + (w - .5) + " " + h / 2 + " L" + (w - n) + " " + (h - .5) + " L" + n + " " + (h - .5) + " L.5 " + h / 2 + " Z";
                }
                const r = 5, R = w - .5, B = h - .5;
                return "M" + (.5 + r) + " .5 L" + (R - r) + " .5 Q" + R + " .5 " + R + " " + (.5 + r) + " L" + R + " " + (B - r) + " Q" + R + " " + B + " " + (R - r) + " " + B
                    + " L" + (.5 + r) + " " + B + " Q.5 " + B + " .5 " + (B - r) + " L.5 " + (.5 + r) + " Q.5 .5 " + (.5 + r) + " .5 Z";
            }
            // Drop preview reads stronger than hover: a soft glow under a
            // thicker line, so it stays visible next to the dragged ghost.
            ShapePath {
                strokeColor: root.dropHighlighted ? Qt.rgba(chipShape.edge.r, chipShape.edge.g, chipShape.edge.b, .35) : "transparent"
                strokeWidth: root.dropHighlighted ? 6 : 0
                fillColor: "transparent"
                joinStyle: ShapePath.RoundJoin
                PathSvg { path: chipShape.outline }
            }
            ShapePath {
                strokeColor: chipShape.edge
                strokeWidth: root.dropHighlighted ? 2.4 : (root.hovered ? 1.6 : 1)
                joinStyle: ShapePath.RoundJoin
                fillGradient: LinearGradient {
                    x1: 0; y1: 0; x2: chipShape.width; y2: chipShape.height
                    GradientStop { position: 0; color: "#37383c" }
                    GradientStop { position: 1; color: "#292a2d" }
                }
                PathSvg { path: chipShape.outline }
            }
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
        id: menuArea
        anchors.fill: parent; acceptedButtons: Qt.RightButton
        // Built on first use, like a block's menu.
        property var menu: null
        onPressed: mouse => {
            if (!menu) menu = valueMenu.createObject(menuArea);
            menu.popup(mouse.x, mouse.y);
        }
        Component {
            id: valueMenu
            BwMenu {
                BwMenuItem { iconName: "info"; text: "Details"; onTriggered: root.detailsRequested(root.valueData && root.valueData.kind === "Op" ? root.valueData.op : (root.valueData ? root.valueData.kind : "Value")) }
            }
        }
    }
    Row {
        id: content; anchors.centerIn: parent; spacing: 3
        Text { visible: root.opPrefix.length > 0; text: root.opPrefix; color: Theme.textDim; font.pixelSize: 12; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter }
        Repeater {
            model: root.valueData && root.valueData.kind === "Op" ? (root.valueData.args || []) : []
            delegate: Row {
                id: argRow
                required property var modelData; required property int index; spacing: 3
                // The name/choice slot of a reporter is a dropdown over a plain Text leaf.
                readonly property bool isEnum: index === root.enumIndex && !!modelData && modelData.kind === "Text"
                anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                Text { visible: argRow.index > 0 && root.opInfix.length > 0; text: root.opInfix; color: Theme.textDim; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
                Loader {
                    active: argRow.isEnum
                    anchors.verticalCenter: parent.verticalCenter
                    sourceComponent: Component {
                        BwComboBox {
                            id: enumBox
                            readonly property var choices: argRow.isEnum ? BlockRegistry.enumChoices(root.opSpec.enumArg) : []
                            readonly property int chosen: { const v = argRow.modelData ? argRow.modelData.value : ""; for (let i = 0; i < choices.length; ++i) if (choices[i].value === v) return i; return -1; }
                            model: choices; textRole: "label"
                            currentIndex: chosen
                            displayText: chosen >= 0 ? choices[chosen].label : (argRow.modelData && argRow.modelData.value ? String(argRow.modelData.value) : "choose")
                            implicitWidth: Math.min(170, Math.max(56, enumMetrics.advanceWidth + 34)); implicitHeight: 27; font.pixelSize: 12
                            leftPadding: 8; rightPadding: 26
                            enabled: root.editable
                            TextMetrics { id: enumMetrics; font: enumBox.font; text: enumBox.displayText }
                            onActivated: index => { const v = enumBox.choices[index].value; root.emitLeaf([argRow.index], { kind: "Text", value: v }, v); }
                        }
                    }
                }
                Loader {
                    active: !argRow.isEnum
                    source: "ValueChip.qml"; width: item ? item.implicitWidth : 0; height: item ? item.implicitHeight : 0
                    anchors.verticalCenter: parent.verticalCenter
                    onLoaded: root.wireNested(item, argRow.index, argRow.modelData)
                }
            }
        }
        Loader {
            active: !!root.valueData && (root.valueData.kind === "Number" || root.valueData.kind === "Text")
            anchors.verticalCenter: parent.verticalCenter
            sourceComponent: Component {
                BwTextField {
                    id: leafInput
                    readOnly: !root.editable; text: root.valueData ? String(root.valueData.value) : ""; selectByMouse: true
                    font.pixelSize: 12; color: Theme.text; implicitWidth: Math.max(36, Math.min(150, contentWidth + 18)); implicitHeight: 27
                    leftPadding: 7; rightPadding: 7; topPadding: 2; bottomPadding: 2
                    background: Rectangle { radius: 5; color: Theme.field; border.color: leafInput.activeFocus ? Theme.accent : Theme.border }
                    onEditingFinished: if (root.valueData && text !== String(root.valueData.value)) {
                        if (root.location) root.editRequested(root.location, text);
                        else root.leafEdited([], root.leafFromText(root.valueData, text));
                    }
                }
            }
        }
        Text { visible: !!root.valueData && ["Var","Param"].indexOf(root.valueData.kind)>=0; text: root.valueData && root.valueData.name ? root.valueData.name : ""; color: Theme.accent; font.pixelSize: 12; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter }
        Text { visible: !!root.valueData && root.valueData.kind === "Call" && !root.callDef; text: root.callDisplayLabel; color: Theme.text; font.pixelSize: 12; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter }
        Repeater {
            model: root.callPieces
            delegate: Item {
                id: callPiece
                required property var modelData; required property int index
                width: modelData.arg < 0 ? callText.implicitWidth : (callArg.item ? callArg.item.implicitWidth : 0)
                height: modelData.arg < 0 ? callText.implicitHeight : (callArg.item ? callArg.item.implicitHeight : 0)
                anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                Text { id: callText; visible: callPiece.modelData.arg < 0; text: callPiece.modelData.label; color: Theme.text; font.pixelSize: 12; font.weight: Font.DemiBold }
                Loader {
                    id: callArg
                    active: callPiece.modelData.arg >= 0
                    source: "ValueChip.qml"
                    onLoaded: {
                        const i = callPiece.modelData.arg, args = root.valueData.args || [];
                        root.wireNested(item, i, args[i] || (callPiece.modelData.bool ? { kind: "Bool" } : { kind: "Number", value: 0 }));
                    }
                }
            }
        }
        Item { visible: !!root.valueData && root.valueData.kind === "Bool"; width: 24; height: 17 }
        Text { visible: !!root.valueData && root.valueData.kind === "Op" && root.opPrefix.length===0 && root.opSuffix.length===0 && (root.valueData.args||[]).length===0; text: root.valueData && root.valueData.op ? root.valueData.op.toLowerCase() : ""; color: Theme.text; font.pixelSize: 12 }
        Text { visible: root.opSuffix.length>0; text:root.opSuffix; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
    }
}
