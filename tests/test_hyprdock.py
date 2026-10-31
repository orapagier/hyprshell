"""Exercise the actual dock content and editor lifecycle in an isolated Qt scene.

The layer-shell-only properties are removed for the offscreen backend; geometry,
controllers, animation and content remain production QML.
"""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class HyprdockRuntime(unittest.TestCase):
    def test_content_routing_and_settings_lifecycle(self):
        with tempfile.TemporaryDirectory(prefix='hyprdock-test-') as directory:
            root = Path(directory)
            payload = root / 'config/quickshell'
            shutil.copytree(ROOT / 'config/quickshell', payload, ignore=shutil.ignore_patterns('__pycache__'))
            source = (payload / 'Hyprdock.qml').read_text().replace('PanelWindow {', 'FloatingWindow {', 1)
            source = '\n'.join(line for line in source.splitlines() if not any(token in line for token in (
                'anchors { top: true;', 'exclusionMode:', 'exclusiveZone:', 'WlrLayershell.', 'mask: Region')))
            source = source.replace('visible: true\n    color:', 'visible: true\n    implicitWidth: 1200; implicitHeight: 900\n    color:', 1)
            (payload / 'Hyprdock.qml').write_text(source)
            projector = (payload / 'ProjectorWindow.qml').read_text().replace('PanelWindow {', 'FloatingWindow {', 1)
            projector = '\n'.join(line for line in projector.splitlines() if not any(token in line for token in ('anchors { top: true;', 'exclusionMode:', 'WlrLayershell.')))
            (payload / 'ProjectorWindow.qml').write_text(projector)
            (payload / 'DockProbe.qml').write_text('''pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import "."
ShellRoot {
    id: test
    SettingsStore { id: store }
    DesktopServices { id: services }
    NotificationInbox { id: inbox; preferences: store.config.notifications }
    ApplicationService { id: apps; store: store }
    SettingsController { id: editor; store: store; dockEnabled: true; dockResolver: () => dock.prepareSettings(); audioServices: services; batteryInfo: services.batteryInfo }
    ProjectorWindow { id: projector }
    Hyprdock { id: dock; projector: projector; notificationTarget: true; store: store; services: services; inbox: inbox; applicationService: apps; settingsController: editor; clockText: "12:34"; motionEnabled: false }
    function check(ok, reason) { if (!ok) throw new Error(reason); }
    function find(item, name) {
        if (item.objectName === name) return item;
        for (let child of item.children || []) { let found = find(child, name); if (found) return found; }
        return null;
    }
    property int phase: 0
    property var names: ["calendar", "audio", "wifi", "bluetooth", "battery", "power", "notifications", "launcher", "keybindings", "dashboard", "activity", "displays", "settings"]
    Timer {
        interval: 600; running: true; repeat: true
        onTriggered: {
            try {
                if (test.phase === 0) {
                    test.check(!dock.expanded, "starts compact");
                    test.check(dock.targetHeight === 22, "compact clock has small vertical padding");
                    let glass = test.find(dock.contentItem, "dockGlass");
                    test.check(glass.bottomColor.a === 1, "dock defaults to opaque");
                    let transparent = JSON.parse(JSON.stringify(store.config)); transparent.bar.dockTransparency = 0.4; store.acceptConfig(transparent);
                    test.check(Math.abs(glass.bottomColor.a - 0.6) < 0.01, "dock transparency changes background only");
                    transparent.bar.dockTransparency = 0; store.acceptConfig(transparent);
                    let bar = test.find(dock.contentItem, "dockBar");
                    test.check(test.find(dock.contentItem, "settingsDockTrigger") !== null, "Settings is present");
                    let names = ["launcher", "dashboard", "settings", "keybindings", "activity"];
                    let previous = -1;
                    for (let name of names) {
                        let button = test.find(dock.contentItem, name + "DockTrigger");
                        test.check(button && button.x > previous, "leading control order: " + name);
                        previous = button.x;
                    }
                    test.check(dock.stripSize === 36 && bar.appearance("audio").uniformGlyphHeight === 16, "revealed controls are larger");
                    test.check(!bar.itemEnabled("launcher") && !bar.itemEnabled("settings"), "moved controls have no duplicates");
                    let vibrant = JSON.parse(JSON.stringify(store.config)); vibrant.bar.randomVibrantColors = true; store.acceptConfig(vibrant);
                    let originalPalette = dock.itemPalette.join(",");
                    dock.wallpaperSource = "file:///tmp/dock-wallpaper-alternate.png";
                    test.check(dock.itemPalette.join(",") !== originalPalette, "wallpaper changes dock palette");
                    for (let item of bar.settings.items) {
                        test.check(item.iconColor === dock.itemColor(item.id), "wallpaper updates live ink " + item.id);
                        test.check(!["#5dccff", "#86a6ff", "#b88aff"].includes(item.iconColor), "blue slots replaced");
                    }
                    dock.wallpaperSource = "";
                    test.check(dock.itemPalette.join(",") === originalPalette, "returning wallpaper restores palette");
                    test.check(bar.settings.items.slice(-5).map(i => i.id).join(",") === "bluetooth,audio,wifi,battery,power", "status controls trail the strip");
                    test.check(bar.appearance("workspaces").background === "on" && bar.appearance("workspaces").uniformTextHeight === 8, "small workspace numbers with individual pills");
                    test.check(test.find(dock.contentItem, "hyprdockSurface").clip, "items reveal within animated background bounds");
                    dock.revealKeyboard();
                    test.check(dock.expanded && !dock.section, "keyboard reveal only opens strip");
                } else if (test.phase <= test.names.length) {
                    if (dock.section === "power") {
                        let page = test.find(dock.contentItem, "dockMenuPage");
                        test.check(Math.abs(dock.contentHeight - page.item.implicitHeight - 40) < 1, "Power height follows its buttons");
                        test.check(Math.abs(test.find(dock.contentItem, "hyprdockBody").height - dock.contentHeight) < 1, "Power has no unused space below its content");
                        test.find(dock.contentItem, "hyprdockSurface").grabToImage(result => result.saveToFile("/tmp/hyprdock-power-preview.png"));
                    }
                    let name = test.names[test.phase - 1]; dock.open(name, true);
                    test.check(dock.section === name, "route " + name);
                    let bar = test.find(dock.contentItem, "dockBar");
                    if (bar.menuTargets[name]) test.check(dock.headerColor.toString() === bar.menuAccent(name).toString(), "header follows icon " + name);
                } else if (test.phase === test.names.length + 1) {
                    test.check(editor.window && editor.window.dockOpened && !editor.window.visible, "Settings embedded without native window");
                    let root = test.find(dock.contentItem, "settingsRoot");
                    test.check(root && root.visible && root.parent === dock.settingsHost, "editor visual root belongs to dock");
                    dock.open("calendar", true);
                    test.check(!editor.window || !editor.window.dockOpened, "close embedded editor on navigation");
                    dock.closeContent();
                    test.check(!dock.section && dock.expanded, "Escape returns to items");
                    dock.collapse();
                    test.check(!dock.expanded && !dock.requested, "collapse releases shortcut reveal");
                } else if (test.phase <= test.names.length + 5) {
                    let edge = ["top", "bottom", "left", "right"][test.phase - test.names.length - 2];
                    let next = JSON.parse(JSON.stringify(store.config)); next.bar.position = edge; store.acceptConfig(next);
                    dock.open("launcher", true);
                    let surface = test.find(dock.contentItem, "hyprdockSurface");
                    test.check(surface.width <= dock.width && surface.height <= dock.height, "screen bounded " + edge);
                    let origin = surface.mapToItem(dock.contentItem, 0, 0);
                    test.check(edge === "top" ? origin.y === 0 : edge === "bottom" ? Math.abs(origin.y + surface.height - dock.height) < 1 : edge === "left" ? origin.x === 0 : Math.abs(origin.x + surface.width - dock.width) < 1, "attached " + edge);
                    if (edge === "top") surface.grabToImage(result => result.saveToFile("/tmp/hyprdock-launcher-preview.png"));
                } else if (test.phase === test.names.length + 6) {
                    dock.collapse();
                    test.find(dock.contentItem, "dockBase").entered();
                    test.check(dock.expanded && !dock.section, "base reveals items without a menu");
                    test.find(dock.contentItem, "dockMenuState").hover("calendar");
                } else if (test.phase === test.names.length + 7) {
                    let state = test.find(dock.contentItem, "dockMenuState");
                    test.check(dock.section === "calendar" && !state.pinned, "hover opens unpinned content: " + dock.section + "/" + state.pinned + "/" + state.hoveredMenu + "/" + state.hoverEnabled + "/actual:" + state.section);
                    state.retain(true); state.leave("calendar");
                } else if (test.phase === test.names.length + 8) {
                    test.check(dock.section === "calendar", "pointer inside content retains expansion");
                    test.find(dock.contentItem, "dockMenuState").retain(false);
                } else if (test.phase === test.names.length + 9) {
                    test.check(!dock.section, "hover content closes after leaving");
                    dock.open("launcher", true);
                } else if (test.phase === test.names.length + 10) {
                    test.check(test.find(dock.contentItem, "launcherSearch").activeFocus, "launcher search receives keyboard focus");
                    dock.closeContent();
                    test.check(dock.keyboardSession, "first Escape keeps keyboard control of strip");
                    dock.collapse();
                    inbox.popups = [{id:"dock-test", app:"Test", summary:"Dock notification", body:"Test content", actions:[], critical:true, popupDeadline:Date.now()+10000}];
                    test.check(dock.section === "alerts", "notifications expand dock");
                } else if (test.phase === test.names.length + 11) {
                    test.check(test.find(dock.contentItem, "popup-dock-test") !== null, "notification content is inside dock");
                    inbox.popups = [];
                    test.check(!dock.section, "notification dismissal closes alert expansion");
                } else {
                    console.log("HYPRDOCK_OK"); Qt.quit();
                }
                test.phase++;
            } catch (e) { console.error("HYPRDOCK_FAILED", e); Qt.exit(1); }
        }
    }
    Timer {
        interval: 200; running: dock.section === "settings"
        onTriggered: {
            let root = test.find(dock.contentItem, "settingsRoot");
            if (root) root.grabToImage(result => result.saveToFile("/tmp/hyprdock-settings-preview.png"));
        }
    }
    Timer { interval: 25000; running: true; onTriggered: Qt.exit(2) }
}''')
            runtime = root / 'runtime'
            runtime.mkdir(mode=0o700)
            env = dict(os.environ, XDG_CONFIG_HOME=str(root / 'config'), XDG_STATE_HOME=str(root / 'state'),
                       XDG_RUNTIME_DIR=str(runtime), HYPRLAND_INSTANCE_SIGNATURE='', QT_QPA_PLATFORMTHEME='',
                       QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software')
            result = subprocess.run(['quickshell', '--log-rules', 'qml=true', '-p', str(payload / 'DockProbe.qml')], env=env, capture_output=True, text=True, timeout=30)
            output = result.stdout + result.stderr
            Path("/tmp/hyprdock-qt.log").write_text(output)
            self.assertEqual(result.returncode, 0, output)
            self.assertIn('HYPRDOCK_OK', output)
            for error in ('ReferenceError', 'TypeError', 'Binding loop', 'Unable to assign', 'HYPRDOCK_FAILED'):
                self.assertNotIn(error, output)
