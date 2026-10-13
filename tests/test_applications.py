"""Application preferences: isolated file transactions and native Settings controls."""
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
with patch.object(sys, 'path', [str(ROOT / 'config/quickshell/settings')] + sys.path):
    import applications
    import github_sync


class ApplicationsTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(); self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.config = self.root / 'config'
        self.system = self.root / 'system'
        environment = patch.dict(os.environ, XDG_CONFIG_HOME=str(self.config), XDG_STATE_HOME=str(self.root / 'state'), XDG_CONFIG_DIRS=str(self.system), XDG_CURRENT_DESKTOP='Hyprland')
        environment.start(); self.addCleanup(environment.stop)
        app = self.root / 'viewer.desktop'
        app.write_text('[Desktop Entry]\nType=Application\nName=Example Viewer\nExec=example --show %U\nMimeType=application/pdf;text/plain;\nTerminal=true\n')
        self.installed = {'viewer.desktop': {'id': 'viewer.desktop', 'name': 'Example Viewer', 'types': ['application/pdf', 'text/plain'], 'path': str(app)}}
        mock = patch.object(applications, 'apps', return_value=self.installed)
        mock.start(); self.addCleanup(mock.stop)
        mock = patch.object(applications, 'default_for', return_value='')
        mock.start(); self.addCleanup(mock.stop)

    def write(self, root, name, text):
        path = root / name; path.parent.mkdir(parents=True, exist_ok=True); path.write_text(text)
        return path

    def apply(self, **request):
        return applications.apply({'expected': applications.revision(), **request})

    def test_default_merges_associations_and_higher_priority_overrides(self):
        unrelated = '[Default Applications]\nimage/png=keep.desktop;\n[Added Associations]\napplication/pdf=older.desktop;\n[Removed Associations]\napplication/pdf=viewer.desktop;other.desktop;\n'
        self.write(self.config, 'mimeapps.list', unrelated)
        self.write(self.config, 'hyprland-mimeapps.list', '[Default Applications]\napplication/pdf=override.desktop;\ntext/plain=keep.desktop;\n')
        self.apply(operation='default', types=['application/pdf'], application='viewer.desktop')
        generic = applications.parser((self.config / 'mimeapps.list').read_text())
        specific = applications.parser((self.config / 'hyprland-mimeapps.list').read_text())
        self.assertEqual(generic['Default Applications']['image/png'], 'keep.desktop;')
        self.assertEqual(generic['Default Applications']['application/pdf'], 'viewer.desktop;')
        self.assertEqual(generic['Added Associations']['application/pdf'], 'viewer.desktop;older.desktop;')
        self.assertEqual(generic['Removed Associations']['application/pdf'], 'other.desktop;')
        self.assertEqual(specific['Default Applications']['application/pdf'], 'viewer.desktop;')
        self.assertEqual(specific['Default Applications']['text/plain'], 'keep.desktop;')
        self.assertEqual(applications.saved()['defaults'], {'application/pdf': 'viewer.desktop'})

    def test_chromium_default_restores_across_distributions(self):
        for saved_id, installed_id in [('chromium-browser.desktop', 'chromium.desktop'),
                                       ('chromium.desktop', 'chromium-browser.desktop')]:
            with self.subTest(saved_id=saved_id):
                data = {'version': 1, 'defaults': {'text/html': saved_id}, 'startup': {}}
                changes, skipped = applications.changes_for(data, {installed_id: {}}, restoring=True)
                result = applications.parser(changes[self.config / 'mimeapps.list'])
                self.assertEqual(result['Default Applications']['text/html'], installed_id + ';')
                self.assertEqual(skipped, [])
                self.assertEqual(data['defaults']['text/html'], saved_id)

    def test_external_edit_and_invalid_input_leave_files_untouched(self):
        revision = applications.revision()
        path = self.write(self.config, 'mimeapps.list', '[Default Applications]\ntext/plain=keep.desktop;\n')
        original = path.read_text()
        with self.assertRaisesRegex(ValueError, 'changed elsewhere'):
            applications.apply({'operation': 'default', 'types': ['text/plain'], 'application': 'viewer.desktop', 'expected': revision})
        for request in [dict(operation='default', types=['text/plain\nevil=true'], application='viewer.desktop'), dict(operation='default', types=['text/plain'], application='../viewer.desktop'), dict(operation='startup', entry='../bad.desktop', enabled=True)]:
            with self.assertRaises(ValueError):
                self.apply(**request)
        self.assertEqual(path.read_text(), original)
        self.assertFalse((self.config / 'hyprshell/applications.json').exists())

    def test_failure_restores_mime_and_startup_files(self):
        path = self.write(self.config, 'mimeapps.list', '[Default Applications]\ntext/plain=original.desktop;\n')
        original = path.read_text()
        atomic = applications.atomic
        def fail(path, text):
            if path.name == 'applications.json':
                raise OSError('Simulated disk failure')
            atomic(path, text)
        with patch.object(applications, 'atomic', side_effect=fail), self.assertRaises(OSError):
            self.apply(operation='default', types=['text/plain'], application='viewer.desktop')
        self.assertEqual(path.read_text(), original)
        with patch.object(applications, 'atomic', side_effect=fail), self.assertRaises(OSError):
            self.apply(operation='add', application='viewer.desktop', enabled=True)
        self.assertFalse((self.config / 'autostart/hyprshell-viewer.desktop').exists())
        self.assertFalse((self.config / 'hyprshell/applications.json').exists())
        self.assertTrue(list((self.root / 'state/hyprshell/backups').glob('applications-*')))

    def test_startup_overrides_system_entry_without_altering_command_or_conditions(self):
        original = '[Desktop Entry]\nType=Application\nName=Service\nExec=example --login\nOnlyShowIn=Hyprland;\nTryExec=python3\n'
        system = self.write(self.system, 'autostart/service.desktop', original)
        self.apply(operation='startup', entry='service.desktop', enabled=False)
        live = applications.parser((self.config / 'autostart/service.desktop').read_text())['Desktop Entry']
        self.assertEqual(live['Hidden'], 'true'); self.assertEqual(live['Exec'], 'example --login')
        self.assertEqual(live['OnlyShowIn'], 'Hyprland;')
        self.assertEqual(system.read_text(), original)
        self.apply(operation='startup', entry='service.desktop', enabled=True)
        self.assertTrue(applications.startup_rows()[0]['enabled'])

    def test_hidden_stub_enable_recovers_upstream_and_add_uses_desktop_metadata(self):
        self.write(self.config, 'autostart/service.desktop', '[Desktop Entry]\nHidden=true\n')
        self.write(self.system, 'autostart/service.desktop', '[Desktop Entry]\nType=Application\nName=Service\nExec=example\n')
        self.apply(operation='startup', entry='service.desktop', enabled=True)
        self.assertIn('Exec=example', (self.config / 'autostart/service.desktop').read_text())
        self.apply(operation='add', application='viewer.desktop', enabled=True)
        added = applications.parser((self.config / 'autostart/hyprshell-viewer.desktop').read_text())['Desktop Entry']
        self.assertNotIn('Terminal', added)
        self.assertEqual(added['Exec'], 'uwsm app -t service -- viewer.desktop')
        self.assertEqual(added['OnlyShowIn'], 'Hyprland;')

    def test_one_edit_does_not_reapply_other_saved_choices(self):
        self.apply(operation='default', types=['application/pdf'], application='viewer.desktop')
        path = self.config / 'mimeapps.list'
        path.write_text('[Default Applications]\napplication/pdf=manual.desktop;\n')
        self.apply(operation='default', types=['text/plain'], application='viewer.desktop')
        self.assertEqual(applications.parser(path.read_text())['Default Applications']['application/pdf'], 'manual.desktop;')

    def test_restore_skips_missing_apps_and_is_idempotent(self):
        data = {'version': 1, 'defaults': {'application/pdf': 'viewer.desktop', 'text/plain': 'missing.desktop'}, 'startup': {'hyprshell-viewer.desktop': {'enabled': True, 'application': 'viewer.desktop'}, 'missing.desktop': {'enabled': True}}}
        self.write(self.config, 'hyprshell/applications.json', json.dumps(data))
        result = applications.restore()
        self.assertEqual(result['skipped'], ['missing.desktop'])
        self.assertIn('viewer.desktop', (self.config / 'mimeapps.list').read_text())
        backups = list((self.root / 'state/hyprshell/backups').iterdir())
        applications.restore()
        self.assertEqual(backups, list((self.root / 'state/hyprshell/backups').iterdir()))
        self.assertEqual(applications.saved(), data)

    def test_sync_exports_choices_without_custom_commands(self):
        path = self.write(self.config, 'autostart/custom.desktop', '[Desktop Entry]\nType=Application\nName=Custom\nExec=private-command --personal-argument\n')
        self.apply(operation='startup', entry=path.name, enabled=False)
        self.apply(operation='default', types=['application/pdf'], application='viewer.desktop')
        repo = self.root / 'repo'
        github_sync.snapshot_managed_files(repo, self.config, self.root)
        snapshot = (repo / 'config/hyprshell/applications.json').read_text()
        self.assertNotIn('private-command', snapshot)
        self.assertFalse((repo / 'config/autostart/custom.desktop').exists())
        self.assertEqual(json.loads(snapshot), applications.saved())


