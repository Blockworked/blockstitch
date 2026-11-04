import QtQuick
import QtTest
import com.blockworked.Blockstitch 1.0

// One right-click on a value opens exactly one menu, and always the same one.
Item {
    id: scene
    width: 900; height: 600
    BlockCanvas {
        id: canvas
        width: 900; height: 600
        floatingValues: [{ id: "f1", x: 40, y: 40, value: { kind: "Op", op: "Round", args: [{ kind: "Op", op: "Round", args: [{ kind: "Number", value: 2.5 }] }] } }]
    }
    InstructionBlock {
        id: waitBlock
        x: 20; y: 400
        strandId: "s1"; path: [{ index: 0 }]
        instruction: ({ id: "w", type: "Wait", duration: { kind: "Op", op: "Round", args: [{ kind: "Number", value: 2.5 }] } })
    }
    SignalSpy { id: removed; target: canvas; signalName: "floatingValueRemoved" }
    TestCase {
        name: "ValueMenu"
        when: windowShown
        function descendants(item) {
            let result = [item];
            for (const child of item.children || []) result = result.concat(descendants(child));
            return result;
        }
        function openMenus() {
            const menus = descendants(scene).filter(o => o.hasOwnProperty("menu") && o.menu && o.menu.opened).map(o => o.menu);
            return menus.map(m => {
                let texts = [];
                for (let i = 0; i < m.count; ++i) { const it = m.itemAt(i); if (it && it.visible) texts.push(it.text); }
                return { menu: m, texts: texts };
            });
        }
        function closeAll() {
            for (const m of openMenus()) m.menu.close();
            if (waitBlock.contextMenu) waitBlock.contextMenu.close();
            tryVerify(() => (!waitBlock.contextMenu || !waitBlock.contextMenu.visible) && descendants(scene).every(o => !(o.hasOwnProperty("menu") && o.menu && o.menu.visible)));
        }
        function chips() { return descendants(canvas).filter(o => o.valueData && o.valueData.kind === "Op"); }

        function test_floatingValueOpensOneMenuWithDelete() {
            waitForRendering(canvas);
            const outer = chips()[0];
            mouseClick(outer, 4, outer.height / 2, Qt.RightButton);
            tryVerify(() => openMenus().length > 0);
            wait(100);
            const open = openMenus();
            compare(open.length, 1);
            compare(open[0].texts, ["Details", "Delete value"]);
            for (let i = 0; i < open[0].menu.count; ++i) {
                const it = open[0].menu.itemAt(i);
                if (it && it.visible && it.text === "Delete value") it.triggered();
            }
            compare(removed.count, 1);
            compare(removed.signalArguments[0][0], "f1");
            closeAll();
        }
        function test_nestedValueOpensOnlyItsOwnMenu() {
            waitForRendering(canvas);
            const inner = chips()[1];
            mouseClick(inner, 4, inner.height / 2, Qt.RightButton);
            tryVerify(() => openMenus().length > 0);
            wait(100);
            const open = openMenus();
            compare(open.length, 1);
            compare(open[0].texts, ["Details"]);
            closeAll();
        }
        function test_valueInABlockOpensOneMenu() {
            waitForRendering(waitBlock);
            const all = descendants(waitBlock);
            const op = all.find(o => o.valueData && o.valueData.kind === "Op");
            mouseClick(op, 4, op.height / 2, Qt.RightButton);
            tryVerify(() => openMenus().length > 0);
            wait(100);
            compare(openMenus().length, 1);
            verify(!waitBlock.contextMenu || !waitBlock.contextMenu.opened);
            closeAll();
            closeAll();
        }
    }
}
