"""Retired shell preferences must not prevent upgrades or own the standalone app."""
import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('monitor_backend', ROOT / 'config/quickshell/settings/backend.py')
backend = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backend)

class MonitorPreferencesTests(unittest.TestCase):
    def test_old_preferences_are_retired_without_changing_panel_settings(self):
        data = {'version': 1, 'systemMonitor': {'enabled': False, 'workspaceOverrides': {'2': True}}, 'bar': {'clockFormat': 'hh:mm'}}
        result = backend.validate(data)
        self.assertNotIn('systemMonitor', result)
        self.assertEqual(result['bar']['clockFormat'], 'hh:mm')
        self.assertIn('systemMonitor', data)

if __name__ == '__main__':
    unittest.main()
