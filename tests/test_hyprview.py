"""Exercise the native viewer's selection, lifecycle and aspect fit offscreen."""
import os
import json
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('quickshell'), 'Native Quickshell is needed')
class HyprviewTests(unittest.TestCase):
    def test_close_shortcut_routes_to_shell(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            stub = root / 'quickshell'
            stub.write_text('#!/usr/bin/python3\nimport json, os, sys\n'
                            'from pathlib import Path\n'
                            'Path(os.environ["HYPRVIEW_TEST_LOG"]).write_text(json.dumps(sys.argv[1:]))\n')
            stub.chmod(0o755)
            config = root / 'config with spaces'
            log = root / 'arguments.json'
            env = dict(os.environ, PATH=str(root) + os.pathsep + os.environ['PATH'],
                       XDG_CONFIG_HOME=str(config), HYPRVIEW_TEST_LOG=str(log))
            result = subprocess.run([str(ROOT / 'bin/hyprshell-shortcut'), 'hyprview-close'],
                                    env=env, capture_output=True, text=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertEqual(json.loads(log.read_text()),
                             ['ipc', '--path', str(config / 'quickshell'), 'call', 'bar', 'closeHyprview'])

    def test_viewer_lifecycle(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            payload = root / 'quickshell'
            payload.mkdir()
            source = (ROOT / 'config/quickshell/Hyprview.qml').read_text()
            # Offscreen Qt has no layer-shell/capture backend. Keep the real
            # selection and rendering logic with a stand-in external surface.
            source = source.replace('PanelWindow {', 'FloatingWindow {')
            source = source.replace('        screen: view.externalOutput\n', '')
            source = source.replace('        anchors { top: true; bottom: true; left: true; right: true }',
                                    '        implicitWidth: 1920; implicitHeight: 1080')
            source = '\n'.join(line for line in source.splitlines()
                               if 'exclusionMode:' not in line and 'WlrLayershell.' not in line)
            source = source.replace('captureSource: canvas.capturing && view.source && !view.streamStopped ? view.source.wayland : null',
                                    'captureSource: null')
            source = source.replace('live: canvas.capturing && !!view.source && !view.streamStopped', 'live: false')
            (payload / 'Hyprview.qml').write_text(source)
            (payload / 'Check.qml').write_text('''import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
ShellRoot {
    id: root
    property QtObject handle: QtObject { property bool fullscreen: false }
    property QtObject viewerHandle: QtObject {
        property bool fullscreen: false
        function fullscreenOn(screen) { throw new Error("must not move a toplevel to the external output"); }
    }
    property var laptop: ({name: "eDP-1"})
    property var hdmi: ({name: "HDMI-A-1"})
    property var dp: ({name: "DP-1"})
    property var extended: [
        {name: "HDMI-A-1", lastIpcObject: {mirrorOf: "none", disabled: false}},
        {name: "DP-1", lastIpcObject: {mirrorOf: "none", disabled: false}}]
    property var first: ({address: "0x1", title: "First window", wayland: handle})
    property var second: ({address: "0x2", title: "Second window", wayland: handle})
    property var own: ({address: "0x3", title: "Hyprview", wayland: viewerHandle,
        lastIpcObject: {pid: Quickshell.processId, initialTitle: "Hyprview"}})
    Hyprview {
        id: view
        windows: [root.first, root.second, root.own]
        activeWindow: root.first
        displays: [root.laptop]
        monitors: root.extended
    }
    TestCase { id: keyboard; parent: view.contentItem; when: false }
    function check(value, message) { if (!value) throw new Error(message); }
    function find(item, name) {
        if (item.objectName === name) return item;
        for (let child of item.children || []) { let found = find(child, name); if (found) return found; }
        return null;
    }
    Timer {
        property int stage: 0
        interval: 100; running: true; repeat: true
        onTriggered: {
            try {
                switch (stage++) {
                case 0:
                    root.check(!view.visible && !view.externalOutput, "start hidden on a single screen");
                    view.projectActive();
                    root.check(view.visible && view.source === root.first, "project active source before opening");
                    break;
                case 1:
                    let image = root.find(view.contentItem, "hyprviewProjection");
                    root.check(!image.paintCursor, "do not copy the source cursor into the projection");
                    root.check(image.parent.width === view.width && image.parent.height === view.height,
                        "projection canvas fills entire window without header or footer");
                    root.check(!root.find(view.contentItem, "hyprviewPicker"), "no visible source picker");
                    root.check(image.width <= image.parent.width && image.height <= image.parent.height
                        && Math.abs(image.width / image.height - 16/9) < 0.001, "aspect fit without cropping");
                    view.activeWindow = root.second;
                    root.check(view.source === root.first, "focus changes do not switch source");
                    view.projectActive();
                    root.check(view.source === root.second, "repeat shortcut replaces source");
                    view.selectWindow(root.first);
                    root.check(view.source === root.first, "source selection still works");
                    view.toggleFullscreen();
                    root.check(view.fullscreen && !root.handle.fullscreen, "fullscreen targets only viewer");
                    view.toggleFullscreen();
                    root.check(!view.fullscreen, "leave fullscreen");
                    view.streamStopped = true;
                    view.selectWindow(root.first);
                    root.check(!view.streamStopped, "reselecting source retries a stopped stream");
                    view.displays = [root.laptop, root.dp, root.hdmi];
                    break;
                case 2:
                    root.check(view.fullscreen && view.projectedOutput === root.hdmi && !view.visible
                        && view.projectionOpen && !root.viewerHandle.fullscreen, "external layer covers HDMI without fullscreening a toplevel");
                    root.check(view.source === root.first && !root.handle.fullscreen, "routing preserves original window");
                    view.toggleFullscreen();
                    root.check(view.visible && !view.projectedOutput && view.source === root.first,
                        "F11 can leave the external layer for the floating viewer");
                    view.toggleFullscreen();
                    root.check(!view.visible && view.projectedOutput === root.hdmi,
                        "F11 can return to the external layer without moving a toplevel");
                    view.monitors = [
                        {name: "HDMI-A-1", lastIpcObject: {mirrorOf: "eDP-1"}},
                        {name: "DP-1", lastIpcObject: {mirrorOf: "none"}}];
                    break;
                case 3:
                    root.check(view.externalOutput === root.dp && view.projectedOutput === root.dp, "skip mirrored HDMI and use DP");
                    view.monitors = [
                        {name: "HDMI-A-1", lastIpcObject: {mirrorOf: "eDP-1"}},
                        {name: "DP-1", lastIpcObject: {disabled: true}}];
                    break;
                case 4:
                    root.check(!view.externalOutput && !view.fullscreen, "skip disabled outputs and return to windowed");
                    view.displays = [root.laptop];
                    view.windows = [root.second, root.own];
                    break;
                case 5:
                    root.check(!view.source && view.visible, "source closing releases capture without closing viewer");
                    view.activeWindow = root.own;
                    view.projectActive();
                    root.check(!view.visible && !view.sourceAddress, "shortcut in viewer closes and releases source");
                    view.activeWindow = root.second;
                    view.projectActive();
                    root.check(view.visible && view.source === root.second, "reopen after close");
                    view.windows = [root.second];
                    view.monitors = root.extended;
                    view.displays = [root.laptop, root.hdmi];
                    break;
                case 6:
                    root.check(!view.viewerHandle && view.projectedOutput === root.hdmi,
                        "external projection works without mapping a toplevel window");
                    view.windows = [root.second, root.own];
                    break;
                case 7:
                    root.check(view.fullscreen && view.projectedOutput === root.hdmi && !root.viewerHandle.fullscreen,
                        "external projection does not move or fullscreen the mapped toplevel either");
                    view.displays = [root.laptop];
                    break;
                case 8:
                    root.check(!view.fullscreen && view.visible && view.source === root.second, "unplug returns existing projection to a window");
                    root.check(!view.selectWindow(root.own) && view.source === root.second, "reject recursive capture");
                    view.selectWindow({address: "0x4", title: "No handle"});
                    root.check(!!view.message && view.source === root.second, "unsupported source preserves selection");
                    view.contentItem.Window.window.requestActivate();
                    view.contentItem.forceActiveFocus();
                    break;
                case 9:
                    keyboard.keyClick(Qt.Key_F11);
                    root.check(view.fullscreen, "actual F11 event activates viewer shortcut");
                    break;
                case 10:
                    keyboard.keyClick(Qt.Key_Escape);
                    root.check(!view.fullscreen && view.visible, "actual Escape event leaves fullscreen");
                    break;
                case 11:
                    keyboard.keyClick(Qt.Key_Escape);
                    root.check(!view.visible && !view.sourceAddress, "actual Escape event closes viewer and releases capture");
                    view.projectActive();
                    view.activeWindow = root.first;
                    view.dismiss();
                    root.check(!view.visible && !view.sourceAddress, "remote close does not depend on viewer focus");
                    view.activeWindow = null;
                    view.projectActive();
                    root.check(view.visible && !view.source && !!view.message, "no focused window shows shortcut guidance");
                    view.dismiss();
                    console.log("HYPRVIEW_OK");
                    Qt.quit();
                }
            } catch (error) { console.error("HYPRVIEW_FAILED " + error); Qt.exit(1); }
        }
    }
}''')
            runtime = root / 'runtime'
            runtime.mkdir(mode=0o700)
            env = dict(os.environ, XDG_RUNTIME_DIR=str(runtime), HYPRLAND_INSTANCE_SIGNATURE='',
                       QT_QPA_PLATFORMTHEME='', QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software')
            result = subprocess.run(['quickshell', '--log-rules', 'qml.debug=true', '-p', str(payload / 'Check.qml')],
                                    env=env, capture_output=True, text=True, timeout=15)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn('HYPRVIEW_OK', output, output)
            for error in ('ReferenceError', 'TypeError', 'Binding loop', 'Unable to assign', 'HYPRVIEW_FAILED'):
                self.assertNotIn(error, output, output)
