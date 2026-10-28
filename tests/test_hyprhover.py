"""Exercise production Hyprhover controls and lifecycle with isolated native Qt."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('quickshell'), 'Native Quickshell required')
class HyprhoverTests(unittest.TestCase):
    def test_groups_and_workspace_lifecycle(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            payload = root / 'quickshell'
            payload.mkdir()
            for source in (ROOT / 'config/quickshell').iterdir():
                if source.name not in ('Hyprhover.qml', 'Dropdown.qml'):
                    (payload / source.name).symlink_to(source, target_is_directory=source.is_dir())
            for name in ('Hyprhover.qml', 'Dropdown.qml'):
                source = (ROOT / 'config/quickshell' / name).read_text().replace('PanelWindow {', 'FloatingWindow {')
                source = '\n'.join(line for line in source.splitlines() if not any(token in line for token in ('anchors { top:', 'exclusionMode:', 'exclusiveZone:', 'WlrLayershell.')))
                (payload / name).write_text(source)
            (root / 'Check.qml').write_text('''import QtQuick
import Quickshell
import "quickshell"
ShellRoot {
    id: test
    function check(value, message) { if (!value) throw new Error(message); }
    Hyprhover {
        id: hover
        width: 1200; height: 800
        available: true
        services: ({workspace: function(id) {}, scrollWorkspace: function(delta) {}})
        inbox: null
        statusData: ({workspaces: [], audio: {}, network: {}, bluetooth: {}, battery: {present:false}})
        settings: ({bar:{}, items:[{id:'audio',side:'left'},{id:'wifi',enabled:false}]})
    }
    Timer {
        interval: 200; running: true
        onTriggered: {
            try {
                hover.reveal('left');
                test.check(hover.opened, 'left opens');
                test.check(hover.controls !== null, 'controls loaded');
                test.check(hover.controls.itemEnabled('audio'), 'saved reassignment follows group');
                test.check(!hover.controls.itemEnabled('calendar'), 'other group excluded');
                hover.reveal('center');
                test.check(hover.controls.itemEnabled('calendar'), 'center clock available');
                test.check(!hover.controls.itemEnabled('audio'), 'old group excluded');
                hover.reveal('right');
                test.check(hover.controls.itemEnabled('power'), 'right controls available');
                test.check(!hover.controls.itemEnabled('wifi'), 'disabled items stay hidden');
                hover.workspace = 2;
                test.check(!hover.opened, 'workspace transition closes');
                hover.reveal('center');
                hover.available = false;
                test.check(!hover.opened, 'showing Hyprpane closes hover');
                hover.reveal('left');
                test.check(!hover.opened, 'cannot reveal while Hyprpane shown');
                console.log('HYPRHOVER_OK');
                Qt.quit();
            } catch(error) { console.error(error); Qt.exit(1); }
        }
    }
    Timer { interval:5000; running:true; onTriggered: Qt.exit(2) }
}''')
            runtime = root / 'runtime'
            runtime.mkdir(mode=0o700)
            env = dict(os.environ, XDG_RUNTIME_DIR=str(runtime), HYPRLAND_INSTANCE_SIGNATURE='',
                       QT_QPA_PLATFORMTHEME='', QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software')
            result = subprocess.run(['quickshell', '--log-rules', 'qml.debug=true', '-p', str(root / 'Check.qml')], env=env,
                                    capture_output=True, text=True, timeout=12)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn('HYPRHOVER_OK', output)
            for error in ('ReferenceError', 'TypeError', 'Binding loop', 'Unable to assign'):
                self.assertNotIn(error, output)
