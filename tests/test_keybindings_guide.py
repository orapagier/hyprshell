"""Audit configured Lua bindings without executing their actions."""
import json
import importlib.util
import os
import shlex
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('keybindings_guide', ROOT / 'config/quickshell/settings/keybindings_guide.py')
guide_reader = importlib.util.module_from_spec(spec)
spec.loader.exec_module(guide_reader)

# Evaluate registration and remapping only. Dispatcher calls create inert tokens;
# callbacks, application launches, power actions and compositor IPC never run.
AUDIT_LUA = r'''
local rows = {}
local function normalize(keys)
    return keys:upper():gsub('%s+', '')
end
local function dispatcher(path)
    return setmetatable({}, {
        __index = function(_, key) return dispatcher(path == '' and key or path .. '.' .. key) end,
        __call = function(_, arguments) return {dispatcher = path, arguments = arguments} end
    })
end
hl = {dsp = dispatcher('')}
hl.bind = function(keys, action, options)
    local row = {keys = keys, action = action, options = options or {}, enabled = true}
    row.set_enabled = function(self, enabled) self.enabled = enabled end
    table.insert(rows, row)
    return row
end
hl.unbind = function(keys)
    for _, row in ipairs(rows) do
        if normalize(row.keys) == normalize(keys) then row.enabled = false end
    end
end
local root = arg[1]
local bindings = dofile(root .. '/hypr/keybindings.lua')
bindings.capture()
dofile(root .. '/hyprshell/hyprland/shortcuts.lua')(dofile(root .. '/hyprshell/hyprland/programs.lua'))
bindings.apply()
for _, row in ipairs(rows) do
    if row.enabled then
        local options = row.options
        local action = type(row.action) == 'table' and row.action or {dispatcher = 'lua callback'}
        io.write(row.keys, '\t', options.description or '', '\t',
            tostring(options.release or false), '\t', tostring(options.repeating or false), '\t',
            tostring(options.mouse or false), '\t', tostring(options.locked or false), '\t',
            action.dispatcher, '\t', type(action.arguments) == 'string' and action.arguments or '', '\n')
    end
end
'''


def configured_bindings(config):
    env = dict(os.environ, XDG_CONFIG_HOME=str(config))
    result = subprocess.run(['lua', '-', str(config)], input=AUDIT_LUA, env=env,
                            text=True, capture_output=True, check=True, timeout=10)
    rows = []
    for line in result.stdout.splitlines():
        keys, description, release, repeat, mouse, locked, dispatcher, argument = line.split('\t')
        parts = [p.strip() for p in keys.split('+')]
        mask = sum({'SUPER': 64, 'CTRL': 4, 'ALT': 8, 'SHIFT': 1}[p] for p in parts[:-1])
        rows.append(dict(key=parts[-1], modmask=mask, description=description,
                         release=release == 'true', repeat=repeat == 'true',
                         mouse=mouse == 'true', locked=locked == 'true',
                         dispatcher=dispatcher, arg=argument))
    return rows


