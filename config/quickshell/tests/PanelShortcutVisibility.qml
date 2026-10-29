import QtQuick
import Quickshell
import ".."
import "../SettingsModel.js" as Model

ShellRoot {
    id: test
    property int phase: 0
    SettingsStore { id: prefs }
    PanelVisibilityController { id: toggle; store: prefs }
    function fail(message) { console.error(message); Qt.exit(1); }
    Timer {
        interval: 20; running: true; repeat: true
        onTriggered: {
            if (test.phase === 0 && prefs.loaded) {
                toggle.toggle(3);
                if (Model.barVisible(toggle.config.bar, 3) || !Model.barVisible(prefs.config.bar, 3)) {
                    test.fail("SHORTCUT_WAITED_FOR_SAVE"); return;
                }
                toggle.toggle(3);
                if (!Model.barVisible(toggle.config.bar, 3)) { test.fail("SECOND_TOGGLE_NOT_IMMEDIATE"); return; }
                toggle.toggle(3);
                toggle.toggle(4);
                test.phase = 1;
            } else if (test.phase === 1) {
                // Every intermediate save must preserve the latest visible state.
                if (Model.barVisible(toggle.config.bar, 3) || Model.barVisible(toggle.config.bar, 4)) {
                    test.fail("SHORTCUT_FLICKERED_DURING_SAVE"); return;
                }
                if (toggle.busy) return;
                if (Model.barVisible(prefs.config.bar, 3) || Model.barVisible(prefs.config.bar, 4)
                        || !Model.barVisible(prefs.config.bar, 1)) {
                    test.fail("SHORTCUT_DID_NOT_PERSIST"); return;
                }
                toggle.toggle(3, "hyprdock");
                if (!toggle.config.bar.dockEnabled || !Model.barVisible(toggle.config.bar, 3)) { test.fail("DOCK_NOT_SHOWN"); return; }
                toggle.toggle(3, "hyprpane");
                if (toggle.config.bar.dockEnabled || !Model.barVisible(toggle.config.bar, 3)) { test.fail("PANE_NOT_SHOWN"); return; }
                toggle.toggle(3, "hyprpane");
                if (Model.barVisible(toggle.config.bar, 3)) { test.fail("PANE_NOT_HIDDEN"); return; }
                test.phase = 3;
            } else if (test.phase === 3 && !toggle.busy) {
                if (prefs.config.bar.dockEnabled || Model.barVisible(prefs.config.bar, 3)) { test.fail("MODE_NOT_PERSISTED"); return; }
                toggle.toggle(9);
                if (Model.barVisible(toggle.config.bar, 9)) { test.fail("FAILURE_PREVIEW_NOT_IMMEDIATE"); return; }
                test.phase = 2;
            } else if (test.phase === 2 && !toggle.busy) {
                if (!Model.barVisible(toggle.config.bar, 9) || !Model.barVisible(prefs.config.bar, 9)) {
                    test.fail("FAILED_SAVE_DID_NOT_REVERT"); return;
                }
                console.log("PANEL_SHORTCUT_OK"); Qt.quit();
            }
        }
    }
    Timer { interval: 15000; running: true; onTriggered: test.fail("PANEL_SHORTCUT_TIMEOUT " + test.phase) }
}
