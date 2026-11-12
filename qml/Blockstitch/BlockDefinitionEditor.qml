import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Shapes

// Edits a custom block's definition: its pieces (labels, inputs, branches)
// with stable ids, shape, color, icon, identifier, description and input
// defaults. It only emits drafts; the host sends them and decides when to
// close. Capability flags hide what a host's runtime can't run, and anything
// a definition already holds is kept, never dropped.
Item {
    id: root
    implicitWidth: layout.implicitWidth
    implicitHeight: layout.implicitHeight

    // A draft is {pieces, shape, color, icon, identifier, description}.
    signal createRequested(var draft)
    signal editRequested(string blockId, var draft)
    signal cancelled()

    // What the host's runtime supports.
    property bool allowBranches: true
    property bool allowDefaults: true
    property bool allowCustomColor: true
    property var shapes: ["Normal", "Ending", "ReturnsValue", "ReturnsBool"]
    property var colorPresets: ["#4C97FF", "#9966FF", "#C65BCF", "#FFBF00", "#FFAB19", "#5BA9D0", "#59C059", "#FF8C1A", "#FF5B1F", "#FF6680", "#19B88E", "#FF4D4F", "#FF7F7F", "#FFB77B", "#FFF28A", "#8BF77A", "#78F0B0", "#70D5E8", "#7DB5F5", "#8080F5", "#C667E8", "#F27AED", "#B3B3B3"]
    // Host hooks: a context menu for the inline piece editors (created with
    // `editor` set), and how the identifier/description popup is titled.
    property Component textMenu: null
    property string detailsTitle: qsTr("Details")
    property string detailsIcon: "info"
    property string detailsNote: qsTr("A public identifier and a description for this block.")
    // What the identifier field accepts and suggests; a host may narrow it.
    property var identifierValidator: null
    property string identifierPlaceholder: qsTr("AUTHOR_BLOCKNAME")
    // Extra host fields shown under the description.
    property Component detailsPanel: null
    property string submitText: qsTr("OK")

    // The block being edited; empty while making a new one.
    property string blockId: ""
    // The definition as loaded, so fields this editor doesn't show survive.
    property var original: null

    property int selectedPiece: 0
    property int editingPiece: -1
    property var activeEditor: null
    property bool customPickerOpen: false
    property real customHue: 215
    property real customSaturation: 0.7
    property real customValue: 1
    property string blockShape: "Normal"
    property string blockColor: "#4C97FF"
    // Lucide name; empty means the default blocks icon.
    property string blockIcon: ""
    property alias blockIdentifier: detailId.text
    property alias blockDescription: detailDescription.text
    property string iconSearch: ""
    readonly property var allIcons: Object.keys(Icons.paths).sort()
    property string validationError: ""
    readonly property bool returnsValue: blockShape === "ReturnsValue" || blockShape === "ReturnsBool"
    readonly property bool hasBranches: branchCount() > 0
    readonly property bool offersCommands: shapes.indexOf("Normal") >= 0 || shapes.indexOf("Ending") >= 0
    readonly property bool offersReporters: shapes.indexOf("ReturnsValue") >= 0 || shapes.indexOf("ReturnsBool") >= 0


    function hsvToHex(h, s, v) {
        const c = v * s;
        const x = c * (1 - Math.abs((h / 60) % 2 - 1));
        const m = v - c;
        const i = Math.min(5, Math.floor(h / 60));
        const rgb = [[c, x, 0], [x, c, 0], [0, c, x], [0, x, c], [x, 0, c], [c, 0, x]][i];
        return "#" + rgb.map(k => Math.round((k + m) * 255).toString(16).padStart(2, "0")).join("").toUpperCase();
    }
    // [hue 0-360, saturation 0-1, value 0-1], or null for anything but #RRGGBB.
    function hexToHsv(hex) {
        const match = /^#([0-9a-f]{6})$/i.exec(hex);
        if (!match)
            return null;
        const rgb = [0, 2, 4].map(i => parseInt(match[1].slice(i, i + 2), 16) / 255);
        const max = Math.max(...rgb), min = Math.min(...rgb), delta = max - min;
        let hue = 0;
        if (delta !== 0)
            hue = max === rgb[0] ? 60 * (((rgb[1] - rgb[2]) / delta) % 6) : max === rgb[1] ? 60 * ((rgb[2] - rgb[0]) / delta + 2) : 60 * ((rgb[0] - rgb[1]) / delta + 4);
        return [(hue + 360) % 360, max === 0 ? 0 : delta / max, max];
    }
    function loadCustomColor(hex) {
        const hsv = hexToHsv(hex);
        if (!hsv)
            return;
        // A grey has no hue of its own: keep the one already showing.
        if (hsv[1] > 0.001 && hsv[2] > 0.001)
            customHue = hsv[0];
        customSaturation = hsv[1];
        customValue = hsv[2];
    }
    function toggleCustomPicker() {
        if (!customPickerOpen)
            loadCustomColor(blockColor);
        customPickerOpen = !customPickerOpen;
    }
    function openIconPicker() {
        iconPopup.open();
    }
    function updateCustomColor() {
        blockColor = hsvToHex(customHue, customSaturation, customValue);
    }

    BlockIconPopup {
        id: iconPopup
        editor: root
    }

    Popup {
        id: detailsPopup
        objectName: "detailsPopup"
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(540, parent.width - 48)
        padding: 20
        modal: true
        focus: true
        background: Rectangle { radius: Theme.radius; color: Theme.panel; border.color: Theme.border }
        contentItem: ColumnLayout {
            spacing: 12
            Label { text: root.detailsTitle; color: Theme.text; font.bold: true; font.pixelSize: 20 }
            Label {
                Layout.fillWidth: true
                visible: text.length > 0
                text: root.detailsNote
                wrapMode: Text.WordWrap
                color: Theme.textDim
            }
            Label { text: qsTr("Identifier"); color: Theme.text }
            StitchTextField {
                id: detailId
                objectName: "detailsIdentifier"
                Layout.fillWidth: true
                validator: root.identifierValidator
                placeholderText: root.identifierPlaceholder
            }
            Label { text: qsTr("Description"); color: Theme.text }
            StitchTextField {
                id: detailDescription
                objectName: "detailsDescription"
                Layout.fillWidth: true
                placeholderText: qsTr("Description for Details (optional)")
            }
            Loader {
                Layout.fillWidth: true
                active: root.detailsPanel !== null
                visible: active
                sourceComponent: root.detailsPanel
            }
            StitchButton { Layout.alignment: Qt.AlignRight; text: qsTr("Done"); onClicked: detailsPopup.close() }
        }
    }

    BlockInputsPopup {
        id: defaultsPopup
        editor: root
    }

    ListModel {
        id: pieces
    }
    // The pieces being edited, for the popups in their own files.
    readonly property alias pieceModel: pieces
    // One entry per branch piece: its model index, name and the separator label shown below it.
    property var previewGroups: []
    property var branchInfo: []
    function refreshBranches() {
        const out = [];
        for (let i = 0; i < pieces.count; ++i) {
            if (pieces.get(i).pieceKind !== "Branch")
                continue;
            let sep = "", sepIndex = -1;
            for (let j = i + 1; j < pieces.count && pieces.get(j).pieceKind !== "Branch"; ++j)
                if (pieces.get(j).pieceKind === "Label") {
                    sep = pieces.get(j).pieceName;
                    sepIndex = j;
                    break;
                }
            out.push({
                index: i,
                name: pieces.get(i).pieceName,
                sep: sep,
                sepIndex: sepIndex
            });
        }
        branchInfo = out;
        const groups = [];
        let current = null;
        for (let i = 0; i < pieces.count; ++i) {
            const p = pieces.get(i);
            if (p.pieceKind === "Branch") { current = null; continue; }
            if (p.component) {
                current = {component: true, indices: [i]};
                groups.push(current);
            } else if (current) current.indices.push(i);
            else groups.push({component: false, indices: [i]});
        }
        previewGroups = groups;
    }
    function commitSeparator(branchOrdinal, label) {
        const branch = branchInfo[branchOrdinal];
        if (!branch) return;
        const text = label.trim();
        if (branch.sepIndex >= 0)
            pieces.setProperty(branch.sepIndex, "pieceName", text);
        else if (text.length) {
            const insertAt = branch.index + 1;
            pieces.insert(insertAt, blankPiece("Label", text));
            if (selectedPiece >= insertAt) selectedPiece++;
        }
    }
    function commitSeparatorEdits() {
        const edits = [];
        for (let i = 0; i < branchInfo.length - 1; ++i) {
            const row = branchRows.itemAt(i);
            if (row && row.separatorDraft !== branchInfo[i].sep)
                edits.push({ ordinal: i, text: row.separatorDraft });
        }
        for (const edit of edits) commitSeparator(edit.ordinal, edit.text);
    }
    function branchPreviewWidth() {
        let width = 270;
        for (const branch of branchInfo) {
            const name = editingPiece === branch.index && activeEditor ? activeEditor.text : branch.name;
            width = Math.max(width, name.length * 10 + 170);
        }
        return width;
    }
    Connections {
        target: pieces
        function onCountChanged() {
            root.refreshBranches();
        }
        function onDataChanged() {
            root.refreshBranches();
        }
        function onRowsMoved() {
            root.refreshBranches();
        }
    }

    function uuid() { return BlockRegistry.newId(); }
    // Starts editing `def` (a definition as the host's state holds it).
    function load(def) {
        blockId = def.id || "";
        original = JSON.parse(JSON.stringify(def));
        pieces.clear();
        for (const p of def.pieces || []) {
            pieces.append({
                component: !!p.component,
                pieceKind: p.kind,
                pieceName: (p.kind === "Label" || p.kind === "Button" ? p.text : p.name) || "",
                valueType: p.kind === "Input" ? (p.value_type || "Any") : "Any",
                pieceId: p.id || uuid(),
                defaultKind: p.default_value ? p.default_value.kind : "",
                defaultText: p.default_value ? String(p.default_value.value) : "",
                pieceJson: JSON.stringify(p),
                multiline: p.kind === "Input" && !!p.multiline
            });
        }
        if (!pieces.count)
            pieces.append(blankPiece("Label", qsTr("block name")));
        selectedPiece = 0;
        editingPiece = -1;
        activeEditor = null;
        blockShape = def.shape || "Normal";
        blockColor = def.color || "#4C97FF";
        blockIcon = def.icon || "";
        detailId.text = def.identifier || "";
        detailDescription.text = def.description || "";
        validationError = "";
        customPickerOpen = false;
        closePopups();
        Qt.callLater(previewViewport.centerPreview);
    }
    // Starts a new block.
    function reset() {
        blockId = "";
        original = null;
        pieces.clear();
        pieces.append(blankPiece("Label", qsTr("block name")));
        selectedPiece = 0;
        editingPiece = -1;
        activeEditor = null;
        blockShape = shapes.indexOf("Normal") >= 0 ? "Normal" : shapes[0];
        blockColor = colorPresets[0] || "#4C97FF";
        blockIcon = "";
        detailId.text = "";
        detailDescription.text = "";
        validationError = "";
        customPickerOpen = false;
        closePopups();
        Qt.callLater(previewViewport.centerPreview);
    }
    function blankPiece(kind, name, valueType) {
        return { component: false, pieceKind: kind, pieceName: name, valueType: valueType || "Any", pieceId: uuid(), defaultKind: "", defaultText: "", pieceJson: "", multiline: false };
    }
    // Puts the keyboard in the first piece; the host calls it once shown.
    function focusFirst() {
        Qt.callLater(() => focusPiece(0));
    }
    function closePopups() {
        iconPopup.close();
        detailsPopup.close();
        defaultsPopup.close();
        appearancePopup.close();
    }
    // Shows a refusal from the host, e.g. the backend's validation error.
    function fail(message) {
        validationError = String(message);
    }
    function firstShape(options) {
        for (const shape of options)
            if (shapes.indexOf(shape) >= 0)
                return shape;
        return blockShape;
    }
    function branchCount() {
        let count = 0;
        for (let i = 0; i < pieces.count; ++i)
            if (pieces.get(i).pieceKind === "Branch")
                count++;
        return count;
    }
    function firstBranchIndex() {
        for (let i = 0; i < pieces.count; ++i)
            if (pieces.get(i).pieceKind === "Branch")
                return i;
        return -1;
    }
    function nextName(prefix) {
        let n = 1;
        while (true) {
            const candidate = prefix + n;
            let used = false;
            for (let i = 0; i < pieces.count; ++i)
                if (pieces.get(i).pieceKind !== "Label" && pieces.get(i).pieceName === candidate)
                    used = true;
            if (!used)
                return candidate;
            n++;
        }
    }
    function addComponent() {
        addPiece("Input", "Bool");
        pieces.setProperty(selectedPiece, "component", true);
        pieces.setProperty(selectedPiece, "pieceName", nextName(qsTr("component")));
        pieces.setProperty(selectedPiece, "defaultKind", "Bool");
        pieces.setProperty(selectedPiece, "defaultText", "false");
    }
    function addPiece(kind, valueType) {
        commitPiece();
        commitSeparatorEdits();
        if (kind === "Branch" && hasBranches)
            pieces.append(blankPiece("Label", ""));
        const name = kind === "Label" ? qsTr("label") : nextName(kind === "Branch" ? qsTr("branch") : kind === "Button" ? qsTr("settings") : qsTr("value"));
        let insertAt = pieces.count;
        if (kind !== "Branch") {
            if (selectedPiece >= 0 && selectedPiece < pieces.count)
                insertAt = selectedPiece + 1;
            // Keep header fields before the branch mouths.
            if (hasBranches)
                insertAt = Math.min(insertAt, firstBranchIndex());
        }
        pieces.insert(insertAt, blankPiece(kind, name, valueType));
        selectedPiece = insertAt;
        Qt.callLater(() => focusPiece(insertAt));
    }
    function findPiece(item, index) {
        if (!item || !item.visible)
            return null;
        if (item.pieceIndex === index && item.startEdit)
            return item;
        for (const child of item.children || []) {
            const match = findPiece(child, index);
            if (match)
                return match;
        }
        return null;
    }
    function focusPiece(index) {
        const item = findPiece(previewPane, index);
        if (item)
            item.startEdit();
    }
    function beginEdit(index, editor) {
        commitPiece();
        selectedPiece = index;
        editingPiece = index;
        activeEditor = editor;
        Qt.callLater(() => {
            if (editingPiece === index) {
                editor.forceActiveFocus();
                editor.selectAll();
            }
        });
    }
    function commitPiece() {
        if (activeEditor && editingPiece >= 0 && editingPiece < pieces.count) {
            const name = activeEditor.text.trim();
            if (name || pieces.get(editingPiece).pieceKind === "Label")
                pieces.setProperty(editingPiece, "pieceName", name);
        }
        activeEditor = null;
        editingPiece = -1;
    }
    function moveSelected(delta) {
        commitPiece();
        commitSeparatorEdits();
        const target = selectedPiece + delta;
        if (target < 0 || target >= pieces.count)
            return;
        pieces.move(selectedPiece, target, 1);
        selectedPiece = target;
    }
    function moveBranch(ordinal, delta) {
        commitPiece();
        commitSeparatorEdits();
        const targetOrdinal = ordinal + delta;
        if (ordinal < 0 || targetOrdinal < 0 || targetOrdinal >= branchInfo.length)
            return;
        const from = branchInfo[ordinal].index;
        const to = branchInfo[targetOrdinal].index;
        const roles = ["component", "pieceKind", "pieceName", "valueType", "pieceId", "defaultKind", "defaultText", "pieceJson", "multiline"];
        const copy = item => {
            const out = {};
            for (const role of roles)
                out[role] = item[role];
            return out;
        };
        const first = copy(pieces.get(from));
        pieces.set(from, copy(pieces.get(to)));
        pieces.set(to, first);
        selectedPiece = to;
    }
    function removeBranch(ordinal) {
        commitPiece();
        commitSeparatorEdits();
        const branch = branchInfo[ordinal];
        if (!branch)
            return;
        // The separator after a branch belongs to that gap. Removing the last
        // branch removes the preceding gap instead.
        const separatorIndex = ordinal < branchInfo.length - 1
            ? branch.sepIndex
            : ordinal > 0 ? branchInfo[ordinal - 1].sepIndex : -1;
        const indices = separatorIndex >= 0 ? [branch.index, separatorIndex] : [branch.index];
        indices.sort((a, b) => b - a);
        for (const index of indices)
            pieces.remove(index);
        refreshBranches();
        selectedPiece = branchInfo.length
            ? branchInfo[Math.min(ordinal, branchInfo.length - 1)].index
            : pieces.count ? Math.min(branch.index, pieces.count - 1) : -1;
    }
    function removeSelected() {
        if (!pieces.count)
            return;
        commitPiece();
        commitSeparatorEdits();
        if (pieces.get(selectedPiece).pieceKind === "Branch") {
            for (let i = 0; i < branchInfo.length; ++i)
                if (branchInfo[i].index === selectedPiece) {
                    removeBranch(i);
                    return;
                }
        }
        const removedId = pieces.get(selectedPiece).pieceId;
        for (let i = 0; i < pieces.count; ++i) {
            const p = pieces.get(i), saved = p.pieceJson ? JSON.parse(p.pieceJson) : {};
            if (p.pieceKind === "Button") updateButton(i, {inputs: (saved.inputs || []).filter(id => id !== removedId)});
        }
        pieces.remove(selectedPiece);
        selectedPiece = pieces.count ? Math.max(0, Math.min(selectedPiece, pieces.count - 1)) : -1;
    }
    function setInputDefault(index, kind, text) {
        pieces.setProperty(index, "defaultKind", kind);
        pieces.setProperty(index, "defaultText", String(text));
    }
    function updatePieceUi(index, patch) {
        const item = pieces.get(index), saved = item.pieceJson ? JSON.parse(item.pieceJson) : {};
        saved.ui = Object.assign({}, saved.ui || {}, patch);
        pieces.setProperty(index, "pieceJson", JSON.stringify(saved));
    }
    function setChoices(index, text) {
        const choices = text.split("\n").filter(line => line.trim().length).map(line => {
            const split = line.indexOf("|");
            return {label: (split < 0 ? line : line.slice(0, split)).trim(), value: (split < 0 ? line : line.slice(split + 1)).trim()};
        });
        updatePieceUi(index, {choices: choices});
        if (choices.length) {
            pieces.setProperty(index, "multiline", false);
            const p = pieces.get(index);
            if (p.defaultKind !== "Text" || !choices.some(c => c.value === p.defaultText))
                setInputDefault(index, "Text", choices[0].value);
        }
    }
    function updateButton(index, patch) {
        const item = pieces.get(index), saved = item.pieceJson ? JSON.parse(item.pieceJson) : {};
        pieces.setProperty(index, "pieceJson", JSON.stringify(Object.assign({}, saved, patch)));
    }
    function screenInputChoices() {
        const out = [];
        for (let i = 0; i < pieces.count; ++i) {
            const p = pieces.get(i);
            if (p.pieceKind === "Input") out.push({id: p.pieceId, label: p.pieceName});
        }
        return out;
    }
    function inputDefaultForPiece(piece) {
        if (!piece.defaultKind)
            return undefined;
        return {kind: piece.defaultKind, value: piece.defaultKind === "Number"
            ? Number(piece.defaultText) : piece.defaultKind === "Bool"
            ? piece.defaultText === "true" : piece.defaultText};
    }
    function defaultsValid() {
        for (let i = 0; i < pieces.count; ++i) {
            const p = pieces.get(i);
            if (p.pieceKind === "Input" && p.defaultKind === "Number"
                && (!p.defaultText.trim().length || !isFinite(Number(p.defaultText))))
                return false;
        }
        return true;
    }
    function resultPieces() {
        const out = [];
        for (let i = 0; i < pieces.count; ++i) {
            const p = pieces.get(i);
            const name = p.pieceName.trim();
            const piece = p.pieceJson ? JSON.parse(p.pieceJson) : {};
            piece.kind = p.pieceKind;
            piece.id = p.pieceId || uuid();
            if (p.pieceKind === "Label" || p.pieceKind === "Button") {
                piece.text = name;
                if (p.pieceKind === "Button") {
                    piece.title = piece.title || name;
                    piece.inputs = piece.inputs || [];
                    delete piece.name;
                }
            } else {
                piece.name = name;
                if (p.pieceKind === "Input") {
                    piece.value_type = p.valueType;
                    if (p.component) piece.component = true;
                    else delete piece.component;
                    if (p.multiline && p.valueType !== "Bool") piece.multiline = true;
                    else delete piece.multiline;
                    // A host without defaults passes the stored one through.
                    if (root.allowDefaults) {
                        const value = root.inputDefaultForPiece(p);
                        if (value === undefined) delete piece.default_value;
                        else piece.default_value = value;
                    }
                }
            }
            out.push(piece);
        }
        return out;
    }
    // What the host sends, with any field this editor doesn't show kept.
    function draft() {
        return {
            pieces: resultPieces(),
            shape: blockShape,
            color: blockColor,
            icon: blockIcon,
            identifier: detailId.text.trim(),
            description: detailDescription.text.trim()
        };
    }
    // The first problem with the current pieces, or "". The host's backend
    // still validates; this only catches what can be said before sending.
    function validate() {
        if (allowDefaults && !defaultsValid())
            return qsTr("Enter a finite number for each numeric default");
        let hasLabel = false, afterBranch = false;
        const names = ({});
        for (let i = 0; i < pieces.count; ++i) {
            const p = pieces.get(i);
            const text = p.pieceName.trim();
            if (p.pieceKind === "Branch") afterBranch = true;
            if (p.component && afterBranch) return qsTr("Components must come before branches");
            if (p.pieceKind === "Button") {
                const button = p.pieceJson ? JSON.parse(p.pieceJson) : {};
                if (!text.length || !(button.title || text).trim().length || !(button.inputs || []).length)
                    return qsTr("Choose inputs for every settings button in Inputs");
                continue;
            }
            if (p.pieceKind === "Label") {
                if (text.length)
                    hasLabel = true;
                continue;
            }
            if (!text.length)
                return qsTr("Every input and branch needs a name");
            if (names[text])
                return qsTr("Input and branch names must be unique");
            names[text] = true;
        }
        const result = resultPieces(), inputs = result.filter(p => p.kind === "Input");
        const shown = new Set(result.filter(p => p.kind === "Button").reduce((ids, p) => ids.concat(p.inputs || []), []));
        for (const input of inputs) {
            const ui = input.ui || {}, choices = ui.choices || [], seen = new Set();
            if (ui.screen_only && !shown.has(input.id)) return qsTr("Every hidden input needs a settings button");
            if (input.component && (ui.screen_only || choices.length)) return qsTr("Component toggles must stay on the block");
            if (choices.length > 128) return qsTr("A dropdown can have at most 128 choices");
            for (const choice of choices) {
                if (!choice.label.trim() || !choice.value || seen.has(choice.value)) return qsTr("Choices need labels and unique non-empty values");
                seen.add(choice.value);
            }
            if (choices.length && input.default_value && (input.default_value.kind !== "Text" || !seen.has(input.default_value.value)))
                return qsTr("Choose a starting value from the dropdown choices");
        }
        if (!hasLabel)
            return qsTr("Give the block a name");
        return "";
    }
    // Emits the draft, or shows why not. True when emitted.
    function submit() {
        commitPiece();
        commitSeparatorEdits();
        validationError = validate();
        if (validationError.length) {
            if (allowDefaults && !defaultsValid())
                defaultsPopup.open();
            return false;
        }
        if (blockId.length)
            editRequested(blockId, draft());
        else
            createRequested(draft());
        return true;
    }

    BlockAppearancePopup {
        id: appearancePopup
        editor: root
    }




    ColumnLayout {
        id: layout
        anchors.fill: parent
        spacing: 12

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: 300
            Layout.minimumHeight: 170
            radius: Theme.radius
            color: Theme.canvas
            border.color: Theme.border
            clip: true
            Canvas {
                id: previewGrid
                anchors.fill: parent
                Connections { target: Theme; function onDarkChanged() { previewGrid.requestPaint(); } }
                onPaint: {
                    const c = getContext("2d");
                    c.reset();
                    c.fillStyle = Theme.border;
                    for (let x = 11 - previewViewport.contentX % 22; x < width; x += 22)
                        for (let y = 11 - previewViewport.contentY % 22; y < height; y += 22) {
                            c.beginPath();
                            c.arc(x, y, 1.1, 0, Math.PI * 2);
                            c.fill();
                        }
                }
            }

            Flickable {
                id: previewViewport
                objectName: "definitionPreviewViewport"
                anchors.fill: parent
                contentWidth: Math.max(width, previewPane.implicitWidth + 48) + 192
                contentHeight: Math.max(height, previewPane.implicitHeight + 80) + 192
                boundsBehavior: Flickable.StopAtBounds
                flickableDirection: Flickable.HorizontalAndVerticalFlick
                interactive: !previewWheel.active
                SmoothScroll { id: previewScroll; flickable: previewViewport }
                WheelHandler {
                    id: previewWheel
                    target: null
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    orientation: Qt.Horizontal | Qt.Vertical
                    onWheel: event => {
                        const touchpad = previewScroll.isTouchpad(event);
                        const pan = (ad, pd) => previewScroll.wheelStep(ad, pd, touchpad);
                        const px = pan(event.angleDelta.x, event.pixelDelta.x);
                        const py = pan(event.angleDelta.y, event.pixelDelta.y);
                        if (touchpad) previewScroll.follow(px, py);
                        else previewScroll.scrollBy(px, py, true);
                        event.accepted = true;
                    }
                }
                onContentXChanged: previewGrid.requestPaint()
                onContentYChanged: previewGrid.requestPaint()
                onContentWidthChanged: centerPreview()
                onContentHeightChanged: centerPreview()
                onWidthChanged: centerPreview()
                onHeightChanged: centerPreview()
                function centerPreview() {
                    previewScroll.stop();
                    cancelFlick();
                    contentX = (contentWidth - width) / 2;
                    contentY = (contentHeight - height) / 2;
                }

                MouseArea {
                    width: previewViewport.contentWidth
                    height: previewViewport.contentHeight
                    onClicked: {
                        root.commitPiece();
                        root.commitSeparatorEdits();
                        root.selectedPiece = -1;
                        previewViewport.forceActiveFocus();
                    }
                }

            Column {
                id: previewPane
                objectName: "definitionPreviewBlock"
                x: (previewViewport.contentWidth - width) / 2
                y: (previewViewport.contentHeight - height) / 2
                spacing: 8
                Item {
                    visible: !root.hasBranches
                    width: Math.max(root.returnsValue ? 90 : 132, previewRow.implicitWidth + (root.returnsValue ? 36 : 28))
                    height: visible ? (root.returnsValue ? Math.max(55, previewRow.implicitHeight + 14) : Math.max(50, previewRow.implicitHeight + 20) + (root.blockShape === "Ending" ? 0 : 8)) : 0
                    BlockSurface {
                        anchors.fill: parent
                        visible: !root.returnsValue
                        shape: root.blockShape === "Ending" ? "cap" : "stack"
                        fill: Theme.block
                        outline: Theme.border
                        hoverColor: root.blockColor
                    }
                    Canvas {
                        id: reporterCanvas
                        anchors.fill: parent; visible: root.returnsValue; antialiasing: true
                        onWidthChanged: requestPaint(); onHeightChanged: requestPaint()
                        Connections { target: root; function onBlockShapeChanged() { reporterCanvas.requestPaint(); } function onBlockColorChanged() { reporterCanvas.requestPaint(); } }
                        Connections { target: Theme; function onDarkChanged() { reporterCanvas.requestPaint(); } }
                        onPaint: {
                            const c = getContext("2d"); c.reset(); c.beginPath();
                            if (root.blockShape === "ReturnsBool") {
                                const n = Math.min(height * .32, width / 2);
                                c.moveTo(n, .6); c.lineTo(width - n, .6); c.lineTo(width - .6, height / 2);
                                c.lineTo(width - n, height - .6); c.lineTo(n, height - .6); c.lineTo(.6, height / 2); c.closePath();
                            } else c.roundedRect(.6, .6, width - 1.2, height - 1.2, 20, 20);
                            c.fillStyle = Theme.block; c.fill(); c.strokeStyle = Theme.border; c.lineWidth = 1.4; c.stroke();
                        }
                    }
                    Row {
                        id: previewRow
                        x: root.returnsValue ? 18 : 14
                        y: Math.round((parent.height - (root.returnsValue || root.blockShape === "Ending" ? 0 : 8) - height) / 2)
                        spacing: 4
                        LucideIcon {
                            name: root.blockIcon || "blocks"
                            color: root.blockColor
                            width: 16
                            height: 16
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        DefinitionPrototype { editor: root }
                    }
                }

                Item {
                    id: wrapShell
                    visible: root.hasBranches
                    readonly property bool boolShape: root.blockShape === "ReturnsBool"
                    readonly property real padX: root.returnsValue ? (boolShape ? 36 : 22) : 0
                    readonly property real padY: root.returnsValue ? 12 : 0
                    width: wrapPreview.width + 2 * padX
                    height: visible ? wrapPreview.height + 2 * padY : 0
                    Shape {
                        id: wrapShape
                        anchors.fill: parent
                        visible: root.returnsValue
                        preferredRendererType: Shape.CurveRenderer
                        readonly property string outline: {
                            const w = width, h = height;
                            if (w <= 0 || h <= 0) return "";
                            if (wrapShell.boolShape) {
                                const n = Math.min(24, h / 2);
                                return "M" + n + " .5 L" + (w - n) + " .5 L" + (w - .5) + " " + h / 2 + " L" + (w - n) + " " + (h - .5) + " L" + n + " " + (h - .5) + " L.5 " + h / 2 + " Z";
                            }
                            const r = Math.min(24, h / 2), R = w - .5, B = h - .5;
                            return "M" + (.5 + r) + " .5 L" + (R - r) + " .5 Q" + R + " .5 " + R + " " + (.5 + r) + " L" + R + " " + (B - r) + " Q" + R + " " + B + " " + (R - r) + " " + B
                                + " L" + (.5 + r) + " " + B + " Q.5 " + B + " .5 " + (B - r) + " L.5 " + (.5 + r) + " Q.5 .5 " + (.5 + r) + " .5 Z";
                        }
                        ShapePath {
                            strokeColor: Theme.border
                            strokeWidth: 1.3
                            joinStyle: ShapePath.RoundJoin
                            fillColor: Theme.block
                            PathSvg { path: wrapShape.outline }
                        }
                    }
                Item {
                    id: wrapPreview
                    x: wrapShell.padX
                    y: wrapShell.padY
                    visible: root.hasBranches
                    readonly property real mouthHeight: 50
                    readonly property real headerHeight: root.previewGroups.some(g => g.component) ? 66 : 50
                    readonly property bool noTab: root.returnsValue || root.blockShape === "Ending"
                    width: Math.max(270, branchHead.implicitWidth + 70, root.branchPreviewWidth())
                    height: visible ? headerHeight + root.branchInfo.length * mouthHeight + Math.max(0, root.branchInfo.length - 1) * 34 + 26 + (noTab ? 0 : 8) : 0
                    BlockSurface {
                        anchors.fill: parent
                        shape: "wrap"
                        headNotch: !root.returnsValue
                        footTab: !wrapPreview.noTab
                        fill: Theme.block
                        outline: Theme.border
                        hoverColor: root.blockColor
                        headHeight: wrapPreview.headerHeight
                        midHeight: 34
                        footHeight: 26
                        spine: 20
                        mouthHeights: root.branchInfo.map(() => wrapPreview.mouthHeight)
                    }
                    Row {
                        id: branchHead
                        x: 18
                        y: 12
                        spacing: 5
                        LucideIcon {
                            name: root.blockIcon || "blocks"
                            color: root.blockColor
                            width: 16
                            height: 16
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        DefinitionPrototype { editor: root }
                    }
                    Repeater {
                        id: branchRows
                        model: root.branchInfo
                        delegate: Item {
                            id: branchRow
                            required property var modelData
                            required property int index
                            readonly property real rowTop: wrapPreview.headerHeight + index * (wrapPreview.mouthHeight + 34)
                            readonly property string separatorDraft: separatorField.text
                            // A branch parameter is a real stack-shaped header, seated in
                            // the mouth with its connectors aligned to the enclosing wrap.
                            BlockSurface {
                                x: 20
                                y: parent.rowTop
                                width: Math.max(150, branchContents.implicitWidth + 28)
                                height: wrapPreview.mouthHeight + 8
                                shape: "stack"
                                fill: Theme.panelRaised
                                outline: Theme.border
                                hoverColor: root.blockColor
                            }
                            Row {
                                id: branchContents
                                x: 34
                                y: parent.rowTop + 8
                                spacing: 6
                                LucideIcon {
                                    name: "git-branch"
                                    color: root.blockColor
                                    width: 16
                                    height: 16
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                                DefinitionPiece {
                                    id: branchNamePiece
                                    editor: root
                                    width: implicitWidth
                                    pieceIndex: modelData.index
                                    pieceKind: "Branch"
                                    pieceName: modelData.name
                                    valueType: "Any"
                                    index: modelData.index
                                }
                                Rectangle {
                                    visible: branchNamePiece.selected
                                    width: visible ? branchActions.implicitWidth + 6 : 0
                                    height: 28
                                    radius: 5
                                    color: Theme.panelRaised
                                    border.color: Theme.border
                                    Row {
                                        id: branchActions
                                        anchors.centerIn: parent
                                        spacing: 2
                                        Repeater {
                                            model: [
                                                { icon: "chevron-down", tip: qsTr("Move branch up"), direction: -1 },
                                                { icon: "x", tip: qsTr("Remove branch"), direction: 0 },
                                                { icon: "chevron-down", tip: qsTr("Move branch down"), direction: 1 }
                                            ]
                                            delegate: Button {
                                                id: branchAction
                                                required property var modelData
                                                width: 22
                                                height: 22
                                                padding: 0
                                                enabled: modelData.direction === 0 || (modelData.direction < 0
                                                    ? branchRow.index > 0 : branchRow.index < root.branchInfo.length - 1)
                                                ToolTip.visible: hovered
                                                ToolTip.text: modelData.tip
                                                onClicked: modelData.direction === 0
                                                    ? root.removeBranch(branchRow.index) : root.moveBranch(branchRow.index, modelData.direction)
                                                contentItem: LucideIcon {
                                                    name: modelData.icon
                                                    rotation: modelData.direction < 0 ? 180 : 0
                                                    color: modelData.direction === 0 ? Theme.danger : Theme.textDim
                                                    width: 14
                                                    height: 14
                                                    anchors.centerIn: parent
                                                }
                                                background: Rectangle {
                                                    radius: 4
                                                    color: branchAction.hovered ? Theme.hover : "transparent"
                                                    Behavior on color { enabled: Motion.enabled; ColorAnimation { duration: Motion.quick } }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            TextField {
                                id: separatorField
                                visible: index < root.branchInfo.length - 1
                                x: 68
                                y: parent.rowTop + wrapPreview.mouthHeight + 5
                                width: Math.max(104, contentWidth + 18)
                                height: 24
                                text: modelData.sep
                                placeholderText: qsTr("Add label")
                                color: Theme.text
                                font.pixelSize: 12
                                verticalAlignment: TextInput.AlignVCenter
                                leftPadding: 7
                                rightPadding: 7
                                topPadding: 2
                                bottomPadding: 2
                                selectByMouse: true
                                hoverEnabled: true
                                background: Rectangle {
                                    radius: 4
                                    color: separatorField.activeFocus ? Theme.field
                                        : separatorField.hovered ? Theme.hover : "transparent"
                                    border.color: separatorField.activeFocus ? Theme.accent
                                        : separatorField.hovered ? Theme.border : "transparent"
                                }
                                onActiveFocusChanged: {
                                    if (activeFocus) {
                                        root.commitPiece();
                                        root.selectedPiece = -1;
                                    }
                                }
                                onEditingFinished: root.commitSeparator(index, text)
                            }
                        }
                    }
                }
                }
            }
        }

        }

        RowLayout {
            Layout.fillWidth: true
            StitchButton {
                objectName: "appearanceButton"
                Layout.fillWidth: true
                text: qsTr("Appearance")
                iconName: root.blockIcon || "palette"
                onClicked: appearancePopup.open()
            }
            StitchButton {
                objectName: "defaultParametersButton"
                Layout.fillWidth: true
                text: qsTr("Inputs")
                iconName: "sliders-horizontal"
                onClicked: {
                    root.commitPiece();
                    defaultsPopup.open();
                }
            }
            StitchButton {
                objectName: "detailsButton"
                Layout.fillWidth: true
                text: root.detailsTitle
                iconName: root.detailsIcon
                onClicked: detailsPopup.open()
            }
        }

        GridLayout {
            Layout.fillWidth: true
            columns: root.width < 560 ? 3 : root.allowBranches ? 6 : 5
            columnSpacing: 8
            Repeater {
                model: [
                    {
                        title: qsTr("Component"),
                        subtitle: qsTr("optional group"),
                        sample: "+",
                        kind: "Component",
                        valueType: "Bool"
                    },
                    {
                        title: qsTr("Input"),
                        subtitle: qsTr("text or number"),
                        sample: "123",
                        kind: "Input",
                        valueType: "Any"
                    },
                    {
                        title: qsTr("Boolean"),
                        subtitle: qsTr("true or false"),
                        sample: "◇",
                        kind: "Input",
                        valueType: "Bool"
                    },
                    {
                        title: qsTr("Branch"),
                        subtitle: qsTr("nested blocks"),
                        sample: "⌞",
                        kind: "Branch",
                        valueType: "Any"
                    },
                    {
                        title: qsTr("Button"),
                        subtitle: qsTr("settings screen"),
                        sample: "⚙",
                        kind: "Button",
                        valueType: "Any"
                    },
                    {
                        title: qsTr("Label"),
                        subtitle: "",
                        sample: "Abc",
                        kind: "Label",
                        valueType: "Any"
                    }
                ]
                delegate: Button {
                    required property var modelData
                    visible: modelData.kind !== "Branch" || root.allowBranches
                    Layout.fillWidth: true
                    implicitHeight: 52
                    onClicked: modelData.kind === "Component" ? root.addComponent() : root.addPiece(modelData.kind, modelData.valueType)
                    HoverHandler {
                        cursorShape: Qt.PointingHandCursor
                    }
                    contentItem: Row {
                        spacing: 8
                        Item {
                            width: 22
                            height: 30
                            anchors.verticalCenter: parent.verticalCenter
                            Text {
                                anchors.centerIn: parent
                                visible: modelData.valueType !== "Bool" || modelData.kind === "Component"
                                text: modelData.sample
                                color: modelData.kind === "Input" || modelData.kind === "Branch" ? Theme.accent : Theme.text
                                font.pixelSize: modelData.kind === "Branch" ? 26 : 13
                                font.weight: Font.DemiBold
                            }
                            Canvas {
                                anchors.centerIn: parent; width: 30; height: 20
                                visible: modelData.valueType === "Bool" && modelData.kind !== "Component"; antialiasing: true
                                onPaint: {
                                    const c = getContext("2d"); c.reset(); c.beginPath();
                                    const n = Math.min(height * .32, width / 2);
                                    c.moveTo(n, .5); c.lineTo(width - n, .5); c.lineTo(width - .5, height / 2);
                                    c.lineTo(width - n, height - .5); c.lineTo(n, height - .5); c.lineTo(.5, height / 2); c.closePath();
                                    c.fillStyle = Theme.field; c.fill(); c.strokeStyle = Theme.border; c.lineWidth = 1; c.stroke();
                                }
                            }
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            Text {
                                text: modelData.title
                                color: Theme.text
                                font.pixelSize: 12
                                font.weight: Font.DemiBold
                            }
                            Text {
                                visible: modelData.subtitle.length > 0
                                text: modelData.subtitle
                                color: Theme.textDim
                                font.pixelSize: 10
                            }
                        }
                    }
                    background: Rectangle {
                        radius: Theme.radius
                        color: parent.hovered ? Theme.hover : Theme.panelRaised
                        border.color: parent.hovered ? Theme.accent : Theme.border
                        Behavior on color { enabled: Motion.enabled; ColorAnimation { duration: Motion.quick } }
                        Behavior on border.color { enabled: Motion.enabled; ColorAnimation { duration: Motion.quick } }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            StitchButton {
                Layout.fillWidth: true
                visible: root.shapes.indexOf(root.returnsValue ? "ReturnsValue" : "Normal") >= 0
                text: root.returnsValue ? qsTr("Return Text or Number") : qsTr("Normal block")
                primary: root.blockShape === (root.returnsValue ? "ReturnsValue" : "Normal")
                onClicked: root.blockShape = root.returnsValue ? "ReturnsValue" : "Normal"
            }
            StitchButton {
                Layout.fillWidth: true
                visible: root.shapes.indexOf(root.returnsValue ? "ReturnsBool" : "Ending") >= 0
                text: root.returnsValue ? qsTr("Return a Boolean") : qsTr("Ending block")
                primary: root.blockShape === (root.returnsValue ? "ReturnsBool" : "Ending")
                onClicked: root.blockShape = root.returnsValue ? "ReturnsBool" : "Ending"
            }
        }

        StitchCheckBox {
            objectName: "returnsValueToggle"
            visible: root.offersCommands && root.offersReporters
            text: qsTr("Returns a value")
            checked: root.returnsValue
            onToggled: root.blockShape = checked ? root.firstShape(["ReturnsValue", "ReturnsBool"]) : root.firstShape(["Normal", "Ending"])
        }
        Text {
            visible: root.validationError.length > 0
            text: root.validationError
            color: Theme.danger
            font.pixelSize: 12
        }
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Theme.borderSoft
        }
        RowLayout {
            Layout.fillWidth: true
            Item {
                Layout.fillWidth: true
            }
            StitchButton {
                objectName: "cancelButton"
                text: qsTr("Cancel")
                onClicked: root.cancelled()
            }
            StitchButton {
                objectName: "submitButton"
                text: root.submitText
                primary: true
                onClicked: root.submit()
            }
        }
    }
}
