"""Audit configured Lua bindings without executing their actions."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

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
    def test_projection_and_pseudotiling_invoke_the_correct_actions(self):
        rows = configured_bindings(ROOT / 'config')
        by_key = {(r['modmask'], r['key'].upper()): r for r in rows}
        projection = by_key[(64, 'P')]
        self.assertEqual(projection['dispatcher'], 'exec_cmd')
        self.assertEqual(projection['arg'], '"$HOME/.local/bin/hyprshell-shortcut" displays')
        self.assertEqual(by_key[(65, 'P')]['dispatcher'], 'window.pseudo')
        self.assertEqual(by_key[(8, 'S')]['arg'], '"$HOME/.local/bin/hyprshell-shortcut" settings')

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
                'compare(entries.length, rows.length);\n'
                'for (let row of rows) verify(entries.some(e => e.shortcut === Guide.shortcut(row) && e.action === row.description));\n'
                'compare(Guide.matching(entries, "").length, rows.length + Guide.localBindings.length);\n'
                '} }\n')
            env = dict(os.environ, QT_QPA_PLATFORMTHEME='', QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software')
            runner = subprocess.check_output([sys.executable, str(ROOT / 'tools/check_runtime.py'), '--qmltestrunner'], text=True).strip()
            result = subprocess.run([runner, '-input', str(test)], env=env,
                                    capture_output=True, text=True, timeout=15)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)


if __name__ == '__main__':
    unittest.main()
