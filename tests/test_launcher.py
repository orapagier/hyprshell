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
    def test_uwsm_resolves_vim_to_real_kitty_terminal_without_url_launcher(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            shutil.copy2(ROOT / 'config/xdg-terminals.list', root / 'xdg-terminals.list')
            code = '''import json, sys
sys.path.insert(0, '/usr/share/uwsm/modules')
from uwsm.main import app
print(json.dumps(app(['vim.desktop'], terminal=False, slice_name='a', app_unit_type='service', app_name='', unit_name='', unit_description='', return_cmdline=True)))
'''
            environment = dict(os.environ, XDG_CONFIG_HOME=str(root), XDG_CACHE_HOME=str(root / 'cache'))
            result = subprocess.run(['python3', '-c', code], env=environment, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr)
            command = json.loads(result.stdout)
            self.assertIn('--property=Type=exec', command)
            self.assertEqual(command[command.index('--') + 1:], ['kitty', '--', 'vim'])
            self.assertNotIn('%F', command)
            self.assertNotIn('+open', command)

    def test_native_launcher_dispatches_desktop_ids_through_service(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            payload = root / 'config/quickshell'
            shutil.copytree(ROOT / 'config/quickshell', payload, ignore=shutil.ignore_patterns('__pycache__', 'audio-spectrum'))
            commands = root / 'bin'; commands.mkdir()
            log = root / 'launched.jsonl'
            stub = commands / 'uwsm'
            stub.write_text('#!/usr/bin/python3\nimport json, sys\nwith open(' + repr(str(log)) + ', "a") as output: output.write(json.dumps(sys.argv[1:]) + "\\n")\n')
            stub.chmod(0o755)
            fixture = payload / 'LauncherCheck.qml'
            fixture.write_text('''import QtQuick
import QtQuick.Window
import Quickshell
import "."
ShellRoot {
    Window { visible: true; width: 500; height: 500; LauncherMenu { id: launcher; width: 480 } }
    Timer { interval: 100; running: true; onTriggered: { launcher.launch({id: "vim"}); launcher.launch({id: "gparted.desktop"}); } }
    Timer { interval: 500; running: true; onTriggered: { console.log("LAUNCHER_OK"); Qt.quit(); } }
}
''')
            runtime = root / 'runtime'; runtime.mkdir(mode=0o700)
            environment = dict(os.environ, XDG_CONFIG_HOME=str(root / 'config'), XDG_STATE_HOME=str(root / 'state'),
                               XDG_RUNTIME_DIR=str(runtime), QT_QPA_PLATFORMTHEME='', QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software',
                               PATH=str(commands) + os.pathsep + os.environ['PATH'])
            result = subprocess.run(['quickshell', '-p', str(fixture)], capture_output=True, text=True, env=environment, timeout=10)
            self.assertIn('LAUNCHER_OK', result.stdout + result.stderr, result.stdout + result.stderr)
            entries = [json.loads(line) for line in log.read_text().splitlines()]
            self.assertCountEqual(entries, [['app', '-t', 'service', '--', 'vim.desktop'], ['app', '-t', 'service', '--', 'gparted.desktop']])
