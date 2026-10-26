"""Exercise the shell's actual Super-key handler with panel/monitor combinations."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class LauncherRoutingTests(unittest.TestCase):
    def test_focused_output_hidden_panel_and_fallback(self):
        shell = (ROOT / 'config/quickshell/shell.qml').read_text()
        handler = shell[shell.index('        function toggleLauncher(): void {'):].split('\n        }', 1)[0] + '\n        }'
        source = '''import QtQuick
import QtTest
TestCase {
    name: "LauncherRouting"
    property var compositor: ({focusedMonitor:{name:'main'}})
    property var panels: ({instances:[]})
    property string selected: ''
    property var closed: []
    function panel(name,output,shown) {
        return {screen:{name:output},shown:shown,
            closeMenu:function(){closed.push(name);},toggleLauncher:function(){selected=name;}};
    }
    HANDLER
    function test_hidden_panel_keeps_keyboard_launcher() {
        compositor.focusedMonitor={name:'main'};
        for (let shown of [false,true]) {
            panels.instances=[panel('pane','main',shown)];
            selected=''; closed=[]; toggleLauncher();
            compare(selected,'pane'); compare(closed.length,0);
        }
    }
    function test_focused_output_closes_other_menus() {
        panels.instances=[panel('pane-main','main',true),panel('pane-other','other',true)];
        compositor.focusedMonitor={name:'other'};
        closed=[]; toggleLauncher(); compare(selected,'pane-other'); compare(closed,['pane-main']);
        compositor.focusedMonitor=null;
        closed=[]; toggleLauncher(); compare(selected,'pane-main'); compare(closed,['pane-other']);
        panels.instances=[];
        selected=''; toggleLauncher(); compare(selected,'');
    }
}'''.replace('HANDLER', handler.replace('Hyprland.', 'compositor.'))
        runner = subprocess.check_output([sys.executable, str(ROOT / 'tools/check_runtime.py'), '--qmltestrunner'], text=True).strip()
        with tempfile.TemporaryDirectory() as directory:
            fixture = Path(directory) / 'tst_Launcher.qml'
            fixture.write_text(source)
            env = dict(os.environ, QT_QPA_PLATFORMTHEME='', QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software')
            result = subprocess.run([runner, '-input', str(fixture)], env=env, capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
