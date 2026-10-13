"""Application theme transactions isolated from the user's desktop and dconf."""
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
    import theme
    import github_sync


class ThemeTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.config = self.root / 'config'
        env = patch.dict(os.environ, XDG_CONFIG_HOME=str(self.config), XDG_STATE_HOME=str(self.root / 'state'))
        env.start(); self.addCleanup(env.stop)
        self.values = {'color-scheme': "'prefer-light'", 'gtk-theme': "'Adwaita'", 'font-name': "'Noto Sans 11'", 'cursor-theme': "'Adwaita'", 'cursor-size': '24'}
        def setting(action, key, value=None):
            if action == 'get':
                return self.values[key]
            self.values[key] = value if key == 'cursor-size' or value.startswith("'") else "'" + value + "'"
            return ''
        mock = patch.object(theme, 'setting', side_effect=setting)
        mock.start(); self.addCleanup(mock.stop)
        mock = patch.object(theme, 'font_families', return_value=['Noto Sans', 'DejaVu Sans'])
        mock.start(); self.addCleanup(mock.stop)
        mock = patch.object(theme, 'cursor_themes', return_value=['Adwaita'])
        mock.start(); self.addCleanup(mock.stop)
        mock = patch.object(theme.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0, '', ''))
        mock.start(); self.addCleanup(mock.stop)

    def test_light_dark_switch_preserves_unrelated_gtk_environment_and_bar(self):
        gtk = self.config / 'gtk-3.0/settings.ini'
        gtk.parent.mkdir(parents=True)
        gtk.write_text('[Settings]\ngtk-font-name = Noto Sans 12\n')
        env = self.config / 'uwsm/env-hyprland'
        env.parent.mkdir(parents=True); env.write_text('export MY_PREFERENCE=keep\n')
        bar = self.config / 'hyprshell/settings.json'
        bar.parent.mkdir(parents=True); bar.write_text('unchanged bar colors')
        result = theme.apply('dark', 'light')
        self.assertTrue(result['ok'])
        self.assertEqual(self.values['color-scheme'], "'prefer-dark'")
        self.assertIn('gtk-font-name = Noto Sans 12', gtk.read_text())
        self.assertIn('gtk-theme-name = Adwaita-dark', gtk.read_text())
        self.assertIn('export MY_PREFERENCE=keep', env.read_text())
        theme.apply('light', 'dark')
        self.assertEqual(self.values['gtk-theme'], "'Adwaita'")
        self.assertEqual(env.read_text().count('BEGIN Hyprshell'), 1)
        self.assertEqual(bar.read_text(), 'unchanged bar colors')
        self.assertEqual(theme.saved()['mode'], 'light')

    def test_failed_file_write_restores_files_and_desktop_keys(self):
        initial = dict(self.values)
        with patch.object(theme, 'atomic', side_effect=OSError('Disk full')):
            with self.assertRaises(OSError):
                theme.apply('dark')
        self.assertEqual(self.values, initial)
        self.assertIsNone(theme.saved())
        self.assertFalse((self.config / 'gtk-3.0/settings.ini').exists())

    def test_partial_write_failure_restores_saved_theme_and_desktop(self):
        theme.apply('light')
        old = dict(self.values)
        files = {path: path.read_text() for path in self.config.rglob('*') if path.is_file()}
        atomic = theme.atomic
        failed = False
        def fail_once(path, text):
            nonlocal failed
            if not failed and 'gtk-4.0' in str(path):
                failed = True
                raise OSError('Write failed')
            atomic(path, text)
        with patch.object(theme, 'atomic', side_effect=fail_once):
            with self.assertRaises(OSError):
                theme.apply('dark')
        self.assertEqual(old, self.values)
        self.assertEqual(files, {path: path.read_text() for path in files})

    def test_reapplying_saved_theme_does_not_create_new_backups(self):
        theme.apply('dark')
        backups = list((self.root / 'state/hyprshell/backups').iterdir())
        theme.apply('dark')
        self.assertEqual(backups, list((self.root / 'state/hyprshell/backups').iterdir()))

    def test_stale_or_invalid_mode_does_not_change_desktop(self):
        for mode, expected in [('evil', 'light'), ('dark', 'dark')]:
            with self.assertRaises(ValueError):
                theme.apply(mode, expected)
        self.assertEqual(self.values['color-scheme'], "'prefer-light'")
        self.assertIsNone(theme.saved())

    def test_sync_saves_only_theme_preference(self):
        with patch.object(sys, 'path', [str(ROOT / 'config/quickshell/settings')] + sys.path):
            import github_sync
            theme.apply('dark')
            repo = self.root / 'repo'
            github_sync.snapshot_managed_files(repo, self.config, self.root)
        self.assertEqual(json.loads((repo / 'config/hyprshell/theme.json').read_text()), {'version': 1, 'mode': 'dark'})
        self.assertFalse((repo / 'config/gtk-3.0').exists())

    def test_status_without_saved_theme_uses_desktop(self):
        self.assertEqual(theme.status()['mode'], 'light')
        self.values['color-scheme'] = "'prefer-dark'"
        self.assertEqual(theme.status()['mode'], 'dark')

    def test_font_cursor_persist_through_color_switch_and_sync(self):
        appearance = {'font': 'DejaVu Sans 14', 'cursorTheme': 'Adwaita', 'cursorSize': 32}
        theme.apply('light', appearance=appearance, expected_appearance=theme.effective(), expected_revision=theme.revision())
        theme.apply('dark')
        self.assertEqual(theme.saved(), {'version': 1, 'mode': 'dark', **appearance})
        self.assertEqual(self.values['font-name'], "'DejaVu Sans 14'")
        self.assertEqual(self.values['cursor-size'], '32')
        for version in ('3.0', '4.0'):
            text = (self.config / ('gtk-' + version) / 'settings.ini').read_text()
            self.assertIn('gtk-font-name = DejaVu Sans 14', text)
            self.assertIn('gtk-cursor-theme-size = 32', text)
        self.assertIn('export XCURSOR_SIZE=32', (self.config / 'uwsm/env-hyprland').read_text())
        github_sync.snapshot_managed_files(self.root / 'repo', self.config, self.root)
        self.assertEqual(json.loads((self.root / 'repo/config/hyprshell/theme.json').read_text()), theme.saved())

    def test_font_cursor_failure_rolls_back_and_external_edit_is_rejected(self):
        original = self.values.copy()
        atomic = theme.atomic
        def fail(path, text):
            if path.name == 'theme.json':
                raise OSError('Failed saved appearance write')
            atomic(path, text)
        appearance = {'font': 'DejaVu Sans 14', 'cursorTheme': 'Adwaita', 'cursorSize': 32}
        with patch.object(theme, 'atomic', side_effect=fail), self.assertRaises(OSError):
            theme.apply('dark', appearance=appearance)
        self.assertEqual(self.values, original)
        old_revision = theme.revision()
        self.values['font-name'] = "'Noto Sans 12'"
        with self.assertRaisesRegex(ValueError, 'changed elsewhere'):
            theme.apply('light', appearance=appearance, expected_revision=old_revision)
        self.assertIsNone(theme.saved())

    def test_restore_skips_unavailable_font_and_cursor_without_losing_snapshot(self):
        data = {'version': 1, 'mode': 'dark', 'font': 'Missing Font 14', 'cursorTheme': 'Missing', 'cursorSize': 32}
        path = self.config / 'hyprshell/theme.json'
        path.parent.mkdir(parents=True); path.write_text(json.dumps(data))
        theme.apply('dark', restoring=True)
        self.assertEqual(self.values['font-name'], "'Noto Sans 11'")
        self.assertEqual(self.values['cursor-size'], '24')
        self.assertEqual(theme.saved(), data)


