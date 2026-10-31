"""Exercise clock boundaries, shortcut snapshots and hidden media with native Qt."""
import os
import json
import shutil
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class ResourceSchedulingTests(unittest.TestCase):
    def test_production_shell_compiles_without_starting_desktop_services(self):
        with tempfile.TemporaryDirectory(prefix='hyprshell-shell-compile-') as directory:
            root = Path(directory)
            runtime = root / 'runtime'
            runtime.mkdir(mode=0o700)
            payload = root / 'payload'
            shutil.copytree(ROOT / 'config/quickshell', payload,
                            ignore=shutil.ignore_patterns('__pycache__'))
            # Offscreen Qt cannot load the layer-shell PanelWindow backend.
            # Compile all production bindings against a surface-only stand-in;
            # do not instantiate the shell or start its processes.
            for source in payload.glob('*.qml'):
                source.write_text(source.read_text().replace('PanelWindow {', 'HeadlessPanel {'))
            (payload / 'HeadlessPanel.qml').write_text('''import QtQuick
import Quickshell
FloatingWindow {
    property int exclusiveZone: 0
    property int exclusionMode: 0
    property HeadlessAnchors anchors: HeadlessAnchors {}
    property HeadlessMargins margins: HeadlessMargins {}
}
''')
            for name, kind in [('HeadlessAnchors', 'bool'), ('HeadlessMargins', 'real')]:
                (payload / (name + '.qml')).write_text('import QtQuick\nQtObject {\n' +
                    '\n'.join(f'property {kind} {edge}' for edge in ['top', 'bottom', 'left', 'right']) + '\n}\n')
            entry = root / 'Check.qml'
            production = (payload / 'shell.qml').as_uri()
            entry.write_text('''import QtQuick
import Quickshell
ShellRoot {
    Timer { interval: 100; running: true; onTriggered: {
        let component = Qt.createComponent(PRODUCTION);
        if (component.status !== Component.Ready) {
            console.error(component.errorString()); Qt.exit(1); return;
        }
        console.info("SHELL_COMPILES_OK"); Qt.quit();
    }}
}
'''.replace('PRODUCTION', json.dumps(production)))
            env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software',
                       QT_QPA_PLATFORMTHEME='', XDG_RUNTIME_DIR=str(runtime),
                       XDG_CONFIG_HOME=str(root / 'config'), XDG_STATE_HOME=str(root / 'state'))
            result = subprocess.run(['quickshell', '-p', str(entry)], env=env,
                                    capture_output=True, text=True, timeout=10)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn('SHELL_COMPILES_OK', output)

    def test_shortcut_processes_preserve_names_and_skip_unchanged_lists(self):
        with tempfile.TemporaryDirectory(prefix='hyprshell-shortcut-processes-') as directory:
            root = Path(directory)
            runtime = root / 'runtime'
            runtime.mkdir(mode=0o700)
            (root / 'shell').symlink_to(ROOT / 'config/quickshell', target_is_directory=True)
            row = dict(modmask=64, submap='', key='', keycode=0, catch_all=False,
                       description='Open', dispatcher='exec', arg='kitty')
            (root / 'registry.json').write_text(json.dumps([row]))
            (root / 'registry.txt').write_text('bind\n\tmodmask: 64\n\tsubmap: \n\tkey: K\n'
                                             '\tkeycode: 0\n\tcatchall: false\n'
                                             '\tdescription: Open\n\tdispatcher: exec\n')
            command = root / 'hyprctl'
            command.write_text('#!/bin/sh\nif [ "$1" = "-j" ]; then\n'
                               'cat "$RESOURCE_TEST_ROOT/registry.json"\nelse\n'
                               'cat "$RESOURCE_TEST_ROOT/registry.txt"\nfi\n')
            command.chmod(0o700)
            entry = root / 'Check.qml'
            entry.write_text('''import QtQuick
import Quickshell
import "shell"
ShellRoot {
    id: test
    property int changes: 0
    property int initialChanges: 0
    KeybindingsMenu { id: menu; onBindingsChanged: test.changes++ }
    Timer { interval: 500; running: true; onTriggered: {
        if (menu.error || !menu.bindings.some(row => row.shortcut === "Super + K")) {
            console.error("Shortcut names missing", menu.error, JSON.stringify(menu.bindings)); Qt.exit(1);
        }
        test.initialChanges = test.changes;
    }}
    Timer { interval: 2100; running: true; onTriggered: {
        if (menu.error || test.changes !== test.initialChanges) {
            console.error("Unchanged shortcut list rebuilt", menu.error, test.changes); Qt.exit(1); return;
        }
        console.info("SHORTCUT_PROCESSES_OK"); Qt.quit();
    }}
}
''')
            env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software',
                       QT_QPA_PLATFORMTHEME='', XDG_RUNTIME_DIR=str(runtime),
                       XDG_CONFIG_HOME=str(root / 'config'), XDG_STATE_HOME=str(root / 'state'),
                       RESOURCE_TEST_ROOT=str(root), PATH=str(root) + os.pathsep + os.environ['PATH'])
            result = subprocess.run(['quickshell', '-p', str(entry)], env=env,
                                    capture_output=True, text=True, timeout=10)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn('SHORTCUT_PROCESSES_OK', output)

    def test_clock_shortcut_snapshots_and_hidden_media(self):
        with tempfile.TemporaryDirectory(prefix='hyprshell-resource-scheduling-') as directory:
            root = Path(directory)
            runtime = root / 'runtime'
            runtime.mkdir(mode=0o700)
            (root / 'shell').symlink_to(ROOT / 'config/quickshell', target_is_directory=True)
            entry = root / 'Check.qml'
            entry.write_text('''pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import "shell"
import "shell/ClockSchedule.js" as Clock
import "shell/KeybindingsGuide.js" as Guide
ShellRoot {
    id: test
    function check(ok, message) { if (!ok) throw new Error(message); }
    SettingsStore { id: store }
    MediaState { id: media; playing: true; title: "Test"; levels: Array(12).fill(0.8) }
    FloatingWindow {
        visible: true; implicitWidth: 800; implicitHeight: 100
        Bar {
            id: bar
            anchors.fill: parent
            settings: store.panelConfig
            mediaData: media
        }
    }
    function find(item, name) {
        if (item.objectName === name) return item;
        for (let child of item.children || []) { let found = find(child, name); if (found) return found; }
        return null;
    }
    property int phase: 0
    property real initialWidth: 0
    Timer {
        interval: 250; running: true; repeat: true
        onTriggered: {
            try {
                if (test.phase === 0) {
                    test.check(Clock.delay("hh:mm", 60000) === 60000, "minute boundary");
                    test.check(Clock.delay("hh:mm", 119999) === 1, "next minute");
                    test.check(Clock.delay("hh:mm:ss", 61234) === 766, "seconds aligned");
                    test.check(Clock.delay("hh:mm:z", 61234) === 766, "milliseconds retain second cadence");
                    test.check(Clock.delay("'it''s seconds' hh:mm", 61234) === 58766, "quoted literals");
                    let row = {modmask:64, submap:"", key:"", keycode:0, catch_all:false, description:"Open", dispatcher:"exec"};
                    let text = "bind\\n\\tmodmask: 64\\n\\tsubmap: \\n\\tkey: K\\n\\tkeycode: 0\\n\\tcatchall: false\\n\\tdescription: Open\\n\\tdispatcher: exec\\n";
                    test.check(Guide.namedBindings([row, row], text + text).every(r => r.key === "K"), "duplicate symbolic names");
                    test.check(row.key === "", "snapshot input preserved");
                    test.check(Guide.namedBindings([row], text.replace("key: K", "key: J"))[0].key === "J", "symbol-only runtime edits");
                    let rejected = false;
                    try { Guide.namedBindings([row], text.replace("description: Open", "description: Changed")); }
                    catch (e) { rejected = true; }
                    test.check(rejected, "mismatched snapshots rejected");
                    let slot = test.find(bar, "mediaSlot");
                    test.check(slot && slot.item, "media geometry ready");
                    test.initialWidth = slot.width;
                    bar.animateMedia = false;
                } else if (test.phase === 1) {
                    let slot = test.find(bar, "mediaSlot");
                    let spectrum = test.find(bar, "mediaSpectrum");
                    test.check(slot.item && slot.width === test.initialWidth, "hidden media preserves layout");
                    test.check(!spectrum.active && slot.item.levels.length === 0, "hidden media stops animation and level binding");
                    media.levels = Array(12).fill(0.3);
                    test.check(slot.item.levels.length === 0, "hidden spectrum ignores updates");
                    bar.animateMedia = true;
                } else {
                    let slot = test.find(bar, "mediaSlot");
                    test.check(test.find(bar, "mediaSpectrum").active && slot.item.levels[0] === 0.3, "latest spectrum resumes immediately");
                    console.info("RESOURCE_SCHEDULING_OK"); Qt.quit();
                }
                test.phase++;
            } catch (error) { console.error(error); Qt.exit(1); }
        }
    }
}
''')
            env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software',
                       QT_QPA_PLATFORMTHEME='', XDG_RUNTIME_DIR=str(runtime),
                       XDG_CONFIG_HOME=str(root / 'config'), XDG_STATE_HOME=str(root / 'state'))
            result = subprocess.run(['quickshell', '-p', str(entry)], env=env,
                                    capture_output=True, text=True, timeout=10)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn('RESOURCE_SCHEDULING_OK', output)
            for error in ('ReferenceError', 'TypeError', 'Binding loop', 'Unable to assign'):
                self.assertNotIn(error, output)
