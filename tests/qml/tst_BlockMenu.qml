import QtQuick
import QtTest
import com.blockworked.Blockstitch 1.0

Item {
    id: scene
    width: 900; height: 600

    InstructionBlock {
        id: top
        x: 20; y: 20
        strandId: "s1"; path: [{ index: 0 }]
        instruction: ({ id: "a", type: "MenuTest" })
    }
    InstructionBlock {
        id: below
        x: 20; y: 120
        strandId: "s1"; path: [{ index: 1 }]
        instruction: ({ id: "b", type: "MenuTest" })
    }
    PalettePanel {
        id: palette
        x: 300; width: 580; height: 600
        variables: ["score"]
    }
    SignalSpy { id: setSpy; target: palette; signalName: "setVariableValueRequested" }

    TestCase {
        name: "BlockMenu"
        when: windowShown

        function initTestCase() {
            BlockRegistry.registerRows({ MenuTest: { icon: "play", head: [{ kind: "label", text: "menu test" }] } });
            BlockRegistry.blockMenu = [{ id: "top", text: "Top only", when: (ins, sid, path) => path.length === 1 && path[0].index === 0 },
                                       { id: "all", text: "Everywhere" }];
        }
        function cleanupTestCase() { BlockRegistry.blockMenu = []; }

        function descendants(item) {
            let result = [item];
            for (const child of item.children || []) result = result.concat(descendants(child));
            return result;
        }
        function shown(block, text) {
            block.openMenu(0, 0);
            const menu = block.contextMenu;
            let found = false;
            for (let i = 0; i < menu.count; ++i) {
                const item = menu.itemAt(i);
                if (item && item.text === text) found = item.visible;
            }
            menu.close();
            return found;
        }

        function test_hostEntriesFollowTheirWhen() {
            verify(shown(top, "Top only"));
            verify(!shown(below, "Top only"));
            verify(shown(below, "Everywhere"));
        }

        function test_setValueIsOptIn() {
            tryCompare(palette, "pendingEntries", 0);
            const chip = () => descendants(palette).find(o => o.valueData && o.valueData.kind === "Var" && o.valueData.name === "score");
            verify(!!chip());
            verify(!chip().extraMenu.some(e => e.id === "set"));
            palette.offerSetVariableValue = true;
            const entry = chip().extraMenu.find(e => e.id === "set");
            verify(!!entry);
            chip().extraMenuTriggered("set");
            compare(setSpy.count, 1);
            compare(setSpy.signalArguments[0][0], "score");
        }
    }
}
