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

    // Collect the rows occupying the visible strip, ordered by slot.
    function visibleRows(count, visible, anchor) {
        let placed = [];
        for (let row = 0; row < count; row++) {
            for (let copy = 0; copy < 3; copy++) {
                const position = Switcher.carouselSlot(count, visible, anchor, row, copy);
                if (position >= 0 && position < visible) placed.push({position: position, row: row});
            }
        }
        placed.sort((left, right) => left.position - right.position);
        return placed;
    }

    function test_carouselSlotsFillTheStrip() {
        const count = 4;
        const visible = 4;
        compare(visibleRows(count, visible, 2).map(entry => entry.row).join(","), "0,1,2,3");
        // Right moves the cards right: card 4 wraps to the first slot.
        compare(visibleRows(count, visible, Switcher.anchorAfterStep(2, 1)).map(entry => entry.row).join(","), "3,0,1,2");
        // Left is the reverse.
        compare(visibleRows(count, visible, Switcher.anchorAfterStep(2, -1)).map(entry => entry.row).join(","), "1,2,3,0");
    }

    function test_carouselSlotsStayCoveredWhileSpinning() {
        for (let count = 2; count <= 9; count++) {
            const visible = Math.min(count, 5);
            for (let anchor = -80; anchor <= 80; anchor++) {
                const placed = visibleRows(count, visible, anchor);
                compare(placed.length, visible);
                for (let position = 0; position < visible; position++) {
                    compare(placed[position].position, position);
                }
                // Every copy must move at most one slot, unless it jumps while
                // completely outside the visible strip.
                for (let row = 0; row < count; row++) {
                    for (let copy = 0; copy < 3; copy++) {
                        const before = Switcher.carouselSlot(count, visible, anchor, row, copy);
                        const after = Switcher.carouselSlot(count, visible, anchor + 1, row, copy);
                        if (Math.abs(after - before) > 1)
                            verify(before < 0 || before >= visible, "jump from visible slot " + before);
                        if (Math.abs(after - before) > 1)
                            verify(after < 0 || after >= visible, "jump to visible slot " + after);
                    }
                }
            }
        }
    }
}
