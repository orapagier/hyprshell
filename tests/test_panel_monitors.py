"""Panel workspace scopes must resolve on startup without a workspace event."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(os.environ.get('HYPRLAND_INSTANCE_SIGNATURE') and
                     shutil.which('hyprctl') and shutil.which('quickshell'),
                     'A live Hyprland session is required')
class PanelMonitorTests(unittest.TestCase):
    def test_initial_output_workspaces_match_compositor(self):
        monitors = json.loads(subprocess.check_output(['hyprctl', '-j', 'monitors'], text=True, timeout=5))
        expected = {m['name']: m['activeWorkspace']['id'] for m in monitors}
        with tempfile.TemporaryDirectory(prefix='hyprshell-monitor-test-') as directory:
            root = Path(directory)
            fixture = root / 'Check.qml'
            fixture.write_text('''import QtQuick
import Quickshell
import Quickshell.Hyprland
import "PAYLOAD"
ShellRoot {
    QtObject { id: store; property var config: ({pins:{matches:{}}}) }
    ApplicationService { store: store; entries: []; windows: [] }
    Timer { interval:100; running:true; repeat:true; onTriggered: {
        let actual = {};
        for (let screen of Quickshell.screens) {
            let workspace = Hyprland.monitorFor(screen)?.activeWorkspace?.id;
            if (workspace === undefined || workspace <= 0) return;
            actual[screen.name] = workspace;
        }
        console.log('PANEL_MONITORS '+JSON.stringify(actual)); Qt.quit();
    }}
    Timer { interval:5000; running:true; onTriggered:Qt.exit(1) }
}
'''.replace('PAYLOAD', (ROOT / 'config/quickshell').as_uri()))
            env = dict(os.environ, XDG_CONFIG_HOME=str(root / 'config'),
                       XDG_STATE_HOME=str(root / 'state'), QT_QPA_PLATFORM='wayland',
                       QT_QPA_PLATFORMTHEME='')
            result = subprocess.run(['quickshell', '--log-rules', 'qml.debug=true', '-p', str(fixture)],
                                    env=env, capture_output=True, text=True, timeout=8)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            actual = next(json.loads(line.split('PANEL_MONITORS ', 1)[1])
                          for line in output.splitlines() if 'PANEL_MONITORS ' in line)
            self.assertEqual(actual, expected, output)
            for error in ('TypeError', 'ReferenceError', 'Binding loop', 'Unable to assign'):
                self.assertNotIn(error, output)
