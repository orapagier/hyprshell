"""Launcher integration with desktop metadata and an up-to-date app environment."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class LauncherTests(unittest.TestCase):
    @unittest.skipUnless(Path('/usr/share/uwsm/modules/uwsm/main.py').is_file() and shutil.which('kitty'),
                         'Native UWSM and Kitty are required')
    def test_uwsm_resolves_terminal_entry_to_real_kitty_without_url_launcher(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            shutil.copy2(ROOT / 'config/xdg-terminals.list', root / 'xdg-terminals.list')
            apps = root / 'data/applications'; apps.mkdir(parents=True)
            (apps / 'hyprshell-test-terminal.desktop').write_text(
                '[Desktop Entry]\nType=Application\nName=Test terminal app\nExec=sh\nTerminal=true\n')
            code = '''import json, sys
sys.path.insert(0, '/usr/share/uwsm/modules')
from uwsm.main import app
print(json.dumps(app(['hyprshell-test-terminal.desktop'], terminal=False, slice_name='a', app_unit_type='service', app_name='', unit_name='', unit_description='', return_cmdline=True)))
'''
            environment = dict(os.environ, XDG_CONFIG_HOME=str(root), XDG_CACHE_HOME=str(root / 'cache'), XDG_DATA_HOME=str(root / 'data'))
            result = subprocess.run(['python3', '-c', code], env=environment, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            command = json.loads(result.stdout)
            self.assertIn('--property=Type=exec', command)
            self.assertEqual(command[command.index('--') + 1:], ['kitty', '--', 'sh'])
            self.assertNotIn('%F', command)
            self.assertNotIn('+open', command)

    def test_native_launcher_dispatches_desktop_ids_through_service(self):
        self.check_native_launcher(False)

    def test_native_launcher_shared_service_preserves_keyboard_and_launches(self):
        self.check_native_launcher(True)

    def check_native_launcher(self, shared):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            payload = root / 'config/quickshell'
            shutil.copytree(ROOT / 'config/quickshell', payload, ignore=shutil.ignore_patterns('__pycache__', 'audio-spectrum'))
            commands = root / 'bin'; commands.mkdir()
            log = root / 'launched.jsonl'
            stub = commands / 'uwsm'
            stub.write_text('#!/usr/bin/python3\nimport json, sys\nwith open(' + repr(str(log)) + ', "a") as output: output.write(json.dumps(sys.argv[1:]) + "\\n")\n')
            stub.chmod(0o755)
            apps = root / 'data/applications'; apps.mkdir(parents=True)
            for name in ('Alpha', 'Beta'):
                (apps / (name.lower() + '.desktop')).write_text(
                    '[Desktop Entry]\nType=Application\nName=' + name + '\nGenericName=Keyboard check\nExec=true\n')
            fixture = payload / 'LauncherCheck.qml'
            fixture.write_text('''import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import "."
ShellRoot {
    Window {
        visible: true; width: 500; height: 500
        LauncherMenu { id: launcher; width: 480 }
        Item { TestEvent { id: keyboard } }
    }
    function check(condition, message) { if (!condition) { console.error("LAUNCHER_FAILED", message); Qt.quit(); } }
    Timer { interval: 100; running: true; onTriggered: {
        let search = launcher.children.find(child => child.objectName === "launcherSearch");
        let list = launcher.children.find(child => child.objectName === "applicationsList");
        search.text = "Keyboard check";
        search.forceActiveFocus();
        check(launcher.entries.length === 2 && list.currentIndex === 0, "first match not selected");
        keyboard.keyClick(Qt.Key_Down, Qt.NoModifier, 0);
        check(list.currentIndex === 1 && search.activeFocus, "Down lost selection or search focus");
        keyboard.keyClick(Qt.Key_Return, Qt.NoModifier, 0);
        search.text = "Alpha";
        check(list.currentIndex === 0, "typing did not reset selection");
        keyboard.keyClick(Qt.Key_Up, Qt.NoModifier, 0);
        check(list.currentIndex === 0, "Up went past first result");
        search.text = "no-such-application";
        check(list.currentIndex === -1, "empty results kept a selection");
        keyboard.keyClick(Qt.Key_Return, Qt.NoModifier, 0);
        launcher.prepare();
        check(list.currentIndex === 0, "reopen did not reset selection");
        launcher.launch({id: "vim"}); launcher.launch({id: "gparted.desktop"});
    } }
    Timer { interval: 500; running: true; onTriggered: { console.log("LAUNCHER_OK"); Qt.quit(); } }
}
''')
            if shared:
                source = fixture.read_text().replace('    Window {',
                    '    SettingsStore { id: preferences }\n    ApplicationService { id: appService; store: preferences }\n    Window {')
                source = source.replace('LauncherMenu { id: launcher;', 'LauncherMenu { applicationService: appService; id: launcher;')
                source = source.replace('launcher.launch({id: "vim"});',
                    'keyboard.keyClick(Qt.Key_P, Qt.ControlModifier, 0); check(launcher.interacting, "pin menu did not open"); '
                    'let menu = launcher.data.find(item => item.objectName === "launcherPinMenu"); '
                    'check(menu && menu.background.objectName === "launcherPinGlass" && menu.background.radius === 16, "pin menu glass missing"); '
                    'check(menu.background.gradient.stops[0].color.a < 1, "pin menu lost transparency"); '
                    'keyboard.keyClick(Qt.Key_Down, Qt.NoModifier, 0); keyboard.keyClick(Qt.Key_Return, Qt.NoModifier, 0); launcher.launch({id: "vim"});')
                fixture.write_text(source)
            runtime = root / 'runtime'; runtime.mkdir(mode=0o700)
            environment = dict(os.environ, XDG_CONFIG_HOME=str(root / 'config'), XDG_STATE_HOME=str(root / 'state'),
                               XDG_RUNTIME_DIR=str(runtime), XDG_DATA_HOME=str(root / 'data'), XDG_DATA_DIRS=str(root / 'data'), QT_QPA_PLATFORMTHEME='', QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software',
                               PATH=str(commands) + os.pathsep + os.environ['PATH'])
            result = subprocess.run(['quickshell', '--log-rules', 'qml=true', '-p', str(fixture)], capture_output=True, text=True, env=environment, timeout=10)
            self.assertIn('LAUNCHER_OK', result.stdout + result.stderr, result.stdout + result.stderr)
            for error in ('LAUNCHER_FAILED', 'TypeError', 'ReferenceError', 'Unable to assign', 'Binding loop'):
                self.assertNotIn(error, result.stdout + result.stderr)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            if shared:
                saved = json.loads((root / 'config/hyprshell/settings.json').read_text())
                self.assertEqual(saved['pins']['shared'], ['alpha.desktop'])
            entries = [json.loads(line) for line in log.read_text().splitlines()]
            self.assertCountEqual(entries, [['app', '-t', 'service', '--', 'beta.desktop'], ['app', '-t', 'service', '--', 'vim.desktop'], ['app', '-t', 'service', '--', 'gparted.desktop']])
