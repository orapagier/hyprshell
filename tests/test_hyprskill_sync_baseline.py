"""Exercise skill completion against the real offline sync reconciliation."""
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / 'docs/skills/hyprskill/scripts'
sys.path.insert(0, str(ROOT / 'config/quickshell/settings'))
sys.path.insert(0, str(SCRIPTS))
import checkpoint
import github_sync
from backend import validate

spec = importlib.util.spec_from_file_location('skill_sync_baseline', SCRIPTS / 'sync_baseline.py')
helper = importlib.util.module_from_spec(spec)
spec.loader.exec_module(helper)


class BaselineTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo, self.config = self.root / 'repo', self.root / 'live'
        self.env = patch.dict(os.environ, HOME=str(self.root / 'home'),
                              XDG_CONFIG_HOME=str(self.config),
                              XDG_STATE_HOME=str(self.root / 'state'),
                              XDG_DATA_HOME=str(self.root / 'home/.local/share'))
        self.env.start()
        self.addCleanup(self.env.stop)
        subprocess.run(['git', 'init', '-b', 'main', str(self.repo)],
                       check=True, capture_output=True)
        self.git('config', 'user.name', 'Test')
        self.git('config', 'user.email', 'test@example.com')
        for name in ('hypr', 'quickshell'):
            self.write_both('config/' + name + '/current', 'initial')
        self.settings = 'config/hyprshell/settings.json'
        data = validate({'version': 1})
        self.write_both(self.settings, json.dumps(data, indent=2) + '\n')
        self.git('add', '.')
        self.git('commit', '-m', 'initial')
        self.baseline = self.root / 'state/hyprshell/local-config-baseline.json'
        self.baseline.parent.mkdir(parents=True)
        self.baseline.write_text(json.dumps({'repo': str(self.repo), 'files': {
            self.settings: github_sync.file_hash(self.repo / self.settings),
            'config/hypr/current': github_sync.file_hash(self.repo / 'config/hypr/current'),
        }}))

    def git(self, *args):
        return github_sync.git(self.repo, *args)

    def live(self, relative):
        return self.config / relative.removeprefix('config/')

    def write_both(self, relative, text):
        for path in (self.repo / relative, self.live(relative)):
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text)

    def common_agent_settings(self):
        data = json.loads((self.repo / self.settings).read_text())
        data['bar']['workspaceOverrides']['2'] = False
        self.write_both(self.settings, json.dumps(data, indent=2) + '\n')
        self.git('add', self.settings)
        self.git('commit', '-m', 'Agent workspace change')
        return data

    def test_agent_then_manual_settings_edit_syncs_without_false_conflict(self):
        data = self.common_agent_settings()
        agent_head = self.git('rev-parse', 'HEAD')
        newer = json.loads(json.dumps(data))
        newer['bar']['workspaceOverrides']['3'] = False
        self.live(self.settings).write_text(json.dumps(newer, indent=2) + '\n')
        with self.assertRaisesRegex(RuntimeError, 'both changed'):
            github_sync.save_local(self.repo, self.config)
        self.live(self.settings).write_text(json.dumps(data, indent=2) + '\n')
        helper.refresh(self.repo, [self.settings], apply=True)
        self.live(self.settings).write_text(json.dumps(newer, indent=2) + '\n')
        self.assertTrue(github_sync.save_local(self.repo, self.config))
        self.assertEqual(json.loads((self.repo / self.settings).read_text()), newer)
        self.assertEqual(self.git('log', '-1', '--format=%s', agent_head), 'Agent workspace change')
        self.assertEqual(self.git('status', '--short'), '')

    def test_preview_apply_backup_restore_and_idempotence(self):
        self.common_agent_settings()
        before = self.baseline.read_bytes()
        head = self.git('rev-parse', 'HEAD')
        result = helper.refresh(self.repo, [self.settings])
        self.assertEqual(result['updated'], [self.settings])
        self.assertFalse(result['applied'])
        self.assertEqual(self.baseline.read_bytes(), before)
        self.assertEqual(checkpoint.backups(), [])
        result = helper.refresh(self.repo, [self.settings], apply=True)
        folder = Path(result['checkpoint'])
        self.assertTrue((folder / 'after.json').is_file())
        self.assertEqual(self.git('rev-parse', 'HEAD'), head)
        self.assertEqual(self.git('status', '--short'), '')
        self.assertFalse(helper.refresh(self.repo, [self.settings], apply=True)['applied'])
        self.assertEqual(len(checkpoint.backups()), 1)
        subprocess.run([sys.executable, str(SCRIPTS / 'checkpoint.py'),
                        'restore', str(folder), '--apply'], check=True, capture_output=True)
        self.assertEqual(self.baseline.read_bytes(), before)

    def test_mismatch_refuses_entire_batch_and_preserves_real_conflict(self):
        self.common_agent_settings()
        self.write_both('config/hypr/current', 'agent change')
        self.live('config/hypr/current').write_text('different desktop change')
        before = self.baseline.read_bytes()
        with self.assertRaisesRegex(ValueError, 'differ'):
            helper.refresh(self.repo, [self.settings, 'config/hypr/current'], apply=True)
        self.assertEqual(self.baseline.read_bytes(), before)
        self.assertEqual(checkpoint.backups(), [])
        with self.assertRaisesRegex(RuntimeError, 'both changed'):
            github_sync.save_local(self.repo, self.config)
        self.assertEqual((self.repo / 'config/hypr/current').read_text(), 'agent change')
        self.assertEqual(self.live('config/hypr/current').read_text(), 'different desktop change')

    def test_unrelated_manual_edit_and_baseline_entry_are_untouched(self):
        self.common_agent_settings()
        before = json.loads(self.baseline.read_text())
        self.live('config/hypr/current').write_text('manual edit')
        helper.refresh(self.repo, [self.settings], apply=True)
        after = json.loads(self.baseline.read_text())
        self.assertEqual(after['files']['config/hypr/current'], before['files']['config/hypr/current'])
        self.assertEqual(self.live('config/hypr/current').read_text(), 'manual edit')
        self.assertEqual((self.repo / 'config/hypr/current').read_text(), 'initial')

    def test_normalized_settings_snapshot_matches_despite_json_formatting(self):
        data = self.common_agent_settings()
        self.live(self.settings).write_text(json.dumps(data))
        self.assertTrue(helper.refresh(self.repo, [self.settings], apply=True)['applied'])

    def test_missing_installed_ancillary_file_is_not_blessed_as_fallback(self):
        path = self.repo / 'config/kitty/kitty.conf'
        path.parent.mkdir(parents=True)
        path.write_text('font_size 12\n')
        with self.assertRaisesRegex(ValueError, 'differ'):
            helper.refresh(self.repo, ['config/kitty/kitty.conf'], apply=True)

    def test_deleted_files_get_null_baseline_only_when_both_absent(self):
        relative = 'config/hypr/current'
        (self.repo / relative).unlink()
        with self.assertRaisesRegex(ValueError, 'differ'):
            helper.refresh(self.repo, [relative], apply=True)
        self.live(relative).unlink()
        helper.refresh(self.repo, [relative], apply=True)
        self.assertIsNone(json.loads(self.baseline.read_text())['files'][relative])

    def test_invalid_paths_and_foreign_baseline_do_not_write(self):
        before = self.baseline.read_bytes()
        for path in ('../outside', '/tmp/outside', 'README.md', '.', 'compatibility.json'):
            with self.assertRaises(ValueError):
                helper.refresh(self.repo, [path], apply=True)
            self.assertEqual(self.baseline.read_bytes(), before)
        self.baseline.write_text(json.dumps({'repo': '/another/checkout', 'files': {}}))
        with self.assertRaisesRegex(ValueError, 'another checkout'):
            helper.refresh(self.repo, [self.settings], apply=True)

    def test_concurrent_desktop_change_is_detected_without_baseline_write(self):
        self.common_agent_settings()
        original = github_sync.snapshot
        def changed_snapshot(*args):
            original(*args)
            self.live(self.settings).write_text('{"version":1}')
        before = self.baseline.read_bytes()
        with patch.object(github_sync, 'snapshot', side_effect=changed_snapshot):
            with self.assertRaisesRegex(ValueError, 'changed during completion'):
                helper.refresh(self.repo, [self.settings], apply=True)
        self.assertEqual(self.baseline.read_bytes(), before)
        self.assertEqual(checkpoint.backups(), [])

    def test_initial_baseline_creation_is_recoverable(self):
        self.baseline.unlink()
        result = helper.refresh(self.repo, [self.settings], apply=True)
        self.assertEqual(json.loads(self.baseline.read_text())['files'], {
            self.settings: github_sync.file_hash(self.repo / self.settings)})
        subprocess.run([sys.executable, str(SCRIPTS / 'checkpoint.py'), 'restore',
                        result['checkpoint'], '--apply'], check=True, capture_output=True)
        self.assertFalse(self.baseline.exists())


if __name__ == '__main__':
    unittest.main()
