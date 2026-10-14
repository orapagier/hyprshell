"""Select and restore dated setup backups through native Settings in a fake home."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('quickshell'), 'Native Quickshell is needed')
class SetupBackupNativeTests(unittest.TestCase):
    def test_dated_backup_picker_refresh_selection_and_restore_with_undo(self):
        source = r'''import QtQuick
import Quickshell
import Quickshell.Io
import "."
ShellRoot {
    id: test
    property int phase: 0
    property string firstBackup: ""
    SettingsStore { id: prefs }
    SettingsWindow { id: editor; store: prefs }
    Process {
        id: changeConfiguration
        command: ["python3", "-c", "from pathlib import Path; import os; (Path(os.environ['XDG_CONFIG_HOME'])/'hypr/hyprland.lua').write_text('-- second saved setup\\n')"]
    }
    function find(root, name) {
        if (!root) return null;
        if (root.objectName === name) return root;
        for (let child of root.children || []) { let found = find(child, name); if (found) return found; }
        return null;
    }
    function fail(message) { console.error("SETUP_BACKUP_FAILED", phase, message); Qt.quit(); }
    Timer {
        interval: 100; repeat: true; running: true
        onTriggered: {
            if (!prefs.loaded) return;
            if (test.phase === 0) { editor.open(); editor.firstRunPending = false; editor.section = -23; test.phase++; return; }
            let loader = test.find(editor.contentItem, "settingsSetupBackupLoader");
            let page = loader ? loader.item : null;
            if (!page || page.busy || !page.loaded || !page.ready) return;
            let picker = test.find(page, "configurationCheckpointPicker");
            if (test.phase === 1) {
                if (page.checkpoints.length) { test.fail("unexpected initial backups"); return; }
                test.find(page, "createConfigurationCheckpoint").clicked(); test.phase++;
            } else if (test.phase === 2 && page.checkpoints.length === 1) {
                let row = page.checkpoints[0];
                if (!/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}/.test(row.label) || row.label.indexOf("UTC") < 0) { test.fail("date/time missing"); return; }
                test.firstBackup = row.id; changeConfiguration.running = true; test.phase++;
            } else if (test.phase === 3 && !changeConfiguration.running) {
                page.request("status"); test.phase++;
            } else if (test.phase === 4) {
                test.find(page, "createConfigurationCheckpoint").clicked(); test.phase++;
            } else if (test.phase === 5 && page.checkpoints.length === 2) {
                let index = page.checkpoints.findIndex(row => row.id === test.firstBackup);
                picker.currentIndex = index; picker.activated(index);
                test.find(page, "refreshSetupBackups").clicked(); test.phase++;
            } else if (test.phase === 6) {
                if (page.selectedId !== test.firstBackup) { test.fail("refresh changed selected backup"); return; }
                test.find(page, "previewConfigurationRestore").clicked(); test.phase++;
            } else if (test.phase === 7 && page.preview) {
                if (page.preview.id !== test.firstBackup || page.preview.changes.indexOf("hypr/hyprland.lua") < 0) { test.fail("wrong restore preview"); return; }
                picker.currentIndex = 0; picker.activated(0);
                if (page.preview !== null) { test.fail("selection kept old restore confirmation"); return; }
                let index = page.checkpoints.findIndex(row => row.id === test.firstBackup);
                picker.currentIndex = index; picker.activated(index);
                test.find(page, "previewConfigurationRestore").clicked(); test.phase++;
            } else if (test.phase === 8 && page.preview) {
                let confirm = test.find(page, "confirmConfigurationRestore");
                if (!confirm.enabled) { test.fail("restore unavailable"); return; }
                confirm.clicked(); test.phase++;
            } else if (test.phase === 9 && page.checkpoints.length === 3) {
                if (!page.checkpoints.some(row => row.kind === "before-restore") || page.message.indexOf("restored from") < 0) { test.fail("missing dated undo backup"); return; }
                console.log("SETUP_BACKUP_OK"); Qt.quit();
            }
        }
    }
    Timer { interval: 15000; running: true; onTriggered: test.fail("timeout") }
}
'''
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary); payload = root / '.config/quickshell'
            shutil.copytree(ROOT / 'config/quickshell', payload,
                            ignore=shutil.ignore_patterns('__pycache__', 'audio-spectrum'))
            config = root / '.config/hyprshell/settings.json'; config.parent.mkdir(parents=True)
            config.write_text((payload / 'settings/defaults.json').read_text())
            main = root / '.config/hypr/hyprland.lua'; main.parent.mkdir()
            main.write_text('-- first saved setup\n')
            runtime = root / 'runtime'; runtime.mkdir(mode=0o700)
            entry = payload / 'SetupBackupNative.qml'; entry.write_text(source)
            env = dict(os.environ, HOME=str(root), XDG_CONFIG_HOME=str(root / '.config'),
                       XDG_STATE_HOME=str(root / '.local/state'), XDG_RUNTIME_DIR=str(runtime),
                       HYPRLAND_INSTANCE_SIGNATURE='', QT_QPA_PLATFORMTHEME='',
                       QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software')
            result = subprocess.run(['quickshell', '--log-rules', 'qml=true', '-p', str(entry)],
                                    env=env, capture_output=True, text=True, timeout=20)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn('SETUP_BACKUP_OK', output, output)
            for error in ('SETUP_BACKUP_FAILED', 'ReferenceError', 'TypeError', 'Binding loop', 'Unable to assign'):
                self.assertNotIn(error, output, output)
            self.assertEqual(main.read_text(), '-- first saved setup\n')
            backups = root / '.local/state/hyprshell/setup-backups'
            metadata = [json.loads(path.read_text()) for path in backups.glob('setup-*/metadata.json')]
            self.assertEqual(len(metadata), 3)
            self.assertEqual(sum(row['kind'] == 'before-restore' for row in metadata), 1)
            undo = next(path.parent for path in backups.glob('setup-*/metadata.json')
                        if json.loads(path.read_text())['kind'] == 'before-restore')
            self.assertEqual(json.loads((undo / 'files.json').read_text())['hypr/hyprland.lua'], '-- second saved setup\n')


if __name__ == '__main__': unittest.main()
