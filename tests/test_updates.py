"""Real staged installs and local Git update transactions; no network or sudo."""
import copy
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'config/quickshell/settings'))
import compatibility
import deployment
import github_update
sys.path.insert(0, str(ROOT / 'tools'))
import release_acceptance

INFO = {'distribution': 'fedora', 'release': '44', 'architecture': 'x86_64',
        'versions': {'hyprland': '0.56.2', 'quickshell': '0.3.2', 'uwsm': '0.27.0'},
        'atomic': False, 'graphics': ['Intel']}
MANIFEST = json.loads((ROOT / 'compatibility.json').read_text())


class CompatibilityTests(unittest.TestCase):
    def test_supported_unknown_newer_older_and_atomic(self):
        result = compatibility.assess(MANIFEST, INFO)
        self.assertTrue(result['compatible'])
        self.assertIn('not certified', ' '.join(result['warnings']))
        info = copy.deepcopy(INFO); info['versions']['hyprland'] = '0.57.0'
        result = compatibility.assess(MANIFEST, info)
        self.assertTrue(result['compatible']); self.assertIn('not been recorded', ' '.join(result['warnings']))
        for current in ('0.55.0', 'unknown'):
            info['versions']['hyprland'] = current
            self.assertFalse(compatibility.assess(MANIFEST, info)['compatible'])
        info = copy.deepcopy(INFO); info['atomic'] = True
        self.assertFalse(compatibility.assess(MANIFEST, info)['compatible'])
        info = copy.deepcopy(INFO); info['release'] = '45'
        self.assertFalse(compatibility.assess(MANIFEST, info)['compatible'])

    def test_missing_packages_block_and_nvidia_is_not_claimed_certified(self):
        info = copy.deepcopy(INFO); info['graphics'] = ['NVIDIA']
        with patch.object(compatibility, 'missing_packages', return_value=['new-library']):
            result = compatibility.assess(MANIFEST, info, ['new-library'])
        self.assertFalse(result['compatible'])
        self.assertIn('NVIDIA', ' '.join(result['warnings']))


class AcceptanceTests(unittest.TestCase):
    def report(self):
        return {'format': 1, 'revision': 'tested-commit', 'afterLogin': True, 'dirty': False,
                'compatibility': {'compatible': True},
                'readiness': {'checks': [{'title': 'Audio services', 'state': 'ok'}]},
                'manual': {name: {'status': 'pass', 'note': ''} for name in release_acceptance.CHECKLIST}}

    def test_pending_failed_dirty_and_unavailable_reports_are_not_complete(self):
        good = self.report()
        self.assertEqual(release_acceptance.verify(good), [])
        for status in ('pending', 'fail', 'unknown', 'not-applicable'):
            report = self.report(); report['manual']['Session']['status'] = status
            self.assertTrue(release_acceptance.verify(report))
        report = self.report(); report['dirty'] = True
        self.assertTrue(release_acceptance.verify(report))
        report = self.report(); report['readiness']['checks'][0]['state'] = 'unavailable'
        report['exceptions'] = {'Audio services': 'Cannot access from sandbox'}
        self.assertTrue(release_acceptance.verify(report))


class DeploymentTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(); self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        self.repo = self.root / 'repo'
        self.repo.mkdir()
        for name in ('config', 'assets', 'bin', 'profiles'):
            shutil.copytree(ROOT / name, self.repo / name, ignore=shutil.ignore_patterns('__pycache__', 'audio-spectrum'))
        shutil.copy2(ROOT / 'compatibility.json', self.repo / 'compatibility.json')
        self.env = patch.dict(os.environ, HOME=str(self.root / 'home'), XDG_CONFIG_HOME=str(self.root / 'config'),
                              XDG_STATE_HOME=str(self.root / 'state'), XDG_DATA_HOME=str(self.root / 'data'))
        self.env.start(); self.addCleanup(self.env.stop)
        self.config = self.root / 'config'

    def install(self, **kwargs):
        return deployment.install(self.repo, **kwargs)

    def test_generic_install_rerun_personal_restore_and_preserving_update(self):
        first = self.install()
        settings = self.config / 'hyprshell/settings.json'
        defaults = json.loads(settings.read_text())
        self.assertEqual(defaults['bar']['workspaceScope'], 'all')
        self.assertTrue(first['backup'])
        self.assertEqual(self.install()['changed'], [])
        customized = json.loads(settings.read_text()); customized['bar']['height'] = 47
        settings.write_text(json.dumps(customized))
        lua = self.config / 'hyprshell/hyprland/input.lua'
        lua.write_text(lua.read_text() + '\n-- custom input\n')
        extra = self.config / 'hyprshell/hyprland/custom.lua'; extra.write_text('-- user module\n')
        source = self.repo / 'config/quickshell/SettingsButton.qml'
        source.write_text(source.read_text() + '\n// new release\n')
        result = self.install()
        self.assertIn('config/quickshell/SettingsButton.qml', result['changed'])
        self.assertEqual(json.loads(settings.read_text())['bar']['height'], 47)
        self.assertIn('-- custom input', lua.read_text())
        self.assertEqual(extra.read_text(), '-- user module\n')
        self.install(profile='personal')
        self.assertEqual(json.loads(settings.read_text())['bar']['workspaceScope'], 'selected')

    def test_invalid_settings_or_failed_validation_never_replace_live_code(self):
        self.install()
        shell = self.config / 'quickshell/shell.qml'; original = shell.read_bytes()
        incoming = self.repo / 'config/quickshell/shell.qml'; incoming.write_text('// incoming\n')
        with patch.object(deployment, 'validate_staged', side_effect=RuntimeError('validation failed')):
            with self.assertRaisesRegex(RuntimeError, 'validation failed'):
                self.install()
        self.assertEqual(shell.read_bytes(), original)
        settings = self.config / 'hyprshell/settings.json'; settings.write_text('{invalid')
        with self.assertRaises(subprocess.CalledProcessError):
            self.install()
        self.assertEqual(shell.read_bytes(), original)
        self.assertEqual(settings.read_text(), '{invalid')

    def test_conflict_deletion_unknown_files_and_rollback(self):
        self.install()
        managed = self.config / 'quickshell/SettingsButton.qml'
        original = managed.read_bytes()
        managed.write_text('// manual edit')
        with self.assertRaisesRegex(RuntimeError, 'Local edits conflict'):
            self.install()
        managed.write_bytes(original)
        unrelated = self.config / 'quickshell/my-note.txt'; unrelated.write_text('keep')
        (self.repo / 'config/quickshell/SettingsButton.qml').unlink()
        result = self.install()
        self.assertFalse(managed.exists())
        self.assertEqual(unrelated.read_text(), 'keep')
        deployment.rollback(Path(result['backup']))
        self.assertEqual(managed.read_bytes(), original)
        self.assertEqual(unrelated.read_text(), 'keep')

    def test_failed_write_restores_already_written_files(self):
        self.install()
        for name in ('SettingsButton.qml', 'SettingsWindow.qml'):
            p = self.repo / 'config/quickshell' / name; p.write_text(p.read_text() + '\n// update\n')
        originals = {p: p.read_bytes() for p in (self.config / 'quickshell').glob('Settings*.qml')}
        real_replace = os.replace
        failed = False
        def fail_once(source, target):
            nonlocal failed
            if Path(target) == self.config / 'quickshell/SettingsWindow.qml' and not failed:
                failed = True
                raise OSError('simulated disk error')
            return real_replace(source, target)
        with patch.object(deployment.os, 'replace', side_effect=fail_once):
            with self.assertRaisesRegex(OSError, 'simulated'):
                self.install()
        for p, content in originals.items():
            self.assertEqual(p.read_bytes(), content)

    def test_edits_during_validation_are_retained_and_abort(self):
        self.install()
        settings = self.config / 'hyprshell/settings.json'
        real_validate = deployment.validate_staged
        def edit_then_validate(stage, native):
            value = json.loads(settings.read_text()); value['bar']['height'] = 53
            settings.write_text(json.dumps(value))
            real_validate(stage, native)
        with patch.object(deployment, 'validate_staged', side_effect=edit_then_validate):
            with self.assertRaisesRegex(RuntimeError, 'Settings changed during validation'):
                self.install()
        self.assertEqual(json.loads(settings.read_text())['bar']['height'], 53)

    def test_zero_exit_hyprland_parse_error_stops_native_deployment(self):
        self.install()
        shell = self.config / 'quickshell/shell.qml'
        original = shell.read_bytes()
        source = self.repo / 'config/quickshell/shell.qml'
        source.write_text(source.read_text() + '\n// candidate\n')
        real_run = subprocess.run
        def parser_error(args, **kwargs):
            if args[:2] == ['Hyprland', '--verify-config']:
                return subprocess.CompletedProcess(args, 0, 'Configuration error', '')
            return real_run(args, **kwargs)
        with patch.object(deployment.subprocess, 'run', side_effect=parser_error):
            with self.assertRaisesRegex(RuntimeError, 'did not pass validation'):
                self.install(native=True)
        self.assertEqual(shell.read_bytes(), original)


class GitUpdateTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory(); self.addCleanup(temp.cleanup)
        self.root = Path(temp.name); self.repo = self.root / 'repo'; self.remote = self.root / 'remote'
        subprocess.run(['git', 'init', '--bare', str(self.remote)], check=True, capture_output=True)
        subprocess.run(['git', 'init', '-b', 'main', str(self.repo)], check=True, capture_output=True)
        self.git('config', 'user.name', 'Test'); self.git('config', 'user.email', 'test@example.com')
        self.git('remote', 'add', 'origin', str(self.remote))
        (self.repo / 'compatibility.json').write_text(json.dumps(MANIFEST))
        (self.repo / 'packages-fedora.txt').write_text('')
        (self.repo / 'config/quickshell').mkdir(parents=True)
        (self.repo / 'config/quickshell/shell.qml').write_text('// old')
        self.git('add', '.'); self.git('commit', '-m', 'initial'); self.git('push', '-u', 'origin', 'main')
        self.base = self.git('rev-parse', 'HEAD')
        (self.repo / 'config/quickshell/shell.qml').write_text('// new')
        self.git('add', '.'); self.git('commit', '-m', 'Improve shell'); self.git('push')
        self.target = self.git('rev-parse', 'HEAD')
        self.git('reset', '--hard', self.base)  # isolated fixture only
        env = patch.dict(os.environ, HOME=str(self.root / 'home'), XDG_CONFIG_HOME=str(self.root / 'config'),
                         XDG_STATE_HOME=str(self.root / 'state'), XDG_DATA_HOME=str(self.root / 'data'))
        env.start(); self.addCleanup(env.stop)
        src = patch.object(github_update, 'source', return_value={'remote': 'origin', 'ref': 'refs/heads/main',
                          'url': 'https://github.com/example/hyprshell.git', 'branch': 'main'})
        src.start(); self.addCleanup(src.stop)
        hardware = patch.object(compatibility, 'machine', return_value=copy.deepcopy(INFO))
        hardware.start(); self.addCleanup(hardware.stop)

    def git(self, *args):
        return github_update.git(self.repo, *args)

    def test_preview_does_not_checkout_and_apply_uses_exact_reviewed_commit(self):
        result = github_update.preview(self.repo)
        self.assertTrue(result['ready']); self.assertIn('Improve shell', ' '.join(result['commits']))
        self.assertEqual(self.git('rev-parse', 'HEAD'), self.base)
        self.assertEqual((self.repo / 'config/quickshell/shell.qml').read_text(), '// old')
        with patch.object(deployment, 'install', return_value={'backup': ''}) as install:
            result = github_update.apply(self.repo, result['token'])
        self.assertTrue(result['ok']); self.assertTrue(install.call_args.kwargs['native'])
        self.assertEqual(self.git('rev-parse', 'HEAD'), self.target)

    def test_stale_preview_dirty_tree_and_divergence(self):
        result = github_update.preview(self.repo)
        (self.repo / 'local.txt').write_text('work')
        with self.assertRaisesRegex(ValueError, 'changed after'):
            github_update.reviewed(self.repo, result['token'])
        self.assertFalse(github_update.preview(self.repo)['ready'])
        self.git('add', '.'); self.git('commit', '-m', 'local change')
        result = github_update.preview(self.repo)
        self.assertTrue(result['ready'])
        local = self.git('rev-parse', 'HEAD')
        with patch.object(deployment, 'install', return_value={'backup': ''}):
            github_update.apply(self.repo, result['token'])
        self.assertEqual(self.git('rev-parse', 'HEAD^1'), local)
        self.assertEqual(self.git('rev-parse', 'HEAD^2'), self.target)
        self.assertEqual((self.repo / 'local.txt').read_text(), 'work')

    def test_missing_package_blocks_and_expired_preview_fails(self):
        result = github_update.preview(self.repo)
        with patch.object(github_update.time, 'time', return_value=10**12):
            with self.assertRaisesRegex(ValueError, 'expired'):
                github_update.reviewed(self.repo, result['token'])
        with patch.object(compatibility, 'missing_packages', return_value=['new-package']):
            result = github_update.preview(self.repo)
        self.assertFalse(result['ready'])

    def test_live_preferences_change_invalidates_preview(self):
        result = github_update.preview(self.repo)
        p = deployment.roots()['config'] / 'hyprshell/settings.json'; p.parent.mkdir(parents=True)
        p.write_text('{"version":1}')
        with self.assertRaisesRegex(ValueError, 'changed after'):
            github_update.reviewed(self.repo, result['token'])

    def test_hardware_or_version_change_requires_another_preview(self):
        result = github_update.preview(self.repo)
        changed = copy.deepcopy(INFO); changed['graphics'] = ['NVIDIA']
        with patch.object(compatibility, 'machine', return_value=changed):
            with self.assertRaisesRegex(ValueError, 'hardware changed after'):
                github_update.apply(self.repo, result['token'])

    def test_validation_failure_keeps_checkout_at_old_revision(self):
        result = github_update.preview(self.repo)
        with patch.object(deployment, 'install', side_effect=RuntimeError('invalid QML')):
            with self.assertRaisesRegex(RuntimeError, 'invalid QML'):
                github_update.apply(self.repo, result['token'])
        self.assertEqual(self.git('rev-parse', 'HEAD'), self.base)

    def test_archive_rejects_symlinks(self):
        (self.repo / 'escape').symlink_to('/etc/passwd')
        self.git('add', '.'); self.git('commit', '-m', 'bad link')
        with tempfile.TemporaryDirectory() as target:
            with self.assertRaisesRegex(ValueError, 'unsupported file'):
                github_update.archive(self.repo, 'HEAD', Path(target))
