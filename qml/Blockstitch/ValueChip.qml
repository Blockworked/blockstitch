import QtQuick
import QtQuick.Controls
import QtQuick.Shapes

Item {
    id: root
    property var valueData
    property var location: null
    property bool editable: true
    property bool forceBoolean: false
    property string callDisplayLabel: qsTr("custom block")
    property bool boxed: !!valueData && ["Op", "Var", "Param", "Call"].indexOf(valueData.kind) >= 0
    property var blockDefinitions: []
    property bool dropHighlighted: false
    property bool paletteMode: false
    // Bare Number/Text field without its own box, for a host that draws the slot.
    property bool flatLeaf: false
    // Renders a Text/Number leaf as keycaps; a click asks the host to capture a key combo.
    property bool keyMode: false
    property bool keyCapturing: false
    signal keyCaptureRequested()
    // Renders a Text/Number leaf as a button that opens the host's picker:
    // {action, icon, display: function(text) -> label, tip}. A click calls
    // BlockRegistry.requestPick(action, location, value, chip). Reporters
    // still drop onto the slot as usual.
    property var pick: null
    readonly property string pickLabel: {
        if (!pick || !valueData || valueData.value === undefined) return "";
        const text = String(valueData.value);
        return pick.display ? pick.display(text) : text;
    }
    function keyPartLabel(k) {
        const named = {
            Control: "Ctrl", LeftControl: "Ctrl", RightControl: "Ctrl", Shift: "Shift", LeftShift: "Shift", RightShift: "Shift", Meta: "Super", Escape: "Esc", Return: "Enter", Space: "Space", Delete: "Del", Insert: "Ins",
            PageUp: "PgUp", PageDown: "PgDn", UpArrow: "\u2191", DownArrow: "\u2193", LeftArrow: "\u2190", RightArrow: "\u2192",
            CapsLock: "Caps", PrintScr: "PrtSc", Option: "Alt", AltGr: "AltGr"
        };
        if (named[k] !== undefined) return named[k];
        if (k.indexOf("Other:") === 0) return qsTr("Key %1").arg(k.substring(6));
        return k.length === 1 ? k.toUpperCase() : k;
    }
    // "Control+Alt+o" -> ["Control", "Alt", "o"]; a bare "+" is the plus key.
    function keyParts(text) {
        const parts = []; let cur = "";
        for (const c of String(text)) {
            if (c === "+" && cur.length) { parts.push(cur); cur = ""; } else cur += c;
        }
        if (cur.length) parts.push(cur);
        return parts;
    }
    // Marks this item for value-drop hit-testing (recursive childAt walk in BlockCanvas).
    readonly property bool isValueChip: true
    readonly property var valueLocation: location
    signal editRequested(var location, string text)
    // A leaf changed where there is no backend location to edit (a palette
    // prefab): `path` indexes args from this chip down, `leaf` is the new value.
    signal leafEdited(var path, var leaf)
    signal detailsRequested(string kind)
    // Palette entries add their own menu items ([{id, text, icon, danger}]).
    property var extraMenu: []
    signal extraMenuTriggered(string id)
    signal valueDragBegan(var location, var value, real sceneX, real sceneY, real offsetX, real offsetY, real w, real h)
    signal valueDragMoved(real sceneX, real sceneY)
    signal valueDragEnded(real sceneX, real sceneY)
    signal valueDragCanceled()

    // Click-to-preview: only operators and variables evaluate to something.
    property string previewKey: ""
    readonly property bool previewable: !!valueData && ["Op", "Var"].indexOf(valueData.kind) >= 0
    readonly property bool previewShown: previewKey !== "" && !!BlockRegistry.preview && BlockRegistry.preview.key === previewKey
    function requestPreview() {
        if (!previewable) return;
        if (previewKey === "") previewKey = BlockRegistry.nextPreviewKey();
        BlockRegistry.requestPreview(previewKey, valueData);
    }

    readonly property var opSpec: valueData && valueData.kind === "Op" ? BlockRegistry.operator(valueData.op) : null
    function defFor(id) { for (let i = 0; i < (blockDefinitions || []).length; ++i) if (blockDefinitions[i].id === id) return blockDefinitions[i]; return null; }
    readonly property var callDef: valueData && valueData.kind === "Call" ? defFor(valueData.block_id) : null
    readonly property bool booleanShape: forceBoolean || (!!valueData && (valueData.kind === "Bool"
        || (valueData.kind === "Op" && BlockRegistry.isBoolOp(valueData.op, valueData))
        || (valueData.kind === "Call" && !!callDef && callDef.shape === "ReturnsBool")))
    // An operator / variable / param / call reference is always its own
    // distinct block, even when a field passes boxed:false (which is meant
    // for bare Number/Text leaves typed straight into the field).
    readonly property bool isRef: !!valueData && ["Op", "Var", "Param", "Call"].indexOf(valueData.kind) >= 0
    readonly property bool showBox: boxed || isRef || booleanShape
    readonly property bool customCall: !!callDef
    // A call with branches reads as an embedded call-site: empty mouths under its head row.
    readonly property var callBranches: {
        if (!callDef) return [];
        const pieces = callDef.pieces || [], out = [];
        for (let i = 0; i < pieces.length; ++i) {
            if (pieces[i].kind !== "Branch") continue;
            let sep = "";
            for (let j = i + 1; j < pieces.length && pieces[j].kind !== "Branch"; ++j)
                if (pieces[j].kind === "Label") { sep = pieces[j].text; break; }
            out.push({ name: pieces[i].name || "", sep: sep });
        }
        return out;
    }
    readonly property bool hasBranches: callBranches.length > 0
    readonly property color refColor: callDef && callDef.color ? callDef.color : Theme.accent
    readonly property color quietRefColor: Qt.rgba(
        refColor.r * .3 + Theme.border.r * .7,
        refColor.g * .3 + Theme.border.g * .7,
        refColor.b * .3 + Theme.border.b * .7, 1)
    // The ghost carries the value while it is dragged out of its slot;
    // what's left behind reads as the blank field it will become.
    readonly property bool draggedOut: valueGrab.dragging
    readonly property bool inSlot: !!location && (location.kind === "Field" || (location.path || []).length > 0)
    readonly property bool hovered: (valueGrab.hovered && !valueGrab.dragging) || paletteHover.hovered
    // Sidebar prefabs have no location (so valueGrab never arms), but still
    // need the grab cursor + accent outline that blocks get from
    // InstructionBlock. A top HoverHandler does not consume presses, so the
    // palette's own drag surface behind it still receives them.
    HoverHandler { id: paletteHover; enabled: root.paletteMode; cursorShape: Qt.OpenHandCursor }
    readonly property string opPrefix: opSpec && opSpec.prefix ? opSpec.prefix : ""
    // `infix` goes between every pair of args; a list gives one per gap.
    readonly property var opInfixes: opSpec && Array.isArray(opSpec.infix) ? opSpec.infix : null
    readonly property string opInfix: opSpec && opSpec.infix && !opInfixes ? opSpec.infix : ""
    function infixAt(index) { return opInfixes ? (opInfixes[index - 1] || "") : opInfix; }
    readonly property string opSuffix: opSpec && opSpec.suffix ? opSpec.suffix : ""
    readonly property int enumIndex: opSpec && opSpec.enumArg ? opSpec.enumArg.index : -1
    readonly property int pickIndex: opSpec && opSpec.pickArg ? opSpec.pickArg.index : -1
    // An operator's own layout, for one whose words depend on the value (a
    // host's generic operator): [{label, arg: -1}|{arg, bool}], or null for the plain
    // prefix / infix / suffix form. The array is cached by the host so the
    // chip keeps its controls while the value changes.
    readonly property var opLayout: {
        if (!opSpec || !opSpec.layout) return null;
        return typeof opSpec.layout === "function" ? opSpec.layout(valueData) : opSpec.layout;
    }
    // What a Call renders: its definition's labels, and one slot per input.
    readonly property var callPieces: {
        if (opLayout) return opLayout;
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
    implicitWidth: Math.max(booleanShape ? 48 : 36, content.implicitWidth + (booleanShape ? 22 : showBox ? 12 : 0), hasBranches ? branchCol.implicitWidth + (booleanShape ? 50 : 28) : 0)
    implicitHeight: hasBranches ? content.implicitHeight + branchCol.implicitHeight + 24 : Math.max(27, content.implicitHeight + (showBox ? 4 : 0))

    // The box also renders while targeted as a drop preview, so even a
    // bare Number/Text leaf (showBox false) lights up when an operator
    // hovers it. Size stays untouched so the slot never shifts mid-drag.
    // A bare leaf has no box, so it doesn't pay for one until then.
    Rectangle {
        visible: root.draggedOut && root.inSlot
        anchors.fill: parent; radius: 5; color: Theme.field; border.color: Theme.border
    }
    Loader {
        anchors.fill: parent
        visible: !root.draggedOut
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
                    const n = Math.min(root.hasBranches ? 24 : h * .32, w / 2);
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
                fillColor: "#2e2f32"
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
        // `visible`, not `enabled`: a disabled area still swallows the hover
        // (and cursor) of the chip behind it. Hidden, it takes no presses.
        visible: dragEnabled
        onDragBegan: (sx, sy, ox, oy) => root.valueDragBegan(root.location, root.valueData, sx, sy, ox, oy, root.implicitWidth, root.implicitHeight)
        onDragMoved: (sx, sy) => root.valueDragMoved(sx, sy)
        onDragEnded: (sx, sy) => root.valueDragEnded(sx, sy)
        onDragCanceled: root.valueDragCanceled()
        onTapped: root.requestPreview()
    }
    // A handler, not a MouseArea: a MouseArea here would swallow the hover
    // (and grab cursor) of everything behind it.
    Item {
        id: menuArea
        anchors.fill: parent
        // Built on first use, like a block's menu.
        property var menu: null
        TapHandler {
            acceptedButtons: Qt.RightButton
            onTapped: eventPoint => {
                if (!menuArea.menu) menuArea.menu = valueMenu.createObject(menuArea);
                menuArea.menu.popup(eventPoint.position.x, eventPoint.position.y);
            }
        }
        Component {
            id: valueMenu
            BwMenu {
                id: valueMenuPopup
                BwMenuItem { visible: !root.extraMenu || root.extraMenu.length === 0; iconName: "info"; text: qsTr("Details"); onTriggered: root.detailsRequested(root.valueData && root.valueData.kind === "Call" ? root.valueData.block_id : root.valueData && root.valueData.kind === "Op" ? root.valueData.op : (root.valueData ? root.valueData.kind : "Value")) }
                Instantiator {
                    model: root.extraMenu
                    delegate: BwMenuItem {
                        required property var modelData
                        iconName: modelData.icon || ""; text: modelData.text; danger: !!modelData.danger
                        onTriggered: modelData.id === "details" ? root.detailsRequested(root.valueData && root.valueData.kind === "Call" ? root.valueData.block_id : root.valueData && root.valueData.kind === "Op" ? root.valueData.op : (root.valueData ? root.valueData.kind : "Value")) : root.extraMenuTriggered(modelData.id)
                    }
                    onObjectAdded: (index, object) => valueMenuPopup.addItem(object)
                    onObjectRemoved: (index, object) => valueMenuPopup.removeItem(object)
                }
            }
        }
    }
    Row {
        id: content; anchors.centerIn: parent; spacing: 3
        anchors.verticalCenterOffset: root.hasBranches ? 10 + content.implicitHeight / 2 - root.implicitHeight / 2 : 0
        visible: !root.draggedOut
        LucideIcon { visible: root.customCall; name: root.callDef && root.callDef.icon ? root.callDef.icon : "blocks"; color: root.refColor; width: 14; height: 14; anchors.verticalCenter: parent.verticalCenter }
        Text { visible: root.opPrefix.length > 0; text: root.opPrefix; color: Theme.textDim; font.pixelSize: 12; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter }
        Repeater {
            model: root.valueData && root.valueData.kind === "Op" && !root.opLayout ? (root.valueData.args || []) : []
            delegate: Row {
                id: argRow
                required property var modelData; required property int index; spacing: 3
                // The name/choice slot of a reporter is a dropdown over a plain Text leaf.
                readonly property bool isEnum: index === root.enumIndex && !!modelData && modelData.kind === "Text"
                anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                Text { visible: argRow.index > 0 && root.infixAt(argRow.index).length > 0; text: root.infixAt(argRow.index); color: Theme.textDim; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
                Loader {
                    active: argRow.isEnum
                    width: item ? item.implicitWidth : 0; height: item ? item.implicitHeight : 0
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
                // The host's picker for this slot, while it holds typed text.
                Rectangle {
                    id: pickButton
                    visible: argRow.index === root.pickIndex && !!argRow.modelData && argRow.modelData.kind === "Text"
                    width: visible ? 27 : 0; height: 27; radius: 5
                    anchors.verticalCenter: parent.verticalCenter
                    color: pickMouse.containsMouse && pickMouse.enabled ? Theme.panelRaised : Theme.field
                    border.color: pickMouse.containsMouse && pickMouse.enabled ? Theme.accent : Theme.border
                    LucideIcon { anchors.centerIn: parent; name: root.opSpec && root.opSpec.pickArg && root.opSpec.pickArg.icon ? root.opSpec.pickArg.icon : "list"; width: 14; height: 14; color: Theme.textDim }
                    MouseArea {
                        id: pickMouse
                        anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                        enabled: root.editable && !!root.location && !root.paletteMode
                        onClicked: BlockRegistry.requestPick(root.opSpec.pickArg.action || "", root.childLocation(argRow.index), argRow.modelData)
                    }
                }
            }
        }
        Loader {
            active: !!root.valueData && (root.valueData.kind === "Number" || root.valueData.kind === "Text")
            // Explicit, or the Loader keeps the width of a leaf it no longer shows.
            width: item ? item.implicitWidth : 0; height: item ? item.implicitHeight : 0
            anchors.verticalCenter: parent.verticalCenter
            sourceComponent: root.keyMode ? keycapLeaf : root.pick ? pickLeaf : textLeaf
        }
        Component {
            id: keycapLeaf
            Item {
                id: keycaps
                readonly property var parts: root.keyParts(root.valueData && root.valueData.value !== undefined ? root.valueData.value : "")
                readonly property bool showHint: root.keyCapturing || parts.length === 0
                implicitHeight: 30
                implicitWidth: showHint ? Math.max(36, hint.implicitWidth + 24) : Math.max(36, capRow.implicitWidth + 24)
                Rectangle {
                    anchors.fill: parent; radius: 5
                    color: root.keyCapturing ? Theme.accent : (capHover.hovered ? "#3b3c40" : Theme.field)
                    border.color: root.keyCapturing ? Theme.accentHover : Theme.border
                }
                Text {
                    id: hint; anchors.centerIn: parent; font.pixelSize: 12; visible: keycaps.showHint
                    text: root.keyCapturing ? qsTr("Press keys...") : qsTr("Click to set key")
                    color: root.keyCapturing ? "white" : Theme.textDim
                }
                Row {
                    id: capRow; spacing: 4; visible: !keycaps.showHint
                    anchors.centerIn: parent
                    Repeater {
                        model: keycaps.parts
                        delegate: Row {
                            id: capPart
                            required property var modelData; required property int index; spacing: 4
                            anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                            Text { visible: capPart.index > 0; text: "+"; color: Theme.textDim; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: root.keyPartLabel(capPart.modelData); color: Theme.text; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
                        }
                    }
                }
                HoverHandler { id: capHover; enabled: root.editable; cursorShape: Qt.PointingHandCursor }
                TapHandler { enabled: root.editable; onTapped: root.keyCaptureRequested() }
                ToolTip.visible: capHover.hovered && !root.keyCapturing; ToolTip.delay: 500; ToolTip.text: qsTr("Click to set key, or drop a variable here")
            }
        }
        Component {
            id: pickLeaf
            Rectangle {
                id: pickChip
                readonly property bool live: root.editable && !!root.location && !root.paletteMode
                implicitHeight: 27
                implicitWidth: Math.max(36, pickRow.implicitWidth + 18)
                radius: 5
                color: pickHover.hovered && live ? "#3b3c40" : (root.flatLeaf ? "transparent" : Theme.field)
                border.color: root.flatLeaf ? "transparent" : (pickHover.hovered && live ? Theme.accent : Theme.border)
                Behavior on color { enabled: Motion.enabled; ColorAnimation { duration: Motion.quick } }
                Behavior on border.color { enabled: Motion.enabled; ColorAnimation { duration: Motion.quick } }
                Row {
                    id: pickRow
                    anchors.centerIn: parent; spacing: 6
                    LucideIcon {
                        visible: !!root.pick.icon
                        name: root.pick.icon || ""; width: 13; height: 13; color: Theme.textDim
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text { text: root.pickLabel; color: Theme.text; font.pixelSize: 12; anchors.verticalCenter: parent.verticalCenter }
                }
                HoverHandler { id: pickHover; enabled: pickChip.live; cursorShape: Qt.PointingHandCursor }
                TapHandler { enabled: pickChip.live; onTapped: BlockRegistry.requestPick(root.pick.action || "", root.location, root.valueData, pickChip) }
                ToolTip.visible: pickHover.hovered && !!root.pick.tip; ToolTip.delay: 500; ToolTip.text: root.pick.tip || ""
                Accessible.role: Accessible.Button
                Accessible.name: root.pickLabel
            }
        }
        Component {
            id: textLeaf
            Item {
                implicitWidth: leafInput.implicitWidth; implicitHeight: leafInput.implicitHeight
                BwTextField {
                    id: leafInput
                    readOnly: !root.editable; text: root.valueData ? String(root.valueData.value) : ""; selectByMouse: true
                    font.pixelSize: 12; color: Theme.text; implicitHeight: 27
                    implicitWidth: Math.max(36, Math.min(600, contentWidth + 18))
                    leftPadding: 7; rightPadding: 7; topPadding: 2; bottomPadding: 2
                    background: Rectangle { radius: 5; color: root.flatLeaf ? "transparent" : Theme.field; border.color: root.flatLeaf ? "transparent" : (leafInput.activeFocus ? Theme.accent : Theme.border) }
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
        Text { visible: !!root.valueData && root.valueData.kind === "Op" && !root.opLayout && root.opPrefix.length===0 && root.opSuffix.length===0 && (root.valueData.args||[]).length===0; text: root.valueData && root.valueData.op ? root.valueData.op.toLowerCase() : ""; color: Theme.text; font.pixelSize: 12 }
        Text { visible: root.opSuffix.length>0; text:root.opSuffix; color:Theme.textDim; font.pixelSize:12; anchors.verticalCenter:parent.verticalCenter }
    }
    Column {
        id: branchCol
        visible: root.hasBranches && !root.draggedOut
        x: root.booleanShape ? 26 : 14; y: 10 + content.implicitHeight + 6
        spacing: 4
        Repeater {
            model: root.callBranches
            delegate: Column {
                id: branchItem
                required property var modelData
                required property int index
                spacing: 4
                // The branch parameter as a block seated in its mouth, as in the definition header.
                Rectangle {
                    width: Math.max(110, branchRow.implicitWidth + 24); height: 32; radius: 5
                    color: Theme.panelRaised; border.color: Theme.border
                    Row {
                        id: branchRow
                        anchors.centerIn: parent; spacing: 6
                        LucideIcon { name: "git-branch"; color: root.refColor; width: 14; height: 14; anchors.verticalCenter: parent.verticalCenter }
                        Text { text: branchItem.modelData.name; color: Theme.text; font.pixelSize: 12; font.weight: Font.DemiBold; anchors.verticalCenter: parent.verticalCenter }
                    }
                }
                Text {
                    visible: branchItem.index < root.callBranches.length - 1 && branchItem.modelData.sep.length > 0
                    text: branchItem.modelData.sep; color: Theme.text; font.pixelSize: 12; font.weight: Font.DemiBold
                    height: 20; verticalAlignment: Text.AlignVCenter; leftPadding: 4
                }
            }
        }
    }
    // Sample-evaluation result floating above the chip; it never takes input.
    Rectangle {
        visible: root.previewShown
        z: 100; enabled: false
        x: (root.width - width) / 2; y: -height - 6
        width: Math.min(260, tipText.implicitWidth + 16); height: tipText.implicitHeight + 8
        radius: Theme.radius; color: Theme.panelRaised
        border.color: BlockRegistry.preview && BlockRegistry.preview.error ? Theme.danger : Theme.border
        Text {
            id: tipText
            x: 8; y: 4; width: Math.min(244, implicitWidth)
            text: BlockRegistry.preview ? BlockRegistry.preview.text : ""
            color: BlockRegistry.preview && BlockRegistry.preview.error ? Theme.danger : Theme.text
            font.pixelSize: 12; font.weight: Font.DemiBold; wrapMode: Text.Wrap
        }
    }
}
