import QtQuick
import Quickshell
import ".."

ShellRoot {
    id: test
    property int phase: 0
    ProjectorWindow { id: projector }
    function find(root, name) {
        if (root.objectName === name) return root;
        for (let child of root.children || []) { let match = find(child, name); if (match) return match; }
        return null;
    }
    function fail(message) { console.error("PROJECTOR_FAILED", phase, message); Qt.quit(); }
    Component.onCompleted: projector.open()
    Timer {
        interval: 50; running: true; repeat: true
        onTriggered: {
            let page = test.find(projector.contentItem, "projectorPage");
            if (!page) { test.fail("missing projector page"); return; }
            if (test.phase === 0 && page.loaded && !page.busy) {
                if (!page.projectionOnly || test.find(page, "displayResolution")) { test.fail("advanced settings in projector"); return; }
                let duplicate = test.find(page, "duplicateDisplays");
                let extend = test.find(page, "extendDisplays");
                if (!duplicate.visible || duplicate.enabled || !extend.visible || extend.enabled) { test.fail("single display readiness"); return; }
                page.monitors = page.monitors.concat([Object.assign({}, page.monitors[0], {name: "HDMI-A-1"})]);
                page.entries = page.entries.concat([Object.assign({}, page.entries[0], {output: "HDMI-A-1"})]);
                duplicate.clicked();
                if (page.entries[1].mirror !== "eDP-1" || page.entries[0].mirror) { test.fail("mirror source"); return; }
                extend.clicked();
                if (page.entries.some(e => e.mirror || e.position !== "auto")) { test.fail("extend"); return; }
                page.request("preview"); test.phase = 1;
            } else if (test.phase === 1 && page.pending) {
                projector.visible = false; test.phase = 2;
            } else if (test.phase === 2 && !page.busy && !page.refreshAfterExit) {
                if (page.message !== "Previous display settings restored.") { test.fail("close did not revert"); return; }
                projector.open(); test.phase = 3;
            } else if (test.phase === 3 && projector.visible && !page.busy) {
                page.request("preview"); test.phase = 4;
            } else if (test.phase === 4 && page.pending) {
                page.decide("keep"); test.phase = 5;
            } else if (test.phase === 5 && !page.busy && page.message === "Display settings saved.") {
                console.log("PROJECTOR_NATIVE_OK"); Qt.quit();
            }
        }
    }
    Timer { interval: 10000; running: true; onTriggered: test.fail("timeout") }
}
