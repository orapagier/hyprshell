"""Verify projection selection, aspect fit, display modes, and teardown."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('quickshell'), 'Native Quickshell is needed')
class PresentationViewTests(unittest.TestCase):
    def test_projection_lifecycle_and_aspect_fit(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            payload = root / 'quickshell'
            payload.mkdir()
            source = (ROOT / 'config/quickshell/PresentationView.qml').read_text()
            # Offscreen Qt has no compositor/capture backend. Keep the actual
            # selection and sizing logic, substituting only the native surface
            # and capture source. Real video/input still need a desktop check.
            source = source.replace('PanelWindow {', 'FloatingWindow {', 1)
            source = source.replace('    screen: output\n', '')
            source = source.replace('    anchors { top: true; bottom: true; left: true; right: true }',
                                    '    implicitWidth: 1440; implicitHeight: 900')
            source = '\n'.join(line for line in source.splitlines()
                               if 'exclusionMode:' not in line and 'WlrLayershell.' not in line)
            source = source.replace('captureSource: window.visible ? window.slideshow.wayland : null',
                                    'captureSource: null').replace('live: window.visible', 'live: false')
            (payload / 'PresentationView.qml').write_text(source)
            (payload / 'ProjectionCheck.qml').write_text('''import QtQuick
import Quickshell
ShellRoot {
    id: root
    property QtObject handle: QtObject {}
    property var laptop: ({name: "eDP-1"})
    property var hdmi: ({name: "HDMI-A-1"})
    property var extended: [{name: "HDMI-A-1", lastIpcObject: {mirrorOf: "none", disabled: false}}]
    property var source: ({address: "0x123abc", title: "Test.pptx — ONLYOFFICE", monitor: laptop,
        wayland: handle, lastIpcObject: {class: "ONLYOFFICE", pid: 42, fullscreen: 2, fullscreenClient: 2}})
    PresentationView { id: view; windows: [root.source]; displays: [root.laptop, root.hdmi]; monitors: root.extended }
    function check(value, message) { if (!value) throw new Error(message); }
    function projection(item) {
        if (item.objectName === "slideProjection") return item;
        for (let child of item.children || []) {
            let found = projection(child);
            if (found) return found;
        }
        return null;
    }
    Timer {
        property int stage: 0
        interval: 100; running: true; repeat: true
        onTriggered: {
            try {
                switch (stage++) {
                case 0:
                    root.check(view.visible && view.output === root.hdmi && view.laptop === root.laptop, "project from laptop onto HDMI");
                    let image = root.projection(view.contentItem);
                    root.check(image && Math.abs(image.width - 1440) < 1 && Math.abs(image.height - 810) < 1, "fit 16:9 image into 1440x900 without cropping");
                    view.windows = [root.source, {title: "ONLYOFFICE", lastIpcObject:
                        {class: "ONLYOFFICE", pid: 42, mapped: true, hidden: false, visible: false, acceptsInput: false, fullscreen: 0}}];
                    break;
                case 1:
                    root.check(!view.visible, "leave native Presenter View alone");
                    view.windows = [root.source];
                    view.monitors = [{name: "HDMI-A-1", lastIpcObject: {mirrorOf: "eDP-1"}}];
                    break;
                case 2:
                    root.check(!view.visible, "no extra projection in Duplicate mode");
                    view.monitors = root.extended;
                    break;
                case 3:
                    root.check(view.visible, "resume in Extend mode");
                    view.displays = [root.laptop];
                    break;
                case 4:
                    root.check(!view.visible, "stop on HDMI disconnect");
                    view.displays = [root.laptop, root.hdmi];
                    view.windows = [];
                    break;
                case 5:
                    root.check(!view.visible, "stop when slideshow ends");
                    view.windows = [root.source, {title: "ONLYOFFICE", lastIpcObject:
                        {class: "ONLYOFFICE", pid: 42, mapped: false, fullscreen: 0}}];
                    break;
                case 6:
                    root.check(view.visible, "unmapped home window is not a presenter");
                    view.windows = [root.source, {title: root.source.title, lastIpcObject:
                        {class: "ONLYOFFICE", pid: 42, mapped: true, fullscreen: 0}}];
                    break;
                case 7:
                    root.check(view.visible, "ordinary editor is not a presenter");
                    view.windows = [root.source, {title: "ONLYOFFICE", lastIpcObject:
                        {class: "ONLYOFFICE", pid: 42, mapped: true, fullscreen: 2, fullscreenClient: 0}}];
                    break;
                case 8:
                    root.check(!view.visible, "presenter filling laptop must not enable slide copier");
                    console.log("PRESENTATION_PROJECTION_OK");
                    Qt.quit();
                }
            } catch (error) { console.error("PROJECTION_FAILED " + error); Qt.exit(1); }
        }
    }
}''')
            runtime = root / 'runtime'
            runtime.mkdir(mode=0o700)
            env = dict(os.environ, XDG_RUNTIME_DIR=str(runtime), HYPRLAND_INSTANCE_SIGNATURE='',
                       QT_QPA_PLATFORMTHEME='', QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software')
            result = subprocess.run(['quickshell', '--log-rules', 'qml.debug=true', '-p',
                                     str(payload / 'ProjectionCheck.qml')], env=env,
                                    capture_output=True, text=True, timeout=15)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn('PRESENTATION_PROJECTION_OK', output, output)
            for error in ('ReferenceError', 'TypeError', 'Binding loop', 'Unable to assign', 'PROJECTION_FAILED'):
                self.assertNotIn(error, output, output)
