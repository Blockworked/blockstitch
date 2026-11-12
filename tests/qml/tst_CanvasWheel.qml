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

        function longStrand() {
            const strand = { id: "long", x: 0, y: 0, instructions: [] };
            for (let i = 0; i < 80; ++i) strand.instructions.push({ id: "w" + i, type: "Wait", ms: i });
            canvas.strands = [strand];
            tryVerify(() => canvas.pendingBuilds() === 0);
        }

        // A Windows precision touchpad arrives as a burst of small wheel
        // steps with no phase. It follows the fingers like a Linux touchpad
        // instead of starting a wheel glide per step, and comes to rest
        // right after the last one.
        function test_windowsTouchpadFollows() {
            Motion.durationScale = 1;
            longStrand();
            const f = flick();
            const s = canvas.scroller;
            verify(!!s, "found the canvas scroller");
            s.windows = true;
            s._fineUntil = 0;
            wait(50);
            const start = f.contentY;
            for (let i = 0; i < 20; ++i) {
                mouseWheel(canvas, 450, 350, 0, -24, Qt.NoButton, Qt.NoModifier, 8);
                verify(!s.glidingY, "step " + i + " started a wheel glide");
            }
            verify(s.following);
            // Settles within a few frames of the last step, not a 220 ms glide later.
            tryVerify(() => !s.following, 200);
            const moved = f.contentY - start;
            // Same as Linux: 2 px per step, accelerated from 6 px per px.
            compare(Math.round(moved), Math.round(20 * s.wheelStep(-24, 0, true) * -1));
            // A wheel notch after the swipe has stopped still glides.
            wait(s.fineStreamGap + 50);
            mouseWheel(canvas, 450, 350, 0, -120);
            verify(s.glidingY);
            tryVerify(() => !s.glidingY, 1000);
            s.windows = Qt.platform.os === "windows";
            canvas.strands = [];
        }

        // Windows turns a touchpad pinch into Ctrl + small wheel steps; they
        // zoom at a Linux touchpad's rate with short glides, not as notches.
        function test_windowsPinchZoomsGently() {
            Motion.durationScale = 0;
            const f = flick();
            const s = canvas.scroller;
            s.windows = true;
            s._fineUntil = 0;
            const z0 = canvas.zoom;
            for (let i = 0; i < 10; ++i)
                mouseWheel(canvas, 450, 350, 0, 12, Qt.NoButton, Qt.ControlModifier, 8);
            tryVerify(() => Math.abs(canvas.zoom - z0 * Math.pow(1.12, 120 / 240)) < 0.01, 500, "zoom " + canvas.zoom);
            s.windows = Qt.platform.os === "windows";
            canvas.setZoom(z0);
            Motion.durationScale = 1;
        }
    }
}