class KeybindingsGuideTests(unittest.TestCase):
    def test_workspace_placement_shortcuts_are_unique_and_call_saved_toggles(self):
        rows = configured_bindings(ROOT / 'config')
        for key, mode in (('F', 'floating'), ('S', 'pseudotiled')):
            matches = [row for row in rows if row['modmask'] == 68 and row['key'].upper() == key]
            self.assertEqual(len(matches), 1)
            self.assertEqual(matches[0]['dispatcher'], 'exec_cmd')
            self.assertIn('behavior.py" --toggle-workspace ' + mode, matches[0]['arg'])

    def test_hyprview_close_callback_invokes_helper(self):
        # Exercise only this callback with an inert exec function. Nothing is
        # launched, and no other desktop callback runs.
        script = AUDIT_LUA + r'''
hl.exec_cmd = function(command) io.write('HYPRVIEW_CLOSE_COMMAND\t', command, '\n') end
for _, row in ipairs(rows) do
    if row.enabled and row.keys == 'SUPER + SHIFT + V' then row.action() end
end
'''
        with tempfile.TemporaryDirectory(prefix='hyprview home ') as home:
            result = subprocess.run(['lua', '-', str(ROOT / 'config')], input=script,
                                    env=dict(os.environ, HOME=home, XDG_CONFIG_HOME=str(ROOT / 'config')),
                                    text=True, capture_output=True, check=True, timeout=10)
            commands = [line.split('\t', 1)[1] for line in result.stdout.splitlines()
                        if line.startswith('HYPRVIEW_CLOSE_COMMAND\t')]
            self.assertEqual(len(commands), 1)
            self.assertEqual(shlex.split(commands[0]),
                             [str(Path(home) / '.local/bin/hyprshell-shortcut'), 'hyprview-close'])

    def test_lua_display_names_preserve_every_runtime_registration(self):
        rows = configured_bindings(ROOT / 'config')
        names = [row['key'] for row in rows]
        for row in rows:
            row.update(key='', keycode=0, submap='', catch_all=False)
        text = ''.join('bindd\n' + ''.join('\t' + key + ': ' + str(value) + '\n' for key, value in [
            ('modmask', row['modmask']), ('submap', row['submap']), ('key', name),
            ('keycode', 0), ('catchall', 'false'), ('description', row['description']),
            ('dispatcher', row['dispatcher']), ('arg', row['arg'])]) + '\n'
            for row, name in zip(rows, names))
        with patch.object(guide_reader.subprocess, 'run') as run:
            run.side_effect = [subprocess.CompletedProcess([], 0, json.dumps(rows)),
                               subprocess.CompletedProcess([], 0, text)]
            entries = guide_reader.read_bindings()
        self.assertEqual([entry['key'] for entry in entries], names)
        self.assertEqual(len(entries), len(rows))
        for row, entry in zip(rows, entries):
            self.assertEqual({k: v for k, v in entry.items() if k != 'key'},
                             {k: v for k, v in row.items() if k != 'key'})
        with self.assertRaises(ValueError):
            guide_reader.named_bindings(rows, text.replace('keycode: 0', 'keycode: 1', 1))
        with self.assertRaises(ValueError):
            guide_reader.named_bindings(rows[:-1], text)

    def test_named_legacy_and_code_bindings_need_no_second_query(self):
        rows = [{'key': 'F1'}, {'key': '', 'keycode': 38}, {'key': '', 'catch_all': True}]
        with patch.object(guide_reader.subprocess, 'run') as run:
            run.return_value = subprocess.CompletedProcess([], 0, json.dumps(rows))
            self.assertEqual(guide_reader.read_bindings(), rows)
            self.assertEqual(run.call_count, 1)

    def test_projection_and_pseudotiling_invoke_the_correct_actions(self):
        rows = configured_bindings(ROOT / 'config')
        by_key = {(r['modmask'], r['key'].upper()): r for r in rows}
        projection = by_key[(64, 'P')]
        self.assertEqual(projection['dispatcher'], 'exec_cmd')
        self.assertEqual(projection['arg'], '"$HOME/.local/bin/hyprshell-shortcut" displays')
        self.assertEqual(by_key[(65, 'P')]['dispatcher'], 'window.pseudo')
        self.assertEqual(by_key[(8, 'S')]['arg'], '"$HOME/.local/bin/hyprshell-shortcut" settings')
        self.assertEqual(by_key[(64, 'V')]['arg'], '"$HOME/.local/bin/hyprshell-shortcut" hyprview')
        self.assertEqual(by_key[(65, 'V')]['dispatcher'], 'lua callback')
        self.assertEqual(by_key[(72, 'V')]['dispatcher'], 'window.float')

    def test_every_configured_binding_survives_guide_and_remaps_are_respected(self):
        rows = configured_bindings(ROOT / 'config')
        combinations = [(r['modmask'], r['key'].upper()) for r in rows]
        self.assertEqual(len(combinations), len(set(combinations)), 'Conflicting configured shortcuts')
        self.assertTrue(all(r['description'] for r in rows), 'Missing shortcut descriptions')
        by_key = dict(zip(combinations, rows))
        self.assertIn((64, 'P'), by_key)
        self.assertIn((65, 'P'), by_key)
        self.assertIn((64, 'K'), by_key)
        self.assertIn((64, 'Z'), by_key)
        self.assertNotIn((64, 'T'), by_key)
        self.assertIn((8, 'X'), by_key)
        self.assertNotIn((8, 'T'), by_key)
        for key in '0123456789':
            self.assertIn((64, key), by_key)
            self.assertIn((65, key), by_key)
        with tempfile.TemporaryDirectory() as directory:
            test = Path(directory) / 'tst_ConfiguredGuide.qml'
            guide = (ROOT / 'config/quickshell/KeybindingsGuide.js').as_uri()
            test.write_text('import QtQuick\nimport QtTest\nimport "' + guide + '" as Guide\n'
                'TestCase { name: "ConfiguredGuide"; function test_all_configured_bindings() {\n'
                'let rows = ' + json.dumps(rows) + '; let entries = Guide.desktopBindings(rows);\n'
                'compare(entries.reduce((count, entry) => count + entry.variants.length, 0), rows.length);\n'
                'for (let row of rows) verify(entries.some(e => e.keyLabels.includes(Guide.shortcut(row)) && e.action === row.description));\n'
                'compare(new Set(entries.map(e => e.context + "\\n" + e.action)).size, entries.length);\n'
                'compare(Guide.matching(entries, "").length, entries.length + Guide.localBindings.length);\n'
                '} }\n')
            env = dict(os.environ, QT_QPA_PLATFORMTHEME='', QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software')
            runner = subprocess.check_output([sys.executable, str(ROOT / 'tools/check_runtime.py'), '--qmltestrunner'], text=True).strip()
            result = subprocess.run([runner, '-input', str(test)], env=env,
                                    capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
