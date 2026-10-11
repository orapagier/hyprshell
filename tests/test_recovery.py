"""Recovery transactions and update workflows isolated from the real desktop."""
import copy
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import MagicMock, patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'config/quickshell/settings'))
import backend
import recovery


class RecoveryTests(unittest.TestCase):
    def setUp(self):
        distro = patch.object(recovery.system_packages, 'distribution', return_value='arch')
        distro.start(); self.addCleanup(distro.stop)
        temporary = tempfile.TemporaryDirectory(); self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.config = self.root / 'config'
        self.state = self.root / 'state/hyprshell'
        env = patch.dict(os.environ, XDG_CONFIG_HOME=str(self.config), XDG_STATE_HOME=str(self.root / 'state'), HYPRLAND_INSTANCE_SIGNATURE='')
        env.start(); self.addCleanup(env.stop)
        self.target = self.config / 'hyprshell/settings.json'
        self.target.parent.mkdir(parents=True)
        self.target.write_text(json.dumps(backend.DEFAULTS))
        main = self.config / 'hypr/hyprland.lua'
        main.parent.mkdir(); main.write_text('-- original Lua\n')

    def changed(self):
        data = copy.deepcopy(backend.DEFAULTS)
        data['bar']['height'] = 40
        data['hyprland']['pointerSpeed'] = 0.4
        return data

    def checkpoint(self):
        return recovery.checkpoint(recovery.revision())

    def test_checkpoint_preview_restore_uses_transaction_and_keeps_undo(self):
        ident = self.checkpoint()
        self.assertEqual(len(recovery.backups()), 1)
        backend.save(self.changed())
        self.assertEqual(len(recovery.backups()), 2)
        preview = recovery.preview(ident)
        self.assertEqual(preview['changes'], ['Bar & layout', 'Compositor, mouse & keyboard'])
        result = recovery.request({'operation': 'restore', 'token': preview['token']})
        self.assertEqual(result['restored'], backend.DEFAULTS)
        self.assertIn('hl.config', (self.config / 'hyprshell/overrides.lua').read_text())
        self.assertEqual(len(recovery.backups()), 3)
        self.assertFalse((self.state / 'recovery-preview.json').exists())
        undo = next(row['id'] for row in recovery.backups() if row['id'].startswith('settings-') and recovery.snapshot(row['id']) == self.changed())
        recovery.restore(recovery.preview(undo)['token'])
        self.assertEqual(recovery.current(), self.changed())

    def test_existing_transaction_backup_imports_only_json_and_never_old_lua(self):
        backend.save(self.changed())
        ident = recovery.backups()[0]['id']
        manifest = json.loads((self.state / 'backups' / ident / 'manifest.json').read_text())
        for entry in manifest:
            if entry['path'].endswith('.lua') and entry['existed']:
                (self.state / 'backups' / ident / entry['file']).write_text('error("unsafe backup")')
        recovery.restore(recovery.preview(ident)['token'])
        self.assertEqual(recovery.current(), backend.DEFAULTS)
        self.assertNotIn('unsafe backup', (self.config / 'hypr/hyprland.lua').read_text())

    def test_backup_traversal_and_symlinks_are_rejected(self):
        ident = self.checkpoint()
        path = self.state / 'backups' / ident / 'settings.json'
        for name in ('../settings-secret', 'settings-../../secret', '/tmp/recovery-secret'):
            with self.assertRaises(ValueError): recovery.snapshot(name)
        path.unlink(); path.symlink_to(self.target)
        with self.assertRaises(ValueError): recovery.snapshot(ident)
        self.assertEqual(recovery.backups(), [])

    def test_manifest_cannot_redirect_to_an_unrelated_file(self):
        backend.save(self.changed())
        ident = recovery.backups()[0]['id']
        path = self.state / 'backups' / ident / 'manifest.json'
        path.write_text(json.dumps([{'path': str(self.target), 'existed': True, 'file': '../../private'}]))
        with self.assertRaises(ValueError): recovery.preview(ident)
        self.assertEqual(recovery.current(), self.changed())

    def test_stale_settings_generated_file_expiry_token_and_snapshot_rejected(self):
        ident = self.checkpoint()
        backend.save(self.changed())
        preview = recovery.preview(ident)
        with self.assertRaises(ValueError): recovery.restore('invalid')
        self.target.write_text(json.dumps(backend.DEFAULTS))
        with self.assertRaisesRegex(ValueError, 'changed elsewhere'): recovery.restore(preview['token'])
        preview = recovery.preview(ident)
        (self.config / 'hyprshell/overrides.lua').write_text('-- manual edit\n')
        with self.assertRaisesRegex(ValueError, 'changed elsewhere'): recovery.restore(preview['token'])
        preview = recovery.preview(ident)
        with patch.object(recovery.time, 'time', return_value=0):
            with self.assertRaisesRegex(ValueError, 'expired'): recovery.restore(preview['token'])
        preview = recovery.preview(ident)
        (self.state / 'backups' / ident / 'settings.json').write_text(json.dumps(self.changed()))
        with self.assertRaisesRegex(ValueError, 'backup changed'): recovery.restore(preview['token'])

    def test_concurrent_change_during_restore_is_rejected_by_backend(self):
        ident = self.checkpoint()
        preview = recovery.preview(ident)
        save = backend.save
        def concurrent(data, expected):
            self.target.write_text(json.dumps(self.changed()))
            return save(data, expected=expected)
        with patch.object(backend, 'save', side_effect=concurrent):
            with self.assertRaisesRegex(ValueError, 'outside this window'): recovery.restore(preview['token'])
        self.assertEqual(recovery.current(), self.changed())

    def test_failed_restore_rolls_back_json_and_generated_config(self):
        ident = self.checkpoint()
        backend.save(self.changed())
        initial = {p: p.read_text() for p in self.config.rglob('*') if p.is_file()}
        preview = recovery.preview(ident)
        atomic = backend.atomic
        failed = False
        def fail_once(path, text):
            nonlocal failed
            if path == self.target and not failed:
                failed = True
                raise OSError('Disk full')
            return atomic(path, text)
        with patch.object(backend, 'atomic', side_effect=fail_once):
            with self.assertRaises(OSError): recovery.restore(preview['token'])
        self.assertEqual({p: p.read_text() for p in initial}, initial)
        self.assertEqual(recovery.current(), self.changed())

    def test_checkpoint_conflict_and_invalid_data_create_no_checkpoint(self):
        expected = recovery.revision()
        self.target.write_text(json.dumps(self.changed()))
        with self.assertRaisesRegex(ValueError, 'changed elsewhere'): recovery.checkpoint(expected)
        self.target.write_text('{broken')
        with self.assertRaises(ValueError): self.checkpoint()
        self.assertEqual(recovery.backups(), [])

    def test_personal_backup_is_local_self_report_and_missing_folder_visible(self):
        self.assertFalse(recovery.backup_status()['confirmed'])
        folder = self.root / 'external-backup'; folder.mkdir()
        recovery.confirm_backup(str(folder))
        status = recovery.backup_status()
        self.assertTrue(status['available']); self.assertTrue(status['confirmed'])
        self.assertEqual(list(folder.iterdir()), [])
        folder.rmdir()
        self.assertFalse(recovery.backup_status()['available'])
        with self.assertRaises(ValueError): recovery.confirm_backup(str(folder))
        with self.assertRaises(ValueError): recovery.confirm_backup('relative')
        import github_sync
        repo = self.root / 'repo'
        github_sync.snapshot_managed_files(repo, self.config, self.root)
        self.assertFalse(list(repo.rglob('personal-backup.json')))

    def test_update_check_uses_isolated_db_and_handles_no_updates_and_failure(self):
        with patch.object(recovery.shutil, 'which', return_value='/usr/bin/checkupdates'), patch.object(recovery.subprocess, 'run') as run:
            run.return_value = subprocess.CompletedProcess([], 0, 'example 1 -> 2\n', '')
            self.assertEqual(recovery.check_updates()['packages'], ['example 1 -> 2'])
            args, kwargs = run.call_args
            self.assertEqual(args[0], ['checkupdates', '--nocolor'])
            self.assertNotEqual(kwargs['env']['CHECKUPDATES_DB'], '/var/lib/pacman')
            self.assertFalse(Path(kwargs['env']['CHECKUPDATES_DB']).exists())
            run.return_value = subprocess.CompletedProcess([], 2, '', '')
            self.assertEqual(recovery.check_updates()['packages'], [])
            run.return_value = subprocess.CompletedProcess([], 1, '', 'network failure')
            with self.assertRaisesRegex(ValueError, 'internet'): recovery.check_updates()

    def test_detached_terminal_argument_boundaries_launch_failure_and_duplicate(self):
        with patch.object(recovery.shutil, 'which', return_value='/usr/bin/example'), patch.object(recovery.subprocess, 'run') as run:
            run.return_value = subprocess.CompletedProcess([], 0, '', '')
            recovery.launch_upgrade()
            self.assertEqual(run.call_args.args[0], ['kitty', '--detach', '--title', 'Hyprshell system upgrade', sys.executable, str(Path(recovery.__file__).resolve()), '--upgrade-terminal'])
            self.assertEqual(recovery.update_status()['status'], 'launching')
            with self.assertRaises(ValueError): recovery.launch_upgrade()
            self.assertEqual(run.call_count, 1)
            recovery.write_update('failed', 'previous failure')
            run.return_value = subprocess.CompletedProcess([], 1, '', 'No display')
            with self.assertRaises(ValueError): recovery.launch_upgrade()
            self.assertEqual(recovery.update_status()['status'], 'failed')
        with recovery.upgrade_lock():
            with self.assertRaises(ValueError):
                with recovery.upgrade_lock(): pass

    def test_terminal_cancel_never_runs_package_manager(self):
        with patch('builtins.input', return_value='n'), patch.object(recovery.subprocess, 'Popen') as launch, patch('sys.stdout', io.StringIO()):
            self.assertEqual(recovery.upgrade_terminal(), 0)
            launch.assert_not_called()
        self.assertEqual(recovery.update_status()['status'], 'cancelled')

    def test_terminal_runs_full_interactive_upgrade_and_reports_failures(self):
        for code, output in [(0, 'completed\n'), (1, 'error: unable to lock database\n')]:
            process = MagicMock()
            process.__enter__.return_value = process
            process.stdout = [output]
            process.wait.return_value = code
            with patch('builtins.input', side_effect=['y', '']), patch.object(recovery.subprocess, 'Popen', return_value=process) as launch, patch('sys.stdout', io.StringIO()):
                self.assertEqual(recovery.upgrade_terminal(), code)
                self.assertEqual(launch.call_args.args[0], ['sudo', 'pacman', '-Syu'])
                self.assertNotIn('stdin', launch.call_args.kwargs)
            result = recovery.update_status()
            self.assertEqual(result['status'], 'completed' if not code else 'failed')
            if code: self.assertIn('package manager', result['message'])

    def test_upgrade_error_guidance_and_interrupted_status(self):
        for output, fragment in [('invalid signature', 'signature'), ('not enough disk space', 'disk space'), ('failed retrieving file', 'network'), ('exists in filesystem', 'conflict'), ('unclassified', 'did not complete')]:
            self.assertIn(fragment, recovery.update_error(output))
        with patch('builtins.input', side_effect=EOFError), patch('sys.stdout', io.StringIO()):
            self.assertEqual(recovery.upgrade_terminal(), 1)
        self.assertEqual(recovery.update_status()['status'], 'unknown')
        recovery.write_update('launching', 'opening')
        with patch.object(recovery.time, 'time', return_value=10**12):
            self.assertEqual(recovery.update_status()['status'], 'unknown')


