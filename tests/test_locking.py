"""Lock settings and command execution without locking the real desktop."""
import copy
import fcntl
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch, Mock, ANY

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('locking_backend', ROOT / 'config/quickshell/settings/backend.py')
backend = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backend)
query_session_locked = backend.session_locked


class LockingTests(unittest.TestCase):
    def setUp(self):
        state = patch.object(backend, 'session_locked', return_value=None)
        state.start()
        self.addCleanup(state.stop)

    def test_legacy_settings_leave_locking_disabled(self):
        data = copy.deepcopy(backend.DEFAULTS)
        del data['locking']
        self.assertEqual(backend.validate(data)['locking'], backend.DEFAULTS['locking'])
        self.assertFalse(backend.validate(data)['locking']['enabled'])

    def test_invalid_settings(self):
        for key, value in [('enabled', 1), ('beforeSleep', 'yes'), ('idleMinutes', True),
                           ('idleMinutes', -1), ('idleMinutes', 241), ('idleMinutes', 1.5),
                           ('backgroundTransparency', -1), ('backgroundTransparency', 101),
                           ('backgroundTransparency', True), ('backgroundTransparency', 1.5),
                           ('command', ''), ('command', '"unterminated'),
                           ('command', 'hyprlock\nshutdown'), ('unknown', True)]:
            with self.subTest(key=key, value=value):
                data = copy.deepcopy(backend.DEFAULTS)
                data['locking'][key] = value
                with self.assertRaises(ValueError):
                    backend.validate(data)

    def test_lock_theme_transparency_and_custom_configuration(self):
        template = (ROOT / 'config/hypr/hyprlock.conf').read_text()
        for transparency, alpha in [(0, 'ff'), (85, '26'), (100, '00')]:
            with self.subTest(transparency=transparency):
                rendered = backend.render_lock_theme(template, transparency)
                self.assertIn('$hyprshell_lock_overlay = rgba(1e1e2e' + alpha + ')', rendered)
                self.assertIn('placeholder_text = Enter your password', rendered)
                self.assertIn('fail_text = Authentication failed ($ATTEMPTS)', rendered)
                self.assertNotIn('text = ', rendered)
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'hypr').mkdir()
            (root / 'hypr/hyprlock.conf').write_text(template)
            custom = ['hyprlock', '--config', '/some/custom.conf']
            self.assertEqual(backend.lock_theme_args(custom, {}, root, root), custom)
            self.assertFalse((root / 'hyprshell/hyprlock.conf').exists())
            (root / 'hypr/hyprlock.conf').write_text('background {\n color = rgb(000000)\n}\n')
            self.assertEqual(backend.lock_theme_args(['hyprlock'], {}, root, root), ['hyprlock'])
            self.assertFalse((root / 'hyprshell/hyprlock.conf').exists())

    def test_default_locker_uses_saved_transparency(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'hypr').mkdir()
            (root / 'hypr/hyprlock.conf').write_text((ROOT / 'config/hypr/hyprlock.conf').read_text())
            with patch.dict(os.environ, XDG_CONFIG_HOME=directory, XDG_STATE_HOME=directory), \
                 patch.object(backend, 'read_locking', return_value={'command': 'hyprlock', 'backgroundTransparency': 100}), \
                 patch.object(backend.shutil, 'which', return_value='/bin/hyprlock'), \
                 patch.object(backend, 'supervise_locker', return_value=0) as supervise:
                self.assertEqual(backend.run_locker(), 0)
                generated = root / 'hyprshell/hyprlock.conf'
                self.assertEqual(supervise.call_args.args[0], ['hyprlock', '--config', str(generated)])
                self.assertIn('$hyprshell_lock_overlay = rgba(1e1e2e00)', generated.read_text())
                self.assertEqual(generated.stat().st_mode & 0o777, 0o600)

    def test_user_command_never_becomes_hyprlang(self):
        settings = dict(backend.DEFAULTS['locking'], command='locker "a b" "; touch /tmp/unwanted"', idleMinutes=7)
        config = backend.render_idle(settings)
        self.assertIn('timeout = 420', config)
        self.assertNotIn('unwanted', config)
        self.assertIn('before_sleep_cmd = loginctl lock-session', config)
        self.assertIn('inhibit_sleep = 3', config)
        config = backend.render_idle(dict(settings, idleMinutes=0, beforeSleep=False))
        self.assertNotIn('listener', config)
        self.assertNotIn('before_sleep_cmd', config)
        self.assertNotIn('inhibit_sleep', config)

    def test_lock_executes_quoted_arguments_without_shell(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch.dict(os.environ, XDG_STATE_HOME=directory), \
                 patch.object(backend, 'read_locking', return_value={'command': 'locker "a b" "; touch /tmp/unwanted"'}), \
                 patch.object(backend.shutil, 'which', return_value='/bin/locker'), \
                 patch.object(backend.subprocess, 'run', return_value=Mock(returncode=0)) as run:
                self.assertEqual(backend.run_locker(), 0)
                run.assert_called_once_with(['locker', 'a b', '; touch /tmp/unwanted'], check=False)

    def test_compositor_lock_query_validates_response_and_handles_unavailable_ipc(self):
        for payload, expected in [({'locked': True}, True), ({'locked': False}, False),
                                  ({'locked': 'false'}, None), ({}, None), ([], None)]:
            with self.subTest(payload=payload), \
                 patch.dict(os.environ, HYPRLAND_INSTANCE_SIGNATURE='test'), \
                 patch.object(backend.subprocess, 'run', return_value=Mock(returncode=0, stdout=json.dumps(payload))):
                self.assertIs(query_session_locked(), expected)
        for error in (OSError('offline'), backend.subprocess.TimeoutExpired('hyprctl', 3)):
            with patch.dict(os.environ, HYPRLAND_INSTANCE_SIGNATURE='test'), \
                 patch.object(backend.subprocess, 'run', side_effect=error):
                self.assertIsNone(query_session_locked())

    def test_missing_dependencies_do_not_save(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch.dict(os.environ, XDG_CONFIG_HOME=directory, XDG_STATE_HOME=directory), \
                 patch.object(backend.shutil, 'which', return_value=None):
                data = copy.deepcopy(backend.DEFAULTS)
                data['locking']['enabled'] = True
                with self.assertRaisesRegex(ValueError, 'Install hypridle'):
                    backend.save(data)
                self.assertFalse((Path(directory) / 'hyprshell/settings.json').exists())

    def test_default_locker_resolves_artwork_from_custom_config_root(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch.dict(os.environ, XDG_STATE_HOME=directory, XDG_CONFIG_HOME=directory), \
                 patch.object(backend, 'read_locking', return_value={'command': 'hyprlock'}), \
                 patch.object(backend.shutil, 'which', return_value='/bin/hyprlock'), \
                 patch.object(backend.subprocess, 'run', return_value=Mock(returncode=0)) as run:
                self.assertEqual(backend.run_locker(), 0)
                run.assert_called_once_with(['hyprlock'], check=False, cwd=Path(directory) / 'hypr',
                                            stdout=ANY, stderr=backend.subprocess.STDOUT)
                self.assertEqual((Path(directory) / 'hyprshell/locker.log').stat().st_mode & 0o777, 0o600)

    def test_locked_session_recovers_beyond_old_budget_even_after_zero_exit(self):
        failures = backend.LOCKER_MAX_RESTARTS + 3
        with patch.object(backend, 'session_locked', side_effect=[True] * failures + [False]), \
             patch.object(backend.time, 'sleep') as rest, \
             patch.object(backend.subprocess, 'run', return_value=Mock(returncode=0)) as run:
            self.assertEqual(backend.supervise_locker(['hyprlock'], {}), 0)
            self.assertEqual(run.call_count, failures + 1)
            self.assertEqual(rest.call_args.args, (backend.LOCKER_RECOVERY_DELAY,))

    def test_crash_after_unlock_does_not_relock_desktop(self):
        with patch.object(backend, 'session_locked', return_value=False), \
             patch.object(backend.time, 'sleep') as rest, \
             patch.object(backend.subprocess, 'run', return_value=Mock(returncode=-6)):
            self.assertEqual(backend.supervise_locker(['hyprlock'], {}), -6)
            rest.assert_not_called()

    def test_resume_recovery_only_starts_for_confirmed_lock(self):
        for state in (True, False, None):
            with self.subTest(state=state), \
                 patch.object(backend, 'session_locked', return_value=state), \
                 patch.object(backend.subprocess, 'Popen') as spawn:
                backend.recover_locker()
                self.assertEqual(spawn.call_count, int(state is True))
                if state is True:
                    self.assertEqual(spawn.call_args.args[0][-1], '--lock')
                    self.assertTrue(spawn.call_args.kwargs['start_new_session'])

    def test_recovery_cannot_start_a_second_supervisor(self):
        with tempfile.TemporaryDirectory() as directory, \
             patch.dict(os.environ, XDG_STATE_HOME=directory), \
             patch.object(backend, 'read_locking', return_value={'command': 'hyprlock'}), \
             patch.object(backend.shutil, 'which', return_value='/bin/hyprlock'), \
             patch.object(backend, 'supervise_locker') as supervise:
            path = Path(directory) / 'hyprshell/locker.lock'
            path.parent.mkdir()
            with path.open('w') as held:
                fcntl.flock(held, fcntl.LOCK_EX | fcntl.LOCK_NB)
                self.assertEqual(backend.run_locker(), 0)
            supervise.assert_not_called()

    def test_locking_without_power_timers_still_recovers_after_sleep(self):
        text = backend.render_idle(dict(backend.DEFAULTS['locking'], enabled=True), backend.DEFAULTS['power'])
        self.assertIn('after_sleep_cmd = ', text)
        self.assertIn(' --resume', text)

    def test_crashed_locker_is_relaunched_and_clean_unlock_stops_restarting(self):
        with tempfile.TemporaryDirectory() as directory, \
             patch.dict(os.environ, XDG_STATE_HOME=directory), \
             patch.object(backend, 'read_locking', return_value={'command': 'hyprlock'}), \
             patch.object(backend.shutil, 'which', return_value='/bin/hyprlock'), \
             patch.object(backend.time, 'sleep') as rest, \
             patch.object(backend.subprocess, 'run',
                          side_effect=[Mock(returncode=-6), Mock(returncode=-6), Mock(returncode=0)]) as run:
            self.assertEqual(backend.run_locker(), 0)
            self.assertEqual(run.call_count, 3)
            self.assertEqual(rest.call_count, 2)

    def test_hyprlock_failed_acquisition_is_retried(self):
        with patch.object(backend.time, 'sleep'), \
             patch.object(backend.subprocess, 'run',
                          side_effect=[Mock(returncode=1), Mock(returncode=0)]) as run:
            self.assertEqual(backend.supervise_locker(['hyprlock'], {}), 0)
            self.assertEqual(run.call_count, 2)

    def test_persistent_hyprlock_error_has_bounded_retries(self):
        with patch.object(backend.time, 'sleep'), \
             patch.object(backend.subprocess, 'run', return_value=Mock(returncode=1)) as run:
            self.assertEqual(backend.supervise_locker(['/usr/bin/hyprlock'], {}), 1)
            self.assertEqual(run.call_count, backend.LOCKER_MAX_RESTARTS + 1)

    def test_custom_locker_startup_error_is_not_relaunched(self):
        with tempfile.TemporaryDirectory() as directory, \
             patch.dict(os.environ, XDG_STATE_HOME=directory), \
             patch.object(backend, 'read_locking', return_value={'command': 'custom-locker'}), \
             patch.object(backend.shutil, 'which', return_value='/bin/custom-locker'), \
             patch.object(backend.time, 'sleep') as rest, \
             patch.object(backend.subprocess, 'run', return_value=Mock(returncode=1)) as run:
            self.assertEqual(backend.run_locker(), 1)
            self.assertEqual(run.call_count, 1)
            rest.assert_not_called()

    def test_new_lock_command_must_exist_even_when_auto_lock_is_off(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch.dict(os.environ, XDG_CONFIG_HOME=directory, XDG_STATE_HOME=directory), patch.object(backend.shutil, 'which', return_value=None):
                data = copy.deepcopy(backend.DEFAULTS)
                data['locking']['command'] = 'missing-locker'
                with self.assertRaisesRegex(ValueError, 'Lock program was not found'):
                    backend.save(data)
                self.assertFalse((Path(directory) / 'hyprshell/settings.json').exists())

    def test_existing_idle_process_is_preserved(self):
        with patch.object(backend, 'read_locking', return_value=dict(backend.DEFAULTS['locking'], enabled=True)), \
             patch.object(backend.shutil, 'which', return_value='/bin/present'), \
             patch.object(backend.subprocess, 'run', return_value=Mock(returncode=0)), \
             patch.object(backend.os, 'execvp') as execute:
            with self.assertRaisesRegex(ValueError, 'Another hypridle'):
                backend.run_idle()
            execute.assert_not_called()
