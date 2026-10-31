"""Execute production workspace actions and verify their Lua dispatch side effects."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('quickshell') and shutil.which('lua'), 'Quickshell and Lua required')
class WorkspaceDispatchTests(unittest.TestCase):
    def test_numbered_and_relative_workspace_actions(self):
        source = (ROOT / 'config/quickshell/DesktopServices.qml').read_text()
        actions = source[source.index('    function workspace(id)'):source.index('    function toggleWifi()')]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            runtime = root / 'runtime'
            runtime.mkdir(mode=0o700)
            entry = root / 'test.qml'
            entry.write_text('''import QtQuick
import Quickshell
ShellRoot {
    QtObject {
        id: fixture
        property var commands: []
        property var legacy: []
        property var spaces: [{id: 2, activate: () => fixture.legacy.push(2)}]
        property var hyprland: ({usingLua: true, dispatch: request => fixture.legacy.push(request)})
        property var quickshell: ({execDetached: command => fixture.commands.push(command)})
ACTIONS
        function run() {
            workspace(2); workspace("3"); scrollWorkspace(-1); scrollWorkspace(1);
            workspace(0); workspace(-2); workspace("invalid"); workspace(1.5);
            if (commands.length !== 4 || legacy.length) Qt.exit(1);
            for (let command of commands) {
                if (command[0] !== 'hyprctl' || command[1] !== 'eval') Qt.exit(2);
                console.log('WORKSPACE_LUA ' + command[2]);
            }
            hyprland.usingLua = false;
            workspace(2); scrollWorkspace(-1); scrollWorkspace(1);
            if (JSON.stringify(legacy) !== '[2,"workspace e-1","workspace e+1"]') Qt.exit(3);
            Qt.quit();
        }
    }
    Timer { interval: 20; running: true; onTriggered: fixture.run() }
}'''.replace('ACTIONS', actions.replace('Hyprland.', 'hyprland.').replace('Quickshell.', 'quickshell.')))
            env = dict(os.environ, XDG_RUNTIME_DIR=str(runtime), HYPRLAND_INSTANCE_SIGNATURE='',
                       QT_QPA_PLATFORMTHEME='', QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software')
            result = subprocess.run(['quickshell', '--log-rules', 'qml.debug=true', '-p', str(entry)], env=env,
                                    capture_output=True, text=True, timeout=10)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            commands = [line.split('WORKSPACE_LUA ', 1)[1] for line in output.splitlines() if 'WORKSPACE_LUA ' in line]
            self.assertEqual(len(commands), 4, output)
            lua = '''local focused = {}
hl = {
    dsp = {focus = function(value) return value end},
    dispatch = function(value) table.insert(focused, value.workspace) end
}
''' + '\n'.join(commands) + '''
assert(#focused == 4)
assert(focused[1] == 2 and focused[2] == 3)
assert(focused[3] == 'e-1' and focused[4] == 'e+1')
'''
            checked = subprocess.run(['lua', '-'], input=lua, capture_output=True, text=True, timeout=5)
            self.assertEqual(checked.returncode, 0, checked.stdout + checked.stderr)
