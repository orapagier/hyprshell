"""Recovery invariants, isolated from live configuration and real backup state."""
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    'agent_checkpoint', ROOT / 'docs/skills/hyprskill/scripts/checkpoint.py')
checkpoint = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(checkpoint)


class AgentCheckpointTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.state = self.root / 'state'
        env = patch.dict(os.environ, XDG_STATE_HOME=str(self.state))
        env.start()
        self.addCleanup(env.stop)
        quiet = contextlib.redirect_stdout(io.StringIO())
        quiet.__enter__()
        self.addCleanup(quiet.__exit__, None, None, None)
        self.live = self.root / 'live'
        self.live.write_bytes(b'dirty pre-existing work\x00\xff')
        self.live.chmod(0o640)

    def create(self, *paths):
        return checkpoint.create('test', paths or [self.live])

    def test_restores_dirty_bytes_mode_and_retains_private_backup(self):
        folder = self.create()
        self.live.write_text('broken')
        self.live.chmod(0o600)
        checkpoint.record_after(folder)
        checkpoint.restore(folder, apply=True)
        self.assertEqual(self.live.read_bytes(), b'dirty pre-existing work\x00\xff')
        self.assertEqual(self.live.stat().st_mode & 0o777, 0o640)
        self.assertEqual(folder.stat().st_mode & 0o777, 0o700)
        self.assertEqual((folder / 'before.json').stat().st_mode & 0o777, 0o600)
        checkpoint.restore(folder, apply=True)  # Repeat is harmless.
        self.assertTrue((folder / 'before.json').is_file())

    def test_preview_does_not_mutate_and_apply_retains_undo(self):
        folder = self.create()
        self.live.write_text('changed')
        checkpoint.record_after(folder)
        checkpoint.restore(folder)
        self.assertEqual(self.live.read_text(), 'changed')
        checkpoint.restore(folder, apply=True)
        backups = list((self.state / 'hyprshell/agent-backups').iterdir())
        undo = next(p for p in backups if p != folder)
        checkpoint.restore(undo, apply=True)
        self.assertEqual(self.live.read_text(), 'changed')

    def test_conflict_in_last_file_prevents_all_restoration(self):
        other = self.root / 'other'
        other.write_text('original')
        folder = self.create(self.live, other)
        self.live.write_text('mine')
        other.write_text('mine')
        checkpoint.record_after(folder)
        other.write_text('someone else')
        with self.assertRaisesRegex(ValueError, 'newer edits'):
            checkpoint.restore(folder, apply=True)
        self.assertEqual(self.live.read_text(), 'mine')
        self.assertEqual(other.read_text(), 'someone else')

    def test_new_file_removed_deleted_file_restored_unrelated_file_preserved(self):
        new = self.root / 'new'
        unrelated = self.root / 'unrelated'
        unrelated.write_text('keep')
        folder = self.create(self.live, new)
        self.live.unlink()
        new.write_text('created')
        checkpoint.record_after(folder)
        checkpoint.restore(folder, apply=True)
        self.assertTrue(self.live.exists())
        self.assertFalse(new.exists())
        self.assertEqual(unrelated.read_text(), 'keep')

    def test_symlinks_restored_without_touching_targets(self):
        link = self.root / 'link'
        link.symlink_to('missing-original')
        folder = self.create(link)
        link.unlink()
        link.symlink_to(self.live)
        checkpoint.record_after(folder)
        checkpoint.restore(folder, apply=True)
        self.assertEqual(os.readlink(link), 'missing-original')
        self.assertEqual(self.live.read_bytes(), b'dirty pre-existing work\x00\xff')

    def test_parent_symlink_redirect_is_refused(self):
        parent = self.root / 'parent'
        parent.mkdir()
        file = parent / 'config'
        file.write_text('original')
        folder = self.create(file)
        parent.rename(self.root / 'moved')
        parent.symlink_to(self.root / 'moved', target_is_directory=True)
        with self.assertRaisesRegex(ValueError, 'path'):
            checkpoint.restore(folder, apply=True)

    def test_corrupt_backup_is_rejected_before_write(self):
        folder = self.create()
        self.live.write_text('changed')
        checkpoint.record_after(folder)
        path = folder / 'before.json'
        data = json.loads(path.read_text())
        data['files'][str(self.live)]['sha256'] = 'corrupt'
        path.write_text(json.dumps(data))
        with self.assertRaisesRegex(ValueError, 'checksum'):
            checkpoint.restore(folder, apply=True)
        self.assertEqual(self.live.read_text(), 'changed')

    def test_unrecorded_changes_block_restore(self):
        folder = self.create()
        self.live.write_text('unknown')
        with self.assertRaisesRegex(ValueError, 'Unrecorded'):
            checkpoint.restore(folder, apply=True)
        self.assertEqual(self.live.read_text(), 'unknown')

    def test_directory_and_hardlink_rejected_before_publishing(self):
        with self.assertRaisesRegex(ValueError, 'directories'):
            self.create(self.root)
        os.link(self.live, self.root / 'hardlink')
        with self.assertRaisesRegex(ValueError, 'hard-linked'):
            self.create()
        self.assertFalse(self.state.exists())

    def test_record_after_keeps_original_baseline(self):
        folder = self.create()
        original = (folder / 'before.json').read_bytes()
        for text in ('first edit', 'second edit'):
            self.live.write_text(text)
            checkpoint.record_after(folder)
            self.assertEqual((folder / 'before.json').read_bytes(), original)
        checkpoint.restore(folder, apply=True)
        self.assertEqual(self.live.read_bytes(), b'dirty pre-existing work\x00\xff')

    def test_interrupted_restore_keeps_undo_without_claiming_concurrent_edits(self):
        other = self.root / 'other'
        other.write_text('original')
        folder = self.create(self.live, other)
        self.live.write_text('mine')
        other.write_text('mine')
        checkpoint.record_after(folder)
        real_replace = checkpoint.replace

        def concurrent_edit(path, entry):
            real_replace(path, entry)
            if Path(path) == self.live:
                other.write_text('someone else')

        with patch.object(checkpoint, 'replace', side_effect=concurrent_edit):
            with self.assertRaisesRegex(ValueError, 'during rollback'):
                checkpoint.restore(folder, apply=True)
        undo = next(p for p in (self.state / 'hyprshell/agent-backups').iterdir()
                    if p != folder)
        with self.assertRaisesRegex(ValueError, 'newer edits'):
            checkpoint.restore(undo, apply=True)
        self.assertEqual(other.read_text(), 'someone else')

    def test_listing_empty_history_does_not_create_state(self):
        self.assertEqual(checkpoint.backups(), [])
        self.assertFalse(self.state.exists())

    def test_list_cli_returns_shared_metadata_without_captured_contents(self):
        folder = self.create()
        self.live.write_text('secret current content')
        checkpoint.record_after(folder)
        result = subprocess.run(
            [sys.executable, str(Path(SPEC.origin)), 'list', '--json'],
            capture_output=True, text=True, check=True, cwd='/tmp')
        rows = json.loads(result.stdout)
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]['id'], folder.name)
        self.assertEqual(rows[0]['paths'], [str(self.live)])
        self.assertTrue(rows[0]['recorded_after'])
        self.assertIsNone(rows[0]['error'])
        self.assertNotIn('secret current content', result.stdout)
        self.assertNotIn('data', rows[0])
        self.assertEqual(self.live.read_text(), 'secret current content')

    def test_legacy_and_damaged_backups_remain_discoverable(self):
        folder = self.create()
        manifest = folder / 'before.json'
        data = json.loads(manifest.read_text())
        data.pop('created_at')
        manifest.write_text(json.dumps(data))
        damaged = folder.parent / 'damaged'
        damaged.mkdir()
        (damaged / 'before.json').write_text('{broken')
        malformed = folder.parent / 'malformed'
        malformed.mkdir()
        (malformed / 'before.json').write_text(json.dumps(
            {'version': 1, 'task': 'invalid files', 'files': ['not a mapping']}))
        rows = checkpoint.backups()
        self.assertEqual({row['id'] for row in rows}, {folder.name, 'damaged', 'malformed'})
        legacy = next(row for row in rows if row['id'] == folder.name)
        self.assertIsNotNone(legacy['created_at'])
        self.assertFalse(legacy['recorded_after'])
        self.assertIsNone(legacy['error'])
        self.assertTrue(next(row for row in rows if row['id'] == 'damaged')['error'])
        self.assertTrue(next(row for row in rows if row['id'] == 'malformed')['error'])

    def test_list_and_restore_selected_version_does_not_touch_another_task(self):
        folder = self.create()
        self.live.write_text('mine')
        checkpoint.record_after(folder)
        other = self.root / 'other'
        other.write_text('other original')
        newer = self.create(other)
        other.write_text('other changed')
        checkpoint.record_after(newer)
        rows = checkpoint.backups()
        self.assertEqual(rows[0]['id'], newer.name)
        selected = next(row for row in rows if row['id'] == folder.name)
        checkpoint.restore(Path(selected['checkpoint']), apply=True)
        self.assertEqual(self.live.read_bytes(), b'dirty pre-existing work\x00\xff')
        self.assertEqual(other.read_text(), 'other changed')


if __name__ == '__main__':
    unittest.main()
