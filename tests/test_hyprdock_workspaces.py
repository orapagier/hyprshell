"""Verify workspace clicks release the dock keyboard grab before dispatch."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class DockWorkspaceTests(unittest.TestCase):
    def test_clicks_release_focus_before_dispatch_on_all_edges(self):
        with tempfile.TemporaryDirectory(prefix='hyprdock-workspaces-') as directory:
            root = Path(directory)
            payload = root / 'config/quickshell'
            shutil.copytree(ROOT / 'config/quickshell', payload, ignore=shutil.ignore_patterns('__pycache__'))
            dock = (payload / 'Hyprdock.qml').read_text().replace('PanelWindow {', 'FloatingWindow {', 1)
            dock = dock.replace('WlrLayershell.keyboardFocus:', 'property int requestedKeyboardFocus:')
            dock = '\n'.join(line for line in dock.splitlines() if not any(token in line for token in (
                'anchors { top: true;', 'exclusionMode:', 'exclusiveZone:', 'WlrLayershell.', 'mask: Region')))
            dock = dock.replace('visible: true\n    color:', 'visible: true\n    implicitWidth: 1200; implicitHeight: 900\n    color:', 1)
            (payload / 'Hyprdock.qml').write_text(dock)
            services_path = payload / 'DesktopServices.qml'
            services_source = services_path.read_text()
            start = services_source.index('    function workspace(id)')
            end = services_source.index('    function scrollWorkspace', start)
            services_path.write_text(services_source[:start] +
                '    signal workspaceRequested(int workspaceId)\n'
                '    function workspace(id) { workspaceRequested(Number(id)); }\n' + services_source[end:])
            (payload / 'WorkspaceProbe.qml').write_text('''pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import Quickshell.Wayland
import Quickshell
import "."
ShellRoot {
    id: test
    SettingsStore { id: store }
    DesktopServices { id: services }
    NotificationInbox { id: inbox; preferences: store.config.notifications }
    ApplicationService { id: apps; store: store }
    SettingsController { id: editor; store: store; dockEnabled: true; dockResolver: () => dock.prepareSettings() }
    Hyprdock { id: dock; store: store; services: services; inbox: inbox; applicationService: apps; settingsController: editor; clockText: "12:34"; motionEnabled: true }
    TestCase { id: pointer; name: "DockPointerDriver"; when: false }
    function check(ok, reason) { if (!ok) throw new Error(reason); }
    function find(item, name) {
        if (item.objectName === name) return item;
        for (let child of item.children || []) { let found = find(child, name); if (found) return found; }
        return null;
    }
    Timer {
        interval: 300; running: true
        onTriggered: {
            try {
                let bar = test.find(dock.contentItem, "dockBar");
                bar.outputName = "";
                bar.statusData = Object.assign({}, services.statusData, {workspaces: [{id:1,name:"1",active:true}, {id:2,name:"2",active:false}]});
                let requests = [];
                services.workspaceRequested.connect(id => requests.push({id: id,
                    expanded: dock.expanded, keyboard: dock.keyboardSession,
                    grab: dock.requestedKeyboardFocus}));
                let actions = [];
                bar.action.connect((name, argument) => actions.push([name, argument]));
                for (let edge of ["top", "bottom", "left", "right"]) {
                    dock.collapse();
                    let next = JSON.parse(JSON.stringify(store.config)); next.bar.position = edge; store.acceptConfig(next);
                    pointer.mouseMove(dock.contentItem, 20, 20);
                    dock.revealKeyboard();
                    pointer.wait(1200);
                    let button = test.find(dock.contentItem, "workspace2");
                    test.check(button, "workspace exists");
                    let position = button.mapToItem(dock.contentItem, button.width / 2, button.height / 2);
                    pointer.mouseMove(dock.contentItem, position.x, position.y);
                    pointer.wait(1000);
                    test.check(dock.section === "workspacePreview", "hover preview " + edge);
                    test.check(dock.requestedKeyboardFocus === WlrKeyboardFocus.Exclusive, "grab before click");
                    let count = actions.length;
                    let requestCount = requests.length;
                    pointer.mouseClick(dock.contentItem, position.x, position.y, Qt.LeftButton);
                    pointer.wait(100);
                    test.check(actions.length === count + 1 && actions[count][0] === "workspace" && actions[count][1] === 2, "workspace click " + edge + ": " + JSON.stringify(actions));
                    test.check(requests.length === requestCount + 1, "one workspace request");
                    let request = requests[requestCount];
                    test.check(request.id === 2 && !request.expanded && !request.keyboard
                        && request.grab === WlrKeyboardFocus.None, "release grab before dispatch " + edge + ": " + JSON.stringify(request));
                    pointer.wait(400);
                    test.check(!dock.expanded, "stationary pointer cannot reopen dock");
                    pointer.mouseMove(dock.contentItem, 20, 20);
                    dock.revealKeyboard();
                    bar.previewWorkspaceId = 2;
                    dock.open("workspacePreview", false);
                    pointer.wait(700);
                    let preview = test.find(dock.contentItem, "dockMenuPage").item;
                    requestCount = requests.length;
                    preview.activated(2);
                    pointer.wait(100);
                    test.check(requests.length === requestCount + 1 && !requests[requestCount].expanded
                        && requests[requestCount].grab === WlrKeyboardFocus.None, "preview releases grab " + edge);
                }
                console.log("DOCK_WORKSPACES_OK"); Qt.quit();
            } catch (e) { console.error("DOCK_WORKSPACES_FAILED", e); Qt.exit(1); }
        }
    }
}''')
            runtime = root / 'runtime'
            runtime.mkdir(mode=0o700)
            env = dict(os.environ, XDG_CONFIG_HOME=str(root / 'config'), XDG_STATE_HOME=str(root / 'state'),
                       XDG_RUNTIME_DIR=str(runtime), HYPRLAND_INSTANCE_SIGNATURE='', QT_QPA_PLATFORMTHEME='',
                       QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software')
            result = subprocess.run(['quickshell', '--log-rules', 'qml=true', '-p', str(payload / 'WorkspaceProbe.qml')],
                                    env=env, capture_output=True, text=True, timeout=55)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn('DOCK_WORKSPACES_OK', output)
            for error in ('ReferenceError', 'TypeError', 'Binding loop', 'Unable to assign', 'DOCK_WORKSPACES_FAILED'):
                self.assertNotIn(error, output)

if __name__ == "__main__":
    unittest.main()
