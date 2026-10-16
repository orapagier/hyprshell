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

    def test_dock_visibility_utilities_and_legacy_defaults(self):
        for mode in ('always', 'auto-hide', 'dodge'):
            self.data['panels']['hyprdock'].update(hideMode=mode, showTrash=True, showFiles=True, showSettings=True)
            self.assertEqual(backend.validate(self.data)['panels']['hyprdock']['hideMode'], mode)
        for key, invalid in [('alignment', 'middle'), ('fullscreenPolicy', 'always'), ('showTrash', 1), ('animations', 'yes'), ('indicators', None)]:
            data = copy.deepcopy(self.data)
            data['panels']['hyprdock'][key] = invalid
            with self.assertRaises(ValueError):
                backend.validate(data)
        for key in ('alignment', 'fullscreenPolicy', 'showTrash', 'showFiles', 'showSettings', 'animations', 'indicators'):
            del self.data['panels']['hyprdock'][key]
        dock = backend.validate(self.data)['panels']['hyprdock']
        self.assertEqual(dock['alignment'], 'center')
        self.assertFalse(dock['showTrash'])

    def test_shared_panel_capabilities_and_distinct_status_defaults(self):
        self.assertEqual(self.data['panels']['hyprdock']['rightItems'], [])
        self.assertIsNone(self.data['panels']['hyprbar']['rightItems'])
        for name in ('hyprdock', 'hyprbar'):
            self.data['panels'][name].update(grouped=False, windowWorkspaceScope='current',
                windowMonitorScope='all', rightItems=['audio'], showTrash=True,
                backgroundOpacity=0.5, fullscreenPolicy='show', indicators=False)
            self.assertEqual(backend.validate(self.data)['panels'][name], self.data['panels'][name])
            for key, value in [('rightItems', ['audio', 'audio']), ('grouped', 1),
                               ('showTrash', 1), ('windowMonitorScope', 'invalid')]:
                invalid = copy.deepcopy(self.data)
                invalid['panels'][name][key] = value
                with self.subTest(panel=name, key=key), self.assertRaises(ValueError):
                    backend.validate(invalid)

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

    def test_taskbar_preferences_and_legacy_inheritance(self):
        panel = self.data['panels']['hyprbar']
        for key in ('grouped', 'showTitles', 'buttonWidth', 'verticalWidth', 'windowWorkspaceScope', 'windowMonitorScope'):
            panel.pop(key)
        inherited = backend.validate(self.data)['panels']['hyprbar']
        self.assertTrue(inherited['grouped'])
        self.assertFalse(inherited['showTitles'])
        self.assertEqual(inherited['verticalWidth'], 220)
        panel.update(grouped=False, showTitles=False, buttonWidth=240, verticalWidth=300,
                     windowWorkspaceScope='current', windowMonitorScope='all')
        result = backend.validate(self.data)['panels']['hyprbar']
        for key, value in panel.items():
            self.assertEqual(result[key], value)
        for key, value in [('grouped', 1), ('showTitles', 'yes'), ('buttonWidth', 79),
                           ('verticalWidth', 401), ('windowWorkspaceScope', 'selected'),
                           ('windowMonitorScope', None)]:
            invalid = copy.deepcopy(self.data)
            invalid['panels']['hyprbar'][key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                backend.validate(invalid)

    def test_panel_inside_padding(self):
        for name in ('hyprbar', 'hyprdock'):
            panel = self.data['panels'][name]
            panel.pop('paddingStart')
            panel.pop('paddingEnd')
            inherited = backend.validate(self.data)['panels'][name]
            self.assertEqual(inherited['paddingStart'], 6)
            self.assertIsNone(inherited['paddingEnd'])
            panel.update(paddingStart=0, paddingEnd=100)
            result = backend.validate(self.data)['panels'][name]
            self.assertEqual(result['paddingStart'], 0)
            self.assertEqual(result['paddingEnd'], 100)
            for key in ('paddingStart', 'paddingEnd'):
                for value in (-1, 101, True, 1.5, '6'):
                    invalid = copy.deepcopy(self.data)
                    invalid['panels'][name][key] = value
                    with self.subTest(panel=name, key=key, value=value), self.assertRaises(ValueError):
                        backend.validate(invalid)

    def test_taskbar_independent_spacing(self):
        panel = self.data['panels']['hyprbar']
        panel.pop('spacingRight')
        panel['spacing'] = 10
        inherited = backend.validate(self.data)['panels']['hyprbar']
        self.assertEqual(inherited['spacing'], 10)
        self.assertIsNone(inherited['spacingRight'])
        for value in (0, 7, 30, None):
            panel['spacingRight'] = value
            result = backend.validate(self.data)['panels']['hyprbar']
            self.assertEqual(result['spacingRight'], value)
            self.assertEqual(result['spacing'], 10)
        for value in (-1, 31, True, '5', 2.5):
            panel['spacingRight'] = value
            with self.subTest(value=value), self.assertRaises(ValueError):
                backend.validate(self.data)

    def test_taskbar_right_item_selection(self):
        panel = self.data['panels']['hyprbar']
        self.assertIsNone(backend.validate(self.data)['panels']['hyprbar']['rightItems'])
        for selected in ([], ['audio', 'calendar', 'tray'], None):
            panel['rightItems'] = selected
            self.assertEqual(backend.validate(self.data)['panels']['hyprbar']['rightItems'], selected)
        for selected in (['audio', 'audio'], ['unknown'], 'audio', [1], {}):
            panel['rightItems'] = selected
            with self.subTest(selected=selected), self.assertRaises(ValueError):
                backend.validate(self.data)

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
