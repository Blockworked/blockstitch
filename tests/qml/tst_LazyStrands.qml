import QtQuick
import QtTest
import com.blockworked.Blockstitch 1.0

Item {
    width: 900; height: 700
    BlockCanvas { id: canvas; anchors.fill: parent }
    TestCase {
        name: "LazyStrands"
        when: windowShown
        function all(item) {
            let result = [item];
            for (const child of item.children || []) result = result.concat(all(child));
            return result;
        }
        function block(id) { return all(canvas).find(o => o.instruction && o.instruction.id === id && o.paletteMode === false) || null; }
        function strand(id, x, y) { return { id: id, x: x, y: y, instructions: [{ id: id + "-a", type: "Wait", ms: 1 }, { id: id + "-b", type: "Wait", ms: 2 }] }; }

        function test_farStrandsBuildAfterTheView() {
            canvas.lazyStrands = true;
            canvas.strands = [strand("near", 0, 0), strand("far", 0, 6000)];
            // Blocks in view exist at once; one far away waits a pass.
            verify(!!block("near-a"));
            compare(block("far-a"), null);
            compare(canvas.pendingStrands(), 1);
            tryVerify(() => canvas.pendingBuilds() === 0);
            verify(!!block("far-b"));
            canvas.strands = [];
            wait(20);
        }

        function test_revealBuildsTheStrandItNeeds() {
            canvas.strands = [];
            // Blocks of an earlier test can outlive their strand by a pass.
            tryVerify(() => !block("far-a"));
            canvas.strands = [strand("near", 0, 0), strand("far", 0, 6000)];
            verify(canvas.revealInstruction("far-a"));
            verify(!!block("far-a"));
            canvas.strands = [];
            wait(20);
        }

        function test_aLongStrandBuildsItsFarBlocksLater() {
            canvas.strands = [];
            wait(20);
            const longStrand = { id: "longStrand", x: 0, y: 0, instructions: [] };
            for (let i = 0; i < 200; ++i) longStrand.instructions.push({ id: "l" + i, type: "Wait", ms: i });
            canvas.strands = [longStrand];
            verify(!!block("l0"));
            compare(block("l199"), null);
            // Placeholders keep the strand about as tall as its blocks.
            verify(canvas.needBottom >= 199 * 40);
            verify(canvas.pendingBuilds() > 0);
            tryVerify(() => canvas.pendingBuilds() === 0);
            verify(!!block("l199"));
            // A block added once the strand is there builds at once.
            const more = JSON.parse(JSON.stringify(longStrand));
            more.instructions.push({ id: "l200", type: "Wait", ms: 1 });
            canvas.strands = [more];
            verify(!!block("l200"));
            canvas.strands = [];
            wait(20);
        }

        function test_revealBuildsAFarBlockOfALongStrand() {
            canvas.strands = [];
            wait(20);
            const longStrand = { id: "longStrand", x: 0, y: 0, instructions: [] };
            for (let i = 0; i < 200; ++i) longStrand.instructions.push({ id: "r" + i, type: "Wait", ms: i });
            canvas.strands = [longStrand];
            compare(block("r150"), null);
            verify(canvas.revealInstruction("r150"));
            verify(!!block("r150"));
            canvas.strands = [];
            wait(20);
        }

        function test_aLongTailAttachedBuildsItsFarBlocksLater() {
            canvas.strands = [];
            wait(20);
            const head = { id: "head", x: 0, y: 0, instructions: [] };
            for (let i = 0; i < 3; ++i) head.instructions.push({ id: "h" + i, type: "Wait", ms: i });
            const tail = { id: "tail", x: 400, y: 0, instructions: [] };
            for (let i = 0; i < 200; ++i) tail.instructions.push({ id: "t" + i, type: "Wait", ms: i });
            canvas.strands = [head, tail];
            tryVerify(() => canvas.pendingBuilds() === 0);
            // The tail joins the head: blocks near the view come at once,
            // the rest after, and every block keeps its place.
            const joined = { id: "head", x: 0, y: 0, instructions: head.instructions.concat(tail.instructions) };
            canvas.strands = [joined];
            verify(!!block("h2"));
            verify(!!block("t0"));
            compare(block("t199"), null);
            tryVerify(() => canvas.pendingBuilds() === 0);
            verify(block("t199").mapToItem(canvas, 0, 0).y > block("t198").mapToItem(canvas, 0, 0).y);
            canvas.strands = [];
            wait(20);
        }

        function test_equalIdListsKeepTheirLookups() {
            const state = canvas.canvasState;
            canvas.runningIds = ["a", "b"];
            const running = state.runningSet;
            verify(running.a && running.b);
            canvas.runningIds = ["b", "a"];
            verify(state.runningSet === running);
            canvas.runningIds = ["a"];
            verify(state.runningSet !== running);
            verify(!state.runningSet.b);
            canvas.blockMarks = { a: "oops" };
            const marks = state.marks;
            canvas.blockMarks = { a: "oops" };
            verify(state.marks === marks);
            canvas.runningIds = [];
            canvas.blockMarks = {};
        }

        function test_eachCanvasKeepsItsOwnMarks() {
            const other = Qt.createQmlObject("import com.blockworked.Blockstitch 1.0; BlockCanvas {}", canvas.parent);
            canvas.runningIds = ["a"];
            verify(canvas.canvasState.runningSet.a);
            verify(!other.canvasState.runningSet.a);
            canvas.runningIds = [];
            other.destroy();
        }

        function test_aHoveredBlockStacksOverTheNext() {
            canvas.strands = [];
            wait(20);
            canvas.strands = [strand("pair", 40, 40)];
            const a = block("pair-a"), b = block("pair-b");
            mouseMove(a, 20, 10);
            // Its outline must draw over the block below it.
            tryVerify(() => a.hovered);
            verify(a.parent.z > b.parent.z);
            mouseMove(canvas, canvas.width - 5, canvas.height - 5);
            canvas.strands = [];
            wait(20);
        }

        function test_aHoveredNestedBlockStacksOverTheNext() {
            canvas.strands = [];
            wait(20);
            canvas.strands = [{ id: "loop", x: 40, y: 40, instructions: [{ id: "loop-w", type: "While", body: [
                { id: "in-a", type: "Wait", ms: 1 }, { id: "in-b", type: "Wait", ms: 2 }] }] }];
            const a = block("in-a"), b = block("in-b");
            verify(!!a && !!b);
            mouseMove(a, 20, 10);
            tryVerify(() => a.hovered);
            verify(a.parent.z > b.parent.z);
            mouseMove(canvas, canvas.width - 5, canvas.height - 5);
            canvas.strands = [];
            wait(20);
        }

        function test_aPlaceholderHoldsTheStrandsSize() {
            canvas.strands = [];
            wait(20);
            const many = { id: "tall", x: 0, y: 6000, instructions: [] };
            for (let i = 0; i < 10; ++i) many.instructions.push({ id: "t" + i, type: "Wait", ms: i });
            canvas.strands = [strand("near", 0, 0), many];
            // Sized like ten blocks, so the world already reaches past it.
            verify(canvas.needBottom >= 6000 + 400);
            canvas.strands = [];
            wait(20);
        }
    }
}
