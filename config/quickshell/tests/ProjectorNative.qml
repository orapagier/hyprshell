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
            let duplicate = test.find(projector.contentItem, "duplicateDisplays");
            let extend = test.find(projector.contentItem, "extendDisplays");
            if (!duplicate || !extend) { test.fail("missing controls"); return; }
            if (test.phase === 0) {
                if (duplicate.text !== "Duplicate" || extend.text !== "Extend"
                    || test.find(projector.contentItem, "applyDisplays")
                    || test.find(projector.contentItem, "keepDisplays")) { test.fail("unexpected controls"); return; }
                duplicate.clicked(); test.phase = 1;
            } else if (test.phase === 1 && !projector.busy) {
                if (projector.visible || projector.error) { test.fail("duplicate auto apply"); return; }
                projector.open(); extend.clicked(); test.phase = 2;
            } else if (test.phase === 2 && !projector.busy) {
                if (projector.visible || projector.error) { test.fail("extend auto apply"); return; }
                console.log("PROJECTOR_NATIVE_OK"); Qt.quit();
            }
        }
    }
    Timer { interval: 10000; running: true; onTriggered: test.fail("timeout") }
}
