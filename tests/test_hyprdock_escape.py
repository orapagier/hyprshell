"""Send real Escape events through hovered and keyboard-opened dock content."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class DockEscapeTests(unittest.TestCase):
    def test_escape_collapses_every_view_and_hover_strip(self):
        with tempfile.TemporaryDirectory(prefix='hyprdock-escape-') as directory:
            root = Path(directory)
            payload = root / 'config/quickshell'
            shutil.copytree(ROOT / 'config/quickshell', payload,
                            ignore=shutil.ignore_patterns('__pycache__'))
            path = payload / 'Hyprdock.qml'
            source = path.read_text().replace('PanelWindow {', 'FloatingWindow {', 1)
            source = '\n'.join(line for line in source.splitlines() if not any(token in line for token in (
                'anchors { top: true;', 'exclusionMode:', 'exclusiveZone:', 'WlrLayershell.', 'mask: Region')))
            source = source.replace('visible: true\n    color:',
                                    'visible: true\n    implicitWidth: 1200; implicitHeight: 900\n    color:', 1)
            path.write_text(source)
            (payload / 'EscapeProbe.qml').write_text('''pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
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
    Hyprdock { id: dock; store: store; services: services; inbox: inbox; applicationService: apps; settingsController: editor; motionEnabled: false }
    TestCase { id: keys; name: "DockEscapeDriver"; when: false }
    function check(ok, message) { if (!ok) throw new Error(message); }
    function find(item, name) {
        if (item.objectName === name) return item;
        for (let child of item.children || []) { let result = find(child, name); if (result) return result; }
        return null;
    }
    function pressEscape(label) {
        keys.keyClick(Qt.Key_Escape);
        keys.wait(450);
        check(!dock.expanded && !dock.section && !dock.keyboardSession && !dock.requested, "full collapse: " + label);
        check(!find(dock.contentItem, "dockMenuState").pinned, "unpin: " + label);
    }
    Timer {
        interval: 300; running: true
        onTriggered: {
            try {
                let strip = test.find(dock.contentItem, "dockItemStrip");
                let state = test.find(dock.contentItem, "dockMenuState");
                let base = test.find(dock.contentItem, "dockBase");
                keys.mouseMove(dock.contentItem, dock.width / 2, 1);
                keys.wait(150);
                strip.forceActiveFocus();
                test.check(dock.expanded && !dock.section, "hover reveals strip");
                test.pressEscape("hover strip");
                base.entered(); state.hover("wifi"); keys.wait(250);
                test.check(!dock.expanded, "stationary pointer cannot reopen dock after Escape");
                keys.mouseMove(dock.contentItem, 20, dock.height - 20);
                keys.wait(150);
                keys.mouseMove(dock.contentItem, dock.width / 2, 1);
                keys.wait(150);
                test.check(dock.expanded, "leaving and reentering reveals dock again");
                keys.mouseMove(dock.contentItem, 20, dock.height - 20);
                for (let keyboard of [false, true]) {
                    for (let name of ["launcher", "keybindings", "wifi", "calendar", "audio", "bluetooth", "battery", "power", "notifications", "dashboard", "activity", "settings"]) {
                        dock.hoverDismissed = false;
                        if (keyboard) dock.open(name, true);
                        else { dock.revealed = true; state.hover(name); }
                        keys.wait(200);
                        test.check(dock.section === name, "opened " + name);
                        let search = test.find(dock.contentItem, name === "launcher" ? "launcherSearch" : "keybindingsSearch");
                        if (["launcher", "keybindings"].includes(name)) {
                            test.check(search !== null, "search exists: " + name);
                            search.forceActiveFocus();
                            keys.keyClick(Qt.Key_T);
                        } else strip.forceActiveFocus();
                        test.pressEscape(name + "/" + keyboard);
                    }
                }
                // A focused popup lives in the window overlay, outside the card.
                dock.open("settings", true); keys.wait(200);
                let popup = Qt.createQmlObject('import QtQuick; import QtQuick.Controls.Basic; Popup { width: 100; height: 80; focus: true; closePolicy: Popup.CloseOnEscape; TextField { focus: true } }', strip);
                popup.open(); keys.wait(100);
                test.pressEscape("settings popup");
                popup.destroy();
                test.check(!editor.window || !editor.window.dockOpened, "embedded settings releases host");
                console.log("DOCK_ESCAPE_OK"); Qt.quit();
            } catch (e) { console.error("DOCK_ESCAPE_FAILED", e); Qt.exit(1); }
        }
    }
}''')
            runtime = root / 'runtime'
            runtime.mkdir(mode=0o700)
            env = dict(os.environ, XDG_CONFIG_HOME=str(root / 'config'), XDG_STATE_HOME=str(root / 'state'),
                       XDG_RUNTIME_DIR=str(runtime), HYPRLAND_INSTANCE_SIGNATURE='', QT_QPA_PLATFORMTHEME='',
                       QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software')
            result = subprocess.run(['quickshell', '--log-rules', 'qml=true', '-p', str(payload / 'EscapeProbe.qml')],
                                    env=env, capture_output=True, text=True, timeout=35)
            output = result.stdout + result.stderr
            Path('/tmp/hyprdock-escape-test.log').write_text(output)
            self.assertEqual(result.returncode, 0, output)
            self.assertIn('DOCK_ESCAPE_OK', output)
            for error in ('ReferenceError', 'TypeError', 'Binding loop', 'Unable to assign', 'DOCK_ESCAPE_FAILED'):
                self.assertNotIn(error, output)
