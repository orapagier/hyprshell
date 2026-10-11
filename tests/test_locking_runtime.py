"""Exercise controller restarts using a stub helper, never a desktop locker."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('quickshell'), 'Quickshell is required')
class LockingRuntimeTests(unittest.TestCase):
    def test_enable_disable_restart_and_manual_lock(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            shutil.copy2(ROOT / 'config/quickshell/LockingController.qml', root)
            (root / 'settings').mkdir()
            calls = root / 'calls'
            (root / 'settings/backend.py').write_text(
                'import sys, time\n'
                f'with open({str(calls)!r}, "a") as out: out.write(sys.argv[1] + "\\n")\n'
                'time.sleep(30)\n')
            (root / 'shell.qml').write_text('''
import QtQuick
import Quickshell
ShellRoot {
    id: test
    property int phase: 0
    QtObject {
        id: preferences
        property bool loaded: true
        property var config: ({locking:{enabled:true}})
    }
    LockingController { id: locking; store: preferences }
    Timer {
        interval: 600; running: true; repeat: true
        onTriggered: {
            if (test.phase === 0) preferences.config = {locking:{enabled:false}};
            else if (test.phase === 1) preferences.config = {locking:{enabled:true}};
            else if (test.phase === 2) locking.lockNow();
            else {
                if (locking.error) console.error("LOCK_RUNTIME_ERROR", locking.error);
                Qt.quit();
            }
            test.phase++;
        }
    }
}
''')
            runtime = root / 'runtime'
            runtime.mkdir(mode=0o700)
            env = dict(os.environ, XDG_RUNTIME_DIR=str(runtime), QT_QPA_PLATFORMTHEME='', QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software')
            result = subprocess.run(['quickshell', '-p', str(root / 'shell.qml')], env=env,
                                    capture_output=True, text=True, timeout=10)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertNotIn('LOCK_RUNTIME_ERROR', output)
            self.assertEqual(calls.read_text().splitlines(), ['--idle', '--idle', '--lock'], output)
