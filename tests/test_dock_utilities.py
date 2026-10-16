"""Exercise file-manager commands without accessing or deleting personal files."""
import importlib.util
from pathlib import Path
import subprocess
import unittest
from unittest.mock import Mock

spec = importlib.util.spec_from_file_location('dock_utilities', Path(__file__).resolve().parents[1] / 'config/quickshell/settings/dock_utilities.py')
utilities = importlib.util.module_from_spec(spec)
spec.loader.exec_module(utilities)


class DockUtilitiesTests(unittest.TestCase):
    def test_open_and_status_never_empty_trash(self):
        for name, command in [('files', ['gio', 'open', str(Path.home())]), ('trash', ['gio', 'open', 'trash:///']), ('status', ['gio', 'list', 'trash:///'])]:
            run = Mock(return_value=subprocess.CompletedProcess([], 0, 'item\n', ''))
            result = utilities.action(name, run)
            self.assertTrue(result['ok'])
            self.assertEqual(run.call_args.args[0], command)
        self.assertTrue(result['full'])

    def test_empty_is_explicit_and_failures_do_not_claim_empty(self):
        run = Mock(return_value=subprocess.CompletedProcess([], 0, '', ''))
        self.assertEqual(utilities.action('empty-confirmed', run), {'ok': True})
        self.assertEqual(run.call_args.args[0], ['gio', 'trash', '--empty'])
        self.assertFalse(utilities.action('status', run)['full'])
        run.return_value.returncode = 1
        self.assertFalse(utilities.action('status', run)['ok'])
        with self.assertRaises(ValueError):
            utilities.action('empty', run)


class DockUtilitiesNativeTests(unittest.TestCase):
    def test_native_trash_refresh_and_open_with_stub_file_manager(self):
        import json
        import os
        import shutil
        import tempfile
        if not shutil.which('quickshell'):
            self.skipTest('Quickshell is required')
        payload = Path(__file__).resolve().parents[1] / 'config/quickshell'
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'runtime').mkdir(mode=0o700)
            (root / 'bin').mkdir()
            log = root / 'actions.jsonl'
            gio = root / 'bin/gio'
            gio.write_text('#!/usr/bin/python3\nimport json,sys\nwith open(' + repr(str(log)) + ',"a") as f: f.write(json.dumps(sys.argv[1:])+"\\n")\nif sys.argv[1]=="list": print("item")\n')
            gio.chmod(0o755)
            fixture = root / 'Check.qml'
            fixture.write_text('''import QtQuick
import Quickshell
import "PAYLOAD"
ShellRoot {
    property int step:0
    DockUtilities { id: utilities; watching:true }
    Timer { interval:100; running:true; repeat:true; onTriggered: {
        if (utilities.busy) return;
        if (utilities.error) { console.error(utilities.error); Qt.exit(1); }
        if (step===0 && utilities.available && utilities.full) { utilities.run('trash'); step=1; }
        else if (step===1) { console.log('TRASH_NATIVE_OK'); Qt.quit(); }
    }}
    Timer { interval:4000; running:true; onTriggered:Qt.exit(2) }
}'''.replace('PAYLOAD', payload.as_uri()))
            env = dict(os.environ, XDG_RUNTIME_DIR=str(root / 'runtime'), HYPRLAND_INSTANCE_SIGNATURE='',
                       QT_QPA_PLATFORMTHEME='', QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software',
                       PATH=str(root / 'bin') + os.pathsep + os.environ['PATH'])
            result = subprocess.run(['quickshell', '--log-rules', 'qml.debug=true', '-p', str(fixture)], env=env, capture_output=True, text=True, timeout=8)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn('TRASH_NATIVE_OK', output)
            for error in ('ReferenceError', 'TypeError', 'Binding loop', 'Unable to assign'):
                self.assertNotIn(error, output)
            self.assertEqual([json.loads(line) for line in log.read_text().splitlines()],
                             [['list', 'trash:///'], ['open', 'trash:///']])
