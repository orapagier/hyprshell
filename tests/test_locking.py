"""Lock settings and command execution without locking the real desktop."""
import copy
import importlib.util
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch, Mock

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('locking_backend', ROOT / 'config/quickshell/settings/backend.py')
backend = importlib.util.module_from_spec(spec)
spec.loader.exec_module(backend)


class LockingTests(unittest.TestCase):
    def test_legacy_settings_leave_locking_disabled(self):
        data = copy.deepcopy(backend.DEFAULTS)
        del data['locking']
        self.assertEqual(backend.validate(data)['locking'], backend.DEFAULTS['locking'])
        self.assertFalse(backend.validate(data)['locking']['enabled'])

    def test_invalid_settings(self):
        for key, value in [('enabled', 1), ('beforeSleep', 'yes'), ('idleMinutes', True),
                           ('idleMinutes', -1), ('idleMinutes', 241), ('idleMinutes', 1.5),
                           ('command', ''), ('command', '"unterminated'),
                           ('command', 'hyprlock\nshutdown'), ('unknown', True)]:
            with self.subTest(key=key, value=value):
                data = copy.deepcopy(backend.DEFAULTS)
                data['locking'][key] = value
                with self.assertRaises(ValueError):
                    backend.validate(data)

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
                run.assert_called_once_with(['hyprlock'], check=False, cwd=Path(directory) / 'hypr')

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
