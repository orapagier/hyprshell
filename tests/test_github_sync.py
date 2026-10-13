import importlib.util
import json
import sys
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'config/quickshell/settings'))
spec = importlib.util.spec_from_file_location('github_sync', ROOT / 'config/quickshell/settings/github_sync.py')
syncer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(syncer)


class SyncTests(unittest.TestCase):
    def test_explicit_sync_commits_live_edits_and_preserves_history(self):
        import os
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            repo, remote, config = root / 'repo', root / 'remote', root / 'live'
            subprocess.run(['git', 'init', '--bare', str(remote)], check=True, capture_output=True)
            subprocess.run(['git', 'init', '-b', 'main', str(repo)], check=True, capture_output=True)
            run = lambda *args: syncer.git(repo, *args)
            run('config', 'user.name', 'Test'); run('config', 'user.email', 'test@example.com')
            run('remote', 'add', 'origin', str(remote))
            for name in ('hypr', 'quickshell'):
                (repo / 'config' / name).mkdir(parents=True)
                (repo / 'config' / name / 'current').write_text('original')
                (config / name).mkdir(parents=True)
                (config / name / 'current').write_text('original')
            run('add', '.'); run('commit', '-m', 'initial')
            env = dict(HOME=str(root / 'home'), XDG_CONFIG_HOME=str(config),
                       XDG_STATE_HOME=str(root / 'state'), XDG_DATA_HOME=str(root / 'data'))
            with patch.dict(os.environ, env):
                (config / 'hypr/current').write_text('Manual monitor adjustment')
                previous = run('rev-parse', 'HEAD')
                self.assertEqual((repo / 'config/hypr/current').read_text(), 'original')
                syncer.sync(repo, config, str(remote), 'example/hyprshell')
                first = run('rev-parse', 'HEAD')
                self.assertNotEqual(first, previous)
                self.assertEqual((repo / 'config/hypr/current').read_text(), 'Manual monitor adjustment')
                self.assertEqual(syncer.sync(repo, config, str(remote), 'example/hyprshell'),
                                 'Nothing to sync now.')
                self.assertEqual(first, run('rev-parse', 'HEAD'))
                self.assertEqual(syncer.sync(repo, config, str(remote), 'example/hyprshell'), 'Nothing to sync now.')
                (repo / 'config/hypr/current').write_text('Repo customization')
                self.assertTrue(syncer.save_local(repo, config))
                self.assertEqual((config / 'hypr/current').read_text(), 'Repo customization')
                (repo / 'README.md').write_text('Committed guide')
                run('add', 'README.md')
                description = 'Clarify setup instructions\n\nKeep this description intact.'
                run('commit', '-m', description)
                head = run('rev-parse', 'HEAD')
                syncer.sync(repo, config, str(remote), 'example/hyprshell')
                self.assertEqual(head, run('rev-parse', 'HEAD'))
                self.assertEqual(subprocess.check_output(['git', '--git-dir', str(remote),
                    'log', '-1', '--format=%B', 'main'], text=True).strip(), description)
                (repo / 'config/hypr/current').write_text('repo edit')
                (config / 'hypr/current').write_text('live edit')
                with self.assertRaisesRegex(RuntimeError, 'both changed'):
                    syncer.save_local(repo, config)
                self.assertEqual((repo / 'config/hypr/current').read_text(), 'repo edit')
                self.assertEqual((config / 'hypr/current').read_text(), 'live edit')
                self.assertEqual(run('rev-parse', 'HEAD'), head)
                self.assertEqual(run('diff', '--cached', '--name-only'), '')

    def test_failed_push_retains_the_locally_committed_live_snapshot(self):
        import os
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); repo, config = root / 'repo', root / 'live'
            subprocess.run(['git', 'init', '-b', 'main', str(repo)], check=True, capture_output=True)
            syncer.git(repo, 'config', 'user.name', 'Test'); syncer.git(repo, 'config', 'user.email', 'test@example.com')
            for name in ('hypr', 'quickshell'):
                (repo / 'config' / name).mkdir(parents=True)
                (config / name).mkdir(parents=True)
                (repo / 'config' / name / 'current').write_text('original')
                (config / name / 'current').write_text('original')
            syncer.git(repo, 'add', '.'); syncer.git(repo, 'commit', '-m', 'initial')
            before = syncer.git(repo, 'rev-parse', 'HEAD')
            (config / 'hypr/current').write_text('approved live edit')
            with patch.dict(os.environ, HOME=str(root / 'home'), XDG_CONFIG_HOME=str(config), XDG_STATE_HOME=str(root / 'state')):
                with self.assertRaises(RuntimeError):
                    syncer.sync(repo, config, str(root / 'missing-remote'), 'test/hyprshell')
            self.assertNotEqual(syncer.git(repo, 'rev-parse', 'HEAD'), before)
            self.assertEqual((repo / 'config/hypr/current').read_text(), 'approved live edit')
            self.assertEqual(syncer.git(repo, 'status', '--porcelain'), '')

    def test_managed_payload_uses_live_files_without_importing_private_files(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            repo, config, home = root / 'repo', root / 'live', root / 'home'
            for payload, installed in [
                ('config/kitty', 'live/kitty'),
                ('config/mpv', 'live/mpv'),
                ('config/xdg-desktop-portal', 'live/xdg-desktop-portal'),
                ('config/autostart', 'live/autostart'),
                ('bin', 'home/.local/bin'),
                ('assets/applications', 'home/.local/share/applications'),
                ('assets/wallpapers', 'home/Pictures/Wallpapers'),
            ]:
                destination, source = repo / payload, root / installed
                destination.mkdir(parents=True)
                source.mkdir(parents=True)
                (destination / ('default.jpg' if payload == 'assets/wallpapers' else 'managed')).write_text('repo')
                (destination / 'missing').write_text('installer fallback')
                (source / ('default.jpg' if payload == 'assets/wallpapers' else 'managed')).write_text('live')
                (source / 'private').write_text('private')
            sections = config / 'hyprshell/hyprland'
            sections.mkdir(parents=True)
            (sections / 'programs.lua').write_text('return {terminal = \"kitty\"}\n')
            syncer.snapshot_managed_files(repo, config, home)
            self.assertEqual((repo / 'config/hyprshell/hyprland/programs.lua').read_bytes(),
                             (sections / 'programs.lua').read_bytes())
            for payload in ('config/kitty', 'config/mpv', 'config/xdg-desktop-portal', 'config/autostart', 'bin',
                            'assets/applications', 'assets/wallpapers'):
                self.assertEqual((repo / payload / ('default.jpg' if payload == 'assets/wallpapers' else 'managed')).read_text(), 'live')
                self.assertFalse((repo / payload / 'private').exists())
                self.assertEqual((repo / payload / 'missing').read_text(), 'installer fallback')

    def test_behavior_snapshot_regenerates_rules_and_excludes_backup_and_clipboard_state(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); repo, config, home = root / 'repo', root / 'config', root / 'home'
            (config / 'hyprshell').mkdir(parents=True); home.mkdir()
            data = {'version': 1, 'general': {'layout': 'master'}, 'workspaces': [], 'rules': []}
            (config / 'hyprshell/behavior.json').write_text(json.dumps(data))
            (config / 'hyprshell/behavior.lua').write_text('error("stale generated Lua")')
            (config / 'hyprshell/personal-files.json').write_text('private destination')
            syncer.snapshot_managed_files(repo, config, home)
            self.assertEqual(json.loads((repo / 'config/hyprshell/behavior.json').read_text()), data)
            generated = (repo / 'config/hyprshell/behavior.lua').read_text()
            self.assertIn('layout = "master"', generated); self.assertNotIn('stale', generated)
            self.assertFalse((repo / 'config/hyprshell/personal-files.json').exists())

    def test_identity_is_local_and_validated(self):
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory)
            subprocess.run(['git', 'init', str(repo)], check=True, capture_output=True)
            syncer.identity(repo, 'Example User', 'example@users.noreply.github.com')
            self.assertEqual(syncer.git(repo, 'config', '--local', 'user.name'), 'Example User')
            self.assertEqual(syncer.git(repo, 'config', '--local', 'user.email'), 'example@users.noreply.github.com')
            for name, email in [('', 'a@b'), ('Name', 'bad'), ('Name\nInjected', 'a@b')]:
                with self.assertRaises(ValueError):
                    syncer.identity(repo, name, email)

    def test_authentication_warning_does_not_corrupt_json(self):
        import contextlib
        import io
        import json
        warning = '[glfw error 65544]: No such interface org.freedesktop.portal.Settings'
        completed = [subprocess.CompletedProcess([], 0, '', warning),
                     subprocess.CompletedProcess([], 0, '', '')]
        output = io.StringIO()
        with patch('sys.argv', ['github_sync.py', '--authenticate']), \
             patch.object(syncer.subprocess, 'run', side_effect=completed) as run, \
             patch.object(syncer.shutil, 'which', return_value='/usr/bin/gh'), \
             patch.object(syncer, 'discover', return_value={'ok': True, 'ready': True, 'message': 'Ready'}), \
             contextlib.redirect_stdout(output):
            self.assertEqual(syncer.main(), 0)
        self.assertTrue(json.loads(output.getvalue())['ok'])
        self.assertNotIn('glfw', output.getvalue())
        self.assertTrue(run.call_args_list[0].kwargs['capture_output'])

    def test_authentication_cancel_is_not_reported_as_success(self):
        import contextlib
        import io
        import json
        output = io.StringIO()
        completed = [subprocess.CompletedProcess([], 0, '', ''),
                     subprocess.CompletedProcess([], 1, '', 'not authenticated')]
        with patch('sys.argv', ['github_sync.py', '--authenticate']), \
             patch.object(syncer.subprocess, 'run', side_effect=completed), \
             patch.object(syncer.shutil, 'which', return_value='/usr/bin/gh'), \
             contextlib.redirect_stdout(output):
            self.assertEqual(syncer.main(), 1)
        self.assertFalse(json.loads(output.getvalue())['ok'])

    def test_discovery_accepts_fork_and_new_repository(self):
        for fork in (True, False):
            with self.subTest(fork=fork), patch.object(syncer.shutil, 'which', return_value='/usr/bin/gh'), patch.object(syncer, 'api', side_effect=[
                {'login': 'ramlej', 'id': 123, 'email': None},
                {'full_name': 'ramlej/hyprshell', 'permissions': {'push': True}, 'fork': fork}
            ]) as api:
                result = syncer.discover()
                self.assertTrue(result['ready'])
                self.assertEqual(result['repository'], 'ramlej/hyprshell')
                self.assertEqual(result['target'], 'https://github.com/ramlej/hyprshell.git')
                self.assertEqual(result['email'], '123+ramlej@users.noreply.github.com')
                self.assertEqual(api.call_args_list[1].args, ('repos/ramlej/hyprshell',))

    def test_missing_repository_offers_fork_and_create(self):
        with patch.object(syncer.shutil, 'which', return_value='/usr/bin/gh'), patch.object(syncer, 'api', side_effect=[{'login': 'ramlej', 'id': 123}, None]):
            result = syncer.discover()
        self.assertFalse(result['ready'])
        self.assertEqual(result['repository'], 'ramlej/hyprshell')
        self.assertIn('/orapagier/hyprshell/fork', result['forkUrl'])
        self.assertIn('name=hyprshell&owner=ramlej', result['createUrl'])

    def test_repository_without_write_permission_is_not_ready(self):
        with patch.object(syncer.shutil, 'which', return_value='/usr/bin/gh'), patch.object(syncer, 'api', side_effect=[{'login': 'ramlej', 'id': 123}, {'full_name': 'ramlej/hyprshell', 'permissions': {'push': False}}]):
            self.assertFalse(syncer.discover()['ready'])

    def test_friendly_errors_hide_commands_and_offer_next_steps(self):
        cases = [
            (subprocess.TimeoutExpired(['gh', 'api', '--hostname', 'github.com', 'user'], 30), 'took too long'),
            (RuntimeError("fatal: unable to access 'https://github.com/example/repo': Could not resolve host: github.com"), 'Could not reach GitHub'),
            (RuntimeError('gh: Bad credentials (HTTP 401)'), 'Click Authenticate'),
            (RuntimeError('gh: Forbidden (HTTP 403)'), 'denied access'),
            (subprocess.CalledProcessError(1, ['git', 'push']), 'local changes are still saved'),
        ]
        for error, expected in cases:
            with self.subTest(error=type(error).__name__):
                message = syncer.friendly_error(error)
                self.assertIn(expected, message)
                for raw in ('--hostname', 'gh:', 'fatal:', "['git'", "['gh'"):
                    self.assertNotIn(raw, message)

    def test_api_distinguishes_missing_repository_from_connection_error(self):
        for error, missing in [('gh: Not Found (HTTP 404)', True), ('network unavailable', False), ('gh: Forbidden (HTTP 403)', False)]:
            with self.subTest(error=error), patch.object(syncer.subprocess, 'run', return_value=subprocess.CompletedProcess([], 1, '', error)):
                if missing:
                    self.assertIsNone(syncer.api('repos/example/hyprshell', missing_ok=True))
                else:
                    with self.assertRaises(RuntimeError):
                        syncer.api('repos/example/hyprshell', missing_ok=True)
