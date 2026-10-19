"""Legacy preference compatibility for one-time standalone monitor migration."""
import importlib.util
import json
from unittest.mock import patch
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
QML = ROOT / 'config/quickshell'
backend_spec = importlib.util.spec_from_file_location('monitor_backend', QML / 'settings/backend.py')
backend = importlib.util.module_from_spec(backend_spec)
backend_spec.loader.exec_module(backend)


class MonitorPreferencesTests(unittest.TestCase):
    def test_toggle_and_layout_merge_latest_preferences(self):
        with tempfile.TemporaryDirectory() as directory:
            config = Path(directory) / 'config'
            state = Path(directory) / 'state'
            with patch.dict(os.environ, XDG_CONFIG_HOME=str(config), XDG_STATE_HOME=str(state), HYPRLAND_INSTANCE_SIGNATURE=''):
                initial = backend.validate({'version': 1})
                initial['bar']['clockFormat'] = 'hh:mm'
                backend.save(initial)
                layout = {'x': 0.35, 'y': 0.7, 'width': 420, 'height': 510}
                backend.save(backend.DEFAULTS, monitor_action=layout)
                backend.save(backend.DEFAULTS, monitor_action={'toggleWorkspace': 2})
                saved = json.loads((config / 'hyprshell/settings.json').read_text())
                self.assertEqual(saved['bar']['clockFormat'], 'hh:mm')
                self.assertEqual(saved['systemMonitor'], dict(layout, enabled=True, workspaceOverrides={"2": False}, transparency=0))
                backend.save(backend.DEFAULTS, monitor_action={'toggleWorkspace': 2})
                self.assertTrue(json.loads((config / 'hyprshell/settings.json').read_text())['systemMonitor']['workspaceOverrides']['2'])

    def test_old_preferences_inherit_and_invalid_geometry_is_rejected(self):
        self.assertTrue(backend.validate({'version': 1})['systemMonitor']['enabled'])
        for invalid in ({'x': -0.1}, {'y': 1.1}, {'width': 0}, {'height': True}, {'enabled': 1}, {'unknown': 3}, {'transparency': -1}, {'transparency': 101}, {'transparency': True}, {'transparency': 0.5}):
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                backend.validate({'version': 1, 'systemMonitor': invalid})


if __name__ == '__main__':
    unittest.main()
