"""Native Settings search reaches headings without loading matched pages."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('quickshell'), 'Native Quickshell is needed')
class SettingsSearchNativeTests(unittest.TestCase):
    def test_heading_subheading_control_and_unopened_page_search(self):
        source = r'''import QtQuick
import QtQuick.Window
import Quickshell
import "."
ShellRoot {
    id: test
    property int phase: 0
    SettingsStore { id: prefs }
    SettingsWindow { id: editor; store: prefs }
    function find(root, name) {
        if (!root) return null;
        if (root.objectName === name) return root;
        for (let child of root.children || []) { let found = find(child, name); if (found) return found; }
        return null;
    }
    function fail(message) { console.error("CAPTION_SEARCH_FAILED", phase, message); Qt.quit(); }
    Timer { interval: 100; repeat: true; running: true; onTriggered: {
        if (!prefs.loaded || !editor.searchIndexLoaded) return;
        if (test.phase === 0) {
            editor.open(); editor.firstRunPending = false; editor.section = -1;
            let pane = test.find(editor.contentItem, "hyprpaneSettingsEditor");
            function shown(name) { return test.find(editor.contentItem, name).visible; }
            if (pane.category !== "layout" || !shown("barPositionControl") || shown("hyprknotsControl")) { test.fail("default category"); return; }
            for (let key of ["spacing", "appearance", "menus", "all"]) {
                test.find(editor.contentItem, "hyprpaneCategory_" + key).clicked();
                if (pane.category !== key) { test.fail("category button " + key); return; }
                if (shown("barPositionControl") !== (key === "all")
                    || shown("centerItemsControl") !== ["spacing", "all"].includes(key)
                    || shown("hyprknotsControl") !== ["appearance", "all"].includes(key)
                    || shown("hoverPopdownsDefaultControl") !== ["menus", "all"].includes(key)) { test.fail("category visibility " + key); return; }
            }
            test.find(editor.contentItem, "hyprpaneCategory_spacing").clicked();
            test.find(editor.contentItem, "hyprpaneItem_0").clicked();
            if (editor.section !== 0 || !editor.barItemsExpanded) { test.fail("item shortcut"); return; }
            test.find(editor.contentItem, "hyprpaneBackToSettings").clicked();
            if (editor.section !== -1 || pane.category !== "spacing") { test.fail("return to category"); return; }
            test.find(editor.contentItem, "hyprpaneCategory_appearance").clicked();
            let search = test.find(editor.contentItem, "settingsSearch");
            if (editor.searchResultIndex !== -1) { test.fail("empty search selected a sidebar result"); return; }
            search.text = "system updates";
            if (editor.searchResultIndex !== 0) { test.fail("search did not select first result"); return; }
            if (!editor.searchResults.some(row => row.section === -14)) { test.fail("missing System updates heading"); return; }
            if (editor.section !== -1) { test.fail("typing navigated"); return; }
            search.accepted(); test.phase++;
        } else if (test.phase === 1) {
            if (editor.section !== -14) { test.fail("Enter did not open Updates & recovery"); return; }
            let search = test.find(editor.contentItem, "settingsSearch"); search.text = "  PoPdOwN   GLASS  ";
            if (!editor.searchResults.some(row => row.section === -1) || !editor.searchResults.some(row => row.section >= 0)) { test.fail("missing global/item Popdown glass subheading"); return; }
            search.accepted(); test.phase++;
        } else if (test.phase === 2) {
            if (editor.section !== -1) { test.fail("Enter did not open Hyprpane"); return; }
            let search = test.find(editor.contentItem, "settingsSearch");
            search.text = "hyprpane thickness";
            if (!test.find(editor.contentItem, "heightControl").visible) { test.fail("search hid another category"); return; }
            search.clear();
            if (!test.find(editor.contentItem, "hyprknotsControl").visible || test.find(editor.contentItem, "heightControl").visible) { test.fail("search did not restore category"); return; }
            search.text = "hyprpane thickness";
            let thickness = test.find(editor.contentItem, "heightControl");
            let card = thickness;
            while(card && card.settingsSectionCard !== true) card=card.parent;
            if(!card || !card.collapsible || !card.contentExpanded) { test.fail("search did not reveal its folded section"); return; }
            if (!editor.searchResults.some(row => row.section === -1)) { test.fail("model-defined control label missing"); return; }
            let loader = test.find(editor.contentItem, "settingsSetupBackupLoader");
            if (loader.active) { test.fail("backup page already loaded"); return; }
            search.text = "Hyprshell setup backup & restore";
            if (!editor.searchResults.some(row => row.section === -23) || loader.active) { test.fail("unopened page heading missing or activated"); return; }
            search.clear();
            if (editor.searchResultIndex !== -1) { test.fail("clearing search retained result selection"); return; }
            search.text = "   ";
            if (editor.searchResultIndex !== -1) { test.fail("blank search selected a sidebar result"); return; }
            test.phase++;
        } else if (test.phase === 3) {
            if (editor.searchResultIndex !== -1) { test.fail("deferred search selected a result after clearing"); return; }
            let search = test.find(editor.contentItem, "settingsSearch");
            search.text = "hyprpane thickness";
            if (editor.searchResultIndex !== 0) { test.fail("matching search did not select first result"); return; }
            search.text = "zzzz-no-matching-setting-zzzz";
            if (editor.searchResults.length !== 0 || editor.searchResultIndex !== -1) { test.fail("unmatched search retained result selection"); return; }
            let section = editor.section;
            search.accepted();
            if (editor.section !== section) { test.fail("Enter on unmatched search navigated"); return; }
            test.phase++;
        } else if (test.phase === 4) {
            if (editor.searchResultIndex !== -1) { test.fail("deferred search selected an unmatched result"); return; }
            let search = test.find(editor.contentItem, "settingsSearch");
            search.text = "desktop";
            if (editor.searchResults.some(row => row.section === -19)) { test.fail("desktop matched workspace explanatory copy"); return; }
            search.text = "default tiling layout";
            if (!editor.searchResults.some(row => row.section === -19) || editor.searchResultIndex !== 0) { test.fail("actual workspace setting did not match"); return; }
            if (editor.dirty || editor.saving) { test.fail("search changed preferences"); return; }
            search.clear(); editor.section = -1;
            editor.contentItem.Window.window.width = 720;
            test.phase++;
        } else if (test.phase === 5 || test.phase === 6) {
            let pane = test.find(editor.contentItem, "hyprpaneSettingsEditor");
            for (let key of ["layout", "spacing", "appearance", "menus", "all"]) {
                let button = test.find(editor.contentItem, "hyprpaneCategory_" + key);
                if (button.x < 0 || button.x + button.width > pane.width + 1) { test.fail("category overflow"); return; }
            }
            if (test.phase === 5) { editor.contentItem.Window.window.width = 1280; test.phase++; return; }
            if (editor.dirty || editor.saving) { test.fail("category navigation changed preferences"); return; }
            console.log("CAPTION_SEARCH_OK"); Qt.quit();
        }
    } }
    Timer { interval: 10000; running: true; onTriggered: test.fail("timeout") }
}
'''
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); payload = root / 'config/quickshell'
            shutil.copytree(ROOT / 'config/quickshell', payload, ignore=shutil.ignore_patterns('__pycache__', 'audio-spectrum'))
            runtime = root / 'runtime'; runtime.mkdir(mode=0o700)
            entry = payload / 'CaptionSearchNative.qml'; entry.write_text(source)
            env = dict(os.environ, HOME=str(root), XDG_CONFIG_HOME=str(root / 'config'),
                       XDG_STATE_HOME=str(root / 'state'), XDG_RUNTIME_DIR=str(runtime),
                       HYPRLAND_INSTANCE_SIGNATURE='', QT_QPA_PLATFORMTHEME='',
                       QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software')
            result = subprocess.run(['quickshell', '--log-rules', 'qml=true', '-p', str(entry)],
                                    env=env, capture_output=True, text=True, timeout=15)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn('CAPTION_SEARCH_OK', output, output)
            for error in ('CAPTION_SEARCH_FAILED', 'ReferenceError', 'TypeError', 'Binding loop', 'Unable to assign'):
                self.assertNotIn(error, output, output)
            self.assertFalse((root / 'config/hyprshell/settings.json').exists())


if __name__ == '__main__': unittest.main()
