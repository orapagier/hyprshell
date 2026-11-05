import sys
from pathlib import Path
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
with patch.object(sys, 'path', [str(ROOT / 'tools')] + sys.path):
    import capture_shell_baseline as capture


class FreshBaselineTests(unittest.TestCase):
    initial = {'root': {'pid': 42, 'start': 100}, 'tree': {'processes': {
        '42:100': {'pid': 42, 'start': 100}, '43:101': {'pid': 43, 'start': 101}}}}

    def test_exit_timeout_never_starts_second_shell(self):
        with patch.object(capture, 'run') as run, patch.object(capture, 'wait_until', side_effect=RuntimeError('timeout')):
            with self.assertRaisesRegex(RuntimeError, 'timeout'):
                capture.restart(Path('/fixture'), self.initial)
            run.assert_called_once_with('quickshell', 'kill', '--pid', '42')

    def test_orphan_detected_after_desktop_is_restored(self):
        with patch.object(capture, 'run') as run, patch.object(capture, 'wait_until'), patch.object(capture, 'alive', return_value=True):
            with self.assertRaisesRegex(RuntimeError, 'Old helpers remain'):
                capture.restart(Path('/fixture'), self.initial)
            self.assertEqual(run.call_args_list[1].args,
                             ('quickshell', '--no-duplicate', '--daemonize', '--path', '/fixture'))

    def test_successful_restart_checks_old_process_exit(self):
        with patch.object(capture, 'run', return_value='true') as run, patch.object(capture, 'alive', return_value=False):
            capture.restart(Path('/fixture'), self.initial)
            self.assertEqual(run.call_args_list[-1].args[-3:], ('call', 'bar', 'ready'))

    def test_playback_rejected_before_restart(self):
        from subprocess import CompletedProcess
        with patch.object(capture.subprocess, 'run', return_value=CompletedProcess([], 0, 'Playing\n', '')):
            with self.assertRaisesRegex(RuntimeError, 'Pause media'):
                capture.assert_idle_media()

    def test_cleanup_happens_before_replacement_starts(self):
        events = []
        with patch.object(capture, 'run', side_effect=lambda *a: events.append(a) or 'true'), \
                patch.object(capture, 'alive', return_value=False), \
                patch.object(capture, 'stop_owned_idle', side_effect=lambda *a: events.append(('cleanup',))):
            capture.restart(Path('/fixture'), self.initial)
        self.assertEqual(events[0][:2], ('quickshell', 'kill'))
        self.assertEqual(events[1], ('cleanup',))
        self.assertEqual(events[2][:2], ('quickshell', '--no-duplicate'))

    def test_cleanup_failure_still_restores_desktop(self):
        with patch.object(capture, 'run', return_value='true') as run, \
                patch.object(capture, 'alive', return_value=False), \
                patch.object(capture, 'stop_owned_idle', side_effect=RuntimeError('identity mismatch')):
            with self.assertRaisesRegex(RuntimeError, 'identity mismatch'):
                capture.restart(Path('/fixture'), self.initial)
        self.assertEqual(run.call_args_list[1].args[:2], ('quickshell', '--no-duplicate'))

    def test_before_start_runs_after_exit_and_before_launch(self):
        events = []
        with patch.object(capture, 'run', side_effect=lambda *a: events.append(a) or 'true'), \
                patch.object(capture, 'alive', return_value=False):
            capture.restart(Path('/fixture'), self.initial, before_start=lambda: events.append(('deploy',)))
        self.assertEqual(events[0][:2], ('quickshell', 'kill'))
        self.assertEqual(events[1], ('deploy',))
        self.assertEqual(events[2][:2], ('quickshell', '--no-duplicate'))


class OwnedIdleRecoveryTests(unittest.TestCase):
    initial = {'root': {'pid': 42, 'start': 100}, 'tree': {'processes': {
        '42:100': {'pid': 42, 'start': 100},
        '43:101': {'pid': 43, 'start': 101, 'ppid': 42, 'name': 'hypridle'}}}}

    def test_reused_pid_is_not_signalled(self):
        with patch.object(capture, 'alive', return_value=False), \
                patch.object(capture.os, 'pidfd_open') as opened:
            capture.stop_owned_idle(Path('/fixture/quickshell'), self.initial)
            opened.assert_not_called()

    def test_verified_owned_helper_gets_only_sigterm(self):
        from types import SimpleNamespace
        with patch.object(capture, 'alive', side_effect=[True, False, True, False]), \
                patch.object(capture.os, 'pidfd_open', return_value=99), \
                patch.object(capture.os, 'close') as close, \
                patch.object(capture.signal, 'pidfd_send_signal') as send, \
                patch.object(Path, 'read_bytes', return_value=b'hypridle\0-c\0/fixture/hyprshell/hypridle.conf\0'), \
                patch.object(Path, 'stat', return_value=SimpleNamespace(st_uid=capture.os.getuid())):
            capture.stop_owned_idle(Path('/fixture/quickshell'), self.initial)
            send.assert_called_once_with(99, capture.signal.SIGTERM)
            close.assert_called_once_with(99)

    def test_different_config_is_left_running(self):
        from types import SimpleNamespace
        with patch.object(capture, 'alive', side_effect=[True, False, True]), \
                patch.object(capture.os, 'pidfd_open', return_value=99), \
                patch.object(capture.os, 'close'), \
                patch.object(capture.signal, 'pidfd_send_signal') as send, \
                patch.object(Path, 'read_bytes', return_value=b'hypridle\0-c\0/unrelated.conf\0'), \
                patch.object(Path, 'stat', return_value=SimpleNamespace(st_uid=capture.os.getuid())):
            with self.assertRaisesRegex(RuntimeError, 'does not match'):
                capture.stop_owned_idle(Path('/fixture/quickshell'), self.initial)
            send.assert_not_called()

    def test_unrelated_saved_ancestry_is_left_running(self):
        import copy
        initial = copy.deepcopy(self.initial)
        initial['tree']['processes']['43:101']['ppid'] = 999
        with patch.object(capture, 'alive', return_value=True), \
                patch.object(capture.os, 'pidfd_open') as opened:
            with self.assertRaisesRegex(RuntimeError, 'ownership'):
                capture.stop_owned_idle(Path('/fixture/quickshell'), initial)
            opened.assert_not_called()
