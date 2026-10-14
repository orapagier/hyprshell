import importlib.util
import os
from pathlib import Path
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

HELPERS = Path(__file__).resolve().parents[1] / 'config/quickshell/settings'
sys.path.insert(0, str(HELPERS))
import cleanup


class CleanupTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.env = patch.dict(os.environ, {f'XDG_{key}_HOME': str(self.root / key.lower()) for key in ('CONFIG', 'STATE', 'CACHE')})
        self.env.start()
        self.addCleanup(self.env.stop)
        self.clock = patch.object(cleanup.time, 'time', return_value=time.time() + 40 * 86400)
        self.clock.start()
        self.addCleanup(self.clock.stop)
        self.settings = dict(cleanup.DEFAULTS, temporary=False)
        self.read = patch.object(cleanup, 'read', return_value=self.settings)
        self.read.start()
        self.addCleanup(self.read.stop)

    def file(self, relative):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text('test payload')
        return path

    def test_preview_then_delete_and_keep_recent_backups(self):
        old = self.file('cache/thumbnails/old.png')
        for n in range(7):
            p = self.file(f'state/hyprshell/backups/{n}/config')
            os.utime(p.parent, (n, n))
        result = cleanup.preview()
        self.assertEqual(len(result['entries']), 3)
        self.assertTrue(old.exists())
        self.assertTrue(cleanup.clean(result['token'])['ok'])
        self.assertFalse(old.exists())
        self.assertTrue((self.root / 'state/hyprshell/backups/6/config').exists())

    def test_changed_preview_rejected(self):
        path = self.file('cache/thumbnails/file')
        preview = cleanup.preview()
        path.write_text('changed content')
        with self.assertRaisesRegex(ValueError, 'changed'):
            cleanup.clean(preview['token'])
        self.assertTrue(path.exists())

    def test_symlinks_and_recent_files_excluded(self):
        outside = self.file('outside/important')
        thumbnail = self.root / 'cache/thumbnails'
        thumbnail.mkdir(parents=True)
        (thumbnail / 'linked-directory').symlink_to(outside.parent, target_is_directory=True)
        (thumbnail / 'linked-file').symlink_to(outside)
        self.assertEqual(cleanup.preview()['entries'], [])
        self.file('cache/thumbnails/recent')
        with patch.object(cleanup.time, 'time', return_value=(self.root / 'cache/thumbnails/recent').stat().st_mtime):
            self.assertEqual(cleanup.preview()['entries'], [])
        self.assertTrue(outside.exists())

    def test_symlink_ancestor_excluded(self):
        self.file('real/thumbnails/file')
        (self.root / 'cache').symlink_to(self.root / 'real', target_is_directory=True)
        self.assertEqual(cleanup.preview()['entries'], [])

    def test_schedule_and_failure_rollback(self):
        from subprocess import CompletedProcess
        def success(*args):
            return CompletedProcess(args, 0, 'active\n', '')
        with patch.object(cleanup, 'run', side_effect=success):
            cleanup.save(dict(self.settings, schedule='weekly'))
        unit = self.root / 'config/systemd/user/hyprshell-cleanup.timer'
        self.assertIn('OnCalendar=weekly', unit.read_text())
        with patch.object(cleanup, 'run', return_value=CompletedProcess([], 1, '', 'bus unavailable')):
            with self.assertRaisesRegex(ValueError, 'bus unavailable'):
                cleanup.save(dict(self.settings, schedule='monthly'))
        self.assertIn('OnCalendar=weekly', unit.read_text())

    def test_validation(self):
        for key, value in [('days', 0), ('keep', True), ('schedule', 'hourly'), ('backups', 1)]:
            with self.assertRaises(ValueError):
                cleanup.validate(dict(self.settings, **{key: value}))

    def test_empty_preview_explains_saved_scope_and_manual_cleanup(self):
        result = cleanup.preview()
        self.assertEqual(result['entries'], [])
        self.assertIn('thumbnails, temporary files and backups only', result['message'])
        self.assertIn('Clean now', result['message'])
