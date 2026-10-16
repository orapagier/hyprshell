import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import ".."

ShellRoot {
    id: test
    property int phase: 0
    property int sizeIndex: 0
    readonly property var widths: [720, 900, 1280]
    SettingsStore { id: prefs }
    SettingsWindow { id: editor; store: prefs }
    Item {
        parent: editor.contentItem
        TestEvent { id: keyboard }
    }
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
    function cards(item, result) {
        if (!item.visible) return result;
        if (item.settingsSectionCard === true) result.push(item);
        for (let child of item.children || []) cards(child, result);
        return result;
    }
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
                let sections=test.cards(editor.contentItem,[]);
                if(sections.length<3 || sections.some(card => !card.collapsible || card.contentExpanded)) { test.fail("settings sections did not start collapsed"); return; }
                let search = test.control("settingsSearch");
                if (!search.activeFocus) { test.fail("search did not receive focus on open"); return; }
                search.text = "keyboard";
                if (editor.searchResults.length < 2 || !editor.searchResults.some(page => page.section === -9) || !editor.searchResults.some(page => page.section === -6)) { test.fail("keyword search lost a destination"); return; }
                if (editor.searchResultIndex !== 0 || !test.control("settingsNav-9").keyboardSelected) { test.fail("first match was not automatically selected"); return; }
                keyboard.keyClick(Qt.Key_Down, Qt.NoModifier, 0);
                if (editor.searchResultIndex !== 1 || !search.activeFocus) { test.fail("Down did not select next match while retaining search focus"); return; }
                keyboard.keyClick(Qt.Key_Return, Qt.NoModifier, 0);
                if (editor.section !== -6) { test.fail("Enter ignored selected match"); return; }
                keyboard.keyClick(Qt.Key_Up, Qt.NoModifier, 0);
                if (editor.searchResultIndex !== 0) { test.fail("Up did not return to first match"); return; }
                keyboard.keyClick(Qt.Key_Return, Qt.NoModifier, 0);
                if (editor.section !== -9) { test.fail("Enter did not select first search result"); return; }
                test.phase = 2;
            } else if (test.phase === 2) {
                if (test.control("settingsPageTitle").text !== "Mouse & keyboard") { test.fail("page title does not match navigation"); return; }
                test.control("settingsSearch").text = "no-such-preference";
                test.phase = 3;
            } else if (test.phase === 3) {
                if (editor.searchResultIndex !== -1 || editor.searchResults.length || !test.control("settingsSearchEmpty").visible) { test.fail("missing empty search feedback"); return; }
                test.control("settingsSearchClear").clicked();
                if (editor.searchQuery) { test.fail("clear button did not clear search"); return; }
                editor.section = -2;
                test.phase = 4;
            } else if (test.phase === 4) {
                // A user opens sections before scrolling through their controls.
                for(let card of test.cards(editor.contentItem,[])) card.expanded=true;
                test.phase = 12;
            } else if (test.phase === 12) {
                test.control("settingsEditorScroll").contentItem.contentY = 180;
                editor.section = -1;
                test.phase = 5;
            } else if (test.phase === 5) {
                let sections=test.cards(editor.contentItem,[]);
                for(let name of ["Hyprbar","Hyprdock"]) {
                    let card=sections.find(card => card.title===name);
                    if(!card || !card.collapsible || card.contentExpanded) { test.fail(name+" should start folded"); return; }
                }
                if (!test.control("settingsBarPreview").visible) { test.fail("bar preview missing on bar page"); return; }
                editor.section = -2;
                test.phase = 6;
            } else if (test.phase === 6) {
                if (Math.abs(test.control("settingsEditorScroll").contentItem.contentY - 180) > 1) { test.fail("page scroll position was lost"); return; }
                if (test.control("settingsBarPreview").visible) { test.fail("bar preview leaked into unrelated page"); return; }
                editor.section = editor.draft.items.findIndex(item => item.id === "audio");
                if (!editor.barItemsExpanded) { test.fail("selecting preview item did not reveal navigation"); return; }
                test.control("settingsSearch").text = "bluetooth";
                if (!editor.searchResults.some(page => page.section >= 0 && page.title === "Bluetooth")) { test.fail("bar items missing from search"); return; }
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
                test.control("settingsSearch").text = "keyboard";
                test.control("settingsSearchClear").forceActiveFocus();
                editor.open();
                test.phase = 9;
            } else if (test.phase === 9) {
                let search = test.control("settingsSearch");
                if (!search.activeFocus || search.selectedText !== "keyboard") { test.fail("existing window did not focus and select search"); return; }
                test.control("settingsSearchClear").forceActiveFocus();
                editor.contentItem.Window.window.close();
                test.phase = 10;
            } else if (test.phase === 10) {
                editor.open();
                test.phase = 11;
            } else if (test.phase === 11) {
                let search = test.control("settingsSearch");
                if (!search.activeFocus || search.selectedText !== "keyboard") { test.fail("reopened window did not focus and select search"); return; }
                console.log("NAVIGATION_OK"); Qt.quit();
            }
        }
    }
    Timer { interval: 12000; running: true; onTriggered: test.fail("timeout") }
}
