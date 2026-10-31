"""Opening Settings defers editor sections and preserves their navigation state."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('quickshell'), 'Quickshell is required')
class SettingsOpeningTests(unittest.TestCase):
    def test_dock_animation_keeps_embedded_editor_geometry_stable(self):
        with tempfile.TemporaryDirectory(prefix='hyprshell-settings-geometry-') as directory:
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
            (payload / 'GeometryProbe.qml').write_text('''pragma ComponentBehavior: Bound
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
    SettingsController { id: controller; store: store; dockEnabled: true; dockResolver: () => dock.prepareSettings() }
    Hyprdock { id: dock; store: store; services: services; inbox: inbox; applicationService: apps; settingsController: controller }
    TestCase { id: driver; when: false }
    function check(ok, reason) { if (!ok) throw new Error(reason); }
    Timer {
        interval: 100; running: true
        onTriggered: {
            try {
                for (let edge of ["top", "bottom", "left", "right"]) {
                    let config = JSON.parse(JSON.stringify(store.config));
                    config.bar.position = edge; store.acceptConfig(config);
                    dock.open("settings", false);
                    driver.wait(150);
                    test.check(controller.window && controller.window.dockOpened, "embedded editor opens " + edge);
                    let width = dock.settingsHost.width, height = dock.settingsHost.height;
                    for (let frame = 0; frame < 40; ++frame) {
                        driver.wait(25);
                        test.check(Math.abs(dock.settingsHost.width - width) < 0.1
                            && Math.abs(dock.settingsHost.height - height) < 0.1,
                            "spring resizes embedded editor " + edge);
                    }
                    let slot = dock.settingsHost.parent;
                    test.check(Math.abs(width - Math.max(760, slot.width)) <= 1, "final width " + edge);
                    test.check(Math.abs(height - slot.height) <= 1, "final height " + edge);
                    dock.collapse(); driver.wait(1000);
                }
                console.log("SETTINGS_GEOMETRY_OK"); Qt.quit();
            } catch (error) { console.error("SETTINGS_GEOMETRY_FAILED", error); Qt.exit(1); }
        }
    }
}''')
            runtime = root / 'runtime'
            runtime.mkdir(mode=0o700)
            env = dict(os.environ, XDG_CONFIG_HOME=str(root / 'config'),
                       XDG_STATE_HOME=str(root / 'state'), XDG_RUNTIME_DIR=str(runtime),
                       HYPRLAND_INSTANCE_SIGNATURE='', QT_QPA_PLATFORMTHEME='',
                       QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software')
            result = subprocess.run(['quickshell', '--log-rules', 'qml=true', '-p', str(payload / 'GeometryProbe.qml')],
                                    env=env, capture_output=True, text=True, timeout=18)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn('SETTINGS_GEOMETRY_OK', output)
            for error in ('ReferenceError', 'TypeError', 'Binding loop', 'Unable to assign'):
                self.assertNotIn(error, output)

    def test_editors_load_on_selection_and_keep_their_existing_actions(self):
        with tempfile.TemporaryDirectory(prefix='hyprshell-settings-opening-') as directory:
            root = Path(directory)
            payload = root / 'config/quickshell'
            shutil.copytree(ROOT / 'config/quickshell', payload,
                            ignore=shutil.ignore_patterns('__pycache__'))
            (payload / 'OpeningProbe.qml').write_text('''pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import Quickshell
import "."
ShellRoot {
    id: test
    SettingsStore { id: store }
    SettingsWindow { id: editor; store: store }
    TestCase { id: driver; when: false }
    function check(ok, reason) { if (!ok) throw new Error(reason); }
    Timer {
        interval: 100; running: true
        onTriggered: {
            try {
                editor.open();
                driver.wait(50);
                let bar = driver.findChild(editor.contentItem, "settingsBarEditorLoader");
                let item = driver.findChild(editor.contentItem, "settingsItemEditorLoader");
                let appearance = driver.findChild(editor.contentItem, "settingsAppearanceLoader");
                for (let loader of [bar, item, appearance])
                    test.check(loader && !loader.active && !loader.item, "hidden editor built at startup");
                editor.section = -1;
                driver.wait(30);
                test.check(bar.active && bar.item, "Hyprpane editor loads");
                let originalBar = bar.item;
                bar.item.selectedWorkspace = 7;
                bar.item.edited("spacing", 17);
                test.check(editor.draft.bar.spacing === 17, "Hyprpane edit remains wired");
                editor.section = editor.draft.items.findIndex(row => row.id === "audio");
                driver.wait(30);
                test.check(item.active && item.item && bar.item === originalBar, "item editor loads and retains visited page");
                item.item.edited("textColor", "#ff8800");
                test.check(editor.selected.textColor === "#ff8800", "item edit remains wired");
                editor.section = -2;
                driver.wait(30);
                test.check(appearance.active && appearance.item && item.active, "appearance editor loads");
                appearance.item.selectedWorkspace = 8;
                appearance.item.edited("activeOpacity", 70);
                test.check(editor.draft.hyprland.activeOpacity === 70, "appearance edit remains wired");
                editor.goHome();
                driver.wait(30);
                test.check(!bar.visible && !item.visible && !appearance.visible, "editor pages hidden on overview");
                editor.section = -1;
                driver.wait(30);
                test.check(bar.item === originalBar && bar.item.settings.spacing === 17
                    && bar.item.selectedWorkspace === 7 && appearance.item.selectedWorkspace === 8,
                    "visited editors retain drafts and workspace selectors");
                console.log("SETTINGS_OPENING_OK"); Qt.quit();
            } catch (error) { console.error("SETTINGS_OPENING_FAILED", error); Qt.exit(1); }
        }
    }
}''')
            runtime = root / 'runtime'
            runtime.mkdir(mode=0o700)
            env = dict(os.environ, XDG_CONFIG_HOME=str(root / 'config'),
                       XDG_STATE_HOME=str(root / 'state'), XDG_RUNTIME_DIR=str(runtime),
                       HYPRLAND_INSTANCE_SIGNATURE='', QT_QPA_PLATFORMTHEME='',
                       QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software')
            result = subprocess.run(['quickshell', '--log-rules', 'qml=true', '-p', str(payload / 'OpeningProbe.qml')],
                                    env=env, capture_output=True, text=True, timeout=12)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn('SETTINGS_OPENING_OK', output)
            for error in ('ReferenceError', 'TypeError', 'Binding loop', 'Unable to assign'):
                self.assertNotIn(error, output)
