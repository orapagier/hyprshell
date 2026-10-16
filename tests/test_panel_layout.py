"""Exercise layout presets through native Settings and its real save transaction."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('quickshell'), 'Native Quickshell is needed')
class PanelLayoutNativeTests(unittest.TestCase):
    def test_preview_is_read_only_and_all_presets_save_atomically(self):
        source = r'''import QtQuick
import Quickshell
import "."
ShellRoot {
    id: test
    property int step: -1
    property int selected: 0
    property string before: ''
    SettingsStore { id: prefs }
    SettingsWindow { id: editor; store: prefs }
    function find(root, name) {
        if (root.objectName === name) return root;
        for (let child of root.children || []) { let found=find(child,name); if (found) return found; }
        return null;
    }
    function fail(message) { console.error('PANEL_LAYOUT_FAILED',message); Qt.quit(); }
    Timer { interval:100; repeat:true; running:true; onTriggered: {
        if (!prefs.loaded) return;
        if (test.step === -1) {
            editor.open(); editor.firstRunPending=false; editor.section=-1;
            test.before=JSON.stringify(editor.draft); test.step=0; return;
        }
        let selector=test.find(editor.contentItem,'panelLayoutPreset');
        let apply=test.find(editor.contentItem,'applyPanelLayoutPreset');
        if (test.step === 0) {
            selector.currentIndex=test.selected+1; selector.activated(test.selected+1);
            test.step=1; return;
        }
        if (test.step === 1) {
            if (JSON.stringify(editor.draft)!==test.before || editor.dirty || editor.saving) {
                test.fail('preview changed preferences'); return;
            }
            if (!apply.enabled) { test.fail('preset rejected'); return; }
            apply.clicked(); test.step=2; return;
        }
        if (editor.saving || editor.dirty) return;
        if (!editor.success) { test.fail(editor.message); return; }
        console.log('PANEL_LAYOUT_SAVED',JSON.stringify(editor.draft));
        test.selected++;
        if (test.selected===6) { console.log('PANEL_LAYOUT_OK'); Qt.quit(); return; }
        test.before=JSON.stringify(editor.draft); test.step=0;
    } }
    Timer { interval:15000; running:true; onTriggered:test.fail('timeout') }
}
'''
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            payload = root / 'config/quickshell'
            shutil.copytree(ROOT / 'config/quickshell', payload,
                            ignore=shutil.ignore_patterns('__pycache__', 'audio-spectrum'))
            runtime = root / 'runtime'
            runtime.mkdir(mode=0o700)
            saved = root / 'config/hyprshell/settings.json'
            saved.parent.mkdir()
            original = json.loads((payload / 'settings/defaults.json').read_text())
            original['bar'].update(position='right', marginTop=19, workspaceOverrides={'3': False})
            original['panels']['hyprpane']['monitors'] = ['eDP-1']
            original['panels']['hyprdock'].update(thickness=51, rightItems=['audio'])
            original['pins'].update(mode='separate', hyprdock=['missing.desktop'])
            saved.write_text(json.dumps(original))
            entry = payload / 'PanelLayoutNative.qml'
            entry.write_text(source)
            env = dict(os.environ, HOME=str(root), XDG_CONFIG_HOME=str(root / 'config'),
                       XDG_STATE_HOME=str(root / 'state'), XDG_RUNTIME_DIR=str(runtime),
                       HYPRLAND_INSTANCE_SIGNATURE='', QT_QPA_PLATFORMTHEME='',
                       QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software')
            result = subprocess.run(['quickshell', '--log-rules', 'qml=true', '-p', str(entry)],
                                    env=env, capture_output=True, text=True, timeout=20)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn('PANEL_LAYOUT_OK', output)
            for error in ('PANEL_LAYOUT_FAILED', 'ReferenceError', 'TypeError', 'Binding loop', 'Unable to assign'):
                self.assertNotIn(error, output)
            snapshots = [json.loads(line.split('PANEL_LAYOUT_SAVED ', 1)[1])
                         for line in output.splitlines() if 'PANEL_LAYOUT_SAVED ' in line]
            layouts = [dict(hyprpane='top', hyprdock='bottom'), dict(hyprpane='top', hyprbar='bottom'),
                       dict(hyprdock='left', hyprbar='bottom'), dict(hyprpane='top'),
                       dict(hyprdock='bottom'), dict(hyprbar='bottom')]
            self.assertEqual(len(snapshots), len(layouts), output)
            expected = json.loads(json.dumps(original))
            for layout, actual in zip(layouts, snapshots):
                for name, panel in expected['panels'].items():
                    panel['enabled'] = name in layout
                    if name in layout:
                        (expected['bar'] if name == 'hyprpane' else panel)['position'] = layout[name]
                self.assertEqual(actual, expected)
            self.assertEqual(json.loads(saved.read_text()), expected)


if __name__ == '__main__':
    unittest.main()
