"""Exercise the workspace switch in native Quickshell with no live preferences."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('quickshell'), 'Native Quickshell is needed')
class WorkspaceFloatingUiTests(unittest.TestCase):
    def test_switch_preserves_other_workspace_preferences(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            entry = root / 'test.qml'
            entry.write_text('''import QtQuick
import QtQuick.Window
import Quickshell
import "''' + (ROOT / 'config/quickshell').as_uri() + '''"
ShellRoot {
    Window {
        id: fixture
        visible: true; width: 700; height: 1000
        SettingsBehavior {
            id: editor; visible: false; loaded: true
            draft: ({version:1, general:{layout:"master"}, workspaces:[
                {id:2,name:"Work",layout:"scrolling",persistent:true},
                {id:5,name:"",layout:"inherit",persistent:false}], rules:[]})
        }
        function find(object, name) {
            if (object.objectName === name) return object;
            for (let child of object.children || []) {
                let result = find(child, name); if (result) return result;
            }
            return null;
        }
        function check(value) { if (!value) throw Error("Floating switch assertion failed"); }
        Timer {
            interval: 100; running: true
            onTriggered: {
                try {
                    let control = fixture.find(editor, "workspaceFloating-0");
                    fixture.check(control && !control.checked);
                    control.checked = true; control.toggled();
                    fixture.check(editor.pending && editor.draft.workspaces[0].floating === true);
                    fixture.check(editor.draft.workspaces[0].layout === "scrolling");
                    fixture.check(editor.draft.workspaces[0].persistent === true);
                    fixture.check(editor.draft.workspaces[1].floating === undefined);
                    fixture.check(editor.draft.general.layout === "master");
                    control.checked = false; control.toggled();
                    fixture.check(editor.draft.workspaces[0].floating === false);
                    editor.add("workspaces");
                    fixture.check(editor.draft.workspaces[2].floating === false);
                    console.warn("WORKSPACE_FLOATING_OK");
                } catch (error) { console.error("WORKSPACE_FLOATING_FAILED", error); }
                Qt.quit();
            }
        }
    }
}
''')
            runtime = root / 'runtime'; runtime.mkdir(mode=0o700)
            env = dict(os.environ, XDG_CONFIG_HOME=str(root / 'config'), XDG_STATE_HOME=str(root / 'state'),
                       XDG_RUNTIME_DIR=str(runtime), HYPRLAND_INSTANCE_SIGNATURE='', QT_QPA_PLATFORMTHEME='',
                       QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software')
            result = subprocess.run(['quickshell', '-p', str(entry)], capture_output=True, text=True, env=env, timeout=10)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn('WORKSPACE_FLOATING_OK', output, output)
            self.assertNotIn('WORKSPACE_FLOATING_FAILED', output, output)
            self.assertFalse((root / 'config/hyprshell/behavior.json').exists())
