import QtQuick
import QtTest
import com.blockworked.Blockstitch 1.0

Rectangle {
    id: scene
    width: 900; height: 600
    color: Theme.canvas
    BlockCanvas { id: canvas; anchors.fill: parent }

    TestCase {
        name: "BlockHover"
        when: windowShown

        function test_nestedOutline_data() {
            return [
                { tag: "dark-mouth", nested: false, mode: "dark" },
                { tag: "dark-nested", nested: true, mode: "dark" },
                { tag: "light-mouth", nested: false, mode: "light" },
                { tag: "light-nested", nested: true, mode: "light" }
            ];
        }
        function cleanup() { Theme.mode = ""; }
        function test_nestedOutline(data) {
            Theme.mode = data.mode;
            let body = [{ id: "child", type: "Wait", ms: { kind: "Number", value: 100 } }];
            if (data.nested) body = [{ id: "inner", type: "If", body: body }];
            canvas.strands = [{ id: "target", x: 40, y: 40, instructions: [
                { id: "outer", type: "While", body: body }
            ] }];
            wait(50);
            const child = canvas.findBlockItem(canvas, "child");
            mouseMove(child, 8, 25);
            tryCompare(child, "hovered", true);
            waitForRendering(canvas);
            const image = grabImage(scene);
            const pos = child.mapToItem(scene, 0, 0);
            // Check all four sides, including the edges shared with the parent.
            const points = [[0, 25], [80, 0], [child.width - 1, 25], [80, child.height - 8]];
            for (const point of points) {
                const color = image.pixel(Math.round(pos.x + point[0]), Math.round(pos.y + point[1]));
                verify(color.b - color.r > 0.4, "Missing hover outline at " + point + ": " + color);
            }
            mouseMove(scene, 880, 580);
        }
        // A running block's thick outline isn't covered by the block below it.
        function test_runningOutlineOverNext() {
            Theme.mode = "dark";
            canvas.strands = [{ id: "target", x: 40, y: 40, instructions: [
                { id: "first", type: "Wait", ms: { kind: "Number", value: 100 } },
                { id: "second", type: "Wait", ms: { kind: "Number", value: 100 } }
            ] }];
            wait(50);
            canvas.canvasState.runningIds = ["first"];
            const first = canvas.findBlockItem(canvas, "first");
            tryCompare(first, "running", true);
            waitForRendering(canvas);
            const image = grabImage(scene);
            const pos = first.mapToItem(scene, 0, 0);
            const bottom = first.height - first.tabDepth;
            // The stroke's half below the shared edge used to be under the next block.
            for (const dy of [-1, 0]) {
                const color = image.pixel(Math.round(pos.x + first.width - 20), Math.round(pos.y + bottom + dy));
                verify(color.g - color.r > 0.4, "Running outline covered at dy " + dy + ": " + color);
            }
            canvas.canvasState.runningIds = [];
        }
    }
}
