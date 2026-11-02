import QtQuick
import QtQuick.Controls
import QtTest
import com.blockworked.Blockstitch 1.0

Item {
    id: scene
    width: 1100; height: 700

    readonly property var spec: ({ icon: "cloud", head: [
        { kind: "label", text: "send" },
        { kind: "value", key: "url", field: "Url" },
        { kind: "value", key: "body", field: "Body", box: true, boxLabel: "body" }] })
    readonly property var plainSpec: ({ icon: "cloud", head: [{ kind: "label", text: "say" }, { kind: "value", key: "text", field: "Say" }] })

    InstructionBlock {
        id: block
        x: 20; y: 20
        strandId: "s1"; path: [{ index: 0 }]
    }
    InstructionBlock {
        id: plain
        x: 20; y: 300
        strandId: "s2"; path: [{ index: 0 }]
    }
    BlockDefinitionEditor {
        id: editor
        x: 0; y: 0; width: 800; height: 600
        visible: false
        z: 10
    }
    SignalSpy { id: blockEdits; target: block; signalName: "valueEdited" }
    SignalSpy { id: plainEdits; target: plain; signalName: "valueEdited" }

    TestCase {
        name: "MultilineText"
        when: windowShown

        function initTestCase() { BlockRegistry.registerRows({ TestSend: scene.spec, TestSay: scene.plainSpec }); }
        function init() {
            block.instruction = { id: "b1", type: "TestSend", url: { kind: "Text", value: "https://example.com" }, body: { kind: "Text", value: "one\ntwo\nthree" } };
            plain.instruction = { id: "p1", type: "TestSay", text: { kind: "Text", value: "hello" } };
            blockEdits.clear(); plainEdits.clear();
        }
        function named(item, name) {
            if (!item) return null;
            if (item.objectName === name) return item;
            for (const child of item.children || []) {
                const found = named(child, name);
                if (found) return found;
            }
            return null;
        }
        function openDialog() {
            const area = named(Overlay.overlay, "textEditorArea");
            return area && area.visible ? area : null;
        }

        function test_boxGetsALineUnderTheRow() {
            const boxes = named(block, "blockBoxes");
            verify(boxes && boxes.visible);
            const box = named(boxes, "multilineBox");
            verify(box && box.visible);
            tryVerify(() => block.implicitHeight > 58 + box.height, 2000, "the block grows by its box");
            verify(box.mapToItem(block, 0, 0).y >= 40, "the box sits under the row");
            compare(named(boxes, "multilineBoxArea").text, "one\ntwo\nthree");
            compare(plain.implicitHeight, 58, "a row without a box keeps its height");
        }

        function test_typingInTheBoxEditsTheSlot() {
            const area = named(named(block, "blockBoxes"), "multilineBoxArea");
            mouseClick(area, 5, 5);
            verify(area.activeFocus);
            area.cursorPosition = area.length;
            const box = named(block, "multilineBox");
            const before = box.implicitHeight;
            keyClick(Qt.Key_Return);
            keyClick(Qt.Key_F);
            verify(area.activeFocus, "Enter adds a line in a box");
            verify(box.implicitHeight > before, "the box grows as lines are typed");
            keyClick(Qt.Key_Backspace);
            keyClick(Qt.Key_Backspace);
            compare(box.implicitHeight, before, "and shrinks as they are taken away");
            keyClick(Qt.Key_Return);
            keyClick(Qt.Key_F);
            area.focus = false;
            tryCompare(blockEdits, "count", 1);
            compare(blockEdits.signalArguments[0][0].field_id, "Body");
            compare(blockEdits.signalArguments[0][1], "one\ntwo\nthree\nf");
        }

        function test_textWithLinesShowsItsFirstLineAndACount() {
            plain.instruction = { id: "p1", type: "TestSay", text: { kind: "Text", value: "first\nsecond\nthird" } };
            const summary = named(plain, "multilineSummary");
            verify(summary && summary.visible);
            const badge = named(summary, "multilineBadge");
            verify(badge.children[0].text.indexOf("2") >= 0);
            mouseClick(summary);
            tryVerify(() => openDialog());
            const area = openDialog();
            tryCompare(area, "text", "first\nsecond\nthird");
            area.text = "first\nchanged";
            keyClick(Qt.Key_Return, Qt.ControlModifier);
            tryCompare(plainEdits, "count", 1);
            compare(plainEdits.signalArguments[0][1], "first\nchanged");
            tryVerify(() => !openDialog());
        }

        function test_shiftEnterOpensTheEditorWithANewLine() {
            const field = named(plain, "expandTextButton").parent;
            mouseClick(field, 5, 5);
            verify(field.activeFocus);
            field.cursorPosition = field.length;
            keyClick(Qt.Key_Return, Qt.ShiftModifier);
            tryVerify(() => openDialog());
            const area = openDialog();
            tryCompare(area, "text", "hello\n");
            keyClick(Qt.Key_W);
            keyClick(Qt.Key_Return, Qt.ControlModifier);
            tryVerify(() => plainEdits.count > 0 && plainEdits.signalArguments[plainEdits.count - 1][1] === "hello\nw");
            tryVerify(() => !openDialog());
        }

        function test_cancelKeepsTheText() {
            const field = named(plain, "expandTextButton").parent;
            mouseClick(field, 5, 5);
            const expand = named(plain, "expandTextButton");
            verify(expand.visible);
            mouseClick(expand);
            tryVerify(() => openDialog());
            const area = openDialog();
            tryCompare(area, "activeFocus", true);
            area.text = "something else";
            keyClick(Qt.Key_Escape);
            tryVerify(() => !openDialog());
            verify(plainEdits.count === 0 || plainEdits.signalArguments[plainEdits.count - 1][1] !== "something else");
        }

        function test_customBlockInputsCanBeBoxes() {
            const def = { id: "d1", pieces: [
                { kind: "Label", id: "l", text: "post" },
                { kind: "Input", id: "a", name: "to" },
                { kind: "Input", id: "b", name: "message", multiline: true },
                { kind: "Input", id: "c", name: "loud", value_type: "Bool", multiline: true }] };
            const row = BlockRegistry.customCallRow(def);
            verify(row);
            const values = row.head.filter(p => p.kind === "value");
            compare(values.length, 3);
            verify(!values[0].box);
            verify(values[1].box);
            compare(values[1].boxLabel, "message");
            verify(!values[2].box, "a boolean input stays in the row");
            compare(BlockRegistry.customCallRow({ id: "d2", pieces: [{ kind: "Input", id: "a", name: "x" }] }), null);
        }

        function test_definitionEditorKeepsTheMultilineOption() {
            editor.load({ id: "d1", shape: "Normal", color: "#4C97FF", pieces: [
                { kind: "Label", id: "l", text: "post" },
                { kind: "Input", id: "a", name: "message", value_type: "Any", multiline: true },
                { kind: "Input", id: "b", name: "to", value_type: "Any" }] });
            let pieces = editor.draft().pieces;
            compare(pieces[1].multiline, true);
            verify(!("multiline" in pieces[2]));
            editor.visible = true;
            mouseClick(named(editor, "defaultParametersButton"));
            tryVerify(() => named(Overlay.overlay, "defaultParameterRow2"));
            const row = named(Overlay.overlay, "defaultParameterRow2");
            const box = named(row, "multilineInput");
            verify(box);
            box.toggle(); box.toggled();
            pieces = editor.draft().pieces;
            compare(pieces[2].multiline, true);
            keyClick(Qt.Key_Escape);
            editor.visible = false;
        }
    }
}
