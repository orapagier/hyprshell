"""Workspace and rule validation uses temporary configs, never live windows."""
import copy
import json
import os
import subprocess
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'config/quickshell/settings'))
import behavior
from preferences import revision


class BehaviorTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(); self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        env = patch.dict(os.environ, XDG_CONFIG_HOME=str(self.root / 'config'), XDG_STATE_HOME=str(self.root / 'state'), HYPRLAND_INSTANCE_SIGNATURE='')
        env.start(); self.addCleanup(env.stop)
        main = behavior.paths()[2]; main.parent.mkdir(parents=True); main.write_text('-- personal Lua\n')

    def sample(self):
        return {'version': 1, 'general': {'layout': 'dwindle', 'resizeOnBorder': True, 'followMouse': 1},
                'workspaces': [{'id': 2, 'name': 'Café', 'layout': 'master', 'persistent': True}],
                'rules': [{'class': 'org.example.App', 'mode': 'float', 'workspace': 2, 'pin': True, 'noAnimations': True, 'width': 800, 'height': 600}]}

    def test_actual_parser_literal_class_and_saved_hook(self):
        data = self.sample()
        result = behavior.save(data, revision(behavior.paths()))
        self.assertTrue(result['ok'])
        self.assertEqual(behavior.saved(), data)
        source = behavior.paths()[1].read_text()
        self.assertIn('^org\\\\.example\\\\.App$', source)
        self.assertIn('Café', source)
        self.assertIn('-- personal Lua', behavior.paths()[2].read_text())
        behavior.save(data, revision(behavior.paths()))
        self.assertEqual(behavior.paths()[2].read_text().count('-- Hyprshell behavior rules'), 1)

    def test_invalid_rules_and_stale_revision_leave_files_unchanged(self):
        for changes in ({'pin': True, 'mode': 'tile'}, {'width': 100}, {'class': 'x\ny'}, {'workspace': True}, {'height': 0}):
            data = self.sample(); data['rules'][0].update(changes)
            with self.assertRaises(ValueError): behavior.save(data, revision(behavior.paths()))
        data = self.sample(); data['workspaces'] *= 2
        with self.assertRaises(ValueError): behavior.validate(data)
        with self.assertRaises(ValueError): behavior.save(self.sample(), 'stale')
        self.assertFalse(behavior.paths()[0].exists())

    def test_activation_failure_restores_all_preferences(self):
        with patch.object(behavior, 'reload_live', side_effect=ValueError('reload failed')):
            with self.assertRaises(ValueError): behavior.save(self.sample(), revision(behavior.paths()))
        self.assertFalse(behavior.paths()[0].exists()); self.assertFalse(behavior.paths()[1].exists())
        self.assertEqual(behavior.paths()[2].read_text(), '-- personal Lua\n')

    def test_floating_schema_is_optional_and_strict(self):
        data = self.sample()
        self.assertNotIn('floatingWorkspaces', behavior.render(data))
        for invalid in (1, 'true', None, [], {}):
            data['workspaces'][0]['floating'] = invalid
            with self.assertRaises(ValueError): behavior.validate(data)
        data['workspaces'][0]['floating'] = False
        self.assertNotIn('floatingWorkspaces', behavior.render(data))
        data['workspaces'][0]['floating'] = True
        behavior.save(data, revision(behavior.paths()))
        self.assertEqual(behavior.saved(), data)

    def test_floating_events_select_only_target_workspace_and_window(self):
        data = self.sample()
        data['workspaces'][0]['floating'] = True
        data['rules'][0].update(mode='tile', pin=False, width=0, height=0)
        source = behavior.render(data)
        self.assertGreater(source.index('hyprshell-workspace-float-2'), source.index('hyprshell-user-0'))
        # Execute generated Lua with actual event callbacks, checking dispatch
        # targets, idempotence and non-target/fullscreen/closed-window handling.
        harness = r'''local callbacks, actions, windows = {}, {}, {}
hl = {
    config = function() end, workspace_rule = function() end, window_rule = function() end,
    on = function(name, fn) callbacks[name] = fn end,
    get_windows = function() return windows end,
    dsp = { window = { float = function(args) return args end } },
    dispatch = function(args)
        assert(args.action == "set")
        table.insert(actions, args.window)
        args.window.floating = true
    end,
}
''' + source + r'''
local target = {mapped=true, workspace={id=2}, floating=false, fullscreen=2}
local other = {mapped=true, workspace={id=3}, floating=false, fullscreen=0}
local floating = {mapped=true, workspace={id=2}, floating=true, fullscreen=0}
local closed = {mapped=false, workspace={id=2}, floating=false, fullscreen=0}
windows = {target, other, floating, closed}
callbacks["config.reloaded"]()
assert(#actions == 0 and target.fullscreen == 2)
target.fullscreen = 0
callbacks["window.fullscreen"](target)
assert(#actions == 1 and actions[1] == target)
callbacks["window.open"](target)
callbacks["window.open"](nil)
assert(#actions == 1)
other.workspace.id = 2
callbacks["window.move_to_workspace"](other)
assert(#actions == 2 and actions[2] == other)
local opened = {mapped=true, workspace={id=2}, floating=false, fullscreen=0}
callbacks["window.open"](opened)
assert(#actions == 3 and actions[3] == opened)
opened.workspace.id = 3
callbacks["window.move_to_workspace"](opened)
assert(#actions == 3)
'''
        result = subprocess.run(['lua', '-'], input=harness, text=True, capture_output=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_inaccessible_discovery_keeps_editing_available(self):
        with patch.object(behavior.subprocess, 'run', side_effect=OSError()):
            result = behavior.status()
        self.assertTrue(result['ok']); self.assertEqual(result['classes'], [])
        self.assertIn('unavailable', result['discoveryMessage'])


if __name__ == '__main__': unittest.main()
