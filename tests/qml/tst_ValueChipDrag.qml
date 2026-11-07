import QtQuick
import QtTest
import com.blockworked.Blockstitch 1.0

Item {
    width: 800; height: 400

    ValueChip {
        id: chip
        canvasState: CanvasState { id: chipState }
        x: 30; y: 30
        width: implicitWidth; height: implicitHeight
        location: ({ kind: "Field", strand_id: "s1", index: [{ index: 0 }], field_id: "TextValue", path: [] })
    }
    SignalSpy { id: began; target: chip; signalName: "valueDragBegan" }
    SignalSpy { id: moved; target: chip; signalName: "valueDragMoved" }
    SignalSpy { id: ended; target: chip; signalName: "valueDragEnded" }

    TestCase {
        name: "ValueChipDrag"
        when: windowShown

        function init() {
            chipState.settlingValueKey = "";
            chip.dropHighlighted = false;
            chip.location = { kind: "Field", strand_id: "s1", index: [{ index: 0 }], field_id: "TextValue", path: [] };
            chip.valueData = { kind: "Op", op: "Join", args: [{ kind: "Text", value: "long first input" }, { kind: "Text", value: "long second input" }], saved: { kind: "Text", value: "hello" } };
            began.clear(); moved.clear(); ended.clear();
        }
        function cleanup() {
            mouseRelease(chip, 5, 5);
            chipState.settlingValueKey = "";
            chip.dropHighlighted = false;
        }
        function startDrag() {
            waitForRendering(chip);
            const w = chip.width, h = chip.height;
            mousePress(chip, 5, 5);
            mouseMove(chip, 25, 60, 20);
            tryCompare(chip, "draggedOut", true);
            compare(began.count, 1);
            compare(began.signalArguments[0][6], w);
            compare(began.signalArguments[0][7], h);
        }
        function restored() { return findChild(chip, "restoredValue"); }

        function test_originalSlotShowsDropOutline_data() {
            return [
                { tag: "saved text", saved: { kind: "Text", value: "hello" }, nested: false },
                { tag: "saved boolean", saved: { kind: "Bool" }, nested: false },
                { tag: "empty field", saved: null, nested: false },
                { tag: "nested slot", saved: null, nested: true }
            ];
        }
        function test_originalSlotShowsDropOutline(data) {
            if (data.nested) chip.location = { kind: "Floating", floating_id: "f1", path: [0] };
            chip.valueData = { kind: "Op", op: "Join", args: [], saved: data.saved };
            startDrag();
            waitForRendering(chip);
            const plain = grabImage(chip);
            // Returning to the source selects the same chip while it is vacated.
            chip.dropHighlighted = true;
            waitForRendering(chip);
            const highlighted = grabImage(chip);
            let changed = 0;
            for (let x = 0; x < plain.width; ++x)
                for (let y = 0; y < plain.height; ++y)
                    if (plain.pixel(x, y) !== highlighted.pixel(x, y)) ++changed;
            verify(changed > 20, "The vacated slot must paint its drop outline");
            if (restored().item) compare(restored().item.dropHighlighted, true);
            chip.dropHighlighted = false;
            waitForRendering(chip);
            verify(grabImage(chip).equals(plain), "Leaving the slot must clear its outline");
        }

        function test_savedTextAppearsBeforeReleaseAndSlotShrinks() {
            waitForRendering(chip);
            const w = chip.width;
            startDrag();
            verify(restored().item !== null);
            compare(restored().item.valueData, { kind: "Text", value: "hello" });
            verify(restored().item.visible);
            verify(chip.width < w);
            compare(chip.valueData.kind, "Op");
            mouseMove(chip, 180, 100, 20);
            verify(moved.count > 1);
            mouseRelease(chip, 180, 100);
            compare(ended.count, 1);
            compare(chip.draggedOut, false);
            compare(chip.width, w);
        }
        function test_savedOperatorIsRenderedAsAChip() {
            chip.valueData = { kind: "Call", block_id: "reporter", args: [], saved: { kind: "Op", op: "True", args: [], saved: { kind: "Bool" } } };
            startDrag();
            compare(restored().item.valueData.op, "True");
            verify(restored().item.booleanShape);
        }
        function test_nestedSlotRestoresSavedNumber() {
            chip.location = { kind: "Floating", floating_id: "f1", path: [0] };
            chip.valueData = { kind: "Op", op: "True", args: [], saved: { kind: "Number", value: 42 } };
            startDrag();
            compare(restored().item.valueData, { kind: "Number", value: 42 });
        }
        function test_nestedVariableLeavesBlankNumber() {
            chip.location = { kind: "Floating", floating_id: "f1", path: [0] };
            chip.valueData = { kind: "Var", name: "a rather long variable name" };
            waitForRendering(chip);
            const w = chip.width;
            startDrag();
            compare(restored().item.valueData, { kind: "Number", value: 0 });
            verify(chip.width < w);
        }
        function test_fieldVariableShrinksToBlank() {
            chip.valueData = { kind: "Var", name: "a rather long variable name" };
            waitForRendering(chip);
            const w = chip.width;
            startDrag();
            compare(restored().item, null);
            compare(chip.width, 36);
            compare(chip.height, 27);
            verify(chip.width < w);
            mouseRelease(chip, 25, 60);
            compare(chip.width, w);
        }
        function test_floatingRootLeavesNoRestoredValue() {
            chip.location = { kind: "Floating", floating_id: "f1", path: [] };
            startDrag();
            compare(restored().item, null);
        }
        function test_settlingKeepsSavedValueVisible() {
            chipState.settlingValueKey = BlockRegistry.locationKey(chip.location);
            tryCompare(chip, "draggedOut", true);
            compare(restored().item.valueData.value, "hello");
            chipState.settlingValueKey = "";
            chip.dropHighlighted = false;
            compare(chip.draggedOut, false);
            compare(restored().item, null);
        }
    }
}
