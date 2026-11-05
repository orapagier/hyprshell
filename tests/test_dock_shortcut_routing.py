"""Exercise real shell IPC bodies with the inactive panel mode absent."""
import json
from pathlib import Path
import re
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('node'), 'Node is required to execute QML JavaScript')
class DockShortcutRoutingTests(unittest.TestCase):
    def test_shortcuts_and_readiness_in_both_panel_modes(self):
        source = (ROOT / 'config/quickshell/shell.qml').read_text()
        source = source.split('target: "bar"', 1)[1]
        bodies = {}
        for name in ('ready', 'toggleMenu', 'toggleKeybindings', 'toggleLauncher'):
            match = re.search(r'function ' + name + r'\([^)]*\): \w+ \{', source)
            start = match.end()
            depth = 1
            end = start
            while depth:
                depth += (source[end] == '{') - (source[end] == '}')
                end += 1
            bodies[name] = source[start:end - 1]
        script = r'''
const assert = require('node:assert/strict');
const bodies = BODIES;
const Hyprland = {focusedMonitor: {name: 'focused'}};
const calls = [];
const dock = {available: true, backingWindowVisible: true,
    open: (name, keyboard) => calls.push([name, keyboard])};
const shell = {dockEnabled: true, focusedDock: () => dock};
const docks = {instances: [dock]};
const panels = {instances: []};
const invoke = (name, arg) => new Function('shell', 'docks', 'panels', 'Hyprland', 'name', bodies[name])(
    shell, docks, panels, Hyprland, arg);
assert.equal(invoke('ready'), true);
dock.backingWindowVisible = false;
assert.equal(invoke('ready'), false);
dock.backingWindowVisible = true;
docks.instances = [];
assert.equal(invoke('ready'), false);
docks.instances = [dock];
for (const name of ['calendar', 'notifications', 'audio', 'wifi', 'bluetooth', 'battery', 'power', 'launcher']) {
    invoke('toggleMenu', name);
    assert.deepEqual(calls.pop(), [name, true]);
}
invoke('toggleKeybindings');
assert.deepEqual(calls.pop(), ['keybindings', true]);
invoke('toggleLauncher');
assert.deepEqual(calls.pop(), ['launcher', true]);
invoke('toggleMenu', 'invalid');
assert.equal(calls.length, 0);
shell.dockEnabled = false;
docks.instances = [];
assert.equal(invoke('ready'), false);
const panel = {screen: {name: 'focused'}, shown: true, backingWindowVisible: true,
    toggleMenu: name => calls.push(name), toggleKeybindings: () => calls.push('keybindings'),
    toggleLauncher: () => calls.push('launcher')};
panels.instances = [panel];
assert.equal(invoke('ready'), true);
panel.backingWindowVisible = false;
assert.equal(invoke('ready'), false);
invoke('toggleMenu', 'audio');
invoke('toggleKeybindings');
invoke('toggleLauncher');
assert.deepEqual(calls, ['audio', 'keybindings', 'launcher']);
'''.replace('BODIES', json.dumps(bodies))
        result = subprocess.run(['node', '-e', script], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
