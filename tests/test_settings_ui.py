"""Exercise real asynchronous settings writes without desktop services or sockets."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('quickshell'), 'Quickshell is needed for the native UI smoke test')
class AutosaveTests(unittest.TestCase):
    def test_accessibility_updates_all_controls_and_survives_reopen(self):
        settings = self.run_ui_scenario('SettingsAccessibilityNative', 'ACCESSIBILITY_OK', ('right', '', 1))
        self.assertEqual(settings['accessibility'], {'textScale': 1.5, 'highContrast': True, 'reducedMotion': True})
    def test_debounce_queued_edits_validation_recovery_and_close_flush(self):
        self.run_ui_scenario('SettingsAutosave', 'AUTOSAVE_OK', ('left', '#00ff00', 0.7))

    def test_lazy_loading_close_flush_failed_draft_and_reopen(self):
        self.run_ui_scenario('SettingsLifecycle', 'LIFECYCLE_OK', ('right', '#00ff00', 1))

    def test_bar_positions_autosave_and_survive_reopening(self):
        settings = self.run_ui_scenario('SettingsBarPosition', 'BAR_POSITION_OK', ('right', '', 1))
        self.assertEqual(settings['bar']['position'], 'top')
        self.assertEqual(settings['bar']['compactSpacing'], 4)
        self.assertTrue(settings['bar']['centerItems'])
        for side in ('Top', 'Bottom', 'Left', 'Right'):
            self.assertEqual(settings['bar']['screenMargin' + side], 12)
            self.assertEqual(settings['bar']['contentPadding' + side], 6)

    def test_workspace_shortcut_queues_with_autosave_and_survives_reopening(self):
        settings = self.run_ui_scenario('SettingsWorkspaceVisibility', 'WORKSPACE_VISIBILITY_OK', ('right', '', 1))
        self.assertEqual(settings['bar']['workspaceOverrides'], {'1': False, '3': True})
        self.assertEqual(settings['bar']['workspaceList'], [1])
        self.assertEqual(settings['bar']['spacing'], 17)

    def test_panel_shortcut_is_immediate_during_slow_saves_and_reverts_failure(self):
        settings = self.run_ui_scenario('PanelShortcutVisibility', 'PANEL_SHORTCUT_OK', ('right', '', 1))
        self.assertEqual(settings['bar']['workspaceOverrides'], {'3': False, '4': False})

    def test_search_navigation_scroll_and_responsive_layout(self):
        with tempfile.TemporaryDirectory(prefix='hyprshell-navigation-') as directory:
            root = Path(directory)
            payload = root / 'config/quickshell'
            shutil.copytree(ROOT / 'config/quickshell', payload, ignore=shutil.ignore_patterns('__pycache__', 'audio-spectrum'))
            entry = payload / 'SettingsNavigation.qml'
            entry.write_text((payload / 'tests/SettingsNavigation.qml').read_text().replace('import ".."', 'import "."'))
            runtime = root / 'runtime'
            runtime.mkdir(mode=0o700)
            env = dict(os.environ, XDG_CONFIG_HOME=str(root / 'config'), XDG_STATE_HOME=str(root / 'state'),
                       XDG_RUNTIME_DIR=str(runtime), QT_QPA_PLATFORMTHEME='', QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software')
            result = subprocess.run(['quickshell', '--log-rules', 'qml=true', '-p', str(entry)], env=env, capture_output=True, text=True, timeout=18)
            output = result.stdout + result.stderr
            self.assertIn('NAVIGATION_OK', output, output)
            self.assertEqual(result.returncode, 0, output)
            for error in ('NAVIGATION_FAILED', 'TypeError', 'ReferenceError', 'Unable to assign', 'Binding loop'):
                self.assertNotIn(error, output, output)
            self.assertFalse((root / 'config/hyprshell/settings.json').exists(), 'Navigation must not save preferences')

    def test_github_setup_popup(self):
        with tempfile.TemporaryDirectory(prefix='hyprshell-github-ui-') as directory:
            root = Path(directory)
            payload = root / 'config/quickshell'
            shutil.copytree(ROOT / 'config/quickshell', payload, ignore=shutil.ignore_patterns('__pycache__', 'audio-spectrum'))
            # Discovery finds the repo; sync returns only its acknowledgement.
            (payload / 'settings/github_sync.py').write_text(
                'import json, sys\nfrom pathlib import Path\n'
                'if len(sys.argv) == 1:\n'
                '    print(json.dumps({"ok": True, "message": "Synced to ramlej/hyprshell (main)."}))\n'
                '    sys.exit(0)\n'
                'counter = Path(__file__).with_name("checks")\n'
                'ready = counter.exists()\ncounter.touch()\n'
                'print(json.dumps({"ok": True, "ready": ready, "repository": "ramlej/hyprshell", '
                '"message": "Ready" if ready else "Fork or create your repo", '
                '"forkUrl": "" if ready else "https://github.com/orapagier/hyprshell/fork", '
                '"createUrl": "" if ready else "https://github.com/new?name=hyprshell&owner=ramlej"}))\n')
            entry = payload / 'GithubSetup.qml'
            entry.write_text((payload / 'tests/GithubSetup.qml').read_text().replace('import ".."', 'import "."'))
            runtime = root / 'runtime'
            runtime.mkdir(mode=0o700)
            env = dict(os.environ, XDG_CONFIG_HOME=str(root / 'config'), XDG_STATE_HOME=str(root / 'state'), XDG_RUNTIME_DIR=str(runtime), QT_QPA_PLATFORMTHEME='', QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software')
            result = subprocess.run(['quickshell', '--log-rules', 'qml=true', '-p', str(entry)], env=env, capture_output=True, text=True, timeout=20)
            self.assertIn('GITHUB_SETUP_OK', result.stdout + result.stderr, result.stdout + result.stderr)
            self.assertNotIn('FAIL!', result.stdout + result.stderr)

    def run_ui_scenario(self, scenario, marker, expected_audio):
        with tempfile.TemporaryDirectory(prefix='hyprshell-autosave-') as directory:
            root = Path(directory)
            commands = root / 'bin'
            commands.mkdir()
            # Slow the backend so the QML test can reliably edit while saving.
            wrapper = commands / 'python3'
            failure = ("if '--set-bar-visibility' in sys.argv and sys.argv[-2] == '9':\n"
                       "    print('{\"ok\": false, \"message\": \"simulated save failure\"}'); sys.exit(1)\n"
                       if scenario == 'PanelShortcutVisibility' else '')
            wrapper.write_text(f'#!{sys.executable}\nimport os, sys, time\ntime.sleep(0.3)\n' + failure
                               + f'os.execv({sys.executable!r}, [{sys.executable!r}] + sys.argv[1:])\n')
            wrapper.chmod(0o755)
            runtime = root / 'runtime'
            runtime.mkdir(mode=0o700)
            payload = root / 'config/quickshell'
            shutil.copytree(ROOT / 'config/quickshell', payload, ignore=shutil.ignore_patterns('__pycache__', 'audio-spectrum'))
            entry = payload / (scenario + '.qml')
            entry.write_text((payload / 'tests' / (scenario + '.qml')).read_text()
                             .replace('import ".."', 'import "."').replace('import "../', 'import "./'))
            if scenario == 'SettingsAccessibilityNative':
                main = root / 'config/hypr/hyprland.lua'; main.parent.mkdir(); main.write_text('-- isolated accessibility\n')
            env = dict(os.environ, HYPRLAND_INSTANCE_SIGNATURE='', XDG_CONFIG_HOME=str(root / 'config'), XDG_STATE_HOME=str(root / 'state'), XDG_RUNTIME_DIR=str(runtime), QT_QPA_PLATFORMTHEME='', QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software', PATH=str(commands) + os.pathsep + os.environ['PATH'])
            result = subprocess.run(['quickshell', '-p', str(entry)], env=env, capture_output=True, text=True, timeout=20)
            self.assertIn(marker, result.stdout + result.stderr, result.stdout + result.stderr)
            self.assertEqual(result.returncode, 0)
            settings = json.loads((root / 'config/hyprshell/settings.json').read_text())
            audio = next(i for i in settings['items'] if i['id'] == 'audio')
            self.assertEqual((audio['side'], audio['textColor'], audio['opacity']), expected_audio)
            return settings
