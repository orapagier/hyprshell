"""Display safety transactions with mocked compositor and isolated XDG paths."""
import copy
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
BACKEND = ROOT / 'config/quickshell/settings'
sys.path.insert(0, str(BACKEND))
import displays


class DisplaysTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.config = Path(self.temp.name) / 'config'
        self.state = Path(self.temp.name) / 'state'
        env = patch.dict(os.environ, XDG_CONFIG_HOME=str(self.config), XDG_STATE_HOME=str(self.state))
        env.start()
        self.addCleanup(env.stop)
        self.monitor = {'name': 'eDP-1', 'width': 1920, 'height': 1080, 'refreshRate': 60.0,
                        'scale': 1, 'x': 0, 'y': 0, 'transform': 0, 'availableModes': ['1920x1080@60.00Hz', '1280x720@60.00Hz']}
        self.entry = displays.live_entry(self.monitor)
        self.entry['mode'] = '1280x720@60.00Hz'
        self.request = {'entries': [self.entry], 'expected': {'version': 1, 'entries': []}}
        self.events = []

    def transaction(self, decision):
        with patch.object(displays, 'monitors', return_value=[self.monitor]), patch.object(displays, 'hypr', return_value='ok') as hypr:
            result = displays.preview(self.request, self.events.append, wait=lambda: decision)
        return result, hypr

    def test_confirm_persists_and_backup_retains_previous_files(self):
        result, hypr = self.transaction('keep')
        self.assertIn('saved', result['message'])
        self.assertTrue(self.events[0]['pending'])
        target = self.config / 'hyprshell/displays.json'
        original = target.read_text()
        self.assertEqual(json.loads(original)['entries'], [self.entry])
        self.assertIn('hl.monitor', (target.parent / 'displays.lua').read_text())
        self.assertFalse(any(call.args == ('reload',) for call in hypr.call_args_list))
        self.request['expected'] = json.loads(original)
        self.request['entries'] = [dict(self.entry, scale=1.25)]
        self.transaction('keep')
        manifests = list((self.state / 'hyprshell/backups').glob('*/manifest.json'))
        self.assertTrue(any(any(e['existed'] and (m.parent / e['file']).read_text() == original
                                for e in json.loads(m.read_text())) for m in manifests))

    def test_timeout_cancel_and_eof_restore_live_layout_without_saving(self):
        for decision in ('revert', '', 'unexpected'):
            with self.subTest(decision=decision):
                result, hypr = self.transaction(decision)
                self.assertIn('restored', result['message'])
                self.assertFalse((self.config / 'hyprshell/displays.json').exists())
                self.assertIn(unittest.mock.call('reload'), hypr.call_args_list)
                self.assertIn('1920x1080@60.000', hypr.call_args_list[-1].args[1])

    def test_preview_failure_and_ui_shutdown_restore(self):
        for failure in ('apply', 'wait'):
            with self.subTest(failure=failure):
                def wait():
                    raise RuntimeError('UI stopped')
                with patch.object(displays, 'monitors', return_value=[self.monitor]), patch.object(displays, 'hypr', side_effect=['error', 'ok', 'ok'] if failure == 'apply' else ['ok', 'ok', 'ok']) as hypr:
                    with self.assertRaises((ValueError, RuntimeError)):
                        displays.preview(self.request, self.events.append, wait=wait)
                self.assertIn(unittest.mock.call('reload'), hypr.call_args_list)
                self.assertFalse((self.config / 'hyprshell/displays.json').exists())

    def test_concurrent_preferences_and_unadvertised_mode_rejected_before_apply(self):
        for bad in ('expected', 'mode'):
            request = copy.deepcopy(self.request)
            if bad == 'expected':
                request['expected']['entries'] = [self.entry]
            else:
                request['entries'][0]['mode'] = '9999x9999@999'
            with patch.object(displays, 'monitors', return_value=[self.monitor]), patch.object(displays, 'hypr') as hypr:
                with self.assertRaises(ValueError):
                    displays.preview(request, self.events.append, wait=lambda: 'keep')
                hypr.assert_not_called()

    def test_hotplug_during_confirmation_reverts_and_does_not_save(self):
        with patch.object(displays, 'monitors', side_effect=[[self.monitor], [], []]), patch.object(displays, 'hypr', return_value='ok') as hypr:
            with self.assertRaisesRegex(ValueError, 'Connected displays changed'):
                displays.preview(self.request, self.events.append, wait=lambda: 'keep')
        self.assertIn(unittest.mock.call('reload'), hypr.call_args_list)
        self.assertFalse((self.config / 'hyprshell/displays.json').exists())

    def test_failed_second_write_restores_both_files(self):
        original = {'version': 1, 'entries': [dict(self.entry, scale=1)]}
        displays.persist(original, self.request['expected'])
        config = self.config / 'hyprshell'
        before = {p: p.read_text() for p in config.iterdir()}
        atomic = displays.atomic
        def failing(path, content):
            if path.name == 'displays.lua' and 'scale = 2' in content:
                raise OSError('Disk full')
            atomic(path, content)
        with patch.object(displays, 'atomic', side_effect=failing):
            with self.assertRaises(OSError):
                displays.persist({'version': 1, 'entries': [dict(self.entry, scale=2)]}, original)
        self.assertEqual(before, {p: p.read_text() for p in config.iterdir()})

    def test_timeout_and_eof_confirmation(self):
        with patch.object(displays.select, 'select', return_value=([], [], [])):
            self.assertEqual(displays.wait_for_confirmation(), 'revert')
        import io
        with patch.object(displays.select, 'select', return_value=([1], [], [])), patch.object(displays.sys, 'stdin', io.StringIO('')):
            self.assertEqual(displays.wait_for_confirmation(), '')

    def test_validation_blocks_code_injection_and_invalid_geometry(self):
        for key, value in [('output', 'eDP-1"});os.execute("bad")'), ('mode', 'preferred;bad'),
                           ('position', '0x0;bad'), ('scale', float('nan')), ('scale', True), ('transform', True)]:
            with self.subTest(key=key):
                with self.assertRaises(ValueError):
                    displays.validate({'version': 1, 'entries': [dict(self.entry, **{key: value})]})

    def test_runtime_lua_passes_real_hyprctl_argument_parser(self):
        import subprocess
        with patch.object(displays, 'hypr', return_value='ok') as hypr:
            displays.apply([self.entry])
        code = hypr.call_args.args[1]
        self.assertTrue(code.startswith('hl.monitor('))
        # A missing compositor socket is acceptable here; CLI usage is not.
        environment = dict(os.environ, HYPRLAND_INSTANCE_SIGNATURE='', XDG_RUNTIME_DIR=str(self.state / 'isolated-runtime'))
        result = subprocess.run(['hyprctl', 'eval', code], capture_output=True, text=True, timeout=5, env=environment)
        self.assertNotIn('usage: hyprctl', result.stdout + result.stderr)

    def test_command_help_is_replaced_by_short_error(self):
        import subprocess
        help_text = 'usage: hyprctl [flags] <command>\ncommands:\n' + 'many lines\n' * 100
        with patch.object(displays.subprocess, 'run', return_value=subprocess.CompletedProcess([], 1, help_text, '')):
            with self.assertRaisesRegex(ValueError, '^Hyprland rejected the display command') as caught:
                displays.hypr('eval', 'invalid')
        self.assertLess(len(str(caught.exception)), 120)

    def test_generated_lua_is_accepted_by_real_hyprland(self):
        import subprocess
        generated = self.config / 'hyprshell/displays.lua'
        generated.parent.mkdir(parents=True)
        generated.write_text(displays.render({'version': 1, 'entries': [dict(self.entry, scale=1.25, transform=1, position='-100x0')]}))
        result = subprocess.run(['Hyprland', '--verify-config', '--config', str(ROOT / 'config/hypr/hyprland.lua')],
                                capture_output=True, text=True, timeout=15)
        self.assertIn('config ok', result.stdout.lower(), result.stdout + result.stderr)

    def test_snapshot_regenerates_confirmed_lua(self):
        import github_sync
        data = {'version': 1, 'entries': [self.entry]}
        displays.persist(data, self.request['expected'])
        repo = Path(self.temp.name) / 'repo'
        (repo / 'config').mkdir(parents=True)
        github_sync.snapshot_managed_files(repo, self.config, Path(self.temp.name))
        self.assertEqual(json.loads((repo / 'config/hyprshell/displays.json').read_text()), data)
        self.assertEqual((repo / 'config/hyprshell/displays.lua').read_text(), displays.render(data))


