"""Daily-driver service preservation and redacted hardware readiness checks."""
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
import sys
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))


def module(name):
    spec = importlib.util.spec_from_file_location(name, ROOT / 'tools' / (name + '.py'))
    value = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(value)
    return value


system = module('configure_daily_driver')
readiness = module('check_daily_driver')


class DailyDriverSetupTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.calls = []
        self.existing = set()
        queue = self.root / 'sys/class/block/disk/queue'
        queue.mkdir(parents=True)
        (queue / 'discard_max_bytes').write_text('1048576')

    def runner(self, arguments):
        self.calls.append(arguments)
        code = int(arguments[2] not in self.existing) if arguments[1] in ('is-enabled', 'is-active') else 0
        return subprocess.CompletedProcess(arguments, code, stdout='', stderr='')

    def apply(self):
        with patch('sys.stdout', io.StringIO()):
            system.configure(self.root, self.runner)

    def test_fresh_system_enables_basics_and_discovery_without_reloading_firewall(self):
        self.apply()
        for unit in ('cups.socket', 'avahi-daemon.service', 'fstrim.timer', 'chronyd.service', 'firewalld.service'):
            self.assertTrue(any(unit in call and 'enable' in call for call in self.calls))
        self.assertIn(['firewall-cmd', '--permanent', '--add-service=mdns'], self.calls)
        self.assertFalse(any('--reload' in call or '--set-default-zone' in call for call in self.calls))

    def test_enabled_but_stopped_time_and_firewall_alternatives_are_preserved(self):
        self.existing = {'systemd-timesyncd.service', 'nftables.service'}
        self.apply()
        self.assertFalse(any('enable' in call and ('chronyd.service' in call or 'firewalld.service' in call) for call in self.calls))
        self.assertFalse(any(call[0] == 'firewall-cmd' for call in self.calls))

    def test_hdd_or_unknown_storage_does_not_change_trim_policy(self):
        (self.root / 'sys/class/block/disk/queue/discard_max_bytes').write_text('0')
        self.apply()
        self.assertFalse(any('fstrim.timer' in call for call in self.calls))

    def test_planned_trim_decision_is_applied_without_forcing_discard(self):
        with patch('sys.stdout', io.StringIO()):
            system.configure(self.root, self.runner, policy={'trim': False})
        self.assertFalse(any('fstrim.timer' in call for call in self.calls))

    def test_existing_firewalld_or_admin_zone_keeps_rules(self):
        self.existing.add('firewalld.service')
        self.apply()
        self.assertFalse(any(call[0] == 'firewall-cmd' for call in self.calls))
        self.existing.clear(); self.calls.clear()
        zone = self.root / 'etc/firewalld/zones/public.xml'
        zone.parent.mkdir(parents=True); zone.write_text('<zone/>')
        self.apply()
        self.assertFalse(any(call[0] == 'firewall-cmd' for call in self.calls))
        self.assertEqual(zone.read_text(), '<zone/>')

    def test_service_failure_is_not_reported_as_success(self):
        def failed(arguments):
            return subprocess.CompletedProcess(arguments, 1, stdout='', stderr='unit failed')
        with self.assertRaisesRegex(RuntimeError, 'unit failed'):
            system.configure(self.root, failed)

    def test_keyring_pam_is_optional_backed_up_and_idempotent(self):
        pam = self.root / 'etc/pam.d/sddm'
        pam.parent.mkdir(parents=True)
        original = 'auth include system-login\nsession include system-login\n'
        pam.write_text(original)
        pam.chmod(0o644)
        self.apply()
        self.assertIn('-auth optional pam_gnome_keyring.so', pam.read_text())
        self.assertIn('-session optional pam_gnome_keyring.so auto_start', pam.read_text())
        backups = list(self.root.glob('var/lib/hyprshell/system-backups/*/sddm'))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_text(), original)
        self.apply()
        self.assertEqual(list(self.root.glob('var/lib/hyprshell/system-backups/*/sddm')), backups)
        self.assertEqual(pam.stat().st_mode & 0o777, 0o644)

    def test_existing_distribution_pam_keyring_stanzas_are_preserved(self):
        text = 'auth include password-auth\n-auth optional pam_gnome_keyring.so\n-session optional pam_gnome_keyring.so auto_start\n'
        self.assertEqual(system.pam_keyring(text), text)

    def test_pam_write_failure_leaves_original_authentication_file_intact(self):
        pam = self.root / 'etc/pam.d/sddm'
        pam.parent.mkdir(parents=True)
        original = 'auth include system-login\nsession include system-login\n'
        pam.write_text(original)
        with patch.object(system.os, 'replace', side_effect=OSError('simulated full filesystem')), self.assertRaises(OSError):
            self.apply()
        self.assertEqual(pam.read_text(), original)
        self.assertFalse(list(pam.parent.glob('.hyprshell-pam-*')))

    def test_no_personal_device_names_enter_readiness_report(self):
        def runner(arguments):
            if arguments[0] == 'pactl':
                return 0, json.dumps([{'name': 'private-headset' if arguments[-1] == 'sinks' else 'private-microphone'}])
            if arguments[0] == 'bluetoothctl':
                return 0, 'Controller 00:11:22:33:44:55 personal-laptop'
            if arguments[0] == 'nmcli':
                return 0, 'wifi\nethernet'
            return 0, ''
        with patch.object(readiness.shutil, 'which', return_value='/usr/bin/tool'):
            report = readiness.check(True, self.root, runner)
        text = json.dumps(report)
        for private in ('private-headset', 'private-microphone', '00:11:22:33:44:55', 'personal-laptop'):
            self.assertNotIn(private, text)
        rows = {row['title']: row['state'] for row in report['checks']}
        self.assertEqual(rows['Audio output'], 'ok')
        self.assertEqual(rows['Microphone input'], 'ok')
        self.assertEqual(rows['Wi-Fi adapter'], 'ok')

    def test_dummy_audio_and_missing_hardware_are_not_claimed_ready(self):
        def runner(arguments):
            if arguments[0] == 'pactl':
                return 0, '[{"name": "auto_null"}, {"name": "alsa_output.monitor"}]'
            return 0, ''
        with patch.object(readiness.shutil, 'which', return_value='/usr/bin/tool'):
            report = readiness.check(True, self.root, runner)
        rows = {row['title']: row['state'] for row in report['checks']}
        for title in ('Audio output', 'Microphone input', 'Wi-Fi adapter', 'Bluetooth adapter', 'Graphics driver'):
            self.assertEqual(rows[title], 'attention')

    def test_sandbox_bus_failure_is_unavailable(self):
        failure = subprocess.CompletedProcess([], 1, stdout='', stderr='Failed to connect to bus: Operation not permitted')
        with patch.object(readiness.subprocess, 'run', return_value=failure):
            self.assertEqual(readiness.invoke(['systemctl', 'is-active', 'NetworkManager.service']), (None, ''))

    def test_media_and_portable_monitor_payload(self):
        defaults = json.loads((ROOT / 'config/hyprshell/applications.json').read_text())['defaults']
        self.assertTrue(all(app == 'mpv.desktop' for mime, app in defaults.items() if mime.startswith(('audio/', 'video/'))))
        self.assertNotIn('eDP-1', (ROOT / 'config/hypr/hyprland-gui.lua').read_text())
        for name, packages in (
            ('packages.txt', ('linux-firmware', 'sof-firmware', 'intel-ucode', 'amd-ucode')),
            ('packages-fedora.txt', ('linux-firmware', 'alsa-sof-firmware', 'realtek-firmware', 'atheros-firmware', 'microcode_ctl')),
        ):
            manifest = (ROOT / name).read_text().splitlines()
            for package in (*packages, 'mpv', 'playerctl', 'mousepad', '7zip', 'cups', 'chrony', 'firewalld', 'gnome-keyring'):
                self.assertIn(package, manifest)


if __name__ == '__main__':
    unittest.main()
