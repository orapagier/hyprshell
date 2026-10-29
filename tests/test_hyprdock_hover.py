"""Keep a real pointer on a dock item while spring-driven content changes size."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class DockHoverTests(unittest.TestCase):
    def test_stationary_pointer_and_stable_strip_on_all_edges(self):
        with tempfile.TemporaryDirectory(prefix='hyprdock-hover-') as directory:
            root = Path(directory)
            payload = root / 'config/quickshell'
            shutil.copytree(ROOT / 'config/quickshell', payload, ignore=shutil.ignore_patterns('__pycache__'))
            dock = (payload / 'Hyprdock.qml').read_text().replace('PanelWindow {', 'FloatingWindow {', 1)
            dock = '\n'.join(line for line in dock.splitlines() if not any(token in line for token in (
                'anchors { top: true;', 'exclusionMode:', 'exclusiveZone:', 'WlrLayershell.', 'mask: Region')))
            dock = dock.replace('visible: true\n    color:', 'visible: true\n    implicitWidth: 1200; implicitHeight: 900\n    color:', 1)
            (payload / 'Hyprdock.qml').write_text(dock)
            (payload / 'HoverProbe.qml').write_text('''pragma ComponentBehavior: Bound
import QtQuick
import QtTest
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
                for (let edge of ["top", "bottom", "left", "right"]) {
                    pointer.mouseMove(dock.contentItem, 20, 20);
                    dock.collapse();
                    let next = JSON.parse(JSON.stringify(store.config)); next.bar.position = edge; store.acceptConfig(next);
                    pointer.wait(500);
                    let baseX = edge === "left" ? 1 : edge === "right" ? dock.width - 1 : dock.width / 2;
                    let baseY = edge === "top" ? 1 : edge === "bottom" ? dock.height - 1 : dock.height / 2;
                    pointer.mouseMove(dock.contentItem, baseX, baseY);
                    pointer.wait(600);
                    test.check(dock.expanded && !dock.section, "base only reveals items: " + edge + "/" + dock.section);
                    let trigger = test.find(dock.contentItem, "calendarTrigger");
                    let position = trigger.mapToItem(dock.contentItem, trigger.width / 2, trigger.height / 2);
                    pointer.mouseMove(dock.contentItem, position.x, position.y);
                    pointer.wait(450);
                    test.check(dock.section === "calendar", "hover opens calendar: " + edge + "/" + dock.section + "/" + trigger.hovered + "/" + test.find(dock.contentItem, "dockMenuState").hoveredMenu);
                    for (let frame = 0; frame < 30; ++frame) {
                        pointer.wait(25);
                        let now = trigger.mapToItem(dock.contentItem, trigger.width / 2, trigger.height / 2);
                        test.check(Math.abs(now.x - position.x) < 0.1 && Math.abs(now.y - position.y) < 0.1, "item moved under stationary pointer: " + edge);
                        test.check(dock.section === "calendar", "content oscillated while pointer stayed on item: " + edge + "/" + dock.section);
                        let input = dock.inputRect;
                        test.check(position.x >= input.x && position.x <= input.x + input.width && position.y >= input.y && position.y <= input.y + input.height, "spring excluded pointer from input mask: " + edge);
                    }
                    let strip = test.find(dock.contentItem, "dockItemStrip");
                    let gap = strip.mapToItem(dock.contentItem, dock.vertical ? strip.width / 2 : 7, dock.vertical ? 7 : strip.height / 2);
                    pointer.mouseMove(dock.contentItem, gap.x, gap.y);
                    pointer.wait(600);
                    test.check(dock.section === "calendar", "blank strip should retain content: " + edge);
                    let surface = test.find(dock.contentItem, "hyprdockSurface");
                    let content = surface.mapToItem(dock.contentItem, surface.width / 2, surface.height / 2);
                    pointer.mouseMove(dock.contentItem, content.x, content.y);
                    pointer.wait(500);
                    test.check(dock.section === "calendar", "content hover should retain expansion: " + edge);
                    pointer.mouseMove(dock.contentItem, edge === "left" ? dock.width - 20 : 20, edge === "top" ? dock.height - 20 : 20);
                    pointer.wait(900);
                    test.check(!dock.section && !dock.expanded, "leaving whole dock should collapse: " + edge);
                }
                console.log("DOCK_HOVER_OK"); Qt.quit();
            } catch (e) { console.error("DOCK_HOVER_FAILED", e); Qt.exit(1); }
        }
    }
}''')
            runtime = root / 'runtime'
            runtime.mkdir(mode=0o700)
            env = dict(os.environ, XDG_CONFIG_HOME=str(root / 'config'), XDG_STATE_HOME=str(root / 'state'),
                       XDG_RUNTIME_DIR=str(runtime), HYPRLAND_INSTANCE_SIGNATURE='', QT_QPA_PLATFORMTHEME='',
                       QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software')
            result = subprocess.run(['quickshell', '--log-rules', 'qml=true', '-p', str(payload / 'HoverProbe.qml')],
                                    env=env, capture_output=True, text=True, timeout=35)
            output = result.stdout + result.stderr
            Path('/tmp/hyprdock-pointer-test.log').write_text(output)
            self.assertEqual(result.returncode, 0, output)
            self.assertIn('DOCK_HOVER_OK', output)
            for error in ('ReferenceError', 'TypeError', 'Binding loop', 'Unable to assign', 'DOCK_HOVER_FAILED'):
                self.assertNotIn(error, output)