class ThemeNativeTests(unittest.TestCase):
    def test_toggle_calls_backend_and_recovers_after_save_failure(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            payload = root / 'config/quickshell'
            shutil.copytree(ROOT / 'config/quickshell', payload, ignore=shutil.ignore_patterns('__pycache__', 'audio-spectrum'))
            (payload / 'settings/theme.py').write_text('''import json, sys
from pathlib import Path
request = json.loads(sys.argv[2])
marker = Path(__file__).with_name('theme-test-state')
mode = marker.read_text() if marker.exists() else 'light'
appearance_marker = marker.with_name('appearance-test-state')
appearance = json.loads(appearance_marker.read_text()) if appearance_marker.exists() else {'font': 'Noto Sans 11', 'cursorTheme': 'Adwaita', 'cursorSize': 24}
if request['operation'] == 'save' and request['mode'] == 'light':
    print(json.dumps({'ok': False, 'message': 'Simulated failure'}))
else:
    if request['operation'] == 'save':
        mode = request['mode']; marker.write_text(mode)
        if request.get('appearance'):
            appearance = request['appearance']; appearance_marker.write_text(json.dumps(appearance))
    print(json.dumps({'ok': True, 'mode': mode, **appearance, 'fontFamily': appearance['font'].rsplit(' ', 1)[0], 'fontSize': int(appearance['font'].rsplit(' ', 1)[1]), 'fonts': ['Noto Sans', 'DejaVu Sans'], 'cursors': ['Adwaita']}))
''')
            fixture = payload / 'ThemeNative.qml'
            fixture.write_text('''import QtQuick
import QtQuick.Window
import Quickshell
import "."
ShellRoot {
    id: test
    property int phase: 0
    Window { visible: true; width: 600; height: 600; SettingsTheme { id: page; width: 580 } }
    function find(root, name = "applicationDarkTheme") { if (root.objectName === name) return root; for (let child of root.children || []) { let match = find(child, name); if (match) return match; } return null; }
    Timer { interval: 50; running: true; repeat: true
        onTriggered: {
            let toggle = test.find(page);
            if (test.phase === 0 && page.loaded && !page.busy) {
                if (!toggle || toggle.checked) { console.error("THEME_FAILED initial"); Qt.quit(); return; }
                test.find(page, "applicationFontSize").value = 14;
                toggle.checked = true; toggle.toggled(); test.phase = 1;
            } else if (test.phase === 1 && !page.busy && page.mode === "dark") {
                if (test.find(page, "applicationFontSize").value !== 14 || !page.dirty || page.appearance.font !== "Noto Sans 11") { console.error("THEME_FAILED color discarded manual draft"); Qt.quit(); return; }
                toggle.checked = false; toggle.toggled(); test.phase = 2;
            } else if (test.phase === 2 && !page.busy && !page.success) {
                if (!toggle.checked || page.mode !== "dark") { console.error("THEME_FAILED recovery"); Qt.quit(); return; }
                test.find(page, "applicationFont").currentIndex = 1;
                test.find(page, "applicationFontSize").value = 14;
                test.find(page, "applicationCursorSize").value = 32;
                test.find(page, "saveApplicationAppearance").clicked(); test.phase = 3;
            } else if (test.phase === 3 && !page.busy && page.success) {
                if (page.appearance.font !== "DejaVu Sans 14" || page.appearance.cursorSize !== 32) console.error("THEME_FAILED font cursor");
                else console.log("THEME_NATIVE_OK");
                Qt.quit();
            }
        }
    }
    Timer { interval: 5000; running: true; onTriggered: { console.error("THEME_FAILED timeout", page.message); Qt.quit(); } }
}
''')
            runtime = root / 'runtime'; runtime.mkdir(mode=0o700)
            environment = dict(os.environ, XDG_CONFIG_HOME=str(root / 'config'), XDG_STATE_HOME=str(root / 'state'),
                               XDG_RUNTIME_DIR=str(runtime), QT_QPA_PLATFORMTHEME='', QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software')
            result = subprocess.run(['quickshell', '-p', str(fixture)], capture_output=True, text=True, env=environment, timeout=10)
            output = result.stdout + result.stderr
            self.assertIn('THEME_NATIVE_OK', output, output)
            self.assertNotIn('THEME_FAILED', output)
