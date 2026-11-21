import QtQuick
import QtTest
import com.blockworked.Blockstitch

// A dock region: tabs pick a panel, the open tab folds it, the edge resizes.
Item {
    id: scene
    width: 600; height: 400

    TestCase {
        id: test
        name: "DockRegion"
        when: windowShown

        Component {
            id: regionComponent
            DockRegion {
                id: region
                width: 600
                tabs: [{ title: "Assets", iconName: "folder" }, { title: "Log", iconName: "list" }]
                onTabRequested: i => currentIndex = i
                onOpenRequested: o => open = o
                onResizeRequested: s => size = s
                Item { objectName: "panel-assets" }
                Item { objectName: "panel-log" }
            }
        }

        function make(props) {
            const region = createTemporaryObject(regionComponent, scene, props || {});
            verify(region);
            return region;
        }

        function test_tabsPickAndFold() {
            const region = make({ size: 180 });
            compare(region.implicitHeight, 180);
            const log = findChild(region, "dock-tab-Log");
            mouseClick(log);
            compare(region.currentIndex, 1);
            verify(findChild(region, "panel-log").visible);
            verify(!findChild(region, "panel-assets").visible);
            mouseClick(log);
            verify(!region.open, "clicking the open tab folds it");
            compare(region.implicitHeight, region.stripSize);
            mouseClick(findChild(region, "dock-tab-Assets"));
            verify(region.open);
            compare(region.currentIndex, 0);
        }

        function test_aFoldedSideIsARail() {
            const region = make({ edge: "left", open: false, height: 400 });
            compare(region.implicitWidth, region.stripSize);
            mouseClick(findChild(region, "dock-tab-Log"));
            verify(region.open);
            compare(region.implicitWidth, region.size);
        }

        function test_aSingleTabCanLeaveTheStripToThePanel() {
            const region = make({ edge: "right", height: 400, hideSingleTab: true, tabs: [{ title: "Inspector", iconName: "info" }] });
            verify(!region.stripShown);
            verify(!findChild(region, "dock-tab-Inspector").visible || !region.stripShown);
            region.open = false;
            verify(region.stripShown, "a folded region still shows its rail");
        }

        function test_theInnerEdgeResizesWithinBounds() {
            const region = make({ edge: "left", size: 200, height: 400, minSize: 150, maxSize: 300, width: 200 });
            mouseDrag(region, 199, 200, 50, 0);
            compare(region.size, 250);
            mouseDrag(region, 199, 200, -400, 0);
            compare(region.size, 150, "held to minSize");
        }
    }
}
