import QtQuick
import QtQuick.Window
import Quickshell
import ".."

ShellRoot {
    id: test
    property int phase: 0
    property int sizeIndex: 0
    readonly property var widths: [720, 900, 1280]
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
    function control(name) { return find(editor.contentItem, name, []); }
    function fail(message) { console.error("NAVIGATION_FAILED", phase, message); Qt.quit(); }
    Timer {
        interval: 120; running: true; repeat: true
        onTriggered: {
            if (!prefs.loaded) return;
            if (test.phase === 0) {
                editor.open(); editor.section = -2;
                editor.contentItem.Window.window.width = 1180;
                editor.contentItem.Window.window.height = 810;
                test.phase = 1;
            } else if (test.phase === 1) {
                let search = test.control("settingsSearch");
                search.text = "keyboard";
                if (editor.searchResults.length !== 2) { test.fail("keyword search lost a destination"); return; }
                search.accepted();
                if (editor.section !== -9) { test.fail("Enter did not select first search result"); return; }
                test.phase = 2;
            } else if (test.phase === 2) {
                if (test.control("settingsPageTitle").text !== "Mouse & keyboard") { test.fail("page title does not match navigation"); return; }
                test.control("settingsSearch").text = "no-such-preference";
                test.phase = 3;
            } else if (test.phase === 3) {
                if (editor.searchResults.length || !test.control("settingsSearchEmpty").visible) { test.fail("missing empty search feedback"); return; }
                test.control("settingsSearchClear").clicked();
                if (editor.searchQuery) { test.fail("clear button did not clear search"); return; }
                editor.section = -2;
                test.phase = 4;
            } else if (test.phase === 4) {
                test.control("settingsEditorScroll").contentItem.contentY = 180;
                editor.section = -1;
                test.phase = 5;
            } else if (test.phase === 5) {
                if (!test.control("settingsBarPreview").visible) { test.fail("bar preview missing on bar page"); return; }
                editor.section = -2;
                test.phase = 6;
            } else if (test.phase === 6) {
                if (Math.abs(test.control("settingsEditorScroll").contentItem.contentY - 180) > 1) { test.fail("page scroll position was lost"); return; }
                if (test.control("settingsBarPreview").visible) { test.fail("bar preview leaked into unrelated page"); return; }
                editor.section = editor.draft.items.findIndex(item => item.id === "audio");
                if (!editor.barItemsExpanded) { test.fail("selecting preview item did not reveal navigation"); return; }
                test.control("settingsSearch").text = "bluetooth";
                if (editor.searchResults.length !== 1 || editor.searchResults[0].section < 0) { test.fail("bar items missing from search"); return; }
                test.control("settingsSearchClear").clicked();
                editor.section = -2;
                test.phase = 7;
            } else if (test.phase === 7) {
                editor.contentItem.Window.window.width = test.widths[test.sizeIndex];
                test.phase = 8;
            } else if (test.phase === 8) {
                let page = test.control("settingsPageContent");
                let scroll = test.control("settingsEditorScroll");
                if (page.width > scroll.availableWidth + 1) { test.fail("horizontal page overflow at " + editor.width); return; }
                for (let child of page.children) {
                    if (child.visible && (child.x < -1 || child.x + child.width > page.width + 1)) { test.fail("clipped page child at " + editor.width); return; }
                }
                if (++test.sizeIndex < test.widths.length) { test.phase = 7; return; }
                if (editor.dirty || editor.saving || JSON.stringify(editor.draft) !== JSON.stringify(editor.initial)) { test.fail("navigation changed saved preferences"); return; }
                console.log("NAVIGATION_OK"); Qt.quit();
            }
        }
    }
    Timer { interval: 12000; running: true; onTriggered: test.fail("timeout") }
}
