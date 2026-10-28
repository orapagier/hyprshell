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
    QtObject {
        id: fakeInbox
        property var rows: []
        property int unread: 0
        function markRead() {}
    }
    Hyprhover {
        id: hover
        width: 1200; height: 800
        available: true
        services: ({workspace: function(id) {}, scrollWorkspace: function(delta) {}, outputs: [], inputs: [], sink: null, microphone: null, wifiEnabled: false, wifiNetworks: [], bluetoothDevices: [], adapter: null, statusData: {network:{}}, scanWifi: function(enabled) {}})
        inbox: fakeInbox
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
                let content = hover.controls.parent;
                content.select('audio');
                test.check(content.selected === 'audio', 'tab selects controls inline');
                content.select('calendar');
                test.check(content.selected === 'audio', 'cannot select another group');
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
                hover.available = true;
                hover.reveal('left');
                test.check(hover.drawerSurface.bodyRect.y === 0 && hover.drawerSurface.bodyRect.x === 0, 'left drawer touches both edges');
                hover.reveal('center');
                test.check(hover.drawerSurface.bodyRect.y === 0, 'center drawer touches top');
                test.check(Math.abs(hover.drawerSurface.bodyRect.x + hover.drawerSurface.bodyWidth / 2 - hover.width / 2) < 1, 'center drawer centered');
                hover.reveal('right');
                test.check(hover.drawerSurface.bodyRect.x + hover.drawerSurface.bodyWidth === hover.width, 'right drawer touches right edge');
                // Exercise every inline page without invoking its external actions.
                for (let id of ['settings','workspaces','media','calendar','tray','notifications','audio','wifi','bluetooth','battery','power','launcher']) {
                    hover.controls.parent.selected = id;
                    test.check(hover.controls.parent.children.find(child => child.objectName === 'hyprhoverTabPage').item !== null, 'inline page loaded: ' + id);
                }
                hover.reveal('left');
                hover.controls.parent.select('audio');
                capture.restart();
            } catch(error) { console.error(error); Qt.exit(1); }
        }
    }
    Timer {
        id: capture
        property int stage: 0
        interval: 1300
        onTriggered: {
            hover.drawerSurface.grabToImage(result => {
                result.saveToFile('/tmp/hyprhover-' + ['left','center','right'][capture.stage] + '.png');
                if (capture.stage < 2) {
                    capture.stage++;
                    hover.reveal(['left','center','right'][capture.stage]);
                    if (capture.stage === 2) hover.controls.parent.select('power');
                    capture.restart();
                } else {
                    console.log('HYPRHOVER_OK');
                    Qt.quit();
                }
            });
        }
    }
    Timer { interval:8000; running:true; onTriggered: Qt.exit(2) }
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
