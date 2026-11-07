import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtTest
import com.blockworked.Blockstitch 1.0

Item {
    id: scene
    width: 800; height: 600
    Component {
        id: pageComponent
        StitchPage {
            width: 360; height: 260
            title: "A long heading which wraps on a narrow screen"
            description: "A description of this screen."
            Rectangle { Layout.fillWidth: true; implicitHeight: 500; color: Theme.panel }
            StitchTextField { objectName: "lastField"; Layout.fillWidth: true }
            footer: StitchButton { text: "Save" }
        }
    }
    Component {
        id: dialogComponent
        StitchScreenDialog {
            title: "Options"
            description: "Some options"
            standardButtons: Dialog.Ok | Dialog.Cancel
            Rectangle { Layout.fillWidth: true; implicitHeight: 900; color: Theme.panel }
            StitchTextField { objectName: "dialogField"; Layout.fillWidth: true }
        }
    }
    Component {
        id: listComponent
        StitchListView {
            width: 250; height: 180
            model: 50
            delegate: Text { required property int index; text: index; height: 30 }
        }
    }
    Component {
        id: wideScrollComponent
        StitchScrollView {
            width: 200; height: 150
            Rectangle { implicitWidth: 900; implicitHeight: 600; color: Theme.panel }
        }
    }
    Component {
        id: nameComponent
        NameDialog {
            noun: "variable"
            Text { text: "An extra host option" }
        }
    }
    TestCase {
        name: "Screens"
        when: windowShown
        function init() { Motion.durationScale = 0; }
        function cleanup() { Motion.durationScale = 1; }

        function test_scrollViewRetainsBothAxes() {
            const scroll = createTemporaryObject(wideScrollComponent, scene);
            const flick = scroll.contentItem;
            tryVerify(() => flick.contentWidth > flick.width && flick.contentHeight > flick.height);
            mouseWheel(scroll, 80, 70, -120, -120);
            tryVerify(() => flick.contentX > 0 && flick.contentY > 0);
        }

        function test_wheelRestoresInteractiveBinding() {
            const list = createTemporaryObject(listComponent, scene);
            list.interactive = false;
            mouseWheel(list, 100, 80, 0, -120);
            tryVerify(() => list.contentY > 0);
            tryVerify(() => !list.wheelHandler.active, 2000);
            compare(list.interactive, false);
            // A QML property supplies notifications for the restored binding.
            list.interactive = Qt.binding(() => scene.enabled);
            mouseWheel(list, 100, 80, 0, -120);
            tryVerify(() => !list.wheelHandler.active, 2000);
            scene.enabled = false;
            compare(list.interactive, false);
            scene.enabled = true;
            compare(list.interactive, true);
        }

        function test_nameDialogFitsSmallContentAndKeepsHostExtras() {
            const dialog = createTemporaryObject(nameComponent, scene);
            dialog.openForCreate();
            tryCompare(dialog, "opened", true);
            verify(dialog.height < 300);
            verify(dialog.height > dialog.header.height + dialog.footer.height);
            compare(dialog.extra.length, 1);
            dialog.fail("A validation message which should fit inside the body");
            verify(dialog.visible);
            verify(dialog.height < 350);
            dialog.close();
        }

        function test_pageScrollAndFixedChrome() {
            const page = createTemporaryObject(pageComponent, scene);
            verify(page !== null);
            const scroll = page.scrollView;
            const flick = scroll.contentItem;
            tryVerify(() => flick.contentHeight > flick.height);
            const headerY = page.header.y, footerY = page.footer.y;
            mouseWheel(scroll, scroll.width / 2, scroll.height / 2, 0, -120);
            tryVerify(() => flick.contentY > 0);
            compare(page.header.y, headerY);
            compare(page.footer.y, footerY);
            page.width = 220;
            wait(30);
            verify(page.header.height > 50);
            verify(flick.contentWidth <= flick.width + 1);
        }

        function test_keyboardFocusRevealsField() {
            const page = createTemporaryObject(pageComponent, scene);
            const field = findChild(page, "lastField");
            field.forceActiveFocus();
            tryVerify(() => field.activeFocus);
            tryVerify(() => page.scrollView.contentItem.contentY > 0);
            const point = field.mapToItem(page.scrollView, 0, 0);
            verify(point.y >= -1);
            verify(point.y + field.height <= page.scrollView.height + 1);
        }

        function test_listHasDefaultScrolling_data() {
            return [{tag: "instant", scale: 0}, {tag: "animated", scale: 1}];
        }
        function test_listHasDefaultScrolling(data) {
            Motion.durationScale = data.scale;
            const list = createTemporaryObject(listComponent, scene);
            mouseWheel(list, 100, 80, 0, -120);
            tryVerify(() => list.contentY > 0);
            tryVerify(() => !list.wheelScrolling, 1000);
            verify(list.contentY <= list.contentHeight - list.height);
        }

        function test_dialogBoundsActionsAndEscape() {
            const dialog = createTemporaryObject(dialogComponent, scene);
            dialog.open();
            tryCompare(dialog, "opened", true);
            verify(dialog.width <= dialog.parent.width - 32);
            verify(dialog.height <= dialog.parent.height - 32);
            verify(dialog.scrollView.height > 0);
            const footerY = dialog.footer.y;
            const field = findChild(dialog, "dialogField");
            field.forceActiveFocus();
            tryVerify(() => dialog.scrollView.contentItem.contentY > 0);
            compare(dialog.footer.y, footerY);
            verify(dialog.standardButton(Dialog.Ok).visible);
            keyClick(Qt.Key_Escape);
            tryCompare(dialog, "visible", false);
            dialog.title = "A very long dialog title which should wrap within the available width";
            dialog.preferredWidth = 240;
            dialog.open();
            tryCompare(dialog, "opened", true);
            verify(dialog.header.height > 58);
            mouseClick(dialog.standardButton(Dialog.Ok));
            tryCompare(dialog, "visible", false);
        }
    }
}