class ApplicationsIntegrationTests(unittest.TestCase):
    def test_real_gio_discovery_and_default_after_transaction(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); data = root / 'data/applications'; data.mkdir(parents=True)
            (data / 'example.desktop').write_text('[Desktop Entry]\nType=Application\nName=Example\nExec=/usr/bin/true %U\nMimeType=application/pdf;\n')
            environment = dict(os.environ, HOME=str(root), XDG_CONFIG_HOME=str(root / 'config'), XDG_STATE_HOME=str(root / 'state'), XDG_DATA_HOME=str(root / 'data'), XDG_DATA_DIRS=str(root / 'system-data'), XDG_CONFIG_DIRS=str(root / 'system-config'), XDG_CURRENT_DESKTOP='Hyprland')
            def run(request):
                result = subprocess.run([sys.executable, str(ROOT / 'config/quickshell/settings/applications.py'), '--request-json', json.dumps(request)], env=environment, capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertEqual(result.stderr, '')
                return json.loads(result.stdout)
            initial = run({'operation': 'status'})
            self.assertEqual([app['id'] for app in initial['apps']], ['example.desktop'])
            result = run({'operation': 'default', 'types': ['application/pdf'], 'application': 'example.desktop', 'expected': initial['revision']})
            pdf = next(row for row in result['associations'] if row['label'] == 'PDF documents')
            self.assertEqual(pdf['current'], 'example.desktop')
            # Saved choices must be installed before UWSM generates startup units.
            repo = root / 'saved-repo'; (repo / 'config/hyprshell').mkdir(parents=True)
            for entry in (ROOT / 'config').iterdir():
                if entry.name != 'hyprshell':
                    (repo / 'config' / entry.name).symlink_to(entry)
            for entry in (ROOT / 'config/hyprshell').iterdir():
                if entry.name != 'applications.json':
                    if entry.is_dir():
                        shutil.copytree(entry, repo / 'config/hyprshell' / entry.name)
                    else:
                        (repo / 'config/hyprshell' / entry.name).symlink_to(entry)
            data = {'version': 1, 'defaults': {'application/pdf': 'example.desktop'}, 'startup': {'hyprshell-example.desktop': {'enabled': True, 'application': 'example.desktop'}}}
            (repo / 'config/hyprshell/applications.json').write_text(json.dumps(data))
            for name in ('bin', 'assets'):
                (repo / name).symlink_to(ROOT / name)
            fresh_config = root / 'fresh-config'
            installed = subprocess.run([sys.executable, str(ROOT / 'tools/install_configs.py'), str(repo)], env={**environment, 'XDG_CONFIG_HOME': str(fresh_config)}, capture_output=True, text=True, timeout=20)
            self.assertEqual(installed.returncode, 0, installed.stdout + installed.stderr)
            self.assertIn('application/pdf=example.desktop;', (fresh_config / 'mimeapps.list').read_text())
            self.assertIn('Hidden=false', (fresh_config / 'autostart/hyprshell-example.desktop').read_text())
            self.assertEqual(json.loads((fresh_config / 'hyprshell/applications.json').read_text()), data)

    def test_native_selection_startup_and_failed_save_recovery(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); payload = root / 'config/quickshell'
            shutil.copytree(ROOT / 'config/quickshell', payload, ignore=shutil.ignore_patterns('__pycache__', 'audio-spectrum'))
            (payload / 'settings/applications.py').write_text('''import json, sys
from pathlib import Path
r = json.loads(sys.argv[2]); marker = Path(__file__).with_name('application-test-state')
s = json.loads(marker.read_text()) if marker.exists() else {'default': '', 'startup': True}
if r['operation'] == 'default': s['default'] = r['application']
if r['operation'] == 'startup' and not r['enabled']:
    print(json.dumps({'ok': False, 'message': 'Simulated failure'})); raise SystemExit(1)
if r['operation'] == 'add': s['startup'] = True
marker.write_text(json.dumps(s))
print(json.dumps({'ok': True, 'revision': 'revision', 'apps': [{'id': 'example.desktop', 'name': 'Example'}], 'associations': [{'label': 'PDF', 'types': ['application/pdf'], 'current': s['default'], 'mixed': False, 'candidates': ['example.desktop']}], 'startup': [{'id': 'example.desktop', 'name': 'Example', 'enabled': s['startup'], 'reason': ''}]}))
''')
            fixture = payload / 'ApplicationsNative.qml'
            fixture.write_text('''import QtQuick
import QtQuick.Window
import Quickshell
import "."
ShellRoot {
    id: test
    property int phase: 0
    Window { visible: true; width: 600; height: 900; SettingsApplications { id: page; width: 580 } }
    function find(root, name) { if (root.objectName === name) return root; for (let child of root.children || []) { let match = find(child, name); if (match) return match; } return null; }
    Timer { interval: 50; running: true; repeat: true
        onTriggered: {
            if (page.busy || !page.loaded) return;
            if (test.phase === 0) {
                let picker = test.find(page, "defaultApplication-application/pdf");
                if (!picker) { console.error("APPLICATIONS_FAILED picker"); Qt.quit(); return; }
                picker.currentIndex = 1; picker.activated(1); test.phase = 1;
            } else if (test.phase === 1 && page.associations[0].current === "example.desktop") {
                let toggle = test.find(page, "startupApplication-example.desktop");
                toggle.checked = false; toggle.toggled(); test.phase = 2;
            } else if (test.phase === 2 && !page.success) {
                let toggle = test.find(page, "startupApplication-example.desktop");
                if (!toggle || !toggle.checked || page.associations[0].current !== "example.desktop") console.error("APPLICATIONS_FAILED recovery");
                else console.log("APPLICATIONS_NATIVE_OK");
                Qt.quit();
            }
        }
    }
    Timer { interval: 5000; running: true; onTriggered: { console.error("APPLICATIONS_FAILED timeout", page.message); Qt.quit(); } }
}
''')
            runtime = root / 'runtime'; runtime.mkdir(mode=0o700)
            environment = dict(os.environ, XDG_CONFIG_HOME=str(root / 'config'), XDG_STATE_HOME=str(root / 'state'), XDG_RUNTIME_DIR=str(runtime), QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software', QT_QPA_PLATFORMTHEME='')
            result = subprocess.run(['quickshell', '-p', str(fixture)], capture_output=True, text=True, env=environment, timeout=10)
            output = result.stdout + result.stderr
            self.assertIn('APPLICATIONS_NATIVE_OK', output, output)
            self.assertNotIn('APPLICATIONS_FAILED', output)
