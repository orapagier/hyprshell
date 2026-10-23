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
                ui.updateBar("compactSpacing", 4);
                ui.updateBar("centerItems", true);
                for (let side of ["Top", "Bottom", "Left", "Right"]) {
                    ui.updateBar("screenMargin" + side, 12);
                    ui.updateBar("contentPadding" + side, 6);
                }
                test.phase = 15;
            } else if (test.phase === 15) {
                if (prefs.panelConfig.bar.contentPaddingTop !== 6 || prefs.panelConfig.bar.screenMarginLeft !== 12 || prefs.panelConfig.bar.centerItems !== true) {
                    test.fail("Live spacing preview did not follow draft before autosave"); return;
                }
                if (test.edgeIndex === 0 && prefs.config.bar.contentPaddingTop !== 0) {
                    test.fail("Preview changed saved settings before autosave"); return;
                }
                if (test.edgeIndex === 0) {
                    ui.updateBar("contentPaddingTop", 101);
                    test.phase = 16;
                } else test.phase = 2;
            } else if (test.phase === 16 && !ui.success && !ui.saving) {
                if (prefs.panelConfig.bar.contentPaddingTop !== 0 || Object.keys(prefs.panelPreview).length) {
                    test.fail("Rejected save left an invalid live preview"); return;
                }
                ui.updateBar("contentPaddingTop", 6);
                ui.apply();
                test.phase = 2;
            } else if (test.phase === 2 && !ui.dirty && !ui.saving) {
                if (prefs.config.bar.position !== test.edges[test.edgeIndex]) { test.fail("Position was not saved"); return; }
                ui.visible = false;
                test.phase = 3;
            } else if (test.phase === 3 && !ui.dirty && !ui.saving) {
                ui.open();
                if (ui.draft.bar.position !== test.edges[test.edgeIndex]) { test.fail("Position was lost on reopening"); return; }
                if (ui.draft.bar.centerItems !== true) { test.fail("Centered groups were lost on reopening"); return; }
                for (let side of ["Top", "Bottom", "Left", "Right"]) {
                    if (ui.draft.bar["screenMargin" + side] !== 12 || ui.draft.bar["contentPadding" + side] !== 6) {
                        test.fail("Four-side spacing was lost on reopening"); return;
                    }
                }
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
