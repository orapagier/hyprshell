import QtQuick
import QtQuick.Window
import Quickshell
import ".."

ShellRoot {
    id: test
    property int phase: 0
    SettingsStore { id: prefs }
    SettingsController { id: controller; store: prefs }
    function find(object, name, seen) {
        if (!object || seen.includes(object)) return null;
        seen.push(object);
        if (object.objectName === name) return object;
        let children = [];
        if (object.children) for (let child of object.children) children.push(child);
        if (object.data && typeof object.data.length === "number") for (let child of object.data) children.push(child);
        if (object.contentItem) children.push(object.contentItem);
        for (let child of children) { let found = find(child, name, seen); if (found) return found; }
        return null;
    }
    function control(name) { return find(controller.window.contentItem, name, []); }
    function fail(message) { console.error("MANUAL_DRAFT_FAILED", phase, message); Qt.quit(); }
    Timer {
        interval: 80; running: true; repeat: true
        onTriggered: {
            if (!prefs.loaded) return;
            if (test.phase === 0) {
                controller.open(); controller.window.firstRunPending = false; controller.window.section = -19; test.phase++;
            } else if (test.phase === 1) {
                let page = test.control("settingsBehaviorLoader").item;
                if (!page || !page.loaded || page.busy) return;
                page.editGeneral("layout", "master");
                page.add("workspaces");
                controller.window.section = -17; test.phase++;
            } else if (test.phase === 2) {
                let page = test.control("settingsRegionalLoader").item;
                if (!page || !page.loaded || page.busy) return;
                test.control("regionalTimezone").text = "Asia/Manila";
                if (!page.dirty) { test.fail("regional draft not tracked"); return; }
                controller.window.section = -1; test.phase++;
            } else if (test.phase === 3) {
                let floating = test.control("workspaceFloating-0");
                if (!floating) { test.fail("floating workspace switch missing"); return; }
                floating.checked = true; floating.toggled();
                if (!test.control("settingsBehaviorLoader").active || !test.control("settingsRegionalLoader").active || !controller.window.manualDirty) { test.fail("navigation discarded draft"); return; }
                controller.window.contentItem.Window.window.close(); test.phase++;
            } else if (test.phase === 4) {
                if (!controller.loaded) { test.fail("close discarded manual edits"); return; }
                controller.open(); controller.window.section = -19; test.phase++;
            } else if (test.phase === 5) {
                let page = test.control("settingsBehaviorLoader").item;
                if (page.busy) return;
                if (page.draft.general.layout !== "master" || page.draft.workspaces[0].floating !== true) { test.fail("reopen reset workspace draft"); return; }
                page.request("save"); test.phase++;
            } else if (test.phase === 6) {
                let page = test.control("settingsBehaviorLoader").item;
                if (page.busy || page.dirty) return;
                if (page.draft.workspaces[0].floating !== true) { test.fail("save lost floating preference"); return; }
                controller.window.section = -17; test.phase++;
            } else if (test.phase === 7) {
                let page = test.control("settingsRegionalLoader").item;
                if (page.busy) return;
                if (test.control("regionalTimezone").text !== "Asia/Manila") { test.fail("reopen reset regional draft"); return; }
                page.request({operation: "status"}); test.phase++;
            } else if (test.phase === 8) {
                let page = test.control("settingsRegionalLoader").item;
                if (page.busy || page.dirty) return;
                controller.window.section = -3;
                test.control("lockCommandField").edited("missing-locker"); test.phase++;
            } else if (test.phase === 9) {
                if (controller.window.dirty || !controller.window.manualDirty || prefs.config.locking.command !== "hyprlock") { test.fail("typing autosaved lock command"); return; }
                if (test.control("lockNowButton").enabled) { test.fail("lock test enabled with unapplied command"); return; }
                test.control("lockCommandField").edited("hyprlock");
                controller.window.visible = false; test.phase++;
            } else if (test.phase === 10 && !controller.loaded) {
                console.log("MANUAL_DRAFT_OK"); Qt.quit();
            }
        }
    }
    Timer { interval: 12000; running: true; onTriggered: test.fail("timeout") }
}
