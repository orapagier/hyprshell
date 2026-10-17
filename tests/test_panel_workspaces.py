"""Configure all panels on one edge via native Settings in an isolated home."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('quickshell'), 'Native Quickshell is needed')
class PanelWorkspaceNativeTests(unittest.TestCase):
    def test_shared_edge_workspace_controls_save_and_follow_transitions(self):
        source = r'''import QtQuick
import Quickshell
import "."
import "SettingsModel.js" as Model
import "DockModel.js" as Geometry
ShellRoot {
    id: test
    property int phase: 0
    SettingsStore { id: prefs }
    SettingsWindow { id: editor; store: prefs }
    function find(root, name) {
        if (root.objectName === name) return root;
        for (let child of root.children || []) { let found=find(child,name); if (found) return found; }
        return null;
    }
    function fail(message) { console.error('PANEL_WORKSPACES_FAILED',message); Qt.quit(); }
    function select(root, name, index) {
        let control=find(root,name); control.currentIndex=index; control.activated(index);
    }
    function show(root, name) { let control=find(root,name); control.checked=true; control.toggled(); }
    Timer { interval:100; repeat:true; running:true; onTriggered: {
        if (!prefs.loaded || editor.saving || editor.dirty) return;
        let root=editor.contentItem;
        if (test.phase===0) {
            editor.open(); editor.firstRunPending=false; editor.section=-1;
            test.find(root,'barHideAllControl').clicked();
            test.select(root,'barWorkspaceControl',0);
            test.show(root,'barWorkspaceVisibleControl');
            test.select(root,'barPositionControl',3); // Bottom
        } else if (test.phase===1 || test.phase===2) {
            let component=test.phase===1 ? 'hyprdock' : 'hyprbar';
            let panel=test.find(root,component+'Editor');
            test.find(panel,component+'HideAllControl').clicked();
            test.select(panel,component+'WorkspaceControl',test.phase);
            test.show(panel,component+'WorkspaceVisibleControl');
            test.select(panel,'dockEdgeControl',1); // Bottom
            test.show(panel,'dockEnabledControl');
        } else if (test.phase===3) {
            if (!editor.success) { test.fail(editor.message); return; }
            let names=['hyprpane','hyprdock','hyprbar'];
            // Shortcut toggles use the current Settings draft and retain other panels.
            let original=JSON.stringify(editor.draft);
            for (let name of names) {
                let workspace=names.indexOf(name)+1;
                editor.toggleWorkspacePanel(name,workspace);
                if (Model.panelVisible(editor.draft,name,'eDP-1',workspace)) { test.fail('shortcut did not hide '+name); return; }
                editor.toggleWorkspacePanel(name,workspace);
                if (JSON.stringify(editor.draft)!==original) { test.fail('shortcut did not restore draft '+name); return; }
            }
            // Verify runtime visibility, corner/menu protection and return transitions.
            for (let ws of [1,2,3,4,3,2,1]) {
                let active=names.filter(n=>Model.panelVisible(editor.draft,n,'eDP-1',ws));
                if (JSON.stringify(active)!==JSON.stringify(ws<=3 ? [names[ws-1]] : [])) {
                    test.fail('visibility on workspace '+ws); return;
                }
                if (active.length) {
                    let bounds=Geometry.menuBounds(editor.draft,active[0],'eDP-1',ws,32,800,600);
                    if (bounds.width!==800 || bounds.height!==600) { test.fail('hidden neighbour reserved menu space'); return; }
                }
            }
            // All-panel buttons clear individual choices without changing styling.
            let dock=test.find(root,'hyprdockEditor');
            test.find(dock,'hyprdockShowAllControl').clicked();
            if (Object.keys(editor.draft.panels.hyprdock.workspaceOverrides).length) { test.fail('show all retained overrides'); return; }
            // Restore before autosave; no conflicting layout is written.
            test.find(dock,'hyprdockHideAllControl').clicked();
            test.select(dock,'hyprdockWorkspaceControl',1); test.show(dock,'hyprdockWorkspaceVisibleControl');
        } else {
            if (!editor.success) { test.fail(editor.message); return; }
            console.log('PANEL_WORKSPACES_OK'); Qt.quit(); return;
        }
        test.phase++;
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
            original = json.loads((payload / 'settings/defaults.json').read_text())
            original['panels']['hyprdock'].update(thickness=51, rightItems=['audio'])
            original['pins'].update(mode='separate', hyprdock=['missing.desktop'])
            saved = root / 'config/hyprshell/settings.json'
            saved.parent.mkdir()
            saved.write_text(json.dumps(original))
            entry = payload / 'PanelWorkspacesNative.qml'
            entry.write_text(source)
            env = dict(os.environ, HOME=str(root), XDG_CONFIG_HOME=str(root / 'config'),
                       XDG_STATE_HOME=str(root / 'state'), XDG_RUNTIME_DIR=str(runtime),
                       HYPRLAND_INSTANCE_SIGNATURE='', QT_QPA_PLATFORMTHEME='',
                       QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software')
            result = subprocess.run(['quickshell', '--log-rules', 'qml=true', '-p', str(entry)],
                                    env=env, capture_output=True, text=True, timeout=20)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn('PANEL_WORKSPACES_OK', output)
            for error in ('PANEL_WORKSPACES_FAILED', 'ReferenceError', 'TypeError', 'Binding loop', 'Unable to assign'):
                self.assertNotIn(error, output)
            expected = json.loads(json.dumps(original))
            for workspace, name in enumerate(('hyprpane', 'hyprdock', 'hyprbar'), 1):
                expected['panels'][name]['enabled'] = True
                panel = expected['bar'] if name == 'hyprpane' else expected['panels'][name]
                panel.update(position='bottom', visible=False, workspaceScope='all',
                             workspaceList=[], workspaceOverrides={str(workspace): True})
            self.assertEqual(json.loads(saved.read_text()), expected)


if __name__ == '__main__':
    unittest.main()
