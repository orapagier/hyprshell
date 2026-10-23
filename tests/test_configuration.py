"""Complete config recovery is local, validated and never activates saved Lua."""
import copy
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'config/quickshell/settings'))
import backend
import configuration
import preferences


class ConfigurationTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(); self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        env = patch.dict(os.environ, XDG_CONFIG_HOME=str(self.root / 'config'), XDG_STATE_HOME=str(self.root / 'state'), HYPRLAND_INSTANCE_SIGNATURE='')
        env.start(); self.addCleanup(env.stop)
        self.config = self.root / 'config'
        path = self.config / 'hyprshell/settings.json'; path.parent.mkdir(parents=True); path.write_text(json.dumps(backend.DEFAULTS))
        main = self.config / 'hypr/hyprland.lua'; main.parent.mkdir(); main.write_text('-- personal configuration\n')
        (self.config / 'quickshell').mkdir(); (self.config / 'quickshell/shell.qml').write_text('source code is excluded')

    def checkpoint(self):
        result = configuration.request({'operation': 'checkpoint', 'expected': configuration.status()['revision']})
        return result['checkpoints'][0]['id']

    def test_checkpoint_preview_restore_full_files_and_new_preferences(self):
        ident = self.checkpoint()
        self.assertNotIn('quickshell/shell.qml', configuration.read_snapshot(ident))
        main = self.config / 'hypr/hyprland.lua'; main.write_text('-- changed\n')
        new = self.config / 'hyprshell/behavior.json'; new.write_text(json.dumps({'version': 1, 'general': {}, 'workspaces': [], 'rules': []}))
        preview = configuration.request({'operation': 'preview', 'id': ident})['preview']
        self.assertIn('hypr/hyprland.lua', preview['changes'])
        result = configuration.request({'operation': 'restore', 'token': preview['token']})
        self.assertTrue(result['ok']); self.assertIn('log out', result['message'])
        self.assertFalse(new.exists()); self.assertEqual(main.read_text(), '-- personal configuration\n')
        self.assertEqual((self.config / 'quickshell/shell.qml').read_text(), 'source code is excluded')
        self.assertTrue(list((self.root / 'state/hyprshell/backups').glob('configuration-undo-*')))
        rows = configuration.status()['checkpoints']
        self.assertEqual(sum(row['kind'] == 'before-restore' for row in rows), 1)

    def test_stale_preview_and_invalid_saved_lua_write_nothing(self):
        ident = self.checkpoint()
        preview = configuration.request({'operation': 'preview', 'id': ident})['preview']
        main = self.config / 'hypr/hyprland.lua'; main.write_text('-- newer manual edit\n')
        with self.assertRaises(ValueError): configuration.request({'operation': 'restore', 'token': preview['token']})
        folder = configuration.snapshot_folder(ident) / 'files.json'
        data = json.loads(folder.read_text()); data['hypr/hyprland.lua'] = 'this is invalid Lua'; folder.write_text(json.dumps(data))
        details = folder.parent / 'metadata.json'
        info = json.loads(details.read_text()); info['checksum'] = configuration.digest(data); details.write_text(json.dumps(info))
        preview = configuration.request({'operation': 'preview', 'id': ident})['preview']
        with self.assertRaises(ValueError): configuration.request({'operation': 'restore', 'token': preview['token']})
        self.assertEqual(main.read_text(), '-- newer manual edit\n')

    def test_backup_dates_times_metadata_and_cleanup_protection(self):
        ident = self.checkpoint()
        folder = configuration.snapshot_folder(ident)
        self.assertEqual(folder.parent, self.root / 'state/hyprshell/setup-backups')
        self.assertEqual(folder.stat().st_mode & 0o777, 0o700)
        row = configuration.status()['checkpoints'][0]
        self.assertRegex(row['label'], r'\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}')
        self.assertIn('UTC', row['label']); self.assertEqual(row['kind'], 'manual')
        self.assertGreater(row['fileCount'], 0); self.assertGreater(row['bytes'], 0)
        from datetime import datetime
        self.assertIsNotNone(datetime.fromisoformat(row['createdAt']).tzinfo)
        import cleanup
        import system_cleanup
        choice = system_cleanup.options(dict(selected=['backups'], days=0, keep=1), False)
        self.assertEqual(system_cleanup.plan(choice)['entries'], [])
        with patch.object(cleanup, 'read', return_value=dict(cleanup.DEFAULTS, temporary=False, thumbnails=False)):
            self.assertEqual(cleanup.scan(cleanup.read()), [])
        self.assertTrue(folder.is_dir())

    def test_legacy_backups_are_dated_selectable_and_restoreable(self):
        ident = 'configuration-20260203-040506-123456'
        folder = self.root / 'state/hyprshell/backups' / ident; folder.mkdir(parents=True)
        files = configuration.current(); (folder / 'files.json').write_text(json.dumps(files))
        row = configuration.status()['checkpoints'][0]
        self.assertEqual(row['id'], ident); self.assertIn('2026-02-03 04:05:06', row['label'])
        self.assertEqual(row['kind'], 'legacy')
        self.assertEqual(configuration.read_snapshot(ident), files)
        result = configuration.request(dict(operation='preview', id=ident))
        self.assertEqual(result['preview']['id'], ident)
        self.assertIn(row['label'], result['preview']['label'])

    def test_corrupted_backup_is_rejected_before_any_restore(self):
        ident = self.checkpoint(); folder = configuration.snapshot_folder(ident)
        before = configuration.current()
        files = json.loads((folder / 'files.json').read_text())
        files['hypr/hyprland.lua'] = '-- silently changed backup'
        (folder / 'files.json').write_text(json.dumps(files))
        with self.assertRaisesRegex(ValueError, 'checksum'):
            configuration.request(dict(operation='preview', id=ident))
        self.assertEqual(configuration.current(), before)

    def test_invalid_panel_backup_is_rejected_before_restore(self):
        ident = self.checkpoint(); folder = configuration.snapshot_folder(ident)
        before = configuration.current()
        files = json.loads((folder / 'files.json').read_text())
        data = json.loads(files['hyprshell/settings.json'])
        data['panels']['hyprpane']['enabled'] = 'invalid'
        files['hyprshell/settings.json'] = json.dumps(data)
        (folder / 'files.json').write_text(json.dumps(files))
        # A valid checksum must not bypass the shared settings validator.
        info = json.loads((folder / 'metadata.json').read_text())
        info['checksum'] = configuration.digest(files)
        (folder / 'metadata.json').write_text(json.dumps(info))
        with self.assertRaisesRegex(ValueError, 'enabled must be boolean'):
            configuration.request(dict(operation='preview', id=ident))
        self.assertEqual(configuration.current(), before)

    def test_incomplete_and_unsafe_backups_are_not_listed(self):
        folder = self.root / 'state/hyprshell/setup-backups/setup-20260101-010101-000000'
        folder.mkdir(parents=True); (folder / 'files.json').write_text('{}')
        result = configuration.status()
        self.assertEqual(result['checkpoints'], []); self.assertEqual(result['skippedBackups'], 1)
        with self.assertRaises(ValueError): configuration.read_snapshot('../outside')
        folder.rename(folder.with_name('original'))
        folder.symlink_to(folder.with_name('original'), target_is_directory=True)
        self.assertEqual(configuration.status()['checkpoints'], [])

    def test_failed_backup_does_not_publish_incomplete_snapshot(self):
        atomic = configuration.backend.atomic
        def fail_metadata(path, content):
            if path.name == 'metadata.json': raise OSError('disk full')
            return atomic(path, content)
        with patch.object(configuration.backend, 'atomic', side_effect=fail_metadata):
            with self.assertRaises(OSError): self.checkpoint()
        self.assertEqual(configuration.status()['checkpoints'], [])
        self.assertEqual(list((self.root / 'state/hyprshell/setup-backups').iterdir()), [])

    def test_generated_rules_are_regenerated_and_unknown_paths_rejected(self):
        files = configuration.current(); files['hyprshell/overrides.lua'] = 'error("never execute this")'
        self.assertNotIn('never execute', configuration.normalized(files)['hyprshell/overrides.lua'])
        for name in ('../outside', 'quickshell/shell.qml', 'hypr/subdir/secret.lua'):
            with self.assertRaises(ValueError): configuration.validate({**files, name: 'bad'})
        link = self.config / 'hypr/linked.lua'; link.symlink_to(self.config / 'hypr/hyprland.lua')
        with self.assertRaises(ValueError): configuration.current()

    def test_delete_transaction_rolls_back_deleted_and_replaced_files(self):
        one, two = self.root / 'one', self.root / 'two'; one.write_text('one'); two.write_text('two')
        with self.assertRaises(ValueError): preferences.transaction({one: None, two: 'new'}, 'test', lambda: (_ for _ in ()).throw(ValueError('failure')))
        self.assertEqual(one.read_text(), 'one'); self.assertEqual(two.read_text(), 'two')


if __name__ == '__main__': unittest.main()
