"""Check dock-only focus overrides and restoration without moving a real pointer."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('quickshell') and shutil.which('lua'), 'Quickshell and Lua are required')
class DockPointerTests(unittest.TestCase):
    def test_focus_preserves_pointer_options_and_restores_even_on_error(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'runtime').mkdir(mode=0o700)
            source = root / 'Check.qml'
            source.write_text('''import QtQuick
import Quickshell
import "MODEL" as Apps
ShellRoot {
    Timer { interval:30; running:true; onTriggered: {
        if (Apps.pointerFocusCode('bad-selector') !== '') Qt.exit(1);
        console.log('POINTER_CODE ' + JSON.stringify(Apps.pointerFocusCode('abcd')));
        Qt.quit();
    }}
}'''.replace('MODEL', (ROOT / 'config/quickshell/ApplicationModel.js').as_uri()))
            env = dict(os.environ, XDG_RUNTIME_DIR=str(root / 'runtime'), HYPRLAND_INSTANCE_SIGNATURE='',
                       QT_QPA_PLATFORMTHEME='', QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software')
            result = subprocess.run(['quickshell', '--log-rules', 'qml.debug=true', '-p', str(source)],
                                    env=env, capture_output=True, text=True, timeout=5)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            line = next(line for line in output.splitlines() if 'POINTER_CODE ' in line)
            code = json.loads(line.split('POINTER_CODE ', 1)[1])
            fixture = '''
for _, original in ipairs({false, true}) do
    for _, failing in ipairs({false, true}) do
        local config = {no_warps=original, warp_on_change_workspace=2, warp_on_toggle_special=1}
        local focused = false
        hl = {
            get_config = function(key) return config[key:match("cursor%.(.*)")] end,
            config = function(value)
                for key, item in pairs(value.cursor) do config[key] = item end
            end,
            dsp = {focus = function(value) return value end},
            dispatch = function(value)
                assert(config.no_warps == true)
                assert(config.warp_on_change_workspace == 0)
                assert(config.warp_on_toggle_special == 0)
                assert(value.window == 'address:0xabcd')
                focused = true
                if failing then error('window closed during activation') end
            end,
        }
        local ok = pcall(function()
CODE
        end)
        assert(ok ~= failing)
        assert(focused)
        assert(config.no_warps == original)
        assert(config.warp_on_change_workspace == 2)
        assert(config.warp_on_toggle_special == 1)
    end
end
'''.replace('CODE', code)
            checked = subprocess.run(['lua', '-'], input=fixture, capture_output=True, text=True, timeout=5)
            self.assertEqual(checked.returncode, 0, checked.stdout + checked.stderr)