class DisplaysNativeTests(unittest.TestCase):
    def test_real_qml_controls_and_streamed_preview_decisions(self):
        import shutil
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            payload = root / 'config/quickshell'
            shutil.copytree(ROOT / 'config/quickshell', payload, ignore=shutil.ignore_patterns('__pycache__', 'audio-spectrum'))
            (payload / 'settings/displays.py').write_text('''import json, sys
request = json.loads(sys.argv[2])
m = {"name": "eDP-1", "description": "Laptop", "x": 0, "y": 0, "availableModes": ["1920x1080@60.00Hz", "1920x1080@120.00Hz", "1280x720@60.00Hz"]}
e = {"output": "eDP-1", "mode": "1920x1080@60.00Hz", "scale": 1, "transform": 0, "position": "0x0"}
if request["operation"] == "status":
    print(json.dumps({"ok": True, "monitors": [m], "entries": [e], "saved": {"version": 1, "entries": []}}), flush=True)
else:
    print(json.dumps({"ok": True, "pending": True, "seconds": 15, "message": "Confirm"}), flush=True)
    decision = sys.stdin.readline().strip()
    print(json.dumps({"ok": True, "pending": False, "message": "Display settings saved." if decision == "keep" else "Previous display settings restored."}), flush=True)
''')
            fixture = payload / 'SettingsDisplaysNative.qml'
            fixture.write_text((payload / 'tests/SettingsDisplaysNative.qml').read_text().replace('import ".."', 'import "."'))
            runtime = root / 'runtime'
            runtime.mkdir(mode=0o700)
            env = dict(os.environ, XDG_CONFIG_HOME=str(root / 'config'), XDG_STATE_HOME=str(root / 'state'),
                       XDG_RUNTIME_DIR=str(runtime), QT_QPA_PLATFORMTHEME='', QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software')
            import subprocess
            result = subprocess.run(['quickshell', '-p', str(fixture)], env=env,
                                    capture_output=True, text=True, timeout=15)
            output = result.stdout + result.stderr
            self.assertIn('DISPLAYS_NATIVE_OK', output, output)
            self.assertNotIn('DISPLAYS_FAILED', output)
            self.assertEqual(result.returncode, 0)


if __name__ == '__main__':
    unittest.main()
