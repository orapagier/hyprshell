"""Panel acceptance across real deployment, sync and recovery transactions.

All writes, Git remotes and compiled helpers stay inside temporary roots.
These checks do not exercise physical layer-shell placement or input.
"""
import copy
import itertools
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
import backend
import compatibility
import configuration
import deployment
import github_sync
import github_update
import recovery

NAMES = ('hyprpane',)
EDGES = ('top', 'right', 'bottom', 'left')
SETTINGS = 'hyprshell/settings.json'


def preferences(layout, disjoint=False):
    data = copy.deepcopy(backend.DEFAULTS)
    data['bar'].update(position=layout.get('hyprpane', 'right'), height=39,
                       marginTop=13, marginSide=17, verticalPresentation='compact',
                       workspaceOverrides={'7': False})
    data['pins']['matches'] = {'example.App': 'kitty.desktop'}
    data['items'][0]['hideText'] = True
    data['notifications']['doNotDisturb'] = True
    data['accessibility']['reducedMotion'] = True
    for index, name in enumerate(NAMES, 1):
        panel = data['panels'][name]
        panel.update(enabled=name in layout, monitors=['eDP-1', 'HDMI-A-1'])
        visible = data['bar'] if name == 'hyprpane' else panel
        visible.update(workspaceScope='selected', workspaceList=[index] if disjoint else [1, 2],
                       workspaceOverrides={'7': False, str(index if disjoint else 9): True})
    return backend.validate(data)


class PanelPersistenceTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.repo = self.root / 'repo'
        shutil.copytree(ROOT / 'config', self.repo / 'config',
                        ignore=shutil.ignore_patterns('__pycache__', 'audio-spectrum'))
        shutil.copy2(ROOT / 'compatibility.json', self.repo / 'compatibility.json')
        shutil.copy2(ROOT / '.gitignore', self.repo / '.gitignore')
        env = patch.dict(os.environ, HOME=str(self.root / 'home'),
                         XDG_CONFIG_HOME=str(self.root / 'config'),
                         XDG_STATE_HOME=str(self.root / 'state'),
                         XDG_DATA_HOME=str(self.root / 'data'),
                         HYPRLAND_INSTANCE_SIGNATURE='')
        env.start()
        self.addCleanup(env.stop)
        self.config = self.root / 'config'
        self.target = self.config / SETTINGS
        self.source = self.repo / 'config' / SETTINGS

    def write(self, path, data):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(data, indent=2) + '\n')

    def assert_saved(self, data):
        self.assertEqual(json.loads(self.target.read_text()), data)

    def git(self, *args):
        return github_sync.git(self.repo, *args)

    def init_git(self):
        self.git('init', '-b', 'main')
        self.git('config', 'user.name', 'Panel Test')
        self.git('config', 'user.email', 'panel@example.com')
        self.git('add', '.')
        self.git('commit', '-m', 'Initial panel fixture')

    def test_fresh_setup_restores_every_pair_edge_and_disjoint_workspace_layout(self):
        layouts = [({'hyprpane':edge}, False) for edge in EDGES]
        for index, (layout, disjoint) in enumerate(layouts):
            with self.subTest(layout=layout, disjoint=disjoint):
                data = preferences(layout, disjoint)
                self.write(self.source, data)
                locations = {key: self.root / str(index) / key
                             for key in ('config', 'home', 'data', 'state')}
                deployment.install(self.repo, locations=locations)
                installed = locations['config'] / SETTINGS
                self.assertEqual(json.loads(installed.read_text()), data)
                for name in ('PanelLayout.js', 'SettingsPanelLayout.qml'):
                    self.assertEqual((locations['config'] / 'quickshell' / name).read_bytes(),
                                     (self.repo / 'config/quickshell' / name).read_bytes())

    def test_update_and_deployment_rollback_preserve_live_preferences(self):
        deployment.install(self.repo)
        for edge in EDGES:
            with self.subTest(edge=edge):
                data = preferences(dict.fromkeys(NAMES, edge), disjoint=True)
                self.write(self.target, data)
                before = self.target.read_bytes()
                code = self.repo / 'config/quickshell/PanelLayout.js'
                old = (self.config / 'quickshell/PanelLayout.js').read_bytes()
                code.write_text(code.read_text() + '\n// panel acceptance update\n')
                result = deployment.install(self.repo)
                self.assertIn('config/' + SETTINGS, result['preserved'])
                self.assertEqual(self.target.read_bytes(), before)
                self.assertEqual((self.config / 'quickshell/PanelLayout.js').read_bytes(), code.read_bytes())
                deployment.rollback(Path(result['backup']))
                self.assertEqual((self.config / 'quickshell/PanelLayout.js').read_bytes(), old)
                self.assertEqual(self.target.read_bytes(), before)

    def test_invalid_import_is_rejected_before_any_deployment(self):
        data = preferences({'hyprpane': 'left'})
        self.write(self.source, data)
        deployment.install(self.repo)
        before = {p.relative_to(self.config): p.read_bytes()
                  for p in self.config.rglob('*') if p.is_file()}
        data['bar']['position'] = 'invalid'
        self.write(self.source, data)
        with self.assertRaises(subprocess.CalledProcessError) as caught:
            deployment.install(self.repo, resolved=True)
        self.assertIn('Bar position must be', caught.exception.stderr)
        self.assertEqual({p.relative_to(self.config): p.read_bytes()
                          for p in self.config.rglob('*') if p.is_file()}, before)

    def test_legacy_update_adds_defaults_without_changing_existing_preferences(self):
        legacy = copy.deepcopy(backend.DEFAULTS)
        del legacy['panels'], legacy['pins']
        legacy['bar'].update(position='left', workspaceOverrides={'2': False})
        self.write(self.target, legacy)
        deployment.install(self.repo)
        self.assert_saved(backend.validate(legacy))

    def test_installer_entry_point_restores_then_preserves_panel_preferences(self):
        data = preferences({'hyprpane': 'left'})
        self.write(self.source, data)
        command = ['python3', str(ROOT / 'tools/install_configs.py'), str(self.repo)]
        subprocess.run(command, check=True, capture_output=True, text=True, timeout=60)
        self.assert_saved(data)
        changed = preferences(dict.fromkeys(NAMES, 'right'), disjoint=True)
        self.write(self.target, changed)
        subprocess.run(command, check=True, capture_output=True, text=True, timeout=60)
        self.assert_saved(changed)
        self.assertEqual((self.root / 'state/hyprshell/repository').read_text().strip(), str(self.repo))

    def test_settings_and_setup_backup_restore_layouts_with_undo(self):
        for edge in EDGES:
            for kind in ('settings', 'setup'):
                with self.subTest(edge=edge, kind=kind):
                    data = preferences(dict.fromkeys(NAMES, edge), disjoint=True)
                    self.write(self.target, data)
                    if kind == 'settings':
                        ident = recovery.checkpoint(recovery.revision())
                    else:
                        ident = configuration.request({'operation': 'checkpoint',
                            'expected': configuration.status()['revision']})['createdBackup']
                    changed = preferences({'hyprpane': 'bottom'})
                    backend.save(changed)
                    if kind == 'settings':
                        preview = recovery.preview(ident)
                        self.assertIn('Hyprpane', preview['changes'])
                        recovery.restore(preview['token'])
                        undo = next(row['id'] for row in recovery.backups()
                                    if recovery.snapshot(row['id']) == changed)
                        self.assert_saved(data)
                        recovery.restore(recovery.preview(undo)['token'])
                    else:
                        preview = configuration.request({'operation': 'preview', 'id': ident})['preview']
                        self.assertIn(SETTINGS, preview['changes'])
                        result = configuration.request({'operation': 'restore', 'token': preview['token']})
                        self.assert_saved(data)
                        undo = configuration.request({'operation': 'preview', 'id': result['createdBackup']})['preview']
                        configuration.request({'operation': 'restore', 'token': undo['token']})
                    self.assert_saved(changed)

    def test_explicit_sync_captures_panels_and_fresh_setup_restores_snapshot(self):
        deployment.install(self.repo)
        self.init_git()
        remote = self.root / 'remote.git'
        subprocess.run(['git', 'init', '--bare', str(remote)], check=True, capture_output=True)
        self.git('remote', 'add', 'origin', str(remote))
        for edge in EDGES:
            with self.subTest(edge=edge):
                data = preferences(dict.fromkeys(NAMES, edge), disjoint=True)
                self.write(self.target, data)
                github_sync.sync(self.repo, self.config, str(remote), 'test/panels')
                self.assertEqual(json.loads(self.source.read_text()), data)
                published = subprocess.check_output(['git', '--git-dir', str(remote),
                    'show', 'main:config/' + SETTINGS], text=True)
                self.assertEqual(json.loads(published), data)
                self.assertEqual(self.git('status', '--porcelain'), '')
                fresh = {key: self.root / ('synced-' + edge) / key
                         for key in ('config', 'home', 'data', 'state')}
                deployment.install(self.repo, locations=fresh)
                self.assertEqual(json.loads((fresh['config'] / SETTINGS).read_text()), data)

    def test_reviewed_update_applies_explicit_pane_preference_choices(self):
        baseline = preferences({'hyprpane': 'top'})
        self.write(self.source, baseline)
        deployment.install(self.repo)
        self.init_git()
        base = self.git('rev-parse', 'HEAD')
        incoming = preferences({'hyprpane': 'left'})
        self.write(self.source, incoming)
        self.git('add', '.')
        self.git('commit', '-m', 'Change panel layout')
        remote = self.root / 'remote.git'
        subprocess.run(['git', 'init', '--bare', str(remote)], check=True, capture_output=True)
        self.git('remote', 'add', 'origin', str(remote))
        self.git('push', '-u', 'origin', 'main')
        target = self.git('rev-parse', 'HEAD')
        validator = deployment.validate_staged
        # Compatibility evidence is synthetic; real staging, validation and deployment run.
        info = {'distribution': 'fedora', 'release': '44', 'architecture': 'x86_64',
                'versions': {'hyprland': '0.56.2', 'quickshell': '0.3.2', 'uwsm': '0.27.0', 'qt6': '6.11.2'},
                'atomic': False, 'graphics': ['Intel']}
        selection = {'remote': 'origin', 'ref': 'refs/heads/main',
                     'url': 'https://github.com/example/hyprshell.git', 'branch': 'main'}
        for choice in ('local', 'github'):
            with self.subTest(choice=choice):
                self.git('reset', '--hard', base)
                local = preferences(dict.fromkeys(NAMES, 'right'), disjoint=True)
                self.write(self.target, local)
                with patch.object(github_update, 'source', return_value=selection), \
                     patch.object(compatibility, 'machine', return_value=info), \
                     patch.object(compatibility, 'missing_packages', return_value=[]), \
                     patch.object(deployment, 'validate_staged', side_effect=lambda stage, native=False: validator(stage, False)):
                    review = github_update.preview(self.repo)
                    self.assertTrue(review['ready'], review['blockers'])
                    row = next(row for row in review['selections'] if row['path'] == 'config/' + SETTINGS)
                    self.assertEqual(row['choice'], 'local')
                    review = github_update.preview(self.repo, {'config/' + SETTINGS: choice}, review['token'])
                    self.assertTrue(review['ready'], review['blockers'])
                    github_update.apply(self.repo, review['token'])
                self.assert_saved(local if choice == 'local' else incoming)
                if choice == 'github':
                    self.assertEqual(self.git('rev-parse', 'HEAD'), target)
                else:
                    self.assertEqual(self.git('rev-parse', 'HEAD^2'), target)
                self.assertEqual(json.loads(self.source.read_text()), local if choice == 'local' else incoming)
                self.assertEqual(bool(self.git('status', '--porcelain', '--', 'config/' + SETTINGS)),
                                 choice == 'local')


if __name__ == '__main__':
    unittest.main()
