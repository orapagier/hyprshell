"""Cleanup operates only on synthetic files; system maintenance is mocked."""
import copy
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'config/quickshell/settings'))
import backend
import system_cleanup as subject


class SystemCleanupTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(); self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.home = self.root / 'home'; self.home.mkdir()
        self.environment = patch.dict(os.environ, HOME=str(self.home),
            XDG_CONFIG_HOME=str(self.home / '.config'), XDG_CACHE_HOME=str(self.home / '.cache'),
            XDG_STATE_HOME=str(self.home / '.local/state'), HYPRLAND_INSTANCE_SIGNATURE='')
        self.environment.start(); self.addCleanup(self.environment.stop)
        active = patch.object(subject, 'active', return_value=False)
        active.start(); self.addCleanup(active.stop)

    def file(self, name, text='synthetic cache'):
        path = self.home / name
        path.parent.mkdir(parents=True, exist_ok=True); path.write_text(text)
        return path

    def preview(self, selected=None, **extra):
        return subject.request(dict(operation='preview', selected=selected or ['thumbnails'], days=0, keep=1, **extra))['preview']

    def clean(self, preview, **extra):
        return subject.request(dict(operation='clean', token=preview['token'], confirmed=True, **extra))

    def test_catalog_never_starts_maintenance_or_authentication(self):
        with patch.object(subject.subprocess, 'run') as execute:
            self.assertGreater(len(subject.request({'operation': 'catalog'})['groups']), 8)
            self.assertGreater(len(subject.request({'operation': 'system-catalog'})['groups']), 4)
            execute.assert_not_called()
        self.assertFalse((self.home / '.local/state/hyprshell').exists())

    def test_preview_and_file_exclusion_preserve_unselected_data(self):
        first = self.file('.cache/thumbnails/one')
        second = self.file('.cache/thumbnails/two')
        profile = self.file('.config/chromium/profile')
        tool = self.file('.cache/opencode/bin/tool')
        preview = self.preview()
        self.assertEqual(preview['totalFiles'], 2)
        self.assertTrue(first.exists())
        self.assertTrue(Path(preview['listPath']).is_file())
        result = self.clean(preview, excluded=[str(second)])
        self.assertEqual(result['removed'], 1)
        self.assertFalse(first.exists()); self.assertTrue(second.exists())
        self.assertTrue(profile.exists()); self.assertTrue(tool.exists())
        with self.assertRaises((OSError, ValueError)):
            self.clean(preview)

    def test_changed_preview_aborts_before_any_deletion(self):
        first = self.file('.cache/thumbnails/one')
        second = self.file('.cache/thumbnails/two')
        preview = self.preview(); second.write_text('changed after preview')
        with self.assertRaisesRegex(ValueError, 'changed'):
            self.clean(preview)
        self.assertTrue(first.exists()); self.assertTrue(second.exists())

    def test_expired_and_unconfirmed_cleanup_fail(self):
        path = self.file('.cache/thumbnails/one'); preview = self.preview()
        with self.assertRaisesRegex(ValueError, 'confirm'):
            subject.request(dict(operation='clean', token=preview['token']))
        with patch.object(subject.time, 'time', return_value=time.time() + 301):
            with self.assertRaisesRegex(ValueError, 'expired'):
                self.clean(preview)
        self.assertTrue(path.exists())

    def test_symlink_files_roots_and_ancestors_are_not_followed(self):
        outside = self.file('Documents/important')
        directory = self.home / '.cache/thumbnails'; directory.mkdir(parents=True)
        (directory / 'link').symlink_to(outside)
        (directory / 'linked-dir').symlink_to(outside.parent, target_is_directory=True)
        self.assertEqual(self.preview()['totalFiles'], 0)
        directory.rename(directory.with_name('original'))
        directory.symlink_to(outside.parent, target_is_directory=True)
        self.assertEqual(self.preview()['totalFiles'], 0)
        self.assertTrue(outside.exists())

    def test_running_browser_is_skipped_and_starting_after_preview_invalidates(self):
        path = self.file('.cache/chromium/cache')
        with patch.object(subject, 'active', return_value=True):
            preview = self.preview(['chromium'])
            self.assertTrue(preview['groups'][0]['blocked']); self.assertEqual(preview['totalFiles'], 0)
        preview = self.preview(['chromium'])
        with patch.object(subject, 'active', return_value=True):
            with self.assertRaisesRegex(ValueError, 'activity'):
                self.clean(preview)
        self.assertTrue(path.exists())

    def test_retention_always_keeps_newest_backup_sets(self):
        paths = []
        for number in range(3):
            path = self.file(f'.local/state/hyprshell/backups/{number}/config')
            os.utime(path.parent, (number, number)); paths.append(path)
        preview = self.preview(['backups'])
        self.assertEqual(preview['totalFiles'], 2)
        self.clean(preview)
        self.assertTrue(paths[-1].exists()); self.assertFalse(paths[0].exists())

    def test_chosen_folder_excludes_hidden_profiles_and_repositories(self):
        temporary = self.file('Documents/export.tmp')
        original = self.file('Documents/original.txt')
        database = self.file('Documents/database/LOG.old')
        hidden = self.file('Documents/.state/copy.bak')
        project = self.file('Documents/project/copy.bak'); self.file('Documents/project/.git/config')
        preview = self.preview(['chosen-folder'], folder=str(self.home / 'Documents'))
        self.assertEqual([e['path'] for e in preview['entries']], [str(temporary)])
        self.clean(preview)
        for path in (original, database, hidden, project): self.assertTrue(path.exists())
        for folder in (str(self.home), str(self.home / '.config'), str(self.root), str(self.home / 'repos')):
            with self.assertRaises((ValueError, OSError)):
                self.preview(['chosen-folder'], folder=folder)

    def test_validation_and_injected_file_selection(self):
        for change in (dict(selected=['unknown']), dict(days=-1), dict(days=True), dict(keep=0)):
            payload = dict(selected=['thumbnails'], days=0, keep=1); payload.update(change)
            with self.assertRaises(ValueError): subject.options(payload, False)
        self.file('.cache/thumbnails/one'); preview = self.preview()
        with self.assertRaisesRegex(ValueError, 'selection'):
            self.clean(preview, excluded=['/etc/passwd'])
        with self.assertRaises(ValueError): subject.request({'operation': 'factory-wipe'})

    def test_administrator_actions_require_privileges_and_desktop_identity(self):
        with patch.object(subject.os, 'geteuid', return_value=1000):
            with self.assertRaisesRegex(ValueError, 'authentication'):
                subject.state_root(True)
        with patch.object(subject.os, 'geteuid', return_value=0), patch.dict(os.environ, PKEXEC_UID='0'):
            with self.assertRaisesRegex(ValueError, 'desktop user'):
                subject.state_root(True)

    def test_age_limit_retains_recent_files(self):
        self.file('.cache/thumbnails/recent')
        result = subject.request(dict(operation='preview', selected=['thumbnails'], days=7, keep=1))
        self.assertEqual(result['preview']['totalFiles'], 0)
        self.assertIn('Set minimum age to 0', result['preview']['groups'][0]['emptyReason'])

    def test_manual_default_includes_recent_cache_without_changing_schedule(self):
        self.file('.cache/thumbnails/recent')
        schedule = {'schedule': 'weekly', 'days': 7, 'keep': 3,
                    'thumbnails': True, 'temporary': True, 'backups': True}
        path = self.file('.config/hyprshell/cleanup.json', json.dumps(schedule))
        before = path.read_bytes()
        result = subject.request(dict(operation='preview', selected=['thumbnails']))
        self.assertEqual(result['preview']['totalFiles'], 1)
        self.assertEqual(subject.options(dict(selected=['thumbnails']), False)['days'], 0)
        self.assertEqual(subject.options(dict(selected=['crashes']), True)['days'], 7)
        self.assertEqual(path.read_bytes(), before)

    def test_paging_keeps_one_plan_and_allows_excluding_later_files(self):
        for n in range(205): self.file(f'.cache/thumbnails/{n:04d}')
        preview = self.preview()
        self.assertEqual(len(preview['entries']), 200); self.assertEqual(preview['totalFiles'], 205)
        page = subject.request(dict(operation='files', token=preview['token'], offset=200))['filePage']
        self.assertEqual(len(page['entries']), 5)
        retained = page['entries'][-1]['path']
        self.assertEqual(self.clean(preview, excluded=[retained])['removed'], 204)
        self.assertTrue(Path(retained).exists())

    def test_system_actions_are_fixed_and_changing_log_size_is_allowed(self):
        state = self.root / 'admin-state'; state.mkdir()
        log = self.file('synthetic-journal/log')
        row = subject.row('journals', 'Journal', [log.parent], 'History', policy='command')
        with patch.object(subject, 'catalog', return_value=[row]), patch.object(subject, 'state_root', return_value=state), \
             patch.object(subject.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, 'vacuumed', '')) as execute:
            preview = subject.request(dict(operation='preview', selected=['journals'], days=0, keep=1), True)['preview']
            execute.assert_not_called()
            log.write_text('journald added more text')
            result = subject.request(dict(operation='clean', token=preview['token'], confirmed=True), True)
            self.assertTrue(result['ok']); self.assertTrue(log.exists())
            self.assertEqual(execute.call_args.args[0], ['/usr/bin/journalctl', '--rotate', '--vacuum-time=14d', '--vacuum-size=100M'])

    def test_tool_failure_returns_partial_result_without_retrying(self):
        state = self.root / 'admin-state'; state.mkdir()
        row = subject.row('temporary', 'Temporary', ['/tmp'], 'Policy', policy='command')
        with patch.object(subject, 'catalog', return_value=[row]), patch.object(subject, 'state_root', return_value=state), \
             patch.object(subject.subprocess, 'run', return_value=subprocess.CompletedProcess([], 1, '', 'synthetic failure')) as execute:
            preview = subject.request(dict(operation='preview', selected=['temporary'], days=0, keep=1), True)['preview']
            result = subject.request(dict(operation='clean', token=preview['token'], confirmed=True), True)
            self.assertFalse(result['ok']); self.assertIn('failed', result['message']); execute.assert_called_once()
            self.assertFalse((state / 'system-cleanup-preview.json').exists())

    def test_settings_reset_requires_phrase_and_creates_restoreable_checkpoint(self):
        before = copy.deepcopy(backend.DEFAULTS); before['bar']['position'] = 'bottom'
        path = self.file('.config/hyprshell/settings.json', json.dumps(before))
        preview = subject.request({'operation': 'reset-preview'})['preview']
        self.assertIn('bar', preview['changes'])
        with self.assertRaisesRegex(ValueError, 'RESET'):
            subject.request(dict(operation='reset', token=preview['token'], confirmation='yes'))
        result = subject.request(dict(operation='reset', token=preview['token'], confirmation='RESET'))
        self.assertTrue(result['ok']); self.assertEqual(json.loads(path.read_text()), backend.DEFAULTS)
        saved = list((self.home / '.local/state/hyprshell/backups').glob('recovery-*/settings.json'))
        self.assertEqual(len(saved), 1); self.assertEqual(json.loads(saved[0].read_text()), before)

    def test_stale_reset_and_failed_save_preserve_preferences(self):
        before = copy.deepcopy(backend.DEFAULTS); before['bar']['position'] = 'left'
        path = self.file('.config/hyprshell/settings.json', json.dumps(before))
        preview = subject.request({'operation': 'reset-preview'})['preview']
        before['bar']['position'] = 'bottom'; path.write_text(json.dumps(before))
        with self.assertRaisesRegex(ValueError, 'changed'):
            subject.request(dict(operation='reset', token=preview['token'], confirmation='RESET'))
        preview = subject.request({'operation': 'reset-preview'})['preview']
        with patch.object(subject.backend, 'save', side_effect=ValueError('save failed')):
            with self.assertRaisesRegex(ValueError, 'save failed'):
                subject.request(dict(operation='reset', token=preview['token'], confirmation='RESET'))
        self.assertEqual(json.loads(path.read_text()), before)
        self.assertEqual(len(list((self.home / '.local/state/hyprshell/backups').glob('recovery-*'))), 1)


if __name__ == '__main__': unittest.main()
