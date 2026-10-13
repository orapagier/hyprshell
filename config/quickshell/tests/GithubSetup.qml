import QtQuick
import Quickshell
import ".."

ShellRoot {
    id: test
    property int phase: 0
    SettingsStore { id: prefs }
    SettingsWindow { id: editor; store: prefs }
    function find(object, name, seen) {
        if (!object || seen.indexOf(object) !== -1) return null;
        seen.push(object);
        if (object.objectName === name) return object;
        let children = [];
        if (object.children) for (let child of object.children) children.push(child);
        if (object.data && typeof object.data.length === "number")
            for (let i = 0; i < object.data.length; ++i) children.push(object.data[i]);
        if (object.contentItem) children.push(object.contentItem);
        for (let child of children) {
            let result = find(child, name, seen);
            if (result) return result;
        }
        return null;
    }
    function fail(message) { console.error("GITHUB_SETUP_FAILED", message); Qt.quit(); }
    Timer {
        interval: 100; running: true; repeat: true
        onTriggered: {
            if (!prefs.loaded) return;
            if (test.phase === 0) { editor.open(); test.phase = 1; return; }
            if (test.phase === 1) {
                let button = test.find(editor.contentItem, "githubSyncButton", []);
                if (!button) return;
                button.clicked(); test.phase = 2; return;
            }
            if ((test.phase === 2 || test.phase === 3 || test.phase === 4) && editor.idle) {
                let dialog = test.find(editor.contentItem, "githubSyncDialog", []);
                let label = test.find(dialog, "githubRepositoryLabel", []);
                let sync = test.find(dialog, "githubConfirmSync", []);
                let fork = test.find(dialog, "githubForkButton", []);
                let create = test.find(dialog, "githubCreateButton", []);
                if (!dialog || !dialog.opened || !label || !sync || !fork || !create) { test.fail("missing controls"); return; }
                if (label.text !== "ramlej/hyprshell") { test.fail("repository is not dynamic"); return; }
                if (test.find(dialog, "githubCommitName", []) || test.find(dialog, "githubCommitEmail", [])) { test.fail("manual identity fields remain"); return; }
                if (test.phase === 2) {
                    if (sync.enabled || !fork.visible || !create.visible) { test.fail("missing repository actions"); return; }
                    test.find(dialog, "githubCheckButton", []).clicked();
                    test.phase = 3; return;
                }
                if (test.phase === 3) {
                    if (!sync.enabled || fork.visible || create.visible) { test.fail("repository recheck did not enable sync"); return; }
                    sync.clicked(); test.phase = 4; return;
                }
                if (!editor.syncSuccess || editor.syncMessage !== "Synced to ramlej/hyprshell (main).") { test.fail("sync did not complete"); return; }
                console.log("GITHUB_SETUP_OK"); Qt.quit();
            }
        }
    }
    Timer { interval: 15000; running: true; onTriggered: test.fail("timeout") }
}
