import QtQuick
import QtQuick.Controls
import QtTest
import com.blockworked.Blockstitch 1.0

Item {
    id: scene
    width: 1000; height: 700
    property var edited: null
    readonly property var definition: ({id: "custom", shape: "Normal", pieces: [
        {kind: "Label", id: "label", text: "configure"},
        {kind: "Input", id: "mode", name: "mode", ui: {choices: [{label: "Fast", value: "fast"}, {label: "Careful", value: "careful"}]}},
        {kind: "Input", id: "count", name: "count", default_value: {kind: "Number", value: 5}, ui: {screen_only: true}},
        {kind: "Input", id: "enabled", name: "enabled", value_type: "Bool"},
        {kind: "Button", id: "settings", text: "Options", title: "Configure", inputs: ["mode", "count", "enabled"]}
    ]})
    InstructionBlock {
        id: block
        x: 20; y: 20
        strandId: "strand"; path: [{index: 0}]
        canvasState: CanvasState { documentId: "macro" }
        blockDefinitions: [scene.definition]
        onInstructionEdited: (sid, path, instruction) => { scene.edited = instruction; block.instruction = instruction; }
    }
    ValueChip {
        id: reporter
        x: 20; y: 120
        blockDefinitions: [Object.assign({}, scene.definition, {shape: "ReturnsValue"})]
        location: ({strand_id: "strand", index: [{index: 0}], field: "WaitDuration", path: []})
    }
    // A row's pieces reach a dropdown as modelData, where arrays are list wrappers.
    Repeater {
        id: pieceModel
        model: [{kind: "dropdown", key: "scope", options: [{value: "All", label: "all"}, {value: "One", label: "one"}]}]
        Item { readonly property var piece: modelData }
    }
    BlockDefinitionEditor { id: editor; width: 800; height: 500; y: 200; visible: false }
    TestCase {
        name: "BlockUi"
        when: windowShown
        function fresh() { return {id: "call", type: "CallBlock", block_id: "custom", args: BlockRegistry.freshCallArgs(scene.definition)}; }
        function dialog() { return findChild(block, "blockSettingsDialog") || findChild(reporter, "blockSettingsDialog"); }
        function init() {
            scene.edited = null;
            block.locked = false;
            block.canvasState.documentId = "macro";
            block.instruction = fresh();
            reporter.valueData = {kind: "Call", block_id: "custom", args: BlockRegistry.freshCallArgs(scene.definition), saved: {kind: "Number", value: 99}};
            BlockRegistry.valueReplacementHandler = (location, value) => { scene.edited = value; reporter.valueData = value; };
        }
        function cleanup() { editor.closePopups(); editor.visible = false; if (dialog()) { dialog().reject(); wait(250); } BlockRegistry.valueReplacementHandler = null; }
        function test_hiddenInputsKeepTheirArgumentPositions() {
            const spec = BlockRegistry.customCallRow(scene.definition);
            compare(spec, BlockRegistry.customCallRow(scene.definition));
            compare(spec.head.filter(p => p.kind === "value").map(p => p.index), [0, 2]);
            compare(spec.head.find(p => p.kind === "button").screen, "settings");
            compare(block.instruction.args[0], {kind: "Text", value: "fast"});
            compare(spec.head[1].options[1].label, "Careful");
            compare(block.callLabel(), "configure (mode) (count) (enabled) Options");
            compare(BlockRegistry.definitionLabel(scene.definition), block.callLabel());
        }
        function descendants(item) {
            let out = [item];
            for (const child of item.children || []) out = out.concat(descendants(child));
            return out;
        }
        function test_emptyChoicesKeepAPlainTextInput() {
            const definition = JSON.parse(JSON.stringify(scene.definition));
            definition.pieces[1].ui.choices = [];
            const row = BlockRegistry.customCallRow(definition);
            compare(row.head[1].options, null);
        }
        function test_authoringPopupShowsMenuFields() {
            editor.load(scene.definition);
            editor.visible = true;
            const popup = findChild(editor, "defaultParametersPopup");
            popup.open();
            tryCompare(popup, "opened", true);
            const choices = descendants(popup.contentItem).find(item => item.objectName === "inputChoices" && item.visible);
            verify(choices);
            compare(choices.text, "Fast | fast\nCareful | careful");
            choices.forceActiveFocus();
            choices.text = "Quick | fast\nSlow | slow\n";
            compare(editor.resultPieces()[1].ui.choices.length, 2);
            compare(choices.text, "Quick | fast\nSlow | slow\n");
            const title = descendants(popup.contentItem).find(item => item.objectName === "settingsScreenTitle" && item.visible);
            verify(title);
            compare(title.text, "Configure");
            popup.close();
            wait(250);
            editor.visible = false;
        }
        function test_screenDraftPreservesAndEditsReporterInputs() {
            let instruction = fresh();
            instruction.args[1] = {kind: "Op", op: "Add", args: [{kind: "Number", value: 1}, {kind: "Number", value: 2}], saved: {kind: "Number", value: 0}};
            block.instruction = instruction;
            block.openCustomScreen("settings");
            tryVerify(() => !!dialog());
            const screen = dialog();
            screen.setLeaf("count", [1], {kind: "Number", value: 8});
            compare(block.instruction.args[1].args[1].value, 2);
            screen.applyRequested(screen.changes);
            compare(scene.edited.args[1].args[1].value, 8);
            compare(scene.edited.args[1].args[0].value, 1);
        }
        function test_unchangedFormDoesNotCreateAnEdit() {
            block.openCustomScreen("settings");
            tryVerify(() => !!dialog());
            dialog().setValue("count", {kind: "Number", value: 5});
            compare(Object.keys(dialog().changes).length, 0);
            dialog().applyRequested(dialog().changes);
            compare(scene.edited, null);
        }
        function test_statementButtonAppliesOneEditAndPreservesOtherArguments() {
            const button = findChild(block, "blockScreenButton_settings");
            verify(button);
            mouseClick(button);
            tryVerify(() => !!dialog());
            const screen = dialog();
            tryCompare(screen, "opened", true);
            compare(screen.title, "Configure");
            compare(screen.fields.map(f => f.label), ["mode", "count", "enabled"]);
            screen.setValue("mode", {kind: "Text", value: "careful"});
            compare(scene.edited, null);
            mouseClick(findChild(screen, "applyBlockSettings"));
            tryVerify(() => scene.edited !== null);
            compare(scene.edited.args[0].value, "careful");
            compare(scene.edited.args[1].value, 5);
            compare(scene.edited.id, "call");
        }
        function test_cancelDoesNotEdit() {
            block.openCustomScreen("settings");
            tryVerify(() => !!dialog());
            dialog().setValue("count", {kind: "Number", value: 42});
            dialog().reject();
            compare(scene.edited, null);
            compare(block.instruction.args[1].value, 5);
        }
        function test_reporterButtonKeepsItsSavedValue() {
            const button = findChild(reporter, "customSettingsButton");
            verify(button);
            mouseClick(button);
            tryVerify(() => !!dialog());
            dialog().setValue("enabled", BlockRegistry.componentValue(true));
            dialog().applyRequested(dialog().changes);
            compare(scene.edited.args[2].op, "True");
            compare(scene.edited.saved.value, 99);
        }
        function test_staleInputIsRefusedButUnrelatedChangesSurvive() {
            block.openCustomScreen("settings");
            tryVerify(() => !!dialog());
            const screen = dialog();
            screen.setValue("count", {kind: "Number", value: 42});
            let updated = fresh(); updated.args[1] = {kind: "Number", value: 7};
            block.instruction = updated;
            screen.applyRequested(screen.changes);
            verify(screen.errorText.length > 0);
            compare(scene.edited, null);
            updated = fresh(); updated.args[0] = {kind: "Text", value: "careful"};
            block.instruction = updated;
            screen.applyRequested(screen.changes);
            compare(scene.edited.args[0].value, "careful");
            compare(scene.edited.args[1].value, 42);
        }
        function test_authoringPreservesReferencesAndChoices() {
            editor.load(scene.definition);
            editor.pieceModel.setProperty(1, "pieceName", "renamed mode");
            editor.setChoices(1, "Quick | fast\nCareful | careful");
            compare(editor.validate(), "");
            const draft = editor.draft();
            compare(draft.pieces[1].ui.choices[0], {label: "Quick", value: "fast"});
            compare(draft.pieces[4].inputs, ["mode", "count", "enabled"]);
            compare(draft.pieces[2].ui.screen_only, true);
            editor.updateButton(4, {inputs: ["mode"]});
            verify(editor.validate().length > 0);
        }
        function test_invalidNumberCannotBeAppliedAfterAnotherFieldChanges() {
            block.openCustomScreen("settings");
            tryVerify(() => !!dialog());
            const screen = dialog();
            tryCompare(screen, "opened", true);
            const input = descendants(screen.contentItem).find(item => item.objectName === "blockSettingsText" && item.visible && item.parent.modelData.id === "count");
            verify(input);
            input.forceActiveFocus();
            input.text = "1e";
            input.textEdited();
            verify(!findChild(screen, "applyBlockSettings").enabled);
            screen.setValue("mode", {kind: "Text", value: "careful"});
            verify(!findChild(screen, "applyBlockSettings").enabled);
            input.text = "12";
            input.textEdited();
            verify(findChild(screen, "applyBlockSettings").enabled);
            screen.applyRequested(screen.changes);
            compare(scene.edited.args[1].value, 12);
        }
        function test_documentSwitchAndLockRefuseAnOpenDraft() {
            block.openCustomScreen("settings");
            tryVerify(() => !!dialog());
            const screen = dialog();
            screen.setValue("count", {kind: "Number", value: 42});
            block.canvasState.documentId = "other macro";
            screen.applyRequested(screen.changes);
            verify(screen.errorText.length > 0);
            compare(scene.edited, null);
            block.canvasState.documentId = "macro";
            block.locked = true;
            screen.applyRequested(screen.changes);
            compare(scene.edited, null);
        }
        function test_registeredScreensAndBuiltInChoicesUseSharedEntryPoints() {
            let request = null;
            verify(BlockUi.open("pickModel", {instruction: {type: "DetectObjectsInWindow"}}, {pickModel: r => request = r}));
            compare(request.instruction.type, "DetectObjectsInWindow");
            verify(!BlockUi.open("missing", {}, {}));
            compare(BlockRegistry.choices(() => [{value: "Left", label: "Left"}], {}), [{value: "Left", label: "Left"}]);
            const fromModel = BlockRegistry.choices(pieceModel.itemAt(0).piece.options, {});
            compare(fromModel.length, 2);
            compare(fromModel[1].value, "One");
            compare(BlockRegistry.choices("not a list", {}), []);
        }
    }
}
