"""Hyprpane schema preserves appearance, monitor gates and workspace visibility."""
import copy
import importlib.util
import json
from pathlib import Path
import unittest
ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('panel_backend',ROOT/'config/quickshell/settings/backend.py')
backend=importlib.util.module_from_spec(spec)
spec.loader.exec_module(backend)
class PanelConfigurationTests(unittest.TestCase):
    def test_saved_preferences_round_trip(self):
        saved=json.loads((ROOT/'config/hyprshell/settings.json').read_text())
        self.assertEqual(backend.validate(saved),saved)
        self.assertEqual(set(saved['panels']),{'hyprpane'})
    def test_pane_monitor_and_enable_validation(self):
        for changes in ({'enabled':1},{'monitors':['eDP-1','eDP-1']},{'monitors':[None]},{'hideMode':'auto-hide'}):
            data=copy.deepcopy(backend.DEFAULTS);data['panels']['hyprpane'].update(changes)
            with self.subTest(changes=changes),self.assertRaises(ValueError):backend.validate(data)
    def test_legacy_settings_inherit_pane_without_changing_visibility(self):
        data=copy.deepcopy(backend.DEFAULTS);del data['panels']
        data['bar'].update(position='left',workspaceOverrides={'3':False})
        actual=backend.validate(data)
        self.assertEqual(actual['bar'],data['bar'])
        self.assertTrue(actual['panels']['hyprpane']['enabled'])
