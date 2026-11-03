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
            wait(20);
            canvas.strands = [strand("near", 0, 0), strand("far", 0, 6000)];
            compare(block("far-a"), null);
            verify(canvas.revealInstruction("far-a"));
            verify(!!block("far-a"));
            canvas.strands = [];
            wait(20);
        }

        function test_aLongStrandBuildsItsFarBlocksLater() {
            canvas.strands = [];
            wait(20);
            const long = { id: "long", x: 0, y: 0, instructions: [] };
            for (let i = 0; i < 200; ++i) long.instructions.push({ id: "l" + i, type: "Wait", ms: i });
            canvas.strands = [long];
            verify(!!block("l0"));
            compare(block("l199"), null);
            // Placeholders keep the strand about as tall as its blocks.
            verify(canvas.needBottom >= 199 * 40);
            verify(canvas.pendingBuilds() > 0);
            tryVerify(() => canvas.pendingBuilds() === 0);
            verify(!!block("l199"));
            // A block added once the strand is there builds at once.
            const more = JSON.parse(JSON.stringify(long));
            more.instructions.push({ id: "l200", type: "Wait", ms: 1 });
            canvas.strands = [more];
            verify(!!block("l200"));
            canvas.strands = [];
            wait(20);
        }

        function test_revealBuildsAFarBlockOfALongStrand() {
            canvas.strands = [];
            wait(20);
            const long = { id: "long", x: 0, y: 0, instructions: [] };
            for (let i = 0; i < 200; ++i) long.instructions.push({ id: "r" + i, type: "Wait", ms: i });
            canvas.strands = [long];
            compare(block("r150"), null);
            verify(canvas.revealInstruction("r150"));
            verify(!!block("r150"));
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
