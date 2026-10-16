"""Exercise the native viewer's selection, lifecycle and aspect fit offscreen."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('quickshell'), 'Native Quickshell is needed')
class HyprviewTests(unittest.TestCase):
    def test_viewer_lifecycle(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            payload = root / 'quickshell'
            payload.mkdir()
            for name in ('SettingsButton.qml', 'style'):
                source = ROOT / 'config/quickshell' / name
                if source.is_dir():
                    shutil.copytree(source, payload / name)
                else:
                    shutil.copy2(source, payload / name)
            source = (ROOT / 'config/quickshell/Hyprview.qml').read_text()
            # Keep the real UI and state machine; offscreen Qt has no capture
            # protocol. Substitute only the native stream for mock handles.
            source = source.replace('captureSource: view.visible && view.source && !view.streamStopped ? view.source.wayland : null',
                                    'captureSource: null')
            source = source.replace('live: view.visible && !!view.source && !view.streamStopped', 'live: false')
            (payload / 'Hyprview.qml').write_text(source)
            (payload / 'Check.qml').write_text('''import QtQuick
import Quickshell
ShellRoot {
    id: root
    property QtObject handle: QtObject { property bool fullscreen: false }
    property QtObject viewerHandle: QtObject { property bool fullscreen: false }
    property var first: ({address: "0x1", title: "First window", wayland: handle})
    property var second: ({address: "0x2", title: "Second window", wayland: handle})
    property var own: ({address: "0x3", title: "Hyprview", wayland: viewerHandle,
        lastIpcObject: {pid: Quickshell.processId, initialTitle: "Hyprview"}})
    Hyprview { id: view; windows: [root.first, root.second, root.own]; activeWindow: root.first }
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
                    root.check(!view.visible && view.choices.length === 2, "start hidden and exclude the viewer");
                    view.projectActive();
                    root.check(view.visible && view.source === root.first, "project active source before opening");
                    break;
                case 1:
                    let image = root.find(view.contentItem, "hyprviewProjection");
                    root.check(image.width <= image.parent.width && image.height <= image.parent.height
                        && Math.abs(image.width / image.height - 16/9) < 0.001, "aspect fit without cropping");
                    view.activeWindow = root.second;
                    root.check(view.source === root.first, "focus changes do not switch source");
                    view.projectActive();
                    root.check(view.source === root.second, "repeat shortcut replaces source");
                    view.selectWindow(root.first);
                    root.check(view.source === root.first, "picker changes source");
                    view.toggleFullscreen();
                    root.check(view.fullscreen && !root.handle.fullscreen, "fullscreen targets only viewer");
                    view.toggleFullscreen();
                    root.check(!view.fullscreen, "leave fullscreen");
                    view.streamStopped = true;
                    view.selectWindow(root.first);
                    root.check(!view.streamStopped, "reselecting source retries a stopped stream");
                    root.find(view.contentItem, "hyprviewPicker").popup.open();
                    break;
                case 2:
                    root.find(view.contentItem, "hyprviewPicker").popup.close();
                    view.windows = [root.second, root.own];
                    break;
                case 3:
                    root.check(!view.source && view.visible, "source closing keeps chooser available");
                    view.activeWindow = root.own;
                    view.projectActive();
                    root.check(!view.visible && !view.sourceAddress, "shortcut in viewer closes and releases source");
                    view.activeWindow = root.second;
                    view.projectActive();
                    root.check(view.visible && view.source === root.second, "reopen after close");
                    root.check(!view.selectWindow(root.own) && view.source === root.second, "reject recursive capture");
                    view.selectWindow({address: "0x4", title: "No handle"});
                    root.check(!!view.message && view.source === root.second, "unsupported source preserves selection");
                    view.dismiss();
                    view.activeWindow = null;
                    view.projectActive();
                    root.check(view.visible && !view.source && !!view.message, "no focused window opens chooser");
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
