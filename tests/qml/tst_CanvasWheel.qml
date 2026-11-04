import QtQuick
import QtTest
import com.blockworked.Blockstitch 1.0

Item {
    width: 900; height: 700
    BlockCanvas { id: canvas; anchors.fill: parent }
    TestCase {
        name: "CanvasWheel"
        when: windowShown
        function all(item) {
            let result = [item];
            for (const child of item.children || []) result = result.concat(all(child));
            return result;
        }
        function flick() { return all(canvas).find(o => o.flickableDirection !== undefined && o.contentY !== undefined); }

        // A wheel notch on the canvas glides rather than jumping, and notches
        // spun in a row keep it moving the whole way.
        function test_wheelNotchesGlide() {
            Motion.durationScale = 1;
            const strand = { id: "long", x: 0, y: 0, instructions: [] };
            for (let i = 0; i < 80; ++i) strand.instructions.push({ id: "w" + i, type: "Wait", ms: i });
            canvas.strands = [strand];
            tryVerify(() => canvas.pendingBuilds() === 0);
            const f = flick();
            verify(!!f);
            wait(50);
            const start = f.contentY;
            mouseWheel(canvas, 450, 350, 0, -120);
            verify(f.contentY - start < 5, "moved " + (f.contentY - start) + " at once");
            let last = f.contentY;
            for (let i = 0; i < 4; ++i) {
                wait(60);
                verify(f.contentY > last, "still gliding after notch " + i);
                last = f.contentY;
                mouseWheel(canvas, 450, 350, 0, -120);
            }
            tryVerify(() => Math.abs(f.contentY - start - 5 * Qt.styleHints.wheelScrollLines * 24) < 1, 1500);
            canvas.strands = [];
        }
    }
}
