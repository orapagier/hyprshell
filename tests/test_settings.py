"""Settings transactions in isolated XDG directories; never change a desktop."""
import copy
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('settings_backend', ROOT / 'config/quickshell/settings/backend.py')
backend = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backend)


class SettingsTests(unittest.TestCase):
    def test_independent_window_edges_render_css_gaps_and_inherit_uniform_value(self):
        data = copy.deepcopy(self.data)
        data['hyprland'] = {'gapsOut': 17, 'gapsOutTop': 0, 'gapsOutBottom': 31}
        data['bar']['paddingBottom'] = 19
        validated = backend.validate(data)
        lua = backend.render_hypr(validated['hyprland'], True)
        for text in ('top = 0', 'right = 17', 'bottom = 31', 'left = 17'):
            self.assertIn(text, lua)
        self.assertNotIn('gapsOutTop', lua)
        self.assertIn('general:gaps_out = 0,17,31,17', backend.render_hypr(validated['hyprland'], False))
        data['hyprland'] = {'gapsOutLeft': 9}
        self.assertIn('top = 10', backend.render_hypr(data['hyprland'], True))
        for key in ('gapsOutTop', 'gapsOutRight', 'gapsOutBottom', 'gapsOutLeft'):
            for value in (-1, 101, True, 1.5):
                data['hyprland'] = {key: value}
                with self.assertRaises(ValueError): backend.validate(data)
        data['hyprland'] = {}
        for value in (-1, 101, True, 1.5):
            data['bar']['paddingBottom'] = value
            with self.assertRaises(ValueError): backend.validate(data)

    def test_accessibility_migrates_old_settings_and_reduced_motion_restores_animation_choice(self):
        self.assertEqual(backend.validate({'version': 1})['accessibility'], {'textScale': 1, 'highContrast': False, 'reducedMotion': False})
        main = self.config / 'hypr/hyprland.lua'; main.parent.mkdir(parents=True); main.write_text('-- isolated\n')
        data = copy.deepcopy(self.data)
        data['hyprland']['animations'] = True
        data['accessibility'] = {'textScale': 1.5, 'highContrast': True, 'reducedMotion': True}
        backend.save(data)
        generated = self.config / 'hyprshell/overrides.lua'
        self.assertIn('enabled = false', generated.read_text())
        data['accessibility']['reducedMotion'] = False
        backend.save(data)
        self.assertIn('enabled = true', generated.read_text())
        self.assertEqual(json.loads(self.path.read_text())['accessibility']['textScale'], 1.5)

    def test_accessibility_rejects_invalid_values_before_writing(self):
        for changes in ({'textScale': 0.8}, {'textScale': True}, {'textScale': 2}, {'highContrast': 1}, {'reducedMotion': 'false'}, {'unknown': True}):
            data = copy.deepcopy(self.data); data['accessibility'].update(changes)
            with self.assertRaises(ValueError): backend.save(data)
            self.assertFalse(self.path.exists())
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='hyprshell-settings-')
        self.addCleanup(self.temp.cleanup)
        self.config = Path(self.temp.name) / 'config with spaces'
        self.state = Path(self.temp.name) / 'state'
        self.env = patch.dict(os.environ, XDG_CONFIG_HOME=str(self.config), XDG_STATE_HOME=str(self.state), HYPRLAND_INSTANCE_SIGNATURE='')
        self.env.start()
        self.addCleanup(self.env.stop)
        self.data = copy.deepcopy(backend.DEFAULTS)
        self.path = self.config / 'hyprshell/settings.json'

    def test_bar_position_inherits_top_and_round_trips_all_edges(self):
        legacy = copy.deepcopy(self.data)
        del legacy['bar']['position']
        self.assertEqual(backend.validate(legacy)['bar']['position'], 'top')
        for position in ('top', 'left', 'right', 'bottom'):
            self.data['bar']['position'] = position
            self.assertTrue(backend.save(self.data)['ok'])
            self.assertEqual(json.loads(self.path.read_text())['bar']['position'], position)

    def test_bar_position_rejects_invalid_values_before_writing(self):
        for position in ('center', 'TOP', '', None, True, 1, [], {}):
            with self.subTest(position=position):
                self.data['bar']['position'] = position
                with self.assertRaisesRegex(ValueError, 'Bar position'):
                    backend.save(self.data)
                self.assertFalse(self.path.exists())

    def test_notification_preferences_round_trip_backup_and_conflict(self):
        self.assertTrue(backend.save(self.data)['ok'])
        original = self.path.read_text()
        expected = copy.deepcopy(self.data)
        self.data['notifications'].update(popups=True, doNotDisturb=True, popupSeconds=8,
                                          apps={'org.test.App': 'inbox', 'Other': 'off'})
        result = backend.save(self.data, expected)
        self.assertTrue(result['ok'])
        self.assertEqual(json.loads(self.path.read_text())['notifications'], self.data['notifications'])
        backup = Path(result['backup'])
        manifest = json.loads((backup / 'manifest.json').read_text())
        entry = next(i for i in manifest if i['path'] == str(self.path))
        self.assertEqual((backup / entry['file']).read_text(), original)
        with self.assertRaisesRegex(ValueError, 'changed outside'):
            backend.save(expected, expected)
        self.assertEqual(json.loads(self.path.read_text())['notifications'], self.data['notifications'])

    def test_input_preferences_round_trip_and_real_lua_parser(self):
        main = self.config / 'hypr/hyprland.lua'
        main.parent.mkdir(parents=True)
        main.write_text('-- test config\n')
        self.data['hyprland'] = {
            'pointerSpeed': -0.35, 'mouseNaturalScroll': True,
            'touchpadNaturalScroll': False, 'tapToClick': True,
            'disableWhileTyping': True, 'repeatRate': 40, 'repeatDelay': 350,
            'keyboardLayouts': 'us,gb', 'layoutSwitch': 'grp:alt_shift_toggle',
            'rounding': 8,
        }
        self.assertTrue(backend.save(self.data)['ok'])
        self.assertEqual(json.loads(self.path.read_text())['hyprland'], self.data['hyprland'])
        generated = self.config / 'hyprshell/overrides.lua'
        self.assertIn('tap_to_click = true', generated.read_text())
        main.write_text(generated.read_text())
        result = subprocess.run(['Hyprland', '--verify-config', '--config', str(main)],
                                capture_output=True, text=True, timeout=15)
        self.assertIn('config ok', result.stdout.lower(), result.stdout + result.stderr)
        conf = backend.render_hypr(self.data['hyprland'], False)
        self.assertIn('input:kb_layout = us,gb', conf)
        self.assertIn('input:touchpad:tap_to_click = true', conf)
        self.data['hyprland'] = {'rounding': 8}
        self.assertTrue(backend.save(self.data)['ok'])
        self.assertNotIn('input', generated.read_text())

    def test_input_rejects_invalid_values_before_writing(self):
        for key, values in {
            'pointerSpeed': [-1.01, 1.01, True, float('nan')],
            'repeatRate': [0, 101, 3.5, False],
            'repeatDelay': [99, 2001, 200.5],
            'tapToClick': [1, 'true', None],
            'keyboardLayouts': ['us;os.execute("bad")', 'US', '../us', 'us\nus', 'not_a_layout', 'us,gb,de,fr,es', []],
            'layoutSwitch': ['grp:madeup', 'grp:caps_toggle\nexec = bad', False],
        }.items():
            for value in values:
                with self.subTest(key=key, value=value):
                    data = copy.deepcopy(self.data)
                    data['hyprland'][key] = value
                    with self.assertRaises(ValueError):
                        backend.save(data)
                    self.assertFalse(self.path.exists())

    def test_apply_preserves_hyprland_and_backup_can_restore_previous_settings(self):
        result = backend.save(self.data)
        self.assertTrue(result['ok'])
        self.assertFalse((self.config / 'hypr').exists())
        original = self.path.read_text()
        self.data['items'][0]['enabled'] = False
        result = backend.save(self.data, backend.DEFAULTS)
        backup = Path(result['backup'])
        manifest = json.loads((backup / 'manifest.json').read_text())
        entry = next(i for i in manifest if i['path'] == str(self.path))
        self.assertEqual((backup / entry['file']).read_text(), original)
        self.assertFalse(json.loads(self.path.read_text())['items'][0]['enabled'])

    def test_bar_visibility_defaults_validation_and_round_trip(self):
        legacy = copy.deepcopy(self.data)
        del legacy['bar']['visible']
        self.assertTrue(backend.validate(legacy)['bar']['visible'])
        for visible in (False, True):
            self.data['bar']['visible'] = visible
            self.assertTrue(backend.save(self.data)['ok'])
            self.assertIs(json.loads(self.path.read_text())['bar']['visible'], visible)
        for invalid in (0, 1, 'false', None):
            self.data['bar']['visible'] = invalid
            with self.assertRaises(ValueError):
                backend.validate(self.data)

    def test_workspace_scope_defaults_validation_and_round_trip(self):
        legacy = copy.deepcopy(self.data)
        del legacy['bar']['workspaceScope']
        del legacy['bar']['workspaceList']
        result = backend.validate(legacy)
        self.assertEqual(result['bar']['workspaceScope'], 'all')
        self.assertEqual(result['bar']['workspaceList'], [])
        self.data['bar']['workspaceScope'] = 'selected'
        self.data['bar']['workspaceList'] = [1, 3, 5]
        self.assertTrue(backend.save(self.data)['ok'])
        saved = json.loads(self.path.read_text())
        self.assertEqual(saved['bar']['workspaceScope'], 'selected')
        self.assertEqual(saved['bar']['workspaceList'], [1, 3, 5])
        invalid_cases = [
            {'workspaceScope': 'some', 'workspaceList': []},
            {'workspaceScope': 'selected', 'workspaceList': []},
            {'workspaceScope': 'all', 'workspaceList': [0]},
            {'workspaceScope': 'all', 'workspaceList': [100]},
            {'workspaceScope': 'all', 'workspaceList': [1, 1]},
            {'workspaceScope': 'all', 'workspaceList': ['1']},
            {'workspaceScope': 'all', 'workspaceList': 1},
            {'workspaceScope': True, 'workspaceList': []},
        ]
        for case in invalid_cases:
            self.data['bar'].update(case)
            with self.assertRaises(ValueError, msg=case):
                backend.validate(self.data)
        self.data['bar']['workspaceScope'] = 'all'
        self.data['bar']['workspaceList'] = []
        self.assertTrue(backend.save(self.data)['ok'])
        self.assertEqual(json.loads(self.path.read_text())['bar']['workspaceScope'], 'all')

    def test_shortcut_toggle_preserves_saved_settings(self):
        self.data['bar']['spacing'] = 17
        self.data['bar'].update(workspaceScope='selected', workspaceList=[1])
        self.data['items'][0]['textColor'] = '#abcdef'
        backend.save(self.data)
        for visible in (True, False):
            self.assertTrue(backend.save(backend.DEFAULTS, toggle_workspace=3)['ok'])
            saved = json.loads(self.path.read_text())
            self.assertIs(backend.bar_visible(saved['bar'], 3), visible)
            self.assertTrue(backend.bar_visible(saved['bar'], 1))
            self.assertFalse(backend.bar_visible(saved['bar'], 2))
            self.assertEqual(saved['bar']['spacing'], 17)
            self.assertEqual(saved['items'][0]['textColor'], '#abcdef')
            self.assertEqual(saved['bar']['workspaceList'], [1])

    def test_workspace_toggle_from_all_visible_and_all_hidden(self):
        for baseline in (True, False):
            self.data['bar'].update(visible=baseline, workspaceOverrides={})
            backend.save(self.data)
            for visible in (not baseline, baseline):
                result = subprocess.run(['python3', str(ROOT / 'config/quickshell/settings/backend.py'),
                                         '--toggle-bar', '3'], capture_output=True, text=True, timeout=10)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                bar = json.loads(self.path.read_text())['bar']
                self.assertIs(backend.bar_visible(bar, 3), visible)
                self.assertIs(backend.bar_visible(bar, 1), baseline)
                self.assertIs(bar['visible'], baseline)

    def test_workspace_overrides_validation_and_legacy_inheritance(self):
        legacy = copy.deepcopy(self.data)
        del legacy['bar']['workspaceOverrides']
        self.assertEqual(backend.validate(legacy)['bar']['workspaceOverrides'], {})
        for invalid in ([], {'0': True}, {'100': False}, {'01': True}, {'1': 1}, {'1': 'true'}, {1: True}):
            with self.subTest(overrides=invalid), self.assertRaises(ValueError):
                data = copy.deepcopy(self.data)
                data['bar']['workspaceOverrides'] = invalid
                backend.save(data)
        for invalid in (0, 100, True, '3'):
            with self.subTest(workspace=invalid), self.assertRaises(ValueError):
                backend.save(self.data, toggle_workspace=invalid)
        self.assertFalse(self.path.exists())

    def test_random_vibrant_colors_validation_and_round_trip(self):
        legacy = copy.deepcopy(self.data)
        del legacy['bar']['randomVibrantColors']
        self.assertFalse(backend.validate(legacy)['bar']['randomVibrantColors'])
        self.data['bar']['randomVibrantColors'] = True
        self.assertTrue(backend.save(self.data)['ok'])
        self.assertTrue(json.loads(self.path.read_text())['bar']['randomVibrantColors'])
        for invalid in (1, 'true', None):
            self.data['bar']['randomVibrantColors'] = invalid
            with self.assertRaises(ValueError):
                backend.validate(self.data)

    def test_popdown_translucency_defaults_and_validation(self):
        legacy = copy.deepcopy(self.data)
        del legacy['bar']['popdownTranslucency']
        for item in legacy['items']:
            del item['popdownTranslucency']
        result = backend.validate(legacy)
        self.assertEqual(result['bar']['popdownTranslucency'], 0.06)
        self.assertEqual(result['items'][0]['popdownTranslucency'], -1)
        for section in (self.data['bar'], self.data['items'][0]):
            for valid in (0, 0.2, 1):
                section['popdownTranslucency'] = valid
                backend.validate(self.data)
            for invalid in (-0.1, 1.1, True, '0.5'):
                section['popdownTranslucency'] = invalid
                with self.assertRaises(ValueError):
                    backend.validate(self.data)
            section['popdownTranslucency'] = 0.06

    def test_invalid_and_unknown_values_write_nothing(self):
        variants = []
        for key, value in [('opacity', 2), ('backgroundOpacity', -0.5), ('textColor', 'red'), ('side', 'bottom'), ('order', True)]:
            data = copy.deepcopy(self.data)
            data['items'][0][key] = value
            variants.append(data)
        data = copy.deepcopy(self.data)
        data['hyprland']['rounding'] = '__import__("os")'
        variants.append(data)
        data = copy.deepcopy(self.data)
        data['items'].append(data['items'][0])
        variants.append(data)
        for data in variants:
            with self.assertRaises(ValueError):
                backend.save(data)
        self.assertFalse(self.path.exists())

    def test_spacing_and_backgrounds_round_trip_with_legacy_defaults(self):
        legacy = copy.deepcopy(self.data)
        del legacy['bar']['background']
        for item in legacy['items']:
            del item['spacingLeft']
            del item['spacingRight']
        self.assertEqual(backend.validate(legacy), self.data)
        self.data['bar']['background'] = 'off'
        wifi = next(i for i in self.data['items'] if i['id'] == 'wifi')
        wifi.update(spacingLeft=-7, spacingRight=-200, background='on')
        backend.save(self.data)
        self.assertEqual(json.loads(self.path.read_text()), self.data)

    def test_shared_pills_round_trip_and_validate(self):
        self.data['bar']['groupSpacing'] = 8
        self.data['bar']['sharedBackground'] = 'off'
        for entry in self.data['items']:
            entry['pillGroup'] = 'Connections' if entry['id'] in ('wifi', 'bluetooth', 'audio') else ''
            entry['sharedBackground'] = 'on' if entry['pillGroup'] else 'inherit'
        backend.save(self.data)
        self.assertEqual(json.loads(self.path.read_text()), self.data)
        for value in (True, None, 'x' * 41, 'bad\nname'):
            data = copy.deepcopy(self.data)
            data['items'][0]['pillGroup'] = value
            with self.subTest(value=value), self.assertRaises(ValueError):
                backend.validate(data)
        for value in (-1, 31, True, 1.5):
            data = copy.deepcopy(self.data)
            data['bar']['groupSpacing'] = value
            with self.subTest(value=value), self.assertRaises(ValueError):
                backend.validate(data)
        for value in (True, None, 'yes'):
            for target in ('bar', 'item'):
                data = copy.deepcopy(self.data)
                section = data['bar'] if target == 'bar' else data['items'][0]
                section['sharedBackground'] = value
                with self.subTest(target=target, value=value), self.assertRaises(ValueError):
                    backend.validate(data)
        legacy = copy.deepcopy(self.data)
        del legacy['bar']['groupSpacing']
        del legacy['bar']['sharedBackground']
        for entry in legacy['items']:
            del entry['pillGroup']
            del entry['sharedBackground']
        restored = backend.validate(legacy)
        self.assertEqual(restored['bar']['groupSpacing'], 3)
        self.assertTrue(all(i['pillGroup'] == '' for i in restored['items']))
        self.assertEqual(restored['bar']['sharedBackground'], 'inherit')
        self.assertTrue(all(i['sharedBackground'] == 'inherit' for i in restored['items']))

    def test_individual_padding_round_trip_and_validation(self):
        self.data['items'][0].update(paddingLeft=12, paddingRight=-2)
        backend.save(self.data)
        self.assertEqual(json.loads(self.path.read_text()), self.data)
        for key in ('paddingLeft', 'paddingRight'):
            for value in (-201, 201, 0.5, True, '5'):
                data = copy.deepcopy(self.data)
                data['items'][0][key] = value
                with self.subTest(key=key, value=value), self.assertRaises(ValueError):
                    backend.validate(data)
        legacy = copy.deepcopy(self.data)
        for entry in legacy['items']:
            del entry['paddingLeft']
            del entry['paddingRight']
        self.assertTrue(all(i['paddingLeft'] == i['paddingRight'] == 0 for i in backend.validate(legacy)['items']))

    def test_invalid_spacing_and_global_background_are_rejected(self):
        for key in ('spacingLeft', 'spacingRight'):
            for value in (-201, 201, 0.5, True, '5', float('inf')):
                with self.subTest(key=key, value=value):
                    data = copy.deepcopy(self.data)
                    data['items'][0][key] = value
                    with self.assertRaises(ValueError):
                        backend.save(data)
        for value in ('yes', True, None):
            data = copy.deepcopy(self.data)
            data['bar']['background'] = value
            with self.assertRaises(ValueError):
                backend.save(data)
        self.assertFalse(self.path.exists())

    def test_icon_sizes_round_trip_and_retired_motion_settings_are_removed(self):
        legacy = copy.deepcopy(self.data)
        for section in [legacy['bar'], *legacy['items']]:
            del section['iconSize']
            section.update(genieEffect=True, genieOpenDuration=360, genieCloseDuration=280)
        self.assertEqual(backend.validate(legacy), self.data)
        self.data['bar']['iconSize'] = 24
        self.data['items'][0]['iconSize'] = 36
        backend.save(self.data)
        self.assertEqual(json.loads(self.path.read_text()), self.data)
        self.path.write_text(json.dumps(legacy))
        backend.save(self.data, legacy)
        self.assertEqual(json.loads(self.path.read_text()), self.data)

    def test_invalid_icon_sizes_write_nothing(self):
        for section in ['bar', 'item']:
            for value in (-1, 1, 7, 49, True, False, 12.5, '24', None, float('nan')):
                with self.subTest(section=section, value=value):
                    data = copy.deepcopy(self.data)
                    target = data['bar'] if section == 'bar' else data['items'][0]
                    target['iconSize'] = value
                    with self.assertRaises(ValueError):
                        backend.save(data)
        self.assertFalse(self.path.exists())

    def test_external_edit_is_not_overwritten(self):
        backend.save(self.data)
        self.data['bar']['height'] = 40
        backend.save(self.data)
        before = self.path.read_text()
        with self.assertRaisesRegex(ValueError, 'changed outside'):
            backend.save(backend.DEFAULTS, backend.DEFAULTS)
        self.assertEqual(self.path.read_text(), before)

    def test_lua_override_is_appended_once_and_clearing_restores_inheritance(self):
        main = self.config / 'hypr/hyprland.lua'
        main.parent.mkdir(parents=True)
        main.write_text('-- Personal config\nhl.config({general={gaps_out=17}})\n')
        self.data['hyprland'] = {'gapsOut': 25, 'blur': False}
        backend.save(self.data)
        self.assertTrue(main.read_text().startswith('-- Personal config\n'))
        self.assertEqual(main.read_text().count(backend.MARKER), 1)
        override = self.config / 'hyprshell/overrides.lua'
        self.assertIn('gaps_out = 25', override.read_text())
        self.assertIn('enabled = false', override.read_text())
        self.data['hyprland'] = {}
        backend.save(self.data)
        self.assertNotIn('gaps_out', override.read_text())
        self.assertEqual(main.read_text().count(backend.MARKER), 1)

    def test_conf_user_gets_conf_override(self):
        main = self.config / 'hypr/hyprland.conf'
        main.parent.mkdir(parents=True)
        main.write_text('general {\n gaps_out = 17\n}\n')
        self.data['hyprland'] = {'rounding': 8, 'animations': False}
        backend.save(self.data)
        self.assertIn('source = ', main.read_text())
        override = self.config / 'hyprshell/overrides.conf'
        self.assertIn('decoration:rounding = 8', override.read_text())
        self.assertIn('animations:enabled = false', override.read_text())

    def test_glass_controls_round_trip_lua_and_conf(self):
        self.data['hyprland'] = {
            'activeOpacity': 0.85, 'inactiveOpacity': 0.65,
            'blur': True, 'blurSize': 12, 'blurPasses': 3, 'blurVibrancy': 0.35,
        }
        for lua in (True, False):
            with self.subTest(lua=lua):
                main = self.config / ('hypr/hyprland.lua' if lua else 'hypr/hyprland.conf')
                main.parent.mkdir(parents=True, exist_ok=True)
                main.write_text('-- Personal config\n' if lua else '# Personal config\n')
                backend.save(self.data)
                override = self.config / ('hyprshell/overrides.lua' if lua else 'hyprshell/overrides.conf')
                text = override.read_text()
                for key, value in [('active_opacity', 0.85), ('inactive_opacity', 0.65),
                                   ('size', 12), ('passes', 3), ('vibrancy', 0.35)]:
                    self.assertIn(f'{key} = {value}', text)
                self.assertEqual(json.loads(self.path.read_text())['hyprland'], self.data['hyprland'])
                main.unlink()
                self.path.unlink()

    def test_invalid_glass_values_write_nothing(self):
        for key, values in {
            'blurSize': (0, 21, 1.5, True),
            'blurPasses': (0, 5, 2.5, True),
            'blurVibrancy': (-0.1, 1.1, float('nan'), True),
        }.items():
            for value in values:
                with self.subTest(key=key, value=value):
                    data = copy.deepcopy(self.data)
                    data['hyprland'][key] = value
                    with self.assertRaises(ValueError):
                        backend.save(data)
        self.assertFalse(self.path.exists())

    def test_reload_errors_roll_back_files_and_reload_original(self):
        main = self.config / 'hypr/hyprland.lua'
        main.parent.mkdir(parents=True)
        original = '-- Personal config\n'
        main.write_text(original)
        self.data['hyprland'] = {'rounding': 8}
        with patch.dict(os.environ, HYPRLAND_INSTANCE_SIGNATURE='test'), patch.object(backend.subprocess, 'run') as run:
            run.side_effect = [subprocess.CompletedProcess([], 0, 'ok'), subprocess.CompletedProcess([], 0, 'invalid config'), subprocess.CompletedProcess([], 0, 'ok')]
            with self.assertRaisesRegex(ValueError, 'invalid config'):
                backend.save(self.data)
            self.assertEqual(run.call_count, 3)
        self.assertEqual(main.read_text(), original)
        self.assertFalse(self.path.exists())
        self.assertFalse((self.config / 'hyprshell/overrides.lua').exists())

    def test_partial_write_failure_rolls_back_earlier_files(self):
        main = self.config / 'hypr/hyprland.lua'
        main.parent.mkdir(parents=True)
        main.write_text('-- original\n')
        self.data['hyprland'] = {'rounding': 8}
        atomic = backend.atomic
        def fail_target(path, text):
            if path == self.path:
                raise OSError('disk full')
            atomic(path, text)
        with patch.object(backend, 'atomic', side_effect=fail_target):
            with self.assertRaisesRegex(OSError, 'disk full'):
                backend.save(self.data)
        self.assertEqual(main.read_text(), '-- original\n')
        self.assertFalse((self.config / 'hyprshell/overrides.lua').exists())


if __name__ == '__main__':
    unittest.main()
