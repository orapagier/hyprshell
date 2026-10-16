"""Exercise the shell's actual Super-key handler with panel/monitor combinations."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class LauncherRoutingTests(unittest.TestCase):
    def test_panel_priority_and_focused_output(self):
        shell = (ROOT / 'config/quickshell/shell.qml').read_text()
        handler = shell[shell.index('        function toggleLauncher(): void {'):].split('\n        }', 1)[0] + '\n        }'
        source = '''import QtQuick
import QtTest
TestCase {
    name: "LauncherRouting"
    property var compositor: ({focusedMonitor:{name:'main'}})
    property var panels: ({instances:[]})
    property var docks: ({instances:[]})
    property var taskbars: ({instances:[]})
    property string selected: ''
    function panel(name,output,available) {
        return {screen:{name:output},output:{name:output},launcherAvailable:available,
            closeMenu:function(){},toggleLauncher:function(){selected=name;}};
    }
    HANDLER
    function test_combinations() {
        for (let pane of [false,true]) for (let dock of [false,true]) for (let bar of [false,true]) {
            panels.instances=[panel('pane','main',pane)];
            docks.instances=[panel('dock','main',dock)];
            taskbars.instances=[panel('bar','main',bar)];
            selected=''; toggleLauncher();
            compare(selected,bar ? 'bar' : dock ? 'dock' : 'pane');
        }
    }
    function test_focused_output_and_ineligible_panels() {
        panels.instances=[panel('pane-main','main',true),panel('pane-other','other',true)];
        docks.instances=[panel('dock-main','main',true)];
        taskbars.instances=[panel('bar-other','other',true),panel('bar-hidden','main',false)];
        toggleLauncher(); compare(selected,'dock-main');
        compositor.focusedMonitor={name:'other'};
        toggleLauncher(); compare(selected,'bar-other');
        taskbars.instances=[];
        toggleLauncher(); compare(selected,'pane-other');
    }
}'''.replace('HANDLER', handler.replace('Hyprland.', 'compositor.'))
        runner = subprocess.check_output([sys.executable, str(ROOT / 'tools/check_runtime.py'), '--qmltestrunner'], text=True).strip()
        with tempfile.TemporaryDirectory() as directory:
            fixture = Path(directory) / 'tst_Launcher.qml'
            fixture.write_text(source)
            env = dict(os.environ, QT_QPA_PLATFORMTHEME='', QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software')
            result = subprocess.run([runner, '-input', str(fixture)], env=env, capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
