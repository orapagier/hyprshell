"""Exercise the production panel surface policy with native offscreen windows."""
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('quickshell'), 'Quickshell is required')
class PanelSurfaceTests(unittest.TestCase):
    def test_hidden_surface_stays_mapped_without_input_or_reserved_space(self):
        source = (ROOT / 'config/quickshell/shell.qml').read_text()
        # Use the actual window/reveal policy, with deterministic workspace and
        # screen fixtures. Desktop services and settings writes are not started.
        policy = source.split('            screen: modelData', 1)[1]
        policy = policy.split('            readonly property var workspace:', 1)[0]
        policy = 'screen: modelData' + policy
        policy = re.sub(r'readonly property bool shown: \{.*?\n            \}',
                        'readonly property bool shown: test.showPanel', policy, flags=re.S)
        fixture = r'''import QtQuick
import Quickshell
import "PAYLOAD/SettingsModel.js" as Settings
import "PAYLOAD"
ShellRoot {
    id: test
    property bool showPanel: true
    property int phase: 0
    property string edge: "top"
    property bool autoHide: phase >= 24
    QtObject {
        id: preferences
        property var config: ({bar: {position:test.edge, edgeAttached:test.autoHide, autoHide:test.autoHide}, accessibility:{}, hyprland:{}})
        property var panelConfig: config
    }
    QtObject { id: menuState; property string section: "" }
    QtObject { id: keybindings; property bool opened: false }
    // Offscreen has no layer-shell backend; retain the production policy
    // on a native floating surface and model its panel-only properties.
    FloatingWindow {
        property int exclusionMode
        property int exclusiveZone
        property var outerMargins: ({top:0, bottom:0, left:0, right:0})
        id: panel
        property var modelData: Quickshell.screens[0]
        function closeMenu() { menuState.section = ""; keybindings.opened = false; }
        POLICY
        implicitWidth: 160
        implicitHeight: 32
        color: "transparent"
        Rectangle { parent: panelReveal; anchors.fill: parent; color: "red" }
    }
    function check(condition, reason) {
        if (!condition) { console.error("PANEL_SURFACE_FAILED " + reason); Qt.exit(1); }
    }
    Timer {
        interval: 20; running: true; repeat: true
        onTriggered: {
            if (test.phase === 0 && !panel.backingWindowVisible) return;
            test.check(panel.visible && panel.backingWindowVisible, "surface unmapped");
            test.check(panelReveal.opacity === (test.showPanel ? 1 : 0), "paint state");
            test.check(panelReveal.enabled === test.showPanel, "control state");
            test.check(panel.mask.width === (test.showPanel ? panelReveal.inputRect.width : 0), "input width");
            test.check(panel.mask.height === (test.showPanel ? panelReveal.inputRect.height : 0), "input height");
            test.check(panel.exclusionMode === (test.showPanel ? ExclusionMode.Normal : ExclusionMode.Ignore), "reserved space");
            test.check(!panel.autoHide || panel.exclusiveZone === 0, "auto-hide reserved space");
            if (!test.showPanel) {
                test.check(menuState.section === "" && !keybindings.opened, "hidden menus remained open");
            }
            if (++test.phase === 48) { console.info("PANEL_SURFACE_OK"); Qt.quit(); return; }
            test.edge = ["top", "bottom", "left", "right"][Math.floor(test.phase / 6) % 4];
            if (test.showPanel) { menuState.section = "audio"; keybindings.opened = true; }
            test.showPanel = !test.showPanel;
        }
    }
    Timer { interval: 5000; running: true; onTriggered: Qt.exit(2) }
}
'''.replace('PAYLOAD', (ROOT / 'config/quickshell').as_uri()).replace('POLICY', policy)
        with tempfile.TemporaryDirectory(prefix='hyprshell-panel-surface-') as directory:
            root = Path(directory)
            runtime = root / 'runtime'
            runtime.mkdir(mode=0o700)
            entry = root / 'Surface.qml'
            entry.write_text(fixture)
            env = dict(os.environ, XDG_CONFIG_HOME=str(root / 'config'),
                       XDG_STATE_HOME=str(root / 'state'), XDG_RUNTIME_DIR=str(runtime),
                       HYPRLAND_INSTANCE_SIGNATURE='', QT_QPA_PLATFORMTHEME='',
                       QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software')
            result = subprocess.run(['quickshell', '-p', str(entry)], env=env,
                                    capture_output=True, text=True, timeout=10)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn('PANEL_SURFACE_OK', output)
            for error in ('PANEL_SURFACE_FAILED', 'ReferenceError', 'TypeError',
                          'Unable to assign', 'Binding loop'):
                self.assertNotIn(error, output)
