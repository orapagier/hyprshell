"""Workspace visibility transactions use isolated preferences and no desktop IPC."""
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('hyprmonitor_backend', ROOT / 'config/quickshell/settings/backend.py')
backend = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backend)


class WorkspaceTests(unittest.TestCase):
    def test_workspace_toggles_preserve_latest_layout_and_other_workspaces(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            with patch.dict(os.environ, XDG_CONFIG_HOME=str(path / 'config'), XDG_STATE_HOME=str(path / 'state'), HYPRLAND_INSTANCE_SIGNATURE=''):
                config = backend.validate({'version': 1})
                config['systemMonitor'].update(enabled=False, workspaceOverrides={'1': True, '3': False})
                backend.save(config)
                backend.save(backend.DEFAULTS, monitor_action={'x': 0.2, 'transparency': 47})
                for workspace in (2, 1, 2, 99):
                    backend.save(backend.DEFAULTS, monitor_action={'toggleWorkspace': workspace})
                saved = json.loads((path / 'config/hyprshell/settings.json').read_text())
                expected = config['systemMonitor']
                expected.update(x=0.2, transparency=47, workspaceOverrides={'1': False, '2': False, '3': False, '99': True})
                self.assertEqual(saved['systemMonitor'], expected)
                previous = (path / 'config/hyprshell/settings.json').read_bytes()
                for action in ('toggle', {'toggleWorkspace': 0}, {'toggleWorkspace': 100}, {'toggleWorkspace': True}, {'toggleWorkspace': '2'}, {'toggleWorkspace': 2, 'enabled': True}):
                    with self.subTest(action=action), self.assertRaises(ValueError):
                        backend.save(backend.DEFAULTS, monitor_action=action)
                    self.assertEqual((path / 'config/hyprshell/settings.json').read_bytes(), previous)

    def test_override_validation_and_old_preferences(self):
        self.assertEqual(backend.validate({'version': 1})['systemMonitor']['workspaceOverrides'], {})
        for invalid in (None, [], {'0': True}, {'01': True}, {'100': False}, {'2': 1}, {'-1': False}):
            with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                backend.validate({'version': 1, 'systemMonitor': {'workspaceOverrides': invalid}})


if __name__ == '__main__':
    unittest.main()
