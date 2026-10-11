"""Native on-demand daily-driver controls without changing the live desktop."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('quickshell'), 'Native Quickshell is needed')
class DailyDriverNativeTests(unittest.TestCase):
    def test_first_run_guide_completes_and_does_not_return_on_reopen(self):
        source = '''import QtQuick
import Quickshell
import "."
ShellRoot {
    id: test
    property int phase: 0
    SettingsStore { id: prefs }
    SettingsController { id: controller; store: prefs }
    function find(root, name) { if (!root) return null; if (root.objectName === name) return root; for (let child of root.children || []) { let found = find(child, name); if (found) return found; } return null; }
    function fail(message) { console.error("DAILY_DRIVER_FAILED", phase, message); Qt.quit(); }
    Timer { interval: 100; repeat: true; running: true
        onTriggered: {
            if (!prefs.loaded) return;
            if (test.phase === 0) { controller.open(); test.phase = 1; return; }
            let editor = controller.window;
            if (test.phase === 1 && editor && editor.idle) {
                if (editor.section !== -18) { test.fail("first-run page"); return; }
                let complete = test.find(editor.contentItem, "finishWelcomeGuide");
                if (!complete || !complete.enabled) return;
                complete.clicked(); test.phase = 2;
            } else if (test.phase === 2 && editor && editor.idle && !editor.firstRunPending) {
                editor.visible = false; test.phase = 3;
            } else if (test.phase === 3 && !controller.loaded) {
                controller.open(); test.phase = 4;
            } else if (test.phase === 4 && editor && editor.idle) {
                if (editor.firstRunPending || editor.section === -18 || editor.dirty) { test.fail("guide repeated"); return; }
                console.log("WELCOME_NATIVE_OK"); Qt.quit();
            }
        }
    }
    Timer { interval: 14000; running: true; onTriggered: test.fail("timeout") }
}
'''
        def verify(root):
            self.assertTrue(json.loads((root / 'state/hyprshell/welcome.json').read_text())['completed'])
            self.assertFalse((root / 'config/hyprshell/settings.json').exists())
        self.run_ui(source, 'WELCOME_NATIVE_OK', verify=verify)
    def run_ui(self, source, marker, prepare=None, verify=None):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); payload = root / 'config/quickshell'
            shutil.copytree(ROOT / 'config/quickshell', payload, ignore=shutil.ignore_patterns('__pycache__', 'audio-spectrum'))
            if prepare: prepare(root, payload)
            entry = payload / 'DailyDriverNative.qml'; entry.write_text(source)
            runtime = root / 'runtime'; runtime.mkdir(mode=0o700)
            env = dict(os.environ, HYPRLAND_INSTANCE_SIGNATURE='', XDG_CONFIG_HOME=str(root / 'config'), XDG_STATE_HOME=str(root / 'state'), XDG_RUNTIME_DIR=str(runtime), QT_QPA_PLATFORMTHEME='', QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software')
            result = subprocess.run(['quickshell', '-p', str(entry)], env=env, capture_output=True, text=True, timeout=18)
            output = result.stdout + result.stderr
            self.assertIn(marker, output, output)
            for error in ('DAILY_DRIVER_FAILED', 'ReferenceError', 'TypeError', 'Unable to assign', 'Binding loop'):
                self.assertNotIn(error, output, output)
            self.assertEqual(result.returncode, 0, output)
            if verify: verify(root)

    def test_regional_preview_save_and_lazy_release(self):
        source = '''import QtQuick
import Quickshell
import "."
ShellRoot {
    id: test
    property int phase: 0
    SettingsStore { id: prefs }
    SettingsWindow { id: editor; store: prefs }
    function find(root, name) { if (!root) return null; if (root.objectName === name) return root; for (let child of root.children || []) { let found = find(child, name); if (found) return found; } return null; }
    function fail(message) { console.error("DAILY_DRIVER_FAILED", phase, message); Qt.quit(); }
    Timer { interval: 100; repeat: true; running: true
        onTriggered: {
            if (!prefs.loaded) return;
            if (test.phase === 0) { editor.open(); editor.section = -17; test.phase = 1; return; }
            let page = test.find(editor.contentItem, "regionalTimezone");
            if (test.phase === 1 && page && page.enabled) {
                page.text = "UTC"; test.find(editor.contentItem, "previewRegional").clicked(); test.phase = 2;
            } else if (test.phase === 2 && test.find(editor.contentItem, "saveRegional").enabled) {
                test.find(editor.contentItem, "saveRegional").clicked(); test.phase = 3;
            } else if (test.phase === 3 && test.find(editor.contentItem, "saveRegional").enabled) {
                if (editor.dirty || editor.saving) { test.fail("changed unrelated Settings"); return; }
                editor.section = -2; test.phase = 4;
            } else if (test.phase === 4) {
                if (test.find(editor.contentItem, "regionalTimezone")) { test.fail("page retained"); return; }
                console.log("REGIONAL_NATIVE_OK"); Qt.quit();
            }
        }
    }
    Timer { interval: 14000; running: true; onTriggered: test.fail("timeout") }
}
'''
        def verify(root):
            self.assertEqual(json.loads((root / 'config/hyprshell/regional.json').read_text())['timezone'], 'UTC')
            self.assertIn('export TZ=UTC', (root / 'config/uwsm/env-hyprland').read_text())
            self.assertFalse((root / 'config/hyprshell/settings.json').exists())
        self.run_ui(source, 'REGIONAL_NATIVE_OK', verify=verify)


if __name__ == '__main__':
    unittest.main()
