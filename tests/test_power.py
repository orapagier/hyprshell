"""Power controls in isolated state; never dim, suspend, or inhibit this desktop."""
import copy
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[1]
HELPERS = ROOT / 'config/quickshell/settings'
sys.path.insert(0, str(HELPERS))
import backend
import power


class PowerTests(unittest.TestCase):
    def setUp(self):
        distro = patch.object(power.system_packages, 'distribution', return_value='arch')
        distro.start(); self.addCleanup(distro.stop)
        self.temp = tempfile.TemporaryDirectory(prefix='hyprshell-power-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        env = patch.dict(os.environ, XDG_CONFIG_HOME=str(self.root / 'config'),
                         XDG_STATE_HOME=str(self.root / 'state'), HYPRLAND_INSTANCE_SIGNATURE='')
        env.start()
        self.addCleanup(env.stop)

    def test_legacy_settings_do_not_enable_power_management(self):
        data = copy.deepcopy(backend.DEFAULTS)
        del data['power']
        self.assertEqual(backend.validate(data)['power'], backend.DEFAULTS['power'])
        self.assertFalse(backend.power_idle_enabled(backend.DEFAULTS['power']))
        self.assertEqual(backend.DEFAULTS['power']['lidAction'], 'system')

    def test_validate_ranges_order_and_unknown_values(self):
        for changes in ({'dimMinutes': True}, {'offMinutes': 241}, {'suspendMinutes': -1},
                        {'dimMinutes': 1.5}, {'dimPercent': 0}, {'dimPercent': 101},
                        {'profile': 'performance;shutdown'}, {'lidAction': 'exec'},
                        {'unknown': 1}, {'dimMinutes': 10, 'offMinutes': 5},
                        {'offMinutes': 5, 'suspendMinutes': 5}):
            with self.subTest(changes=changes):
                data = copy.deepcopy(backend.DEFAULTS)
                data['power'].update(changes)
                with self.assertRaises(ValueError):
                    backend.save(data)
                self.assertFalse((self.root / 'config/hyprshell/settings.json').exists())

    def test_power_preferences_save_without_enabling_locking_or_hyprland_overrides(self):
        data = copy.deepcopy(backend.DEFAULTS)
        data['power'].update(dimMinutes=3, offMinutes=5, suspendMinutes=10, lidAction='ignore')
        with patch.object(backend.shutil, 'which', return_value='/bin/present'):
            self.assertTrue(backend.save(data)['ok'])
        saved = json.loads((self.root / 'config/hyprshell/settings.json').read_text())
        self.assertEqual(saved['power'], data['power'])
        self.assertFalse(saved['locking']['enabled'])
        self.assertFalse((self.root / 'config/hyprshell/overrides.lua').exists())

    def test_shared_idle_rendering_and_disabled_locking(self):
        timers = dict(backend.DEFAULTS['power'], dimMinutes=3, offMinutes=5, suspendMinutes=10)
        config = backend.render_idle(backend.DEFAULTS['locking'], timers)
        self.assertNotIn('lock_cmd', config)
        self.assertNotIn('lock-session', config)
        for line in ('timeout = 180', 'timeout = 300', 'timeout = 600', '--dim', '--restore', '--screen-off', '--resume', 'systemctl suspend'):
            self.assertIn(line, config)
        config = backend.render_idle(dict(backend.DEFAULTS['locking'], enabled=True, idleMinutes=1), timers)
        self.assertIn('timeout = 60', config)
        self.assertIn('before_sleep_cmd = loginctl lock-session', config)
        config = backend.render_idle(backend.DEFAULTS['locking'], backend.DEFAULTS['power'])
        self.assertNotIn('listener', config)

    def test_missing_idle_dependencies_do_not_save(self):
        data = copy.deepcopy(backend.DEFAULTS)
        data['power']['offMinutes'] = 5
        with patch.object(backend.shutil, 'which', return_value=None):
            with self.assertRaisesRegex(ValueError, 'Install hypridle'):
                backend.save(data)
        self.assertFalse((self.root / 'config/hyprshell/settings.json').exists())

    def backlight_stub(self, raw=80):
        values = {'raw': raw}
        info = lambda: {'device': 'panel', 'raw': values['raw'], 'max': 100, 'percent': values['raw']}
        def set_raw(device, raw):
            self.assertEqual(device, 'panel')
            values['raw'] = raw
        return values, patch.object(power, 'backlight', side_effect=info), patch.object(power, 'set_raw', side_effect=set_raw)

    def test_dim_restore_and_repeated_dim_preserve_original(self):
        values, info, setter = self.backlight_stub()
        with info, setter, patch.object(backend, 'read_power', return_value=backend.DEFAULTS['power']):
            power.dim()
            self.assertEqual(values['raw'], 20)
            power.dim()
            power.restore()
            self.assertEqual(values['raw'], 80)
            self.assertFalse((power.state_root() / 'power-brightness.json').exists())

    def test_dim_never_brightens_already_dark_screen(self):
        values, info, setter = self.backlight_stub(10)
        with info, setter, patch.object(backend, 'read_power', return_value=backend.DEFAULTS['power']):
            power.dim()
            self.assertEqual(values['raw'], 10)
            self.assertFalse((power.state_root() / 'power-brightness.json').exists())

    def test_manual_slider_and_hotkey_changes_survive_resume(self):
        for slider in (True, False):
            values, info, setter = self.backlight_stub()
            with info, setter, patch.object(backend, 'read_power', return_value=backend.DEFAULTS['power']):
                power.dim()
                if slider:
                    power.set_brightness(35)
                else:
                    values['raw'] = 35
                power.restore()
                self.assertEqual(values['raw'], 35)

    def test_dpms_uses_lua_and_restores_only_managed_screen_off(self):
        with patch.object(power, 'command', return_value='') as command:
            power.dpms(True)
            command.assert_not_called()
            power.dpms(False)
            self.assertTrue((power.state_root() / 'power-screen-off').exists())
            power.dpms(True)
            self.assertEqual(command.call_args_list[0].args[0], ['hyprctl', 'dispatch', 'hl.dsp.dpms({ action = "disable" })'])
            self.assertEqual(command.call_args_list[1].args[0], ['hyprctl', 'dispatch', 'hl.dsp.dpms({ action = "enable" })'])
            self.assertFalse((power.state_root() / 'power-screen-off').exists())
            config = self.root / 'dpms.lua'
            config.write_text('\n'.join(f'hl.bind("F{index+1}", {call.args[0][2]})'
                                        for index, call in enumerate(command.call_args_list)))
            parsed = subprocess.run(['Hyprland', '--verify-config', '--config', str(config)],
                                    capture_output=True, text=True, timeout=5)
            self.assertIn('config ok', parsed.stdout.lower(), parsed.stdout + parsed.stderr)

    def test_resume_attempts_brightness_when_dpms_fails(self):
        with patch.object(power, 'dpms', side_effect=ValueError('offline')), patch.object(power, 'restore') as restore:
            with self.assertRaisesRegex(ValueError, 'offline'):
                power.resume()
            restore.assert_called_once()

    def test_profiles_parse_supported_only_and_apply_saved_preference(self):
        with patch.object(power, 'command', side_effect=['  power-saver:\n* balanced:\n', 'balanced\n']):
            self.assertEqual(power.profiles(), {'available': ['power-saver', 'balanced'], 'active': 'balanced'})
        with patch.object(backend, 'read_power', return_value=dict(backend.DEFAULTS['power'], profile='performance')), \
             patch.object(power, 'profiles', return_value={'available': ['balanced'], 'active': 'balanced'}), \
             patch.object(power, 'command') as command:
            with self.assertRaisesRegex(ValueError, 'not supported'):
                power.apply_profile()
            command.assert_not_called()
        with patch.object(backend, 'read_power', return_value=dict(backend.DEFAULTS['power'], profile='power-saver')), \
             patch.object(power, 'profiles', return_value={'available': ['balanced', 'power-saver'], 'active': 'balanced'}), \
             patch.object(power, 'command') as command:
            power.apply_profile()
            command.assert_called_once_with(['powerprofilesctl', 'set', 'power-saver'])

    def test_lid_starts_only_after_hardware_check_and_inhibits_only_lid(self):
        with patch.object(backend, 'read_power', return_value=dict(backend.DEFAULTS['power'], lidAction='ignore')), \
             patch.object(power, 'lid_state', return_value=False), patch.object(power.os, 'execvp') as execute:
            power.run_lid()
            args = execute.call_args.args[1]
            self.assertIn('--what=handle-lid-switch', args)
            self.assertIn('--no-ask-password', args)
            self.assertIn('--watch-lid', args)
        with patch.object(backend, 'read_power', return_value=dict(backend.DEFAULTS['power'], lidAction='ignore')), \
             patch.object(power, 'lid_state', side_effect=ValueError('no lid')), patch.object(power.os, 'execvp') as execute:
            with self.assertRaisesRegex(ValueError, 'no lid'):
                power.run_lid()
            execute.assert_not_called()

    def test_lid_suspend_acts_on_close_transition_and_ignore_never_suspends(self):
        for action, expected in (('suspend', 1), ('ignore', 0)):
            with patch.object(backend, 'read_power', return_value=dict(backend.DEFAULTS['power'], lidAction=action)), \
                 patch.object(power, 'lid_state', side_effect=[True, True, False, True]), \
                 patch.object(power.time, 'sleep', side_effect=[None, None, None, KeyboardInterrupt]), \
                 patch.object(power, 'command') as command:
                with self.assertRaises(KeyboardInterrupt):
                    power.watch_lid()
                self.assertEqual(command.call_count, expected)
                if expected:
                    command.assert_called_once_with(['systemctl', 'suspend'])

    def test_status_reports_independent_unavailable_controls(self):
        with patch.object(power, 'backlight', side_effect=ValueError('no display')), \
             patch.object(power, 'profiles', side_effect=ValueError('no daemon')), \
             patch.object(power, 'lid_state', side_effect=ValueError('no lid')):
            result = power.status()
            self.assertTrue(result['ok'])
            self.assertIsNone(result['brightness'])
            self.assertIsNone(result['profiles'])
            self.assertFalse(result['lidSupported'])
            self.assertEqual(result['profilesError'], 'no daemon')

    def test_real_hypridle_accepts_generated_config_without_desktop_access(self):
        config = self.root / 'hypridle.conf'
        config.write_text(backend.render_idle(dict(backend.DEFAULTS['locking'], enabled=True),
                          dict(backend.DEFAULTS['power'], dimMinutes=3, offMinutes=5, suspendMinutes=10)))
        env = dict(os.environ, XDG_RUNTIME_DIR=str(self.root), WAYLAND_DISPLAY='hyprshell-no-compositor')
        result = subprocess.run(['hypridle', '-c', str(config)], env=env,
                                capture_output=True, text=True, timeout=5)
        output = result.stdout + result.stderr
        self.assertIn("Couldn't connect to a wayland compositor", output)
        for timeout in (180, 300, 600):
            self.assertIn(f'Registered timeout rule for {timeout}s', output)
        self.assertNotIn('Config has errors', output)

    def test_terminating_real_supervisor_stops_stub_daemon_and_restores_managed_state(self):
        commands = self.root / 'bin'
        commands.mkdir()
        started, stopped, calls = [self.root / name for name in ('started', 'stopped', 'calls')]
        stub_scripts = {
            'pgrep': 'raise SystemExit(1)\n',
            'hypridle': (
                'import signal, time\nfrom pathlib import Path\n'
                f'Path({str(started)!r}).touch()\n'
                f'def stop(*args):\n    Path({str(stopped)!r}).touch()\n    raise SystemExit(0)\n'
                'signal.signal(signal.SIGTERM, stop)\nwhile True: time.sleep(1)\n'),
            'hyprctl': f'with open({str(calls)!r}, "a") as out: out.write("dpms " + " ".join(sys.argv[1:]) + "\\n")\n',
            'brightnessctl': (f'with open({str(calls)!r}, "a") as out: out.write("brightness " + " ".join(sys.argv[1:]) + "\\n")\n'
                              'if "set" not in sys.argv: print("panel,backlight,20,20%,100")\n'),
        }
        for name, script in stub_scripts.items():
            path = commands / name
            path.write_text(f'#!{sys.executable}\nimport sys\n' + script)
            path.chmod(0o755)
        data = copy.deepcopy(backend.DEFAULTS)
        data['power']['offMinutes'] = 5
        config = self.root / 'config/hyprshell'
        config.mkdir(parents=True)
        (config / 'settings.json').write_text(json.dumps(data))
        state = power.state_root()
        state.mkdir(parents=True)
        (state / 'power-screen-off').write_text('off')
        (state / 'power-brightness.json').write_text(json.dumps({'device': 'panel', 'raw': 80, 'max': 100, 'dimmed': 20}))
        env = dict(os.environ, PATH=str(commands) + os.pathsep + os.environ['PATH'])
        process = subprocess.Popen([sys.executable, str(HELPERS / 'backend.py'), '--idle'],
                                   env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            deadline = time.monotonic() + 3
            while not started.exists() and process.poll() is None and time.monotonic() < deadline:
                time.sleep(0.02)
            self.assertTrue(started.exists())
            process.terminate()
            stdout, stderr = process.communicate(timeout=10)
            self.assertEqual(process.returncode, 0, stdout + stderr)
            self.assertTrue(stopped.exists())
            self.assertIn('action = "enable"', calls.read_text())
            self.assertIn('set 80', calls.read_text())
            self.assertFalse((state / 'power-screen-off').exists())
            self.assertFalse((state / 'power-brightness.json').exists())
        finally:
            if process.poll() is None:
                process.kill()
                process.communicate()

    def test_idle_supervisor_terminates_child_and_restores_screen(self):
        child = Mock()
        child.wait.side_effect = [SystemExit(0), 0]
        child.poll.return_value = None
        with patch.object(backend, 'read_locking', return_value=backend.DEFAULTS['locking']), \
             patch.object(backend, 'read_power', return_value=dict(backend.DEFAULTS['power'], offMinutes=5)), \
             patch.object(backend.shutil, 'which', return_value='/bin/present'), \
             patch.object(backend.subprocess, 'run', return_value=Mock(returncode=1)) as run, \
             patch.object(backend.subprocess, 'Popen', return_value=child):
            with self.assertRaises(SystemExit):
                backend.run_idle()
            child.terminate.assert_called_once()
            self.assertEqual(run.call_args.args[0][-1], '--resume')


if __name__ == '__main__':
    unittest.main()