@unittest.skipUnless(shutil.which('quickshell'), 'Native Quickshell is needed')
class RecoveryNativeTests(unittest.TestCase):
    def test_native_preview_confirm_failure_and_restored_signal(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            payload = root / 'config/quickshell'
            shutil.copytree(ROOT / 'config/quickshell', payload, ignore=shutil.ignore_patterns('__pycache__', 'audio-spectrum'))
            current = copy.deepcopy(backend.DEFAULTS)
            current['bar']['height'] = 40
            target = root / 'config/hyprshell/settings.json'; target.parent.mkdir(); target.write_text(json.dumps(current))
            backup = root / 'state/hyprshell/backups/recovery-native/settings.json'; backup.parent.mkdir(parents=True); backup.write_text(json.dumps(backend.DEFAULTS))
            fixture = payload / 'RecoveryNative.qml'
            fixture.write_text('''import QtQuick
import QtQuick.Window
import Quickshell
import "."
ShellRoot {
    id: test
    property int phase: 0
    property bool restored: false
    Window { visible: true; width: 650; height: 900
        SettingsRecovery { id: page; width: 620; onRestored: settings => { test.restored = settings.bar.height === 32; } }
    }
    function find(root, name) { if (root.objectName === name) return root; for (let child of root.children || []) { let match = find(child, name); if (match) return match; } return null; }
    Timer { interval: 60; running: true; repeat: true
        onTriggered: {
            if (page.busy || !page.loaded) return;
            if (test.phase === 0) {
                if (page.backups.length !== 1 || page.personal.confirmed) { console.error("RECOVERY_FAILED initial"); Qt.quit(); return; }
                page.request({operation: "restore", token: "bad"}); test.phase = 1;
            } else if (test.phase === 1 && !page.success) {
                test.find(page, "previewSettingsRestore").clicked(); test.phase = 2;
            } else if (test.phase === 2 && page.preview) {
                if (page.preview.changes.join(",") !== "Bar & layout") { console.error("RECOVERY_FAILED preview"); Qt.quit(); return; }
                page.ready = false;
                if (test.find(page, "confirmSettingsRestore").enabled) { console.error("RECOVERY_FAILED unsaved edits"); Qt.quit(); return; }
                page.ready = true;
                test.find(page, "confirmSettingsRestore").clicked(); test.phase = 3;
            } else if (test.phase === 3 && test.restored) {
                if (page.preview || !page.success) console.error("RECOVERY_FAILED restore");
                else console.log("RECOVERY_NATIVE_OK");
                Qt.quit();
            }
        }
    }
    Timer { interval: 8000; running: true; onTriggered: { console.error("RECOVERY_FAILED timeout", page.message); Qt.quit(); } }
}
''')
            runtime = root / 'runtime'; runtime.mkdir(mode=0o700)
            env = dict(os.environ, XDG_CONFIG_HOME=str(root / 'config'), XDG_STATE_HOME=str(root / 'state'),
                       XDG_RUNTIME_DIR=str(runtime), QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software', QT_QPA_PLATFORMTHEME='', HYPRLAND_INSTANCE_SIGNATURE='')
            result = subprocess.run(['quickshell', '-p', str(fixture)], capture_output=True, text=True, env=env, timeout=12)
            output = result.stdout + result.stderr
            self.assertIn('RECOVERY_NATIVE_OK', output, output)
            self.assertNotIn('RECOVERY_FAILED', output, output)
            self.assertEqual(json.loads(target.read_text())['bar']['height'], 32)


if __name__ == '__main__':
    unittest.main()
