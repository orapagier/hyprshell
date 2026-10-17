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
from unittest.mock import MagicMock, patch
import io
import fcntl

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'config/quickshell/settings'))
import compatibility
import build_info
import deployment
import github_update
sys.path.insert(0, str(ROOT / 'tools'))
import release_acceptance

INFO = {'distribution': 'fedora', 'release': '44', 'architecture': 'x86_64',
        'versions': {'hyprland': '0.56.2', 'quickshell': '0.3.2', 'uwsm': '0.27.0', 'qt6': '6.11.2'},
        'atomic': False, 'graphics': ['Intel']}
MANIFEST = json.loads((ROOT / 'compatibility.json').read_text())


class CompatibilityTests(unittest.TestCase):
    def test_manifest_transition_and_future_format(self):
        legacy = copy.deepcopy(MANIFEST); legacy['format'] = 1
        self.assertTrue(compatibility.assess(legacy, INFO)['compatible'])
        future = copy.deepcopy(MANIFEST); future['format'] = 3
        with self.assertRaisesRegex(ValueError, 'newer compatibility checker'):
            compatibility.assess(future, INFO)
    def test_arch_evidence_does_not_inherit_fedora_dependency_claims(self):
        info = copy.deepcopy(INFO); info.update(distribution='arch', release='rolling')
        result = compatibility.assess(MANIFEST, info)
        self.assertTrue(result['compatible'])
        self.assertIn('2026-10-11', ' '.join(result['checks']))
        self.assertIn('LTS', ' '.join(result['warnings']))
        self.assertNotIn('recorded baseline', ' '.join(result['checks']))

    def test_qt_major_unknown_and_exact_exclusions(self):
        for qt in ('unknown', '5.15.0', '7.0.0'):
            info = copy.deepcopy(INFO); info['versions']['qt6'] = qt
            self.assertFalse(compatibility.assess(MANIFEST, info)['compatible'])
        manifest = copy.deepcopy(MANIFEST)
        manifest['incompatible'] = {'hyprland': {'0.56.2': 'Regression under investigation'}}
        result = compatibility.assess(manifest, INFO)
        self.assertFalse(result['compatible'])
        self.assertIn('Regression under investigation', ' '.join(result['blockers']))
        info = copy.deepcopy(INFO); info['versions']['hyprland'] = '0.56.3'
        self.assertTrue(compatibility.assess(manifest, info)['compatible'])

    def test_host_qt_query_uses_distribution_package(self):
        def output(args):
            if args[0] == 'rpm':
                self.assertEqual(args, ['rpm', '-q', '--qf', '%{VERSION}', 'qt6-qtbase'])
                return '6.11.2'
            return ''
        with patch.object(Path, 'read_text', return_value='ID=fedora\nVERSION_ID=44\n'), \
             patch.object(compatibility, 'command', side_effect=output):
            self.assertEqual(compatibility.machine()['versions']['qt6'], '6.11.2')

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
        for name in ('config', 'assets', 'bin'):
            shutil.copytree(ROOT / name, self.repo / name, ignore=shutil.ignore_patterns('__pycache__', 'audio-spectrum'))
        shutil.copy2(ROOT / 'compatibility.json', self.repo / 'compatibility.json')
        self.env = patch.dict(os.environ, HOME=str(self.root / 'home'), XDG_CONFIG_HOME=str(self.root / 'config'),
                              XDG_STATE_HOME=str(self.root / 'state'), XDG_DATA_HOME=str(self.root / 'data'))
        self.env.start(); self.addCleanup(self.env.stop)
        self.config = self.root / 'config'

    def install(self, **kwargs):
        return deployment.install(self.repo, **kwargs)

    def test_build_identity_survives_checkout_changes_and_rollback(self):
        first = {'channel': 'rolling', 'revision': 'local-merge', 'upstream_revision': 'abc123',
                 'date': '2026-10-11', 'modified': True}
        self.install(build=first)
        self.assertIn('abc123', build_info.installed()['label'])
        self.assertIn('local changes', build_info.installed()['label'])
        source = self.repo / 'config/quickshell/SettingsButton.qml'
        source.write_text(source.read_text() + '\n// upstream change\n')
        second = {**first, 'upstream_revision': 'def456', 'date': '2026-10-14'}
        result = self.install(build=second)
        self.assertEqual(build_info.installed()['upstream_revision'], 'def456')
        deployment.rollback(Path(result['backup']))
        self.assertEqual(build_info.installed()['upstream_revision'], 'abc123')
        self.assertNotIn('upstream change', (self.config / 'quickshell/SettingsButton.qml').read_text())

    def test_metadata_only_update_has_a_recovery_backup(self):
        first = {'revision': 'first', 'channel': 'rolling'}
        self.install(build=first)
        result = self.install(build={'revision': 'second', 'channel': 'rolling'})
        self.assertEqual(result['changed'], [])
        self.assertTrue(result['backup'])
        deployment.rollback(Path(result['backup']))
        self.assertEqual(build_info.installed()['revision'], 'first')

    def test_unified_install_rerun_and_preserving_update(self):
        first = self.install()
        settings = self.config / 'hyprshell/settings.json'
        defaults = json.loads(settings.read_text())
        self.assertEqual(defaults, json.loads((self.repo / 'config/hyprshell/settings.json').read_text()))
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

    def test_reviewed_update_merges_live_customization_and_new_code(self):
        from github_sync import git
        subprocess.run(['git', 'init', '-b', 'main', str(self.repo)], check=True, capture_output=True)
        shutil.copy2(ROOT / '.gitignore', self.repo / '.gitignore')
        (self.repo / 'packages-fedora.txt').write_text('')
        git(self.repo, 'config', 'user.name', 'Test')
        git(self.repo, 'config', 'user.email', 'test@example.com')
        git(self.repo, 'add', '.'); git(self.repo, 'commit', '-m', 'initial')
        remote = self.root / 'remote'
        subprocess.run(['git', 'init', '--bare', str(remote)], check=True, capture_output=True)
        git(self.repo, 'remote', 'add', 'origin', str(remote))
        git(self.repo, 'push', '-u', 'origin', 'main')
        self.install()
        upstream = self.root / 'upstream'
        subprocess.run(['git', 'clone', str(remote), str(upstream)], check=True, capture_output=True)
        # Bare fixtures may default to master despite publishing main.
        git(upstream, 'checkout', 'main')
        git(upstream, 'config', 'user.name', 'Upstream')
        git(upstream, 'config', 'user.email', 'upstream@example.com')
        new = upstream / 'config/quickshell/SettingsWindow.qml'
        new.write_text(new.read_text() + '\n// new upstream feature\n')
        git(upstream, 'add', '.'); git(upstream, 'commit', '-m', 'Add upstream feature')
        git(upstream, 'push', 'origin', 'main')
        settings = self.config / 'hyprshell/settings.json'
        data = json.loads(settings.read_text()); data['bar']['height'] = 47
        settings.write_text(json.dumps(data))
        local_code = self.config / 'quickshell/SettingsButton.qml'
        local_code.write_text(local_code.read_text() + '\n// my local customization\n')
        wallpaper = Path.home() / 'Pictures/Wallpapers/private.jpg'
        wallpaper.write_bytes(b'private wallpaper')
        selection = {'remote': 'origin', 'ref': 'refs/heads/main',
                     'url': 'https://github.com/example/hyprshell.git', 'branch': 'main'}
        validator = deployment.validate_staged
        with patch.object(github_update, 'source', return_value=selection), \
             patch.object(compatibility, 'machine', return_value=copy.deepcopy(INFO)), \
             patch.object(deployment, 'validate_staged', side_effect=lambda stage, native=False: validator(stage, False)):
            review = github_update.preview(self.repo)
            self.assertTrue(review['ready'], review['blockers'])
            local = git(self.repo, 'rev-parse', 'HEAD')
            github_update.apply(self.repo, review['token'])
        self.assertEqual(git(self.repo, 'rev-parse', 'HEAD'), git(upstream, 'rev-parse', 'HEAD'))
        self.assertEqual(local, git(self.repo, 'rev-parse', 'HEAD^'))
        self.assertIn('SettingsButton.qml', git(self.repo, 'diff', '--name-only'))
        self.assertEqual(json.loads(settings.read_text())['bar']['height'], 47)
        self.assertIn('my local customization', local_code.read_text())
        self.assertIn('new upstream feature', (self.config / 'quickshell/SettingsWindow.qml').read_text())
        self.assertEqual(local_code.read_bytes(), (self.repo / 'config/quickshell/SettingsButton.qml').read_bytes())
        self.assertTrue(wallpaper.exists())
        self.assertNotIn('private.jpg', git(self.repo, 'ls-files'))

    def test_reviewed_choice_can_replace_local_preferences_and_code(self):
        self.install()
        settings = self.config / 'hyprshell/settings.json'
        local = json.loads(settings.read_text()); local['bar']['height'] = 47
        settings.write_text(json.dumps(local))
        chosen = json.loads((self.repo / 'config/hyprshell/settings.json').read_text()); chosen['bar']['height'] = 43
        (self.repo / 'config/hyprshell/settings.json').write_text(json.dumps(chosen))
        live = self.config / 'quickshell/SettingsButton.qml'
        live.write_text(live.read_text() + '\n// local\n')
        source = self.repo / 'config/quickshell/SettingsButton.qml'
        source.write_text(source.read_text() + '\n// github version\n')
        self.install(resolved=True)
        self.assertEqual(json.loads(settings.read_text())['bar']['height'], 43)
        self.assertEqual(live.read_bytes(), source.read_bytes())
        self.assertNotIn('// local', live.read_text())

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


