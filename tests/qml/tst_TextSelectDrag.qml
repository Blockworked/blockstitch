import QtQuick
import QtTest
import com.blockworked.Blockstitch 1.0

Item {
    width: 900; height: 700
    BlockCanvas {
        id: canvas; anchors.fill: parent
        floatingValues: [{ id: "f1", x: 40, y: 40, value: { kind: "Op", op: "Join", args: [{ kind: "Text", value: "hello there world" }, { kind: "Text", value: "" }] } }]
    }
    TestCase {
        name: "TextSelectDrag"
        when: windowShown
        function all(item) {
            let result = [item];
            for (const child of item.children || []) result = result.concat(all(child));
            return result;
        }
        function flick() { return all(canvas).find(o => o.flickableDirection !== undefined && o.contentY !== undefined); }
        function field() { return all(canvas).find(o => o.selectByMouse !== undefined && o.text === "hello there world"); }

        // A drag that starts in a text field selects text and leaves the
        // canvas where it was.
        function test_dragInTextFieldSelectsWithoutPanning() {
            tryVerify(() => !!field());
            const f = flick(), t = field();
            waitForRendering(canvas);
            const x0 = f.contentX, y0 = f.contentY;
            mousePress(t, 4, t.height / 2);
            for (let i = 1; i <= 10; ++i) mouseMove(t, 4 + i * 4, t.height / 2 + i * 8);
            mouseRelease(t, 44, t.height / 2 + 80);
            verify(t.selectedText.length > 0, "nothing selected");
            compare(f.contentX, x0);
            compare(f.contentY, y0);
            verify(f.interactive, "canvas stays pannable afterwards");
        }

        // An empty spot on the canvas still pans it.
        function test_dragOnEmptyCanvasStillPans() {
            const f = flick();
            waitForRendering(canvas);
            const y0 = f.contentY;
            mousePress(canvas, 600, 500);
            for (let i = 1; i <= 10; ++i) mouseMove(canvas, 600, 500 - i * 10);
            mouseRelease(canvas, 600, 400);
            verify(f.contentY !== y0, "canvas did not pan");
        }
    }
}
