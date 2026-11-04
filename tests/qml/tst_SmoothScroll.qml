import QtQuick
import QtTest
import com.blockworked.Blockstitch 1.0

Item {
    width: 400; height: 300
    Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: 4000; contentHeight: 20000
    }
    SmoothScroll { id: smooth; flickable: flick }
    TestCase {
        name: "SmoothScroll"
        when: windowShown

        function init() {
            smooth.stop();
            Motion.durationScale = 1;
            flick.contentX = 0;
            flick.contentY = 0;
        }
        function cleanup() { smooth.stop(); Motion.durationScale = 1; }

        function test_notchGlidesToItsTarget() {
            smooth.scrollBy(0, -72, true);
            verify(smooth.glidingY);
            compare(smooth.targetY, 72);
            tryVerify(() => !smooth.glidingY, 1000);
            compare(flick.contentY, 72);
        }
        function test_instantSpeedJumps() {
            Motion.durationScale = 0;
            smooth.scrollBy(0, -72, true);
            verify(!smooth.glidingY);
            compare(flick.contentY, 72);
        }
        // Spinning the wheel keeps an even pace: a notch mid-glide neither
        // stalls the view nor kicks it to several times its speed.
        function test_notchesMidGlideKeepTheSpeed() {
            let peak = 0, low = Infinity, last = 0;
            for (let i = 0; i < 8; ++i) {
                smooth.scrollBy(0, -72, true);
                const before = smooth.velocityY;
                if (i >= 3) {
                    verify(before > 0, "still moving when the next notch lands");
                    // Never more than a gentle kick on a notch.
                    verify(smooth.velocityY <= before * 2.5 + 1);
                }
                const t = Date.now();
                while (Date.now() - t < 80) {
                    wait(8);
                    if (i >= 3) {
                        peak = Math.max(peak, smooth.velocityY);
                        low = Math.min(low, smooth.velocityY);
                    }
                }
                verify(flick.contentY >= last);
                last = flick.contentY;
            }
            verify(low > 0);
            verify(peak / low < 2.5, "speed varies " + low + " to " + peak);
            tryVerify(() => !smooth.glidingY, 1000);
            compare(flick.contentY, 8 * 72);
        }
        function test_pausedGlideResumesAtItsSpeed() {
            smooth.scrollBy(0, -200, true);
            wait(40);
            const v = smooth.velocityY;
            verify(v > 0);
            smooth.stop();
            smooth.scrollTo(NaN, 200, true, 0, v);
            verify(Math.abs(smooth.velocityY - v) < v * 0.05 + 1, smooth.velocityY + " vs " + v);
        }
        function test_dragStopsTheGlide() {
            smooth.scrollBy(0, -300, true);
            smooth.stop();
            verify(!smooth.glidingY);
            verify(smooth.velocityY === 0);
        }
    }
}
