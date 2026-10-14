import QtQuick
import QtQuick.Window
import Quickshell
import ".."

ShellRoot {
    id: test
    property int phase: 0
    Window {
        visible: true; width: 840; height: 1200
        SettingsDisplays { id: page; anchors.fill: parent }
    }
    function find(root, name) {
        if (root.objectName === name) return root;
        for (let child of root.children || []) { let match = find(child, name); if (match) return match; }
        return null;
    }
    function fail(message) { console.error("DISPLAYS_FAILED", phase, message); Qt.quit(); }
    Timer {
        interval: 50; running: true; repeat: true
        onTriggered: {
            if (test.phase === 0 && page.loaded && !page.busy) {
                let resolution = test.find(page, "displayResolution");
                let refresh = test.find(page, "displayRefresh");
                if (!resolution || !refresh || refresh.model.length !== 2) { test.fail("mode controls"); return; }
                refresh.currentIndex = 1; refresh.activated(1);
                if (page.entries[0].mode !== "1920x1080@120.00Hz") { test.fail("refresh edit"); return; }
                resolution.currentIndex = 2; resolution.activated(2);
                if (page.entries[0].mode !== "1280x720@60.00Hz" || page.saved.entries.length) { test.fail("resolution draft"); return; }
                let oldEntries = page.entries;
                let oldMonitors = page.monitors;
                page.monitors = [{name: "eDP-1", width: 1920, height: 1080, scale: 1, x: 0, y: 0}, {name: "HDMI-A-1", width: 2560, height: 1440, scale: 2, x: 1920, y: 0}];
                page.entries = [{output: "eDP-1", mode: "preferred", scale: 1, transform: 0, position: "auto"}, {output: "HDMI-A-1", mode: "preferred", scale: 2, transform: 0, position: "auto"}];
                let duplicate = test.find(page, "duplicateDisplays");
                let extend = test.find(page, "extendDisplays");
                if (!duplicate || !extend) { test.fail("layout controls"); return; }
                duplicate.clicked();
                if (page.entries[0].mirror !== "" || page.entries[1].mirror !== "eDP-1") { test.fail("duplicate laptop on TV"); return; }
                extend.clicked();
                if (page.entries.some(e => e.mirror || e.position !== "auto")) { test.fail("extend clears mirrors"); return; }
                page.duplicate("eDP-1");
                page.place(1, "eDP-1", "right");
                if (page.entries[1].position !== "1920x0" || page.entries[0].position !== "0x0" || page.entries.some(e => e.mirror)) { test.fail("right placement"); return; }
                page.place(1, "eDP-1", "left");
                if (page.entries[1].position !== "-1280x0") { test.fail("scaled left placement"); return; }
                page.monitors = oldMonitors; page.entries = oldEntries;
                page.receive({ok: false, pending: false, message: "Display command failed."});
                page.receive({ok: true, monitors: oldMonitors, entries: oldEntries, saved: page.saved});
                if (page.success || page.message !== "Display command failed.") { test.fail("error became success after refresh"); return; }
                page.request("preview"); test.phase = 1;
            } else if (test.phase === 1 && page.pending) {
                if (page.seconds !== 15 || !test.find(page, "keepDisplays").enabled) { test.fail("confirmation"); return; }
                page.decide("keep"); test.phase = 2;
            } else if (test.phase === 2 && !page.busy && page.message === "Display settings saved.") {
                // Wait for the delayed status request to finish before starting another.
                test.phase = 3;
            } else if (test.phase === 3 && !page.busy && !page.refreshAfterExit) {
                page.request("preview"); test.phase = 4;
            } else if (test.phase === 4 && page.pending) {
                page.decide("revert"); test.phase = 5;
            } else if (test.phase === 5 && !page.busy && page.message === "Previous display settings restored.") {
                console.log("DISPLAYS_NATIVE_OK"); Qt.quit();
            }
        }
    }
    Timer { interval: 10000; running: true; onTriggered: test.fail("timeout: " + page.message) }
}
