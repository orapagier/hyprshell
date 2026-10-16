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
            if (editor.section !== -1) { test.fail("Enter did not open Bar & layout"); return; }
            let search = test.find(editor.contentItem, "settingsSearch");
            search.text = "bar thickness";
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
            if (editor.dirty || editor.saving) { test.fail("search changed preferences"); return; }
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
