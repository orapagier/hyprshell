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
}
