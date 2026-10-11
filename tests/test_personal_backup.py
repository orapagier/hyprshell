"""Only temporary synthetic personal files are copied or verified."""
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'config/quickshell/settings'))
import personal_backup as backup


class PersonalBackupTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(); self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name); self.home = self.root / 'home'; self.home.mkdir()
        env = patch.dict(os.environ, XDG_CONFIG_HOME=str(self.root / 'config'), XDG_STATE_HOME=str(self.root / 'state'))
        env.start(); self.addCleanup(env.stop)
        home = patch.object(Path, 'home', return_value=self.home); home.start(); self.addCleanup(home.stop)
        self.source = self.home / 'Documents'; self.source.mkdir(); (self.source / 'notes.txt').write_text('version one')
        self.target = self.root / 'drive'; self.target.mkdir()

    def configured(self, schedule='off'):
        data = {**backup.DEFAULTS, 'destination': str(self.target), 'sources': [str(self.source)], 'schedule': schedule}
        return backup.configure(data, backup.saved())

    def test_manual_snapshots_preserve_old_versions_reuse_verified_copies_and_verify(self):
        with patch.object(backup, 'systemctl') as manager:
            self.configured(); manager.assert_not_called()
        secret = self.root / 'outside.txt'; secret.write_text('excluded')
        (self.source / 'linked.txt').symlink_to(secret)
        (self.source / 'empty').mkdir()
        self.assertEqual(backup.run_backup(), 0)
        first = backup.snapshots(self.target / 'HyprshellBackups')[0]
        self.assertTrue(backup.verify_latest()['ok'])
        self.assertEqual(backup.run_backup(), 0)
        second = backup.snapshots(self.target / 'HyprshellBackups')[0]
        entry = next(first.glob('*Documents/notes.txt'))
        copied = next(second.glob('*Documents/notes.txt'))
        self.assertEqual(entry.stat().st_ino, copied.stat().st_ino)
        self.assertNotEqual(copied.stat().st_ino, (self.source / 'notes.txt').stat().st_ino)
        self.assertFalse(list(first.glob('**/linked.txt')))
        self.assertTrue(list(first.glob('*Documents/empty')))
        (self.source / 'notes.txt').write_text('version two')
        self.assertEqual(backup.run_backup(), 0)
        self.assertEqual(entry.read_text(), 'version one')
        latest = backup.snapshots(self.target / 'HyprshellBackups')[0]
        self.assertEqual(next(latest.glob('*Documents/notes.txt')).read_text(), 'version two')
        next(latest.glob('*Documents/notes.txt')).write_text('corrupt')
        with self.assertRaises(ValueError): backup.verify_latest()

    def test_missing_or_replaced_drive_and_recursive_sources_are_rejected(self):
        data = self.configured()
        self.target.rename(self.root / 'disconnected'); self.target.mkdir()
        self.assertEqual(backup.run_backup(), 1)
        self.assertFalse((self.target / 'HyprshellBackups').exists())
        with self.assertRaises(ValueError): backup.validate({**data, 'destination': str(self.source)}, True)
        with self.assertRaises(ValueError): backup.validate({**data, 'destination': str(self.root / 'drive/../home/Documents')})
        with self.assertRaises(ValueError): backup.validate({**data, 'sources': [str(self.home)]})
        with self.assertRaises(ValueError): backup.validate({**data, 'sources': [str(self.source), str(self.source / 'nested')]})

    def test_schedule_is_opt_in_and_failure_restores_policy(self):
        with patch.object(backup, 'systemctl') as manager:
            data = self.configured('weekly')
            manager.assert_any_call('enable', '--now', 'hyprshell-backup.timer')
        timer = self.root / 'config/systemd/user/hyprshell-backup.timer'
        self.assertIn('OnCalendar=weekly', timer.read_text())
        service = self.root / 'config/systemd/user/hyprshell-backup.service'
        self.assertIn('TimeoutStartSec=infinity', service.read_text())
        self.assertIn('XDG_STATE_HOME=' + str(self.root / 'state'), service.read_text())
        with patch.object(backup, 'systemctl', side_effect=ValueError('manager inaccessible')):
            with self.assertRaises(ValueError): backup.configure({**data, 'schedule': 'daily'}, data)
        self.assertEqual(backup.saved()['schedule'], 'weekly')
        self.assertIn('OnCalendar=weekly', timer.read_text())
        with patch.object(backup, 'systemctl'):
            backup.configure({**data, 'schedule': 'off'}, backup.saved())
        self.assertFalse(timer.exists())

    def test_no_destination_or_unrelated_backup_folder_is_never_written(self):
        self.assertEqual(backup.run_backup(), 1)
        self.assertFalse((self.target / 'HyprshellBackups').exists())
        self.configured(); folder = self.target / 'HyprshellBackups'; folder.mkdir(); (folder / 'unrelated').write_text('keep')
        self.assertEqual(backup.run_backup(), 1)
        self.assertEqual((folder / 'unrelated').read_text(), 'keep')


if __name__ == '__main__': unittest.main()
