import QtQuick
import Quickshell
import ".."

ShellRoot {
    id: test
    property int phase: 0
    property int edgeIndex: 0
    property var edges: ["left", "right", "bottom", "top"]
    SettingsStore { id: prefs }
    SettingsWindow { id: ui; store: prefs }
    function fail(message) { console.error("BAR_POSITION_FAILED: " + message); Qt.quit(); }
    Timer {
        interval: 60; running: true; repeat: true
        onTriggered: {
            if (test.phase === 0 && prefs.loaded) {
                ui.open();
                test.phase = 1;
            } else if (test.phase === 1 && !ui.dirty && !ui.saving) {
                ui.updateBar("position", test.edges[test.edgeIndex]);
                test.phase = 2;
            } else if (test.phase === 2 && !ui.dirty && !ui.saving) {
                if (prefs.config.bar.position !== test.edges[test.edgeIndex]) { test.fail("Position was not saved"); return; }
                ui.visible = false;
                test.phase = 3;
            } else if (test.phase === 3 && !ui.dirty && !ui.saving) {
                ui.open();
                if (ui.draft.bar.position !== test.edges[test.edgeIndex]) { test.fail("Position was lost on reopening"); return; }
                test.edgeIndex++;
                if (test.edgeIndex === test.edges.length) {
                    console.log("BAR_POSITION_OK"); Qt.quit(); return;
                }
                test.phase = 1;
            }
        }
    }
    Timer { interval: 15000; running: true; onTriggered: test.fail("Timed out") }
}
