import QtQuick
import Quickshell
import ".."
import "../SettingsModel.js" as Model

ShellRoot {
    id: test
    property int phase: 0
    SettingsStore { id: prefs }
    SettingsWindow { id: ui; store: prefs; currentWorkspace: 3 }
    function check(bar) {
        return Model.barVisible(bar, 3) && !Model.barVisible(bar, 1) &&
            !Model.barVisible(bar, 2) && bar.spacing === 17;
    }
    Timer {
        interval: 50; running: true; repeat: true
        onTriggered: {
            if (test.phase === 0 && prefs.loaded) {
                ui.open();
                ui.updateBarSettings(Object.assign({}, ui.draft.bar, {workspaceScope: "selected", workspaceList: [1]}));
                test.phase = 1;
            } else if (test.phase === 1 && ui.saving) {
                // The same entry point as Alt+T while Settings is loaded.
                // These edits must queue behind the selected-scope write.
                ui.toggleWorkspaceBar(3);
                ui.toggleWorkspaceBar(1);
                ui.updateBar("spacing", 17);
                Qt.callLater(() => {
                    if (!test.check(prefs.panelConfig.bar)) {
                        console.error("WORKSPACE_VISIBILITY_NOT_IMMEDIATE"); Qt.exit(1);
                    }
                });
                test.phase = 2;
            } else if (test.phase === 2 && !ui.dirty && !ui.saving) {
                if (!test.check(prefs.config.bar)) { console.error("WORKSPACE_VISIBILITY_LOST_EDITS"); Qt.quit(); return; }
                ui.toggleWorkspaceBar(3);
                ui.toggleWorkspaceBar(3);
                ui.visible = false;
                test.phase = 3;
            } else if (test.phase === 3 && !ui.dirty && !ui.saving) {
                ui.open();
                if (!test.check(ui.draft.bar)) { console.error("WORKSPACE_VISIBILITY_REOPEN_FAILED"); Qt.quit(); return; }
                console.log("WORKSPACE_VISIBILITY_OK");
                Qt.quit();
            }
        }
    }
    Timer { interval: 15000; running: true; onTriggered: { console.error("WORKSPACE_VISIBILITY_TIMEOUT", test.phase, ui.message); Qt.quit(); } }
}
