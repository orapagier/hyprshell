"""Workspace and rule validation uses temporary configs, never live windows."""
import copy
import json
import os
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

    def test_inaccessible_discovery_keeps_editing_available(self):
        with patch.object(behavior.subprocess, 'run', side_effect=OSError()):
            result = behavior.status()
        self.assertTrue(result['ok']); self.assertEqual(result['classes'], [])
        self.assertIn('unavailable', result['discoveryMessage'])


if __name__ == '__main__': unittest.main()
