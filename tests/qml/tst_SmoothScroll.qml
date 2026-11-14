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
        function test_notchesMidGlideKeepTheSpeed_data() {
            return [{ tag: "fast spin", gap: 80 }, { tag: "slow spin", gap: 150 }];
        }
        function test_notchesMidGlideKeepTheSpeed(data) {
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
                while (Date.now() - t < data.gap) {
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
        // Windows sends a precision touchpad's scroll as plain wheel events;
        // fine steps mark it, and a whole 120 inside that stream still counts.
        function wheel(x, y) { return { angleDelta: Qt.point(x, y), pixelDelta: Qt.point(0, 0), phase: Qt.NoScrollPhase, device: null }; }
        function test_windowsTouchpadByStepSize() {
            smooth.windows = true;
            smooth._fineUntil = 0;
            verify(!smooth.isTouchpad(wheel(0, -120)), "a wheel notch");
            verify(!smooth.isTouchpad(wheel(0, 240)), "two notches at once");
            verify(smooth.isTouchpad(wheel(0, -18)), "a touchpad step");
            verify(smooth.isTouchpad(wheel(-7, 0)), "a sideways touchpad step");
            verify(smooth.isTouchpad(wheel(0, -120)), "a whole 120 mid-swipe");
            wait(smooth.fineStreamGap + 50);
            verify(!smooth.isTouchpad(wheel(0, -120)), "a notch once the swipe has stopped");
            smooth.windows = Qt.platform.os === "windows";
        }
        // Windows' driver accelerates already: a fast step pans no more per
        // unit than a slow one, at the wheel's own rate.
        function test_windowsTouchpadIsNotAccelerated() {
            smooth.windows = true;
            const notch = smooth.wheelStep(-120, 0, false);
            compare(smooth.wheelStep(-2, 0, true) * 60, notch);
            compare(smooth.wheelStep(-290, 0, true), notch * 290 / 120);
            smooth.windows = false;
            verify(Math.abs(smooth.wheelStep(-290, 0, true)) > Math.abs(notch * 290 / 120) * 2, "Linux touchpads still accelerate");
            smooth.windows = Qt.platform.os === "windows";
        }
        function test_dragStopsTheGlide() {
            smooth.scrollBy(0, -300, true);
            smooth.stop();
            verify(!smooth.glidingY);
            verify(smooth.velocityY === 0);
        }
    }
}
