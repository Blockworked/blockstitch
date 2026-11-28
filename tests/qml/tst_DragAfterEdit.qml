import QtQuick
import QtTest
import com.blockworked.Blockstitch 1.0

// Typing into an operator's field and dragging the operator straight away
// must carry the typed value, not the one the backend last sent.
Item {
    width: 800; height: 400

    ValueChip {
        id: chip
        canvasState: CanvasState {}
        x: 30; y: 30
        width: implicitWidth; height: implicitHeight
        location: ({ kind: "Field", strand_id: "s1", index: [{ index: 0 }], field_id: "Value", path: [] })
    }
    InstructionBlock {
        id: block
        x: 30; y: 200
        strandId: "s2"; path: [{ index: 0 }]
    }
    SignalSpy { id: blockEdits; target: block; signalName: "valueEdited" }
    SignalSpy { id: blockDrag; target: block; signalName: "dragBegan" }
    SignalSpy { id: began; target: chip; signalName: "valueDragBegan" }
    SignalSpy { id: edited; target: chip; signalName: "editRequested" }

    TestCase {
        name: "DragAfterEdit"
        when: windowShown

        function initTestCase() { BlockRegistry.registerRows({ TestSay: { icon: "cloud", head: [{ kind: "label", text: "say" }, { kind: "value", key: "text", field: "Say" }] } }); }
        function init() {
            block.instruction = { id: "b1", type: "TestSay", text: { kind: "Text", value: "hello" } };
            blockEdits.clear(); blockDrag.clear();
            chip.valueData = { kind: "Op", op: "Div", args: [{ kind: "Number", value: 0 }, { kind: "Number", value: 5 }] };
            began.clear(); edited.clear();
        }
        function cleanup() { mouseRelease(chip, 5, 5); }
        function leafInputs(item, out) {
            out = out || [];
            for (const c of item.children) {
                if (c.canExpand !== undefined && c.selectByMouse !== undefined)
                    out.push(c);
                leafInputs(c, out);
            }
            return out;
        }

        function test_dragCarriesTypedText() {
            waitForRendering(chip);
            const input = leafInputs(chip)[0];
            verify(input, "the first field's input");
            input.forceActiveFocus();
            input.selectAll();
            keyClick(Qt.Key_2); keyClick(Qt.Key_0); keyClick(Qt.Key_0);
            compare(input.text, "200");
            compare(edited.count, 0);
            // Grab the operator by its edge, not the field, and drag right away.
            mousePress(chip, 2, chip.height / 2);
            mouseMove(chip, 30, 80, 20);
            compare(began.count, 1);
            // The edit reaches the backend before the move does.
            compare(edited.count, 1);
            compare(edited.signalArguments[0][1], "200");
            compare(edited.signalArguments[0][0].path, [0]);
            const dragged = began.signalArguments[0][1];
            compare(dragged.args[0], { kind: "Number", value: 200 });
            compare(dragged.args[1], { kind: "Number", value: 5 });
            // The backend's own copy is untouched until its state arrives.
            compare(chip.valueData.args[0].value, 0);
        }
        function test_untouchedFieldDragsAsIs() {
            waitForRendering(chip);
            mousePress(chip, 2, chip.height / 2);
            mouseMove(chip, 30, 80, 20);
            compare(began.count, 1);
            compare(edited.count, 0);
            compare(began.signalArguments[0][1].args[0], { kind: "Number", value: 0 });
        }
        function test_blockDragCommitsTypingFirst() {
            waitForRendering(block);
            const input = leafInputs(block)[0];
            verify(input, "the block's field input");
            input.forceActiveFocus();
            input.selectAll();
            keyClick(Qt.Key_H); keyClick(Qt.Key_I);
            compare(blockEdits.count, 0);
            mousePress(block, 8, 8);
            mouseMove(block, 40, 90, 20);
            compare(blockDrag.count, 1);
            compare(blockEdits.count, 1);
            compare(blockEdits.signalArguments[0][1], "hi");
            mouseRelease(block, 40, 90);
        }
    }
}
