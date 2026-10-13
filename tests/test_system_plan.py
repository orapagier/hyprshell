"""Whole-system decisions on isolated hosts, without privileged actions."""
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import system_plan as sp
import hardware_plan as hp


class SystemPlanTests(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory(); self.addCleanup(tmp.cleanup)
        self.root = Path(tmp.name); self.calls = []
        self.configured = set(); self.user_configured = set(); self.providers = set()
        self.hardware = {'cpuVendors': ['GenuineIntel'], 'pci': [
            {'vendor': '8086', 'device': '46a8', 'class': '030000', 'driver': 'i915'}],
            'usbVendors': [], 'battery': True, 'kernel': '6.20.0-1.fc44.x86_64'}

    def runner(self, arguments):
        self.calls.append(arguments)
        if arguments[:2] == ['rpm', '-qa']:
            return 0, '\n'.join(sorted(self.providers))
        if arguments[:2] == ['pacman', '-T']:
            return 127, '\n'.join(arguments[2:])
        if arguments[:2] == ['pacman', '-Q']:
            return (0 if arguments[-1] in self.providers else 1), ''
        if arguments[0] == 'systemctl':
            units = self.user_configured if '--user' in arguments else self.configured
            return (0 if arguments[-1] in units else 1), ''
        raise AssertionError('Unexpected command: ' + repr(arguments))

    def build(self, distro='fedora', **options):
        base = hp.manifest(ROOT / ('packages-fedora.txt' if distro == 'fedora' else 'packages.txt'))
        return sp.build(distro, base, root=self.root, runner=self.runner, hardware=self.hardware, **options)

    def write(self, path, value):
        target = self.root / path; target.parent.mkdir(parents=True, exist_ok=True); target.write_text(value)

    def test_every_manifest_package_has_a_subsystem_and_provider_status(self):
        for distro, filename in [('fedora', 'packages-fedora.txt'), ('arch', 'packages.txt')]:
            self.assertTrue(all(p in sp.CATEGORY for p in hp.manifest(ROOT / filename)))
            result = self.build(distro)
            self.assertEqual(set(result['packageStates']), {p for group in result['subsystems'] for p in group['packages']})
            self.assertGreaterEqual(len(result['subsystems']), 15)
        self.assertTrue(all(c[0] in ('rpm', 'pacman', 'systemctl') for c in self.calls))
        self.assertFalse(any('enable' in c or 'start' in c for c in self.calls))

    def test_existing_provider_capabilities_satisfy_packages(self):
        self.providers = {'hyprland', 'quickshell', 'libavcodec-freeworld'}
        result = self.build()
        self.assertEqual(result['packageStates']['hyprland'], 'installed')
        self.assertEqual(result['packageStates']['kitty'], 'missing')
        self.assertEqual(len([c for c in self.calls if c[:2] == ['rpm', '-qa']]), 1)

    def test_network_alternative_blocks_only_exclusive_migration(self):
        self.configured = {'systemd-networkd.service'}
        result = self.build()
        self.assertTrue(any('Networking' in b for b in result['blockers']))
        self.assertNotIn('NetworkManager.service', result['services']['enable'])
        self.configured.add('NetworkManager.service')
        self.assertFalse(self.build()['blockers'])

    def test_legacy_audio_is_not_replaced_silently(self):
        self.user_configured = {'pulseaudio.socket'}
        self.assertTrue(any('PulseAudio' in b for b in self.build()['blockers']))
        self.user_configured.clear(); self.providers = {'pulseaudio'}
        self.assertTrue(any('PulseAudio' in b for b in self.build()['blockers']))

    def test_existing_power_provider_is_preserved_across_distributions(self):
        for unit in ['tuned-ppd.service', 'tuned.service', 'power-profiles-daemon.service', 'tlp.service', 'system76-power.service']:
            self.configured = {unit}
            for distro in ('fedora', 'arch'):
                result = self.build(distro)
                self.assertEqual(result['powerProvider'], unit)
                self.assertEqual(result['services']['power'], [])
                self.assertNotIn('tuned-ppd', result['packages'])
                self.assertNotIn('power-profiles-daemon', result['packages'])

    def test_disabled_external_power_tools_are_not_replaced(self):
        for package in ('tlp', 'power-profiles-daemon', 'tuned-ppd'):
            self.providers = {package}
            result = self.build()
            self.assertEqual(result['services']['power'], [])
            self.assertNotIn('tuned-ppd', result['packages'])

    def test_fresh_power_backend_matches_the_distribution(self):
        self.assertEqual(self.build()['services']['power'], ['tuned.service', 'tuned-ppd.service'])
        self.assertEqual(self.build('arch')['services']['power'], ['power-profiles-daemon.service'])

    def test_bluetooth_and_trim_are_enabled_only_when_detected(self):
        result = self.build()
        self.assertNotIn('bluetooth.service', result['services']['enable'])
        self.assertFalse(result['services']['trim'])
        self.write('sys/class/bluetooth/hci0/name', 'private-name')
        self.write('sys/class/block/disk/queue/discard_max_bytes', '1048576')
        result = self.build()
        self.assertIn('bluetooth.service', result['services']['enable'])
        self.assertTrue(result['services']['trim'])
        self.assertNotIn('private-name', json.dumps(result))
        self.write('sys/class/block/disk/queue/discard_max_bytes', '0')
        self.assertFalse(self.build()['services']['trim'])

    def test_existing_login_and_explicit_boot_preferences_control_packages(self):
        result = self.build(login_unit='gdm.service', skip_boot=True)
        self.assertNotIn('sddm', result['packages'])
        self.assertNotIn('plymouth', result['packages'])
        self.assertFalse(result['loginAppearance'])
        self.assertFalse(result['bootAppearance'])
        self.assertEqual(result['loginUnit'], 'gdm.service')
        self.assertIn('sddm', self.build()['packages'])

    def test_configured_time_and_firewall_alternatives_remain(self):
        self.configured = {'systemd-timesyncd.service', 'nftables.service'}
        result = self.build()
        self.assertNotIn('chrony', result['packages'])
        self.assertNotIn('firewalld', result['packages'])

    def test_full_ffmpeg_and_opt_in_tools_are_preserved(self):
        self.providers = {'ffmpeg', 'libavcodec-freeworld'}
        result = self.build()
        self.assertNotIn('ffmpeg-free', result['packages'])
        self.assertIn('restic', result['packages'])
        self.assertTrue(any('opt-in' in n for n in result['notes']))

    def test_inaccessible_services_are_not_claimed_safe(self):
        result = sp.build('fedora', ['kitty'], root=self.root, runner=lambda argv: (None, ''), hardware=self.hardware)
        self.assertFalse(result['serviceStateAvailable'])
        self.assertFalse(result['packageInventoryAvailable'])
        with patch.object(sys, 'argv', ['system_plan.py', '--read-plan', '--require-safe']), \
             patch.object(sys, 'stdin', io.StringIO(json.dumps(result))), patch('sys.stdout', io.StringIO()):
            with self.assertRaises(SystemExit): sp.main()

    def test_saved_plan_is_consumed_without_reprobing(self):
        result = self.build()
        with patch.object(sys, 'argv', ['system_plan.py', '--read-plan', '--format', 'packages']), \
             patch.object(sys, 'stdin', io.StringIO(json.dumps(result))), patch('sys.stdout', io.StringIO()) as output, \
             patch.object(sp, 'build', side_effect=AssertionError('must not re-probe')):
            sp.main()
            self.assertEqual(output.getvalue().splitlines(), result['packages'])

    def test_tty_without_user_bus_can_enable_audio_for_next_login(self):
        def runner(arguments):
            return (None, '') if '--user' in arguments else self.runner(arguments)
        result = sp.build('fedora', ['kitty'], login_unit='sddm.service', root=self.root,
                          runner=runner, hardware=self.hardware)
        self.assertTrue(result['serviceStateAvailable'])
        self.assertFalse(result['blockers'])
        self.assertTrue(any('next login' in note for note in result['notes']))


if __name__ == '__main__':
    unittest.main()