class UpdateSelectionTests(unittest.TestCase):
    def setUp(self):
        import update_merge
        self.merge = update_merge
        temp = tempfile.TemporaryDirectory(); self.addCleanup(temp.cleanup)
        self.root = Path(temp.name)
        for name in ('base', 'local', 'incoming', 'result'):
            (self.root / name).mkdir()

    def put(self, folder, name, value):
        path = self.root / folder / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(value)

    def select(self, choices=None):
        rows, policies = self.merge.selections(self.root / 'base', self.root / 'local', self.root / 'incoming', choices or {})
        skipped = {p for paths, _ in policies for p in paths}
        conflicts = self.merge.merge_directories(self.root / 'base', self.root / 'local', self.root / 'incoming', self.root / 'result', choices or {}, skipped)
        self.merge.apply_selections(self.root / 'result', self.root / 'local', self.root / 'incoming', policies)
        return rows, conflicts

    def test_unchanged_local_preferences_do_not_adopt_new_developer_taste(self):
        path = 'config/hyprshell/settings.json'
        for folder, value in [('base', 'original taste'), ('local', 'original taste'), ('incoming', 'new taste')]:
            self.put(folder, path, value)
        self.put('incoming', 'config/quickshell/new.qml', 'new feature')
        rows, conflicts = self.select()
        self.assertEqual(conflicts, [])
        self.assertEqual(rows[0]['choice'], 'local')
        self.assertEqual((self.root / 'result' / path).read_text(), 'original taste')
        self.assertEqual((self.root / 'result/config/quickshell/new.qml').read_text(), 'new feature')

    def test_generated_files_follow_selected_category_and_other_preferences_stay_local(self):
        for name in ('behavior.json', 'behavior.lua', 'theme.json'):
            for folder in ('base', 'local', 'incoming'):
                self.put(folder, 'config/hyprshell/' + name, folder)
        rows, _ = self.select({'config/hyprshell/behavior.json': 'github'})
        for name in ('behavior.json', 'behavior.lua'):
            self.assertEqual((self.root / 'result/config/hyprshell' / name).read_text(), 'incoming')
        self.assertEqual((self.root / 'result/config/hyprshell/theme.json').read_text(), 'local')
        self.assertEqual(len(rows), 2)

    def test_optional_config_can_be_kept_even_without_a_conflict(self):
        path = 'config/kitty/kitty.conf'
        self.put('base', path, 'old'); self.put('local', path, 'old'); self.put('incoming', path, 'new')
        rows, _ = self.select({'config/kitty/kitty.conf': 'local'})
        self.assertFalse(rows[0]['preference'])
        self.assertEqual((self.root / 'result' / path).read_text(), 'old')

    def test_optional_config_default_retains_local_edits(self):
        path = 'config/mpv/mpv.conf'
        self.put('base', path, 'old'); self.put('local', path, 'custom'); self.put('incoming', path, 'new')
        rows, _ = self.select()
        self.assertEqual(rows[0]['choice'], 'local')
        self.assertEqual((self.root / 'result' / path).read_text(), 'custom')

    def test_developer_deletion_requires_opt_in_for_preferences(self):
        path = 'config/hyprshell/theme.json'
        self.put('base', path, 'old'); self.put('local', path, 'mine')
        rows, _ = self.select()
        self.assertTrue((self.root / 'result' / path).exists())
        # Fresh output, as used by every actual review.
        shutil.rmtree(self.root / 'result'); (self.root / 'result').mkdir()
        self.select({path: 'github'})
        self.assertFalse((self.root / 'result' / path).exists())


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
        for name in ('hypr', 'quickshell'):
            (self.root / 'config' / name).mkdir(parents=True, exist_ok=True)
        (self.root / 'config/quickshell/shell.qml').write_text('// old')
        src = patch.object(github_update, 'source', return_value={'remote': 'origin', 'ref': 'refs/heads/main',
                          'url': 'https://github.com/example/hyprshell.git', 'branch': 'main'})
        self.source_patch = src
        src.start(); self.addCleanup(src.stop)
        hardware = patch.object(compatibility, 'machine', return_value=copy.deepcopy(INFO))
        hardware.start(); self.addCleanup(hardware.stop)

    def git(self, *args):
        return github_update.git(self.repo, *args)

    def dependency_candidate(self, distro='fedora'):
        self.git('reset', '--hard', self.target)
        name = 'packages-fedora.txt' if distro == 'fedora' else 'packages.txt'
        (self.repo / name).write_text('new-library\n')
        self.git('add', name); self.git('commit', '-m', 'Require new library')
        self.git('push', 'origin', 'HEAD:main')
        self.target = self.git('rev-parse', 'HEAD')
        self.git('reset', '--hard', self.base)

    def test_dependency_preview_commands_for_both_distros(self):
        for distro, command in [('fedora', '/usr/bin/pkexec /usr/bin/dnf install --assumeyes new-library'),
                                ('arch', '/usr/bin/pkexec /usr/bin/pacman -Syu --needed --noconfirm new-library')]:
            self.dependency_candidate(distro)
            info = copy.deepcopy(INFO); info['distribution'] = distro
            info['release'] = 'rolling' if distro == 'arch' else '44'
            with patch.object(compatibility, 'machine', return_value=info), \
                 patch.object(compatibility, 'missing_packages', side_effect=lambda names, distro: list(names)):
                review = github_update.preview(self.repo)
            self.assertEqual(review['missingPackages'], ['new-library'])
            self.assertEqual(review['dependencyCommand'], command)
            self.assertTrue(review['canInstallDependencies'])
            self.assertFalse(review['ready'])

    def test_dependency_install_requires_confirmation_and_fresh_review(self):
        self.dependency_candidate()
        launches, installed = [], False
        actual_popen = subprocess.Popen
        def popen(args, **kwargs):
            nonlocal installed
            if '--dependency-worker' in args:
                launches.append(args)
                # The child must be able to revalidate immediately on startup.
                with github_update.repository_lock(self.repo):
                    pass
                self.assertTrue(kwargs['start_new_session'])
                self.assertTrue(kwargs['pass_fds'])
                return MagicMock()
            if args[0] == '/usr/bin/pkexec':
                launches.append(args)
                installed = True
                process = MagicMock()
                process.__enter__.return_value = process
                process.stdout = io.StringIO('Resolving packages\nInstalled new-library\n')
                process.wait.return_value = 0
                return process
            return actual_popen(args, **kwargs)
        with patch.object(compatibility, 'missing_packages', side_effect=lambda names, distro: [] if installed else list(names)), \
             patch.object(github_update.shutil, 'which', return_value='/usr/bin/tool'), \
             patch.object(github_update.subprocess, 'Popen', side_effect=popen):
            review = github_update.preview(self.repo)
            with self.assertRaisesRegex(ValueError, 'confirm installation'):
                github_update.install_dependencies(self.repo, review['token'])
            self.assertEqual(launches, [])
            result = github_update.install_dependencies(self.repo, review['token'], True)
            self.assertTrue(result['running'])
            self.assertEqual(result['operation'], 'dependencies')
            self.assertIn('--dependency-worker', launches[0])
            finished = github_update.run_dependencies(self.repo, review['token'])
            self.assertTrue(finished['ok'])
            self.assertFalse(finished['running'])
            self.assertIn('Installed new-library', finished['output'])
            self.assertEqual(launches[1], ['/usr/bin/pkexec', '/usr/bin/dnf', 'install', '--assumeyes', 'new-library'])
            self.assertEqual(self.git('rev-parse', 'HEAD'), self.base)
            self.assertEqual((self.root / 'config/quickshell/shell.qml').read_text(), '// old')
            with self.assertRaisesRegex(ValueError, 'Check again'):
                github_update.install_dependencies(self.repo, review['token'], True)
            self.assertTrue(github_update.preview(self.repo)['ready'])

    def test_dependency_install_refuses_stale_unsupported_or_changed_requirements(self):
        self.dependency_candidate()
        with patch.object(compatibility, 'missing_packages', side_effect=lambda names, distro: list(names)):
            review = github_update.preview(self.repo)
            (self.repo / 'config/quickshell/shell.qml').write_text('// edited after review')
            with self.assertRaisesRegex(ValueError, 'changed after'):
                github_update.install_dependencies(self.repo, review['token'], True)
            (self.repo / 'config/quickshell/shell.qml').write_text('// old')
            info = copy.deepcopy(INFO); info['release'] = '45'
            with patch.object(compatibility, 'machine', return_value=info):
                unsupported = github_update.preview(self.repo)
                self.assertFalse(unsupported['canInstallDependencies'])
                with self.assertRaisesRegex(ValueError, 'Resolve the update review'):
                    github_update.install_dependencies(self.repo, unsupported['token'], True)
            review = github_update.preview(self.repo)
        with patch.object(compatibility, 'missing_packages', return_value=[]):
            with self.assertRaisesRegex(ValueError, 'dependencies changed'):
                github_update.install_dependencies(self.repo, review['token'], True)

    def test_dependency_background_denial_failure_and_missing_authentication(self):
        self.dependency_candidate()
        actual_popen = subprocess.Popen
        with patch.object(compatibility, 'missing_packages', side_effect=lambda names, distro: list(names)):
            review = github_update.preview(self.repo)
            with patch.object(github_update.shutil, 'which', return_value=None):
                with self.assertRaisesRegex(ValueError, 'authentication.*unavailable'):
                    github_update.install_dependencies(self.repo, review['token'], True)
            for code, expected in [(126, 'cancelled or denied'), (1, 'installation failed'), (0, 'still missing')]:
                def popen(args, **kwargs):
                    if args[0] == '/usr/bin/pkexec':
                        process = MagicMock(); process.__enter__.return_value = process
                        process.stdout = io.StringIO('Transaction could not complete\n')
                        process.wait.return_value = code
                        return process
                    return actual_popen(args, **kwargs)
                with patch.object(github_update.shutil, 'which', return_value='/usr/bin/tool'), \
                     patch.object(github_update.subprocess, 'Popen', side_effect=popen):
                    result = github_update.run_dependencies(self.repo, review['token'])
                    self.assertFalse(result['ok'])
                    self.assertIn(expected, result['message'])
                    self.assertIn('Transaction could not complete', result['output'])
                review = github_update.preview(self.repo)
                self.assertFalse(review['ready'])

    def test_dependency_worker_launch_failure_is_not_left_running(self):
        self.dependency_candidate()
        actual_popen = subprocess.Popen
        def popen(args, **kwargs):
            if '--dependency-worker' in args:
                raise OSError('simulated worker launch failure')
            return actual_popen(args, **kwargs)
        with patch.object(compatibility, 'missing_packages', side_effect=lambda names, distro: list(names)), \
             patch.object(github_update.shutil, 'which', return_value='/usr/bin/tool'), \
             patch.object(github_update.subprocess, 'Popen', side_effect=popen):
            review = github_update.preview(self.repo)
            with self.assertRaisesRegex(OSError, 'simulated worker launch'):
                github_update.install_dependencies(self.repo, review['token'], True)
            result = github_update.status()
            self.assertFalse(result['ok'])
            self.assertFalse(result['running'])
            self.assertFalse(github_update.reviewed(self.repo, review['token'], require_ready=False).get('dependenciesRequested', False))

    def test_dependency_jobs_share_update_lock_and_report_interruption(self):
        self.dependency_candidate()
        with patch.object(compatibility, 'missing_packages', side_effect=lambda names, distro: list(names)), \
             patch.object(github_update.shutil, 'which', return_value='/usr/bin/tool'):
            review = github_update.preview(self.repo)
            state = deployment.roots()['state']
            with (state / 'update-job.lock').open('a') as lock:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                with self.assertRaisesRegex(ValueError, 'already running'):
                    github_update.install_dependencies(self.repo, review['token'], True)
                deployment.atomic_json(state / 'update-status.json', {'operation': 'dependencies', 'ok': True,
                                       'running': True, 'output': 'Downloading package', 'packages': ['new-library']})
                self.assertTrue(github_update.status()['running'])
            result = github_update.status()
            self.assertFalse(result['running'])
            self.assertFalse(result['ok'])
            self.assertEqual(result['operation'], 'dependencies')
            self.assertEqual(result['output'], 'Downloading package')

    def test_developer_updates_ignore_user_fork_and_tracking_branch(self):
        self.source_patch.stop()
        fork = self.root / 'fork'
        subprocess.run(['git', 'init', '--bare', str(fork)], check=True, capture_output=True)
        self.git('remote', 'set-url', 'origin', str(fork))
        self.git('push', 'origin', 'HEAD:refs/heads/personal')
        self.git('branch', '-m', 'personal')
        self.git('config', 'branch.personal.remote', 'origin')
        self.git('config', 'branch.personal.merge', 'refs/heads/personal')
        with patch.object(github_update, 'DEVELOPER_REPOSITORY', str(self.remote)):
            selection = github_update.source(self.repo)
            self.assertEqual(selection['branch'], 'main')
            self.assertEqual(selection['remote'], str(self.remote))
            review = github_update.preview(self.repo)
            self.assertTrue(review['ready'])
            self.assertEqual(review['target'], self.target)
            self.assertEqual(review['repository'], str(self.remote))
            self.git('checkout', '-b', 'other-personal')
            with self.assertRaisesRegex(ValueError, 'changed after'):
                github_update.reviewed(self.repo, review['token'])
            self.git('checkout', 'personal')
            with patch.object(deployment, 'install', return_value={'backup': ''}):
                github_update.apply(self.repo, review['token'])
        self.assertEqual(self.git('rev-parse', 'HEAD'), self.target)
        self.assertEqual(self.git('remote', 'get-url', 'origin'), str(fork))
        self.assertEqual(self.git('config', 'branch.personal.remote'), 'origin')
        self.assertEqual(self.git('config', 'branch.personal.merge'), 'refs/heads/personal')
        self.assertEqual(github_update.git(fork, 'rev-parse', 'personal'), self.base)

    def test_live_settings_preserved_by_default_and_developer_choice_is_reviewed(self):
        self.git('reset', '--hard', self.target)
        source = self.repo / 'config/hyprshell/settings.json'
        source.parent.mkdir(parents=True)
        defaults = json.loads((ROOT / 'config/hyprshell/settings.json').read_text())
        source.write_text(json.dumps(defaults, indent=2) + '\n')
        self.git('add', '.'); self.git('commit', '-m', 'Add settings fixture')
        settings_base = self.git('rev-parse', 'HEAD')
        developer = copy.deepcopy(defaults); developer['bar']['height'] = 43
        source.write_text(json.dumps(developer, indent=2) + '\n')
        self.git('add', '.'); self.git('commit', '-m', 'Change developer bar height'); self.git('push')
        settings_target = self.git('rev-parse', 'HEAD')
        self.git('reset', '--hard', settings_base)
        (self.root / 'config/quickshell/shell.qml').write_text('// new')
        live = self.root / 'config/hyprshell/settings.json'
        live.parent.mkdir(parents=True)
        local = copy.deepcopy(defaults); local['bar']['height'] = 47
        live.write_text(json.dumps(local, indent=2) + '\n')
        review = github_update.preview(self.repo)
        self.assertTrue(review['ready'])
        conflict = next(c for c in review['selections'] if c['path'] == 'config/hyprshell/settings.json')
        self.assertEqual(conflict['choice'], 'local')
        self.assertEqual(json.loads(conflict['local'])['bar']['height'], 47)
        self.assertEqual(json.loads(conflict['github'])['bar']['height'], 43)
        self.assertIn('-    "height": 47', conflict['diff'])
        self.assertIn('+    "height": 43', conflict['diff'])
        for choice, height in (('local', 47), ('github', 43)):
            review = github_update.preview(self.repo, {'config/hyprshell/settings.json': choice}, review['token'])
            self.assertTrue(review['ready'])
            with tempfile.TemporaryDirectory() as directory:
                github_update.archive(self.repo, github_update.reviewed(self.repo, review['token'])['tree'], Path(directory))
                self.assertEqual(json.loads((Path(directory) / 'config/hyprshell/settings.json').read_text())['bar']['height'], height)
        def install(candidate, **kwargs):
            live.write_bytes((candidate / 'config/hyprshell/settings.json').read_bytes())
            return {'backup': ''}
        with patch.object(deployment, 'install', side_effect=install):
            github_update.apply(self.repo, review['token'])
        self.assertEqual(json.loads(live.read_text())['bar']['height'], 43)
        self.assertEqual(self.git('rev-parse', 'HEAD'), settings_target)
        self.assertEqual(self.git('status', '--porcelain'), '')

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

    def test_conflict_choices_apply_without_committing_live_edits(self):
        live = self.root / 'config/quickshell/shell.qml'
        live.write_text('// my uncommitted desktop')
        review = github_update.preview(self.repo)
        self.assertFalse(review['ready'])
        self.assertEqual(review['conflicts'][0]['path'], 'config/quickshell/shell.qml')
        self.assertEqual(review['conflicts'][0]['local'], '// my uncommitted desktop')
        self.assertEqual(review['conflicts'][0]['github'], '// new')
        self.assertIn('-// my uncommitted desktop\n', review['conflicts'][0]['diff'])
        self.assertIn('+// new\n', review['conflicts'][0]['diff'])
        self.assertEqual(self.git('rev-parse', 'HEAD'), self.base)
        self.assertEqual(self.git('status', '--porcelain'), '')
        with self.assertRaisesRegex(ValueError, 'cannot be applied'):
            github_update.apply(self.repo, review['token'])
        for choice, expected in (('local', '// my uncommitted desktop'), ('github', '// new')):
            selected = github_update.preview(self.repo, {'config/quickshell/shell.qml': choice}, review['token'])
            self.assertTrue(selected['ready'], selected['blockers'])
            with tempfile.TemporaryDirectory() as directory:
                github_update.archive(self.repo, github_update.reviewed(self.repo, selected['token'])['tree'], Path(directory))
                self.assertEqual((Path(directory) / 'config/quickshell/shell.qml').read_text(), expected)
            review = selected
        real_install = deployment.install
        def minimal_install(candidate, **kwargs):
            live.write_text((candidate / 'config/quickshell/shell.qml').read_text())
            return {'backup': ''}
        with patch.object(deployment, 'install', side_effect=minimal_install):
            github_update.apply(self.repo, review['token'])
        self.assertEqual(live.read_text(), '// new')
        self.assertEqual(self.git('rev-parse', 'HEAD'), self.target)
        self.assertEqual(self.git('status', '--porcelain'), '')

    def test_keep_local_conflict_remains_uncommitted_after_update(self):
        live = self.root / 'config/quickshell/shell.qml'; live.write_text('// local')
        review = github_update.preview(self.repo)
        selected = github_update.preview(self.repo, {'config/quickshell/shell.qml': 'local'}, review['token'])
        with patch.object(deployment, 'install', return_value={'backup': ''}):
            github_update.apply(self.repo, selected['token'])
        self.assertEqual(self.git('rev-parse', 'HEAD'), self.target)
        self.assertEqual((self.repo / 'config/quickshell/shell.qml').read_text(), '// local')
        self.assertEqual(live.read_text(), '// local')
        self.assertIn('shell.qml', self.git('diff', '--name-only'))
        self.assertEqual(self.git('diff', '--cached', '--name-only'), '')

    def test_skip_nonconflicting_optional_config_applies_core_update_and_records_choice(self):
        self.git('reset', '--hard', self.target)
        optional = self.repo / 'config/kitty/kitty.conf'
        optional.parent.mkdir(parents=True)
        optional.write_text('font_size 14\n')
        self.git('add', '.'); self.git('commit', '-m', 'Add optional terminal config'); self.git('push')
        incoming = self.git('rev-parse', 'HEAD')
        self.git('reset', '--hard', self.base)
        review = github_update.preview(self.repo)
        row = next(r for r in review['selections'] if r['path'] == 'config/kitty/kitty.conf')
        self.assertEqual(row['choice'], 'github')
        self.assertTrue(review['ready'])
        selected = github_update.preview(self.repo, {row['path']: 'local'}, review['token'])
        def install(candidate, **kwargs):
            self.assertFalse((candidate / 'config/kitty/kitty.conf').exists())
            self.assertEqual((candidate / 'config/quickshell/shell.qml').read_text(), '// new')
            return {'backup': ''}
        with patch.object(deployment, 'install', side_effect=install):
            github_update.apply(self.repo, selected['token'])
        self.assertFalse(optional.exists())
        self.assertEqual((self.repo / 'config/quickshell/shell.qml').read_text(), '// new')
        self.assertEqual(self.git('rev-parse', 'HEAD^2'), incoming)
        self.assertEqual(self.git('status', '--porcelain'), '')

    def test_choices_are_bound_to_review_and_reject_stale_or_unknown_paths(self):
        live = self.root / 'config/quickshell/shell.qml'; live.write_text('// local')
        review = github_update.preview(self.repo)
        with self.assertRaisesRegex(ValueError, 'Invalid conflict choices'):
            github_update.preview(self.repo, {'../../escape': 'github'}, review['token'])
        live.write_text('// changed since preview')
        with self.assertRaisesRegex(ValueError, 'changed after'):
            github_update.preview(self.repo, {'config/quickshell/shell.qml': 'github'}, review['token'])
        self.assertEqual(self.git('rev-parse', 'HEAD'), self.base)

    def test_checkout_edit_during_validation_is_retained(self):
        review = github_update.preview(self.repo)
        path = self.repo / 'config/quickshell/shell.qml'
        def changed_checkout(*args, **kwargs):
            path.write_text('// concurrently edited')
            return {'backup': ''}
        with patch.object(deployment, 'install', side_effect=changed_checkout):
            with self.assertRaisesRegex(ValueError, 'changed during validation'):
                github_update.apply(self.repo, review['token'])
        self.assertEqual(path.read_text(), '// concurrently edited')
        self.assertEqual(self.git('rev-parse', 'HEAD'), self.base)

    def test_failed_checkout_merge_restores_uncommitted_edits(self):
        path = self.repo / 'config/quickshell/shell.qml'
        path.write_text('// repo edit')
        live = self.root / 'config/quickshell/shell.qml'; live.write_text('// old')
        review = github_update.preview(self.repo)
        selected = github_update.preview(self.repo, {'config/quickshell/shell.qml': 'local'}, review['token'])
        real_git = github_update.git
        def failed_merge(repo, *args):
            if 'merge' in args and '--ff-only' in args: raise RuntimeError('merge failed')
            return real_git(repo, *args)
        with patch.object(deployment, 'install', return_value={'backup': ''}), patch.object(github_update, 'git', side_effect=failed_merge):
            with self.assertRaisesRegex(RuntimeError, 'merge failed'):
                github_update.apply(self.repo, selected['token'])
        self.assertEqual(path.read_text(), '// repo edit')
        self.assertEqual(self.git('rev-parse', 'HEAD'), self.base)
        self.assertEqual(self.git('diff', '--cached', '--name-only'), '')

    def test_delete_conflict_has_explicit_local_and_github_choices(self):
        self.git('reset', '--hard', self.target)
        (self.repo / 'config/quickshell/shell.qml').unlink()
        self.git('add', '.'); self.git('commit', '-m', 'Remove shell fixture'); self.git('push')
        removed = self.git('rev-parse', 'HEAD')
        self.git('reset', '--hard', self.base)
        live = self.root / 'config/quickshell/shell.qml'; live.write_text('// local')
        review = github_update.preview(self.repo)
        self.assertTrue(review['conflicts'][0]['githubDeleted'])
        self.assertIn('+(File deleted)', review['conflicts'][0]['diff'])
        selected = github_update.preview(self.repo, {'config/quickshell/shell.qml': 'github'}, review['token'])
        self.assertTrue(selected['ready'])
        with tempfile.TemporaryDirectory() as directory:
            github_update.archive(self.repo, github_update.reviewed(self.repo, selected['token'])['tree'], Path(directory))
            self.assertFalse((Path(directory) / 'config/quickshell/shell.qml').exists())
        self.assertEqual(live.read_text(), '// local')
        self.assertEqual(self.git('rev-parse', 'HEAD'), self.base)

    def test_failed_post_merge_overlay_restores_head_and_local_edits(self):
        live = self.root / 'config/quickshell/shell.qml'; live.write_text('// local')
        review = github_update.preview(self.repo)
        selected = github_update.preview(self.repo, {'config/quickshell/shell.qml': 'local'}, review['token'])
        real_overlay = github_update.update_merge.overlay
        calls = 0
        def fail_overlay(*args, **kwargs):
            nonlocal calls
            calls += 1
            if calls == 2: raise OSError('overlay failed')
            return real_overlay(*args, **kwargs)
        with patch.object(deployment, 'install', return_value={'backup': ''}), patch.object(github_update.update_merge, 'overlay', side_effect=fail_overlay):
            with self.assertRaisesRegex(OSError, 'overlay failed'):
                github_update.apply(self.repo, selected['token'])
        self.assertEqual(self.git('rev-parse', 'HEAD'), self.base)
        self.assertEqual((self.repo / 'config/quickshell/shell.qml').read_text(), '// old')
        self.assertEqual(live.read_text(), '// local')
        self.assertEqual(self.git('status', '--porcelain'), '')

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
