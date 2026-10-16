"""Phase 1 compatibility and placement transactions; no real desktop writes."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('panel_backend', ROOT / 'config/quickshell/settings/backend.py')
backend = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backend)


class PanelConfigurationTests(unittest.TestCase):
    def setUp(self):
        self.data = copy.deepcopy(backend.DEFAULTS)

    def test_legacy_payload_preserves_every_existing_preference(self):
        for path in (ROOT / 'config/hyprshell/settings.json',):
            legacy = json.loads(path.read_text())
            result = backend.validate(legacy)
            for section in legacy:
                if isinstance(legacy[section], dict):
                    for key, value in legacy[section].items():
                        if section == 'panels':
                            for preference, saved in value.items():
                                self.assertEqual(result[section][key][preference], saved)
                        else:
                            self.assertEqual(result[section][key], value)
                else:
                    self.assertEqual(result[section], legacy[section])
            for name, default in [('hyprpane', True), ('hyprdock', False), ('hyprbar', False)]:
                self.assertEqual(result['panels'][name]['enabled'], legacy.get('panels', {}).get(name, {}).get('enabled', default))

    def test_dock_opacity_and_edge_distance(self):
        dock = self.data['panels']['hyprdock']
        del dock['backgroundOpacity']
        self.assertEqual(backend.validate(self.data)['panels']['hyprdock']['backgroundOpacity'], 230 / 255)
        for opacity, margin in [(0, 0), (0.5, 35), (1, 100)]:
            dock.update(backgroundOpacity=opacity, marginEdge=margin)
            self.assertEqual(backend.validate(self.data)['panels']['hyprdock'], dock)
        for key, invalid in [('backgroundOpacity', -0.1), ('backgroundOpacity', 1.1), ('backgroundOpacity', True), ('backgroundOpacity', '0.5'), ('marginEdge', 101)]:
            data = copy.deepcopy(self.data)
            data['panels']['hyprdock'][key] = invalid
            with self.subTest(key=key, invalid=invalid), self.assertRaises(ValueError):
                backend.validate(data)

    def test_all_pairs_and_edges(self):
        names = list(self.data['panels'])
        for first, second in [('hyprpane', 'hyprdock'), ('hyprpane', 'hyprbar'), ('hyprdock', 'hyprbar')]:
            for edge1 in ('top', 'bottom', 'left', 'right'):
                for edge2 in ('top', 'bottom', 'left', 'right'):
                    data = copy.deepcopy(self.data)
                    for name in names:
                        data['panels'][name]['enabled'] = name in (first, second)
                    for name, edge in [(first, edge1), (second, edge2)]:
                        (data['bar'] if name == 'hyprpane' else data['panels'][name])['position'] = edge
                    if edge1 == edge2:
                        with self.assertRaisesRegex(ValueError, 'Choose another edge'):
                            backend.validate(data)
                    else:
                        backend.validate(data)

    def test_three_components_and_workspace_override_conflicts(self):
        self.data['panels']['hyprdock']['enabled'] = True
        self.data['panels']['hyprbar'].update(enabled=True, position='right')
        with self.assertRaisesRegex(ValueError, 'at most two'):
            backend.validate(self.data)
        self.data['panels']['hyprbar'].update(visible=False, workspaceOverrides={'99': True})
        with self.assertRaisesRegex(ValueError, 'workspace 99'):
            backend.validate(self.data)
        self.data['panels']['hyprbar']['workspaceOverrides'] = {'99': False}
        backend.validate(self.data)

    def test_disjoint_monitors_and_workspaces_can_share_edge(self):
        pane, dock = self.data['panels']['hyprpane'], self.data['panels']['hyprdock']
        pane['monitors'] = ['eDP-1']
        dock.update(enabled=True, position='top', monitors=['HDMI-A-1'])
        backend.validate(self.data)
        dock['monitors'] = []
        with self.assertRaisesRegex(ValueError, 'eDP-1'):
            backend.validate(self.data)
        pane['monitors'] = []
        self.data['bar'].update(workspaceScope='selected', workspaceList=[1])
        dock.update(workspaceScope='selected', workspaceList=[2])
        backend.validate(self.data)
        dock['workspaceOverrides'] = {'1': True}
        with self.assertRaisesRegex(ValueError, 'workspace 1'):
            backend.validate(self.data)

    def test_pins_round_trip_and_do_not_discard_inactive_lists(self):
        self.data['pins'].update(shared=['org.gnome.Nautilus.desktop'], hyprdock=['kitty.desktop'], hyprbar=['missing.App.desktop'])
        for mode in ('shared', 'separate', 'shared'):
            self.data['pins']['mode'] = mode
            self.assertEqual(backend.validate(self.data)['pins'], self.data['pins'])
        for pins in (['Files'], ['kitty'], ['bad\napp.desktop'], ['/tmp/app.desktop'], ['app.desktop', 'app.desktop'], [True]):
            self.data['pins']['shared'] = pins
            with self.assertRaisesRegex(ValueError, 'desktop application IDs'):
                backend.validate(self.data)

    def test_reserved_schema_rejects_invalid_values(self):
        for name, changes in [('hyprpane', {'enabled': 1}), ('hyprpane', {'position': 'left'}), ('hyprpane', {'hideMode': 'auto-hide'}), ('hyprdock', {'monitors': ['eDP-1', 'eDP-1']}), ('hyprbar', {'monitors': [None]}), ('hyprbar', {'thickness': True}), ('hyprdock', {'workspaceOverrides': {'0': True}}), ('hyprbar', {'workspaceScope': 'selected'}), ('hyprbar', {'background': 'invalid'}), ('hyprdock', {'hideMode': 'invalid'})]:
            data = copy.deepcopy(self.data)
            data['panels'][name].update(changes)
            with self.subTest(name=name, changes=changes), self.assertRaises(ValueError):
                backend.validate(data)

    def test_shortcut_conflict_leaves_saved_settings_and_backups_unchanged(self):
        with tempfile.TemporaryDirectory() as directory, patch.dict(os.environ, XDG_CONFIG_HOME=directory + '/config', XDG_STATE_HOME=directory + '/state', HYPRLAND_INSTANCE_SIGNATURE=''):
            self.data['bar'].update(visible=False)
            self.data['panels']['hyprdock'].update(enabled=True, position='top')
            backend.save(self.data)
            target = Path(directory) / 'config/hyprshell/settings.json'
            before = target.read_bytes()
            files = set(Path(directory).rglob('*'))
            with self.assertRaisesRegex(ValueError, 'workspace 3'):
                backend.save(backend.DEFAULTS, toggle_workspace=3)
            self.assertEqual(target.read_bytes(), before)
            self.assertEqual(set(Path(directory).rglob('*')), files)
            # Independent reserved preferences survive an ordinary legacy edit.
            self.data['bar']['clockFormat'] = 'hh:mm'
            backend.save(self.data)
            self.assertEqual(json.loads(target.read_text())['panels'], self.data['panels'])


if __name__ == '__main__':
    unittest.main()
