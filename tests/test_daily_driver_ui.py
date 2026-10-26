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
    def test_guide_from_settings_home_completes_and_stays_completed(self):
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
                if (editor.section !== editor.homeSection || !editor.firstRunPending) { test.fail("home or initial guide state"); return; }
                editor.section = -18; test.phase = 10;
            } else if (test.phase === 10 && editor && editor.idle) {
                let complete = test.find(editor.contentItem, "finishWelcomeGuide");
                if (!complete || !complete.enabled) return;
                let build = test.find(editor.contentItem, "hyprshellBuild");
                if (!build || build.text.indexOf("Hyprshell Rolling · ") !== 0) { test.fail("build identity missing"); return; }
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
            env = dict(os.environ, HOME=str(root), HYPRLAND_INSTANCE_SIGNATURE='', XDG_CONFIG_HOME=str(root / 'config'), XDG_STATE_HOME=str(root / 'state'), XDG_RUNTIME_DIR=str(runtime), QT_QPA_PLATFORMTHEME='', QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software')
            result = subprocess.run(['quickshell', '-p', str(entry)], env=env, capture_output=True, text=True, timeout=18)
            output = result.stdout + result.stderr
            self.assertIn(marker, output, output)
            for error in ('DAILY_DRIVER_FAILED', 'ReferenceError', 'TypeError', 'Unable to assign', 'Binding loop'):
                self.assertNotIn(error, output, output)
            self.assertEqual(result.returncode, 0, output)
            if verify: verify(root)

    def test_optional_pages_save_rules_and_release_without_starting_capture(self):
        source = r'''import QtQuick
import Quickshell
import "."
ShellRoot {
    id: test
    property int phase: 0
    SettingsStore { id: prefs }
    SettingsWindow { id: editor; store: prefs }
    ClipboardController { id: clipboard; store: prefs }
    function find(root, name) { if (!root) return null; if (root.objectName === name) return root; for (let child of root.children || []) { let found = find(child, name); if (found) return found; } return null; }
    function fail(message) { console.error("DAILY_DRIVER_FAILED", phase, message); Qt.quit(); }
    Timer { interval: 100; repeat: true; running: true
        onTriggered: {
            if (!prefs.loaded) return;
            if (test.phase === 0) { editor.open(); editor.section = -19; test.phase = 1; return; }
            let add = test.find(editor.contentItem, "addWorkspacePreference");
            if (test.phase === 1 && add && add.enabled) {
                add.clicked(); test.find(editor.contentItem, "addApplicationRule").clicked(); test.phase = 2;
            } else if (test.phase === 2) {
                let field = test.find(editor.contentItem, "ruleClass-0");
                if (!field) return;
                field.text = "org.synthetic.Test"; field.textEdited();
                test.find(editor.contentItem, "saveBehavior").clicked(); test.phase = 3;
            } else if (test.phase === 3 && editor.idle) {
                if (test.find(editor.contentItem, "saveBehavior").enabled) { test.fail("rule save failed"); return; }
                editor.section = -20; test.phase = 4;
            } else if (test.phase === 4 && test.find(editor.contentItem, "showClipboardHistory") && editor.idle) {
                if (prefs.config.clipboard.enabled || clipboard.error) { test.fail("capture enabled"); return; }
                editor.section = -21; test.phase = 5;
            } else if (test.phase === 5 && test.find(editor.contentItem, "refreshPeripherals") && editor.idle) {
                if (test.find(editor.contentItem, "showClipboardHistory") || test.find(editor.contentItem, "addWorkspacePreference")) { test.fail("pages retained"); return; }
                editor.section = -14; test.phase = 6;
            } else if (test.phase === 6 && editor.idle) {
                let checkpoint = test.find(editor.contentItem, "createConfigurationCheckpoint");
                if (!checkpoint || !checkpoint.enabled) return;
                checkpoint.clicked(); test.phase = 7;
            } else if (test.phase === 7 && editor.idle) {
                if (test.find(editor.contentItem, "configurationCheckpointPicker").model.length !== 1 || test.find(editor.contentItem, "runPersonalBackup").enabled) { test.fail("checkpoint or backup defaults"); return; }
                console.log("OPTIONAL_PAGES_NATIVE_OK"); Qt.quit();
            }
        }
    }
    Timer { interval: 14000; running: true; onTriggered: test.fail("timeout") }
}
'''
        def prepare(root, payload):
            main = root / 'config/hypr/hyprland.lua'; main.parent.mkdir(parents=True); main.write_text('-- isolated config\n')
        def verify(root):
            data = json.loads((root / 'config/hyprshell/behavior.json').read_text())
            self.assertEqual(data['workspaces'][0]['id'], 1)
            self.assertEqual(data['rules'][0]['class'], 'org.synthetic.Test')
            self.assertTrue(list((root / 'state/hyprshell/setup-backups').glob('setup-*')))
            self.assertFalse((root / 'state/hyprshell/clipboard/db').exists())
            self.assertFalse((root / 'state/hyprshell/personal-files.json').exists())
        self.run_ui(source, 'OPTIONAL_PAGES_NATIVE_OK', prepare=prepare, verify=verify)

    def test_clipboard_and_battery_supervisors_stop_and_restart_only_when_needed(self):
        source = r'''import QtQuick
import Quickshell
import "."
ShellRoot {
    id: test
    property int phase: 0
    SettingsStore { id: prefs }
    ClipboardController { id: clips; store: prefs }
    LockingController { id: idle; store: prefs }
    function change(group, changes) { let next = JSON.parse(JSON.stringify(prefs.config)); Object.assign(next[group], changes); prefs.config = next; }
    Timer { interval: 450; repeat: true; running: true
        onTriggered: {
            if (!prefs.loaded) return;
            if (test.phase === 0) test.change("clipboard", {enabled: true});
            else if (test.phase === 1) test.change("clipboard", {includeImages: true});
            else if (test.phase === 2) { test.change("clipboard", {enabled: false}); test.change("power", {offMinutes: 5, separateBatteryTimers: true, batteryOffMinutes: 2}); }
            else if (test.phase === 3) idle.onBattery = true;
            else if (test.phase === 4) test.change("bar", {height: 35});
            else if (test.phase === 5) test.change("power", {offMinutes: 0, batteryOffMinutes: 0});
            else {
                if (clips.error || idle.error) console.error("DAILY_DRIVER_FAILED", clips.error, idle.error);
                else console.log("SUPERVISORS_NATIVE_OK");
                Qt.quit();
            }
            test.phase++;
        }
    }
    Timer { interval: 8000; running: true; onTriggered: { console.error("DAILY_DRIVER_FAILED", "timeout"); Qt.quit(); } }
}
'''
        def prepare(root, payload):
            calls = root / 'controller-calls.jsonl'
            script = ('import json, os, signal, sys, time\n'
                      f'calls = {str(calls)!r}\n'
                      'def record(event):\n'
                      '    with open(calls, "a") as output: output.write(json.dumps({"event": event, "pid": os.getpid(), "args": sys.argv[1:]}) + "\\n")\n'
                      'def stop(*args):\n'
                      '    record("stop"); sys.exit(0)\n'
                      'signal.signal(signal.SIGTERM, stop)\n'
                      'record("start")\n'
                      'time.sleep(30)\n')
            (payload / 'settings/backend.py').write_text(script)
            (payload / 'settings/clipboard.py').write_text(script)
        def verify(root):
            rows = [json.loads(line) for line in (root / 'controller-calls.jsonl').read_text().splitlines()]
            starts = [row for row in rows if row['event'] == 'start']
            self.assertEqual([row['args'] for row in starts], [['--watch'], ['--watch'], ['--idle'], ['--idle', '--battery']])
            active = set()
            for row in rows:
                if row['event'] == 'start': active.add(row['pid'])
                else: active.remove(row['pid'])
                self.assertLessEqual(len(active), 1, rows)
            self.assertFalse(active, rows)
        self.run_ui(source, 'SUPERVISORS_NATIVE_OK', prepare=prepare, verify=verify)

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
            } else if (test.phase === 3 && editor.idle && !editor.manualDirty) {
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
