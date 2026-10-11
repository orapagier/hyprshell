"""Validate logout selection using inert commands, never ending a real session."""
import importlib.util
import os
from pathlib import Path
import subprocess
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('session_backend', ROOT / 'config/quickshell/settings/session.py')
session = importlib.util.module_from_spec(spec)
spec.loader.exec_module(session)


class SessionTests(unittest.TestCase):
    def test_uwsm_session_uses_ordered_shutdown(self):
        with patch.object(session.shutil, 'which', return_value='/bin/uwsm'), \
             patch.object(session.subprocess, 'run', side_effect=[subprocess.CompletedProcess([], 0), subprocess.CompletedProcess([], 0)]) as run:
            self.assertEqual(session.logout(), 0)
            self.assertEqual([call.args[0] for call in run.call_args_list], [['uwsm', 'check', 'is-active'], ['uwsm', 'stop']])

    def test_unmanaged_session_returns_to_display_manager(self):
        with patch.dict(os.environ, XDG_SESSION_ID='c3'), \
             patch.object(session.shutil, 'which', return_value='/bin/uwsm'), \
             patch.object(session.subprocess, 'run', side_effect=[subprocess.CompletedProcess([], 1), subprocess.CompletedProcess([], 0)]) as run:
            self.assertEqual(session.logout(), 0)
            self.assertEqual(run.call_args.args[0], ['loginctl', 'terminate-session', 'c3'])

    def test_failed_managed_shutdown_does_not_try_another_destructive_action(self):
        with patch.object(session.shutil, 'which', return_value='/bin/uwsm'), \
             patch.object(session.subprocess, 'run', side_effect=[subprocess.CompletedProcess([], 0), subprocess.CompletedProcess([], 1)]) as run:
            with self.assertRaises(RuntimeError): session.logout()
            self.assertEqual(run.call_count, 2)

    def test_inaccessible_bus_or_missing_session_fails_without_terminating(self):
        with patch.object(session.shutil, 'which', return_value='/bin/uwsm'), \
             patch.object(session.subprocess, 'run', return_value=subprocess.CompletedProcess([], 1, '', 'D-Bus is inaccessible')) as run:
            with self.assertRaises(RuntimeError): session.logout()
            self.assertEqual(run.call_count, 1)
        for value in ['', '--all', 'c3;reboot']:
            with patch.dict(os.environ, XDG_SESSION_ID=value), patch.object(session.shutil, 'which', return_value=None), patch.object(session.subprocess, 'run') as run:
                with self.assertRaises(RuntimeError): session.logout()
                run.assert_not_called()
