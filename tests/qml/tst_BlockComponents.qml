import QtQuick
import QtTest
import com.blockworked.Blockstitch 1.0

Item {
    id: scene
    width: 900; height: 300
    property var edited: null

    readonly property var pickComponent: ({ key: "pick", label: "which match", icon: "list-ordered",
        fresh: () => ({ mode: "Nth", index: { kind: "Number", value: 1 } }),
        pieces: [{ kind: "label", text: "match" }, { kind: "dropdown", key: "pick", index: "mode",
                   options: [{ value: "Nth", label: "number" }, { value: "NearMouse", label: "nearest mouse" }] }] })
    readonly property var regionComponent: ({ key: "region", label: "search region", fresh: "",
        pieces: [{ kind: "label", text: "in region" }, { kind: "text", key: "region" }] })
    readonly property var spec: ({ icon: "search", head: [{ kind: "label", text: "find" }, { kind: "components" }, { kind: "label", text: "now" }],
        components: [pickComponent, regionComponent] })

    InstructionBlock {
        id: block
        x: 20; y: 20
        strandId: "s1"; path: [{ index: 0 }]
        instruction: ({ id: "f1", type: "TestFind" })
        onInstructionEdited: (sid, p, n) => { scene.edited = n; block.instruction = n; }
    }

    TestCase {
        name: "BlockComponents"
        when: windowShown

        function initTestCase() { BlockRegistry.registerRows({ TestFind: scene.spec }); }
        function init() { scene.edited = null; block.instruction = { id: "f1", type: "TestFind" }; }

        function kinds(pieces) { return pieces.map(p => p.kind === "label" ? p.text : p.kind); }

        function test_plainBlockShowsOnlyTheHeadAndThePlus() {
            compare(kinds(block.headPieces), ["find", "addComponent", "now"]);
            compare(kinds(BlockRegistry.rowPieces(scene.spec, block.instruction, true)), ["find", "now"]);
        }

        function test_addingAComponentFillsItsFreshValue() {
            block.addComponent(scene.pickComponent);
            compare(scene.edited.pick, { mode: "Nth", index: { kind: "Number", value: 1 } });
            compare(kinds(block.headPieces), ["find", "match", "dropdown", "removeComponent", "addComponent", "now"]);
        }

        function test_componentsKeepDeclaredOrderAndThePlusGoesWhenAllAreOn() {
            block.addComponent(scene.regionComponent);
            block.addComponent(scene.pickComponent);
            compare(kinds(block.headPieces), ["find", "match", "dropdown", "removeComponent", "in region", "text", "removeComponent", "now"]);
            compare(BlockRegistry.missingComponents(scene.spec, block.instruction).length, 0);
        }

        function test_removingTakesTheKeyOut() {
            block.addComponent(scene.regionComponent);
            block.removeComponent(scene.regionComponent);
            verify(!("region" in scene.edited));
            compare(kinds(block.headPieces), ["find", "addComponent", "now"]);
        }

        function test_aNamedIndexEditsOneFieldOfTheComponent() {
            block.addComponent(scene.pickComponent);
            block.setPieceField(scene.pickComponent.pieces[1], "NearMouse");
            compare(scene.edited.pick.mode, "NearMouse");
            compare(scene.edited.pick.index, { kind: "Number", value: 1 });
            compare(block.pieceValue(scene.pickComponent.pieces[1]), "NearMouse");
        }

        function test_piecesStayTheSameObjectsAcrossEdits() {
            block.addComponent(scene.pickComponent);
            const before = block.headPieces;
            block.setPieceField(scene.pickComponent.pieces[1], "NearMouse");
            verify(block.headPieces === before);
        }

        function test_aRowWithoutComponentsIsUnchanged() {
            const plain = { head: [{ kind: "label", text: "a" }, { kind: "label", text: "b", when: i => !!i.b }] };
            compare(kinds(BlockRegistry.rowPieces(plain, { b: false }, false)), ["a"]);
            compare(kinds(BlockRegistry.rowPieces(plain, { b: true }, false)), ["a", "b"]);
        }
    }
}
