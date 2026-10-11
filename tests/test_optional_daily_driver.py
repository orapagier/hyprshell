"""Optional desktop helpers use synthetic clipboard bytes and mocked tools."""
import copy
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'config/quickshell/settings'))
import backend
import clipboard
import peripherals
import optional_tools
import power


class OptionalDailyDriverTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(); self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        env = patch.dict(os.environ, XDG_CONFIG_HOME=str(self.root / 'config'), XDG_STATE_HOME=str(self.root / 'state'), HYPRLAND_INSTANCE_SIGNATURE='')
        env.start(); self.addCleanup(env.stop)

    def test_clipboard_is_disabled_for_old_configs_and_sensitive_data_is_skipped(self):
        data = copy.deepcopy(backend.DEFAULTS); data.pop('clipboard')
        self.assertFalse(backend.validate(data)['clipboard']['enabled'])
        with patch.object(clipboard.os, 'execvp') as execute:
            self.assertEqual(clipboard.watch(), 0); execute.assert_not_called()
        for state in ('sensitive', 'nil', 'clear'):
            with patch.dict(os.environ, CLIPBOARD_STATE=state), patch.object(clipboard, 'read_preferences', return_value={**backend.DEFAULTS, 'clipboard': {'enabled': True}}), patch.object(clipboard, 'run') as execute:
                clipboard.store(); execute.assert_not_called()

    def test_watcher_text_policy_and_bounded_storage(self):
        data = copy.deepcopy(backend.DEFAULTS); data['clipboard'].update(enabled=True, maxItems=30)
        with patch.object(clipboard, 'read_preferences', return_value=data), patch.object(clipboard.shutil, 'which', return_value='/bin/present'), patch.object(clipboard.os, 'execvp') as execute:
            clipboard.watch()
            self.assertEqual(execute.call_args.args[1][:3], ['wl-paste', '--type', 'text'])
            self.assertIn('--store', execute.call_args.args[1])
            self.assertIn('30', clipboard.command('store'))
            with patch.dict(os.environ, CLIPBOARD_STATE='data'), patch.object(clipboard.sys, 'stdin', Mock(buffer=io.BytesIO(b'synthetic clipboard'))), patch.object(clipboard, 'run') as run:
                clipboard.store(); run.assert_called_once_with('store', b'synthetic clipboard')
            with patch.object(clipboard.sys, 'stdin', Mock(buffer=io.BytesIO(b'x' * (clipboard.LIMIT + 1)))), patch.object(clipboard, 'run') as run:
                clipboard.store(); run.assert_not_called()

    def test_history_list_copy_delete_and_clear_use_only_valid_ids(self):
        directory = self.root / 'state/hyprshell/clipboard'; directory.mkdir(parents=True); (directory / 'db').touch()
        with patch.object(clipboard, 'run', return_value=b'42\tsynthetic text\n3\t[[ binary data ]]\ninvalid\tx\n') as run:
            self.assertEqual(len(clipboard.request({'operation': 'list'})['entries']), 2)
            clipboard.request({'operation': 'delete', 'id': '42'}); run.assert_called_with('delete', b'42\n')
        with patch.object(clipboard, 'run', return_value=b'synthetic bytes'), patch.object(clipboard.subprocess, 'run', return_value=Mock(returncode=0)) as copy_command:
            clipboard.request({'operation': 'copy', 'id': '42'})
            self.assertEqual(copy_command.call_args.args[0], ['wl-copy'])
            self.assertEqual(copy_command.call_args.kwargs['input'], b'synthetic bytes')
        with self.assertRaises(ValueError): clipboard.request({'operation': 'copy', 'id': '42;bad'})
        with self.assertRaises(ValueError): clipboard.request({'operation': 'wipe'})
        with patch.object(clipboard, 'run') as run:
            clipboard.request({'operation': 'wipe', 'confirmed': True}); run.assert_called_once_with('wipe')

    def test_tool_status_never_enables_or_probes_devices_and_installs_full_upgrade(self):
        with patch.object(peripherals.shutil, 'which', return_value=None), patch.object(peripherals.subprocess, 'run') as command:
            self.assertTrue(peripherals.status()['ok']); command.assert_not_called()
        with self.assertRaises(ValueError): peripherals.request({'operation': 'enable-printing'})
        with patch.object(optional_tools.shutil, 'which', return_value='/bin/present'), patch.object(optional_tools.subprocess, 'run', return_value=Mock(returncode=0)) as command:
            optional_tools.install('printing')
            args = command.call_args.args[0]
            self.assertIn('-Syu', args); self.assertIn('simple-scan', args); self.assertNotIn('enable', args)

    def test_battery_timers_validate_select_and_render_without_changing_locking(self):
        data = copy.deepcopy(backend.DEFAULTS); data['power'].update(separateBatteryTimers=True, batteryDimMinutes=2, batteryOffMinutes=4, batterySuspendMinutes=10, batteryDimPercent=10)
        data = backend.validate(data)
        battery = backend.effective_power(data['power'], True)
        self.assertEqual(battery['dimMinutes'], 2)
        self.assertEqual(backend.effective_power(data['power'], False)['dimMinutes'], 0)
        text = backend.render_idle(data['locking'], battery)
        self.assertIn('timeout = 120', text); self.assertNotIn('lock_cmd', text)
        data['power']['batteryOffMinutes'] = 1
        with self.assertRaises(ValueError): backend.validate(data)
        data['power']['batteryOffMinutes'] = 4; data['power']['separateBatteryTimers'] = False
        self.assertEqual(backend.effective_power(data['power'], True)['dimMinutes'], 0)


if __name__ == '__main__': unittest.main()
