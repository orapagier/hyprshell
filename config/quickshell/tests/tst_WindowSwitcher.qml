import QtQuick
import QtTest
import "../WindowSwitcherModel.js" as Switcher

TestCase {
    name: "WindowSwitcher"
    function rows() {
        return [
            {address: "one", title: "Zulu", workspace: 2, active: false},
            {address: "two", title: "Alpha", workspace: 2, active: true},
            {address: "three", title: "Other", workspace: 3, active: false}
        ];
    }
    function test_workspaceSelectionAndNavigation() {
        let windows = Switcher.workspaceRows(rows(), 2);
        compare(windows.length, 2);
        compare(windows[0].address, "two");
        compare(Switcher.indexForAddress(windows, "one"), 1);
        compare(Switcher.preferredAddress(windows, "one", "two"), "one");
        compare(Switcher.preferredAddress(windows, "missing", "two"), "two");
        compare(Switcher.nextIndex(2, 0, 1), 1);
        compare(Switcher.nextIndex(2, 1, 1), 0);
        compare(Switcher.nextIndex(2, 0, -1), 1);
        compare(Switcher.nextIndex(2, -1, -1), 1);
        compare(Switcher.nextIndex(0, 0, 1), -1);
    }

    function test_carouselRotation() {
        compare(Switcher.wrapIndex(4, -1), 3);
        compare(Switcher.wrapIndex(4, 5), 1);
        compare(Switcher.wrapIndex(0, 3), -1);
        compare(Switcher.nearestAnchor(4, 0, 3), -1);
        compare(Switcher.nearestAnchor(4, 2, 2), 2);
        compare(Switcher.anchorAfterStep(2, 1), 1);
        compare(Switcher.anchorAfterStep(2, -1), 3);

        // Four cards with the fixed highlight on the 3rd slot: pressing right
        // moves 1->2, 2->3, 3->4 and 4->1; left is the reverse.
        const count = 4;
        const highlight = 2;
        const slot = (row, anchor) => ((row - anchor + highlight) % count + count) % count;
        compare([0, 1, 2, 3].map(row => slot(row, 2)).join(","), "0,1,2,3");
        compare([0, 1, 2, 3].map(row => slot(row, Switcher.anchorAfterStep(2, 1))).join(","), "1,2,3,0");
        compare([0, 1, 2, 3].map(row => slot(row, Switcher.anchorAfterStep(2, -1))).join(","), "3,0,1,2");
    }
}
