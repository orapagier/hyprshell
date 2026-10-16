"""A failed desktop action must leave an explicit restore action, not hide again."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('quickshell'), 'Quickshell is required')
class ShowDesktopNativeTests(unittest.TestCase):
    def test_failed_toggle_offers_restore_and_preserves_error(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root/'runtime').mkdir(mode=0o700)
            (root/'settings').mkdir()
            shutil.copy2(ROOT/'config/quickshell/ShowDesktop.qml', root/'ShowDesktop.qml')
            log = root/'actions.jsonl'
            (root/'settings/show_desktop.py').write_text(
                'import json,sys\n'
                'with open('+repr(str(log))+',"a") as f: f.write(json.dumps(sys.argv[1:])+"\\n")\n'
                'print(json.dumps({"ok":False,"message":"Restore needs retry"} if sys.argv[1]=="toggle" else {"ok":True,"hidden":False}))\n')
            fixture = root/'Test.qml'
            fixture.write_text('''import QtQuick
import Quickshell
import "."
ShellRoot {
    id:test
    property int completed:0
    property int step:0
    ShowDesktop { id:desktop; onActionFinished:test.completed++ }
    Timer { interval:60; running:true; repeat:true; onTriggered: {
        if (desktop.busy || test.completed <= test.step) return;
        if (test.step===0) {
            if (desktop.hidden || !desktop.run('toggle','TEST')) Qt.exit(1);
        } else if (test.step===1) {
            if (!desktop.hidden || desktop.error!=='Restore needs retry') Qt.exit(2);
            desktop.run('toggle','TEST');
        } else {
            if (desktop.hidden || desktop.error) Qt.exit(3);
            console.log('SHOW_DESKTOP_UI_OK'); Qt.quit();
        }
        test.step++;
    }}
    Timer { interval:5000; running:true; onTriggered:Qt.exit(4) }
}
''')
            env = dict(os.environ, XDG_RUNTIME_DIR=str(root/'runtime'), XDG_CONFIG_HOME=str(root/'config'),
                       XDG_STATE_HOME=str(root/'state'), QT_QPA_PLATFORM='offscreen',
                       QT_QPA_PLATFORMTHEME='', QT_QUICK_BACKEND='software', HYPRLAND_INSTANCE_SIGNATURE='')
            result = subprocess.run(['quickshell','--log-rules','qml.debug=true','-p',str(fixture)],
                                    env=env, capture_output=True, text=True, timeout=10)
            output = result.stdout+result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn('SHOW_DESKTOP_UI_OK', output)
            for error in ('TypeError','ReferenceError','Binding loop','Unable to assign'):
                self.assertNotIn(error, output)
            self.assertEqual([json.loads(line)[0] for line in log.read_text().splitlines()], ['status','toggle','restore'])
