"""Native cleanup UI exercises an isolated home; no administrator jobs run."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('quickshell'), 'Native Quickshell is needed')
class CleanupNativeTests(unittest.TestCase):
    def test_cancelled_administrator_authentication_keeps_preview_unconfirmed(self):
        source = '''import QtQuick
import Quickshell
import "."
ShellRoot {
    id: test
    property bool requested: false
    SettingsCleanupTargets { id: page; administrator: true; width: 600 }
    Timer { interval: 100; running: true; repeat: true; onTriggered: {
        if (!page.loaded || page.busy) return;
        if (!test.requested) { page.toggle("journals", true); page.request("preview"); test.requested = true; }
        else if (page.message) {
            if (page.preview !== null || page.success || page.actionable) console.error("AUTH_NATIVE_FAILED");
            else console.log("AUTH_NATIVE_OK");
            Qt.quit();
        }
    } }
    Timer { interval: 8000; running: true; onTriggered: { console.error("AUTH_NATIVE_FAILED timeout"); Qt.quit(); } }
}
'''
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); payload = root / 'config/quickshell'
            shutil.copytree(ROOT / 'config/quickshell', payload, ignore=shutil.ignore_patterns('__pycache__', 'audio-spectrum'))
            fake_bin = root / 'bin'; fake_bin.mkdir()
            pkexec = fake_bin / 'pkexec'; pkexec.write_text('#!/bin/sh\nexit 126\n'); pkexec.chmod(0o755)
            runtime = root / 'runtime'; runtime.mkdir(mode=0o700)
            entry = payload / 'AuthNative.qml'; entry.write_text(source)
            env = dict(os.environ, HOME=str(root), PATH=str(fake_bin) + os.pathsep + os.environ['PATH'],
                XDG_CONFIG_HOME=str(root / 'config'), XDG_STATE_HOME=str(root / 'state'),
                XDG_RUNTIME_DIR=str(runtime), HYPRLAND_INSTANCE_SIGNATURE='', QT_QPA_PLATFORMTHEME='',
                QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software')
            done = subprocess.run(['quickshell', '--log-rules', 'qml=true', '-p', str(entry)],
                env=env, capture_output=True, text=True, timeout=12)
            output = done.stdout + done.stderr
            self.assertEqual(done.returncode, 0, output)
            self.assertIn('AUTH_NATIVE_OK', output, output)
            self.assertNotIn('AUTH_NATIVE_FAILED', output, output)
            self.assertFalse((root / 'state/hyprshell/system-cleanup-preview.json').exists())

    def test_categories_preview_exclusions_reset_and_factory_explanation(self):
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
    function fail(message) { console.error("CLEANUP_NATIVE_FAILED", phase, message); Qt.quit(); }
    Timer { interval: 100; repeat: true; running: true
        onTriggered: {
            if (!prefs.loaded) return;
            if (test.phase === 0) { editor.open(); editor.firstRunPending = false; editor.section = -4; test.phase++; return; }
            let manual = test.find(editor.contentItem, "manualCleanupTargets");
            let admin = test.find(editor.contentItem, "administratorCleanupTargets");
            if (!manual || !admin || manual.busy || admin.busy || !manual.loaded || !admin.loaded) return;
            if (test.phase === 1) {
                if (manual.selected.length || admin.selected.length) { test.fail("categories preselected"); return; }
                if (manual.days !== 0 || admin.days !== 7) { test.fail("manual and system age defaults"); return; }
                manual.toggle("thumbnails", true);
                manual.request("preview"); test.phase++;
            } else if (test.phase === 2 && manual.preview) {
                if (manual.preview.totalFiles !== 2 || manual.fileEntries.length !== 2) { test.fail("file preview"); return; }
                manual.excluded = [manual.fileEntries[1].path]; manual.request("clean"); test.phase++;
            } else if (test.phase === 3 && !manual.preview && manual.message.indexOf("Removed 1") >= 0) {
                let preview = test.find(editor.contentItem, "previewSettingsReset");
                if (!preview || !preview.enabled) return;
                preview.clicked(); test.phase++;
            } else if (test.phase === 4) {
                let field = test.find(editor.contentItem, "settingsResetConfirmation");
                let confirm = test.find(editor.contentItem, "confirmSettingsReset");
                if (!field || !field.visible || !confirm) return;
                if (confirm.enabled) { test.fail("reset enabled without phrase"); return; }
                field.text = "RESET"; test.phase++;
            } else if (test.phase === 5) {
                let confirm = test.find(editor.contentItem, "confirmSettingsReset");
                if (!confirm.enabled) return;
                confirm.clicked(); test.phase++;
            } else if (test.phase === 6 && editor.idle && prefs.config.bar.position === "top") {
                let picker = test.find(editor.contentItem, "factoryResetScope");
                picker.currentIndex = 1; picker.activated(1); test.phase++;
            } else if (test.phase === 7) {
                if (test.find(editor.contentItem, "previewSettingsReset").visible || admin.selected.length) { test.fail("reinstall exposed reset action or selected system jobs"); return; }
                console.log("CLEANUP_NATIVE_OK"); Qt.quit();
            }
        }
    }
    Timer { interval: 18000; running: true; onTriggered: test.fail("timeout") }
}
'''
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            payload = root / '.config/quickshell'
            shutil.copytree(ROOT / 'config/quickshell', payload, ignore=shutil.ignore_patterns('__pycache__', 'audio-spectrum'))
            # Existing scheduler status must not query the real user manager.
            (payload / 'settings/cleanup.py').write_text((payload / 'settings/cleanup.py').read_text().replace(
                "return subprocess.run(args, capture_output=True, text=True, timeout=20)",
                "return subprocess.CompletedProcess(args, 0, 'inactive\\n', '')"))
            data = json.loads((payload / 'settings/defaults.json').read_text()); data['bar']['position'] = 'bottom'
            config = root / '.config/hyprshell/settings.json'; config.parent.mkdir(parents=True)
            config.write_text(json.dumps(data))
            cache = root / '.cache/thumbnails'; cache.mkdir(parents=True)
            (cache / 'one').write_text('synthetic 1'); (cache / 'two').write_text('synthetic 2')
            runtime = root / 'runtime'; runtime.mkdir(mode=0o700)
            entry = payload / 'CleanupNative.qml'; entry.write_text(source)
            env = dict(os.environ, HOME=str(root), XDG_CONFIG_HOME=str(root / '.config'),
                XDG_CACHE_HOME=str(root / '.cache'), XDG_STATE_HOME=str(root / '.local/state'),
                XDG_RUNTIME_DIR=str(runtime), HYPRLAND_INSTANCE_SIGNATURE='', QT_QPA_PLATFORMTHEME='',
                QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software')
            done = subprocess.run(['quickshell', '--log-rules', 'qml=true', '-p', str(entry)], env=env, capture_output=True, text=True, timeout=22)
            output = done.stdout + done.stderr
            self.assertEqual(done.returncode, 0, output)
            self.assertIn('CLEANUP_NATIVE_OK', output, output)
            self.assertEqual(done.returncode, 0, output)
            for error in ('CLEANUP_NATIVE_FAILED', 'ReferenceError', 'TypeError', 'Binding loop', 'Unable to assign'):
                self.assertNotIn(error, output, output)
            self.assertFalse((cache / 'one').exists()); self.assertTrue((cache / 'two').exists())
            self.assertEqual(json.loads(config.read_text())['bar']['position'], 'top')
            checkpoints = list((root / '.local/state/hyprshell/backups').glob('recovery-*/settings.json'))
            self.assertEqual(len(checkpoints), 1)
            self.assertEqual(json.loads(checkpoints[0].read_text())['bar']['position'], 'bottom')


if __name__ == '__main__': unittest.main()
