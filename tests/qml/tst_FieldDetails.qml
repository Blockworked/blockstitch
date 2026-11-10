import QtQuick
import QtTest
import com.blockworked.Blockstitch 1.0

Item {
    width: 1200; height: 900
    BlockCanvas { id: canvas; anchors.fill: parent }
    SignalSpy { id: details; target: canvas; signalName: "detailsRequested" }

    TestCase {
        name: "FieldDetails"
        when: windowShown

        function descendants(item) {
            let result = [item];
            for (const child of item.children || []) result = result.concat(descendants(child));
            return result;
        }
        function init() {
            details.clear();
            canvas.blockDefinitions = [{ id: "custom", shape: "ReturnsBool",
                pieces: [{ kind: "Label", text: "custom condition" }] }];
        }
        function cleanup() {
            for (const item of descendants(canvas)) {
                if (item.menu) {
                    item.menu.close();
                    tryCompare(item.menu, "visible", false);
                }
            }
        }
        function test_fieldMenuForwardsDetails_data() {
            return [
                { tag: "if", type: "If", field: "condition" },
                { tag: "if-else", type: "IfElse", field: "condition" },
                { tag: "while", type: "While", field: "condition" },
                { tag: "repeat", type: "Repeat", field: "count" },
                { tag: "call-argument", type: "CallBlock", field: "args" },
                { tag: "branch-argument", type: "BranchCallBlock", field: "args" },
                { tag: "nested-reporter", type: "If", field: "condition", nested: true }
            ];
        }
        function test_fieldMenuForwardsDetails(data) {
            canvas.blockDefinitions = canvas.blockDefinitions.concat([{ id: "caller", shape: "Stack",
                pieces: [{ kind: "Label", text: "caller" }, { kind: "Input", id: "arg", name: "arg" },
                    { kind: "Branch", id: "body", name: "body" }] }]);
            const value = { kind: "Call", block_id: "custom", args: [] };
            const instruction = { id: "owner", type: data.type, body: [], then_body: [], else_body: [],
                block_id: "caller", branches: [[]] };
            instruction[data.field] = data.field === "args" ? [value]
                : data.nested ? { kind: "Op", op: "Not", args: [value] } : value;
            canvas.strands = [{ id: "strand", x: 40, y: 40, instructions: [instruction] }];
            waitForRendering(canvas);
            wait(50);
            const chip = descendants(canvas).find(o => o.isValueChip && o.visible
                && o.valueData && o.valueData.kind === "Call" && o.valueData.block_id === "custom");
            verify(!!chip);
            mouseClick(chip, 12, chip.height / 2, Qt.RightButton);
            const menuArea = descendants(chip).find(o => o.menu !== undefined && o.menu !== null);
            verify(!!menuArea);
            const menu = menuArea.menu;
            tryCompare(menu, "opened", true);
            compare(menu.itemAt(0).text, "Details");
            mouseClick(menu.itemAt(0));
            compare(details.count, 1);
            compare(details.signalArguments[0][0], "custom");
            menu.close();
            tryCompare(menu, "visible", false);
        }
    }
}
