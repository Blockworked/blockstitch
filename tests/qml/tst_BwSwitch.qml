import QtQuick
import QtTest
import com.blockworked.Blockstitch

Item {
    width: 300; height: 200

    Item { id: before; focus: true; activeFocusOnTab: true; width: 10; height: 10 }
    BwSwitch { id: toggle; x: 20; y: 40; Accessible.name: "Close to tray" }
    SignalSpy { id: toggled; target: toggle; signalName: "toggled" }

    TestCase {
        name: "BwSwitch"
        when: windowShown

        function ring() {
            return findChild(toggle, "focusRing");
        }

        function test_keyboard_focus_ring_and_space() {
            toggle.checked = false;
            toggled.clear();
            before.forceActiveFocus();
            verify(!ring().visible);
            keyClick(Qt.Key_Tab);
            verify(toggle.activeFocus);
            verify(ring().visible, "Tab focus shows the ring");
            keyClick(Qt.Key_Space);
            verify(toggle.checked);
            compare(toggled.count, 1);
            compare(toggled.signalArguments[0][0], true);
        }

        function test_mouse_click_toggles_without_a_ring() {
            toggle.checked = false;
            before.forceActiveFocus();
            mouseClick(toggle.contentItem.children[0]);
            verify(toggle.checked);
            verify(toggle.activeFocus);
            verify(!ring().visible, "a click isn't keyboard focus");
        }
    }
}
