"""Hardware decisions on synthetic machines; no package or service mutations."""
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import Mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import hardware_plan as hp


class HardwarePlanTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(); self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)

    def write(self, name, value):
        path = self.root / name; path.parent.mkdir(parents=True, exist_ok=True); path.write_text(value)

    def pci(self, slot, vendor, ident, kind='030000', driver=''):
        for field, value in [('vendor', vendor), ('device', ident), ('class', kind)]:
            self.write(f'sys/bus/pci/devices/{slot}/{field}', '0x' + value)
        if driver:
            path = self.root / 'sys/bus/pci/drivers' / driver; path.mkdir(parents=True, exist_ok=True)
            (self.root / 'sys/bus/pci/devices' / slot / 'driver').symlink_to(path)

    def plan(self, distro):
        base = hp.manifest(ROOT / ('packages-fedora.txt' if distro == 'fedora' else 'packages.txt'))
        return hp.plan(distro, hp.detect(self.root), base)

    def test_intel_laptop_selects_ihd_and_only_matching_microcode(self):
        self.write('proc/cpuinfo', 'vendor_id : GenuineIntel')
        self.pci('gpu', '8086', '46a8', driver='i915')
        self.pci('audio', '8086', '51c8', '040300')
        self.write('sys/class/power_supply/BAT0/type', 'Battery')
        for distro, microcode in [('arch', 'intel-ucode'), ('fedora', 'microcode_ctl')]:
            result = self.plan(distro)
            self.assertEqual(result['mediaPackages'], ['intel-media-driver'])
            self.assertIn(microcode, result['packages'])
            self.assertNotIn('amd-ucode', result['packages']); self.assertNotIn('amd-ucode-firmware', result['packages'])
            self.assertTrue(result['battery'])
            self.assertEqual(len(result['packages']), len(set(result['packages'])))
        self.assertNotIn('amd-gpu-firmware', self.plan('fedora')['packages'])

    def test_amd_desktop_does_not_get_intel_drivers_or_firmware(self):
        self.write('proc/cpuinfo', 'vendor_id : AuthenticAMD')
        self.pci('gpu', '1002', '164e', driver='amdgpu')
        arch, fedora = self.plan('arch'), self.plan('fedora')
        self.assertIn('amd-ucode', arch['packages']); self.assertIn('vulkan-radeon', arch['packages'])
        self.assertNotIn('intel-media-driver', arch['packages'])
        self.assertEqual(fedora['mediaPackages'], ['mesa-va-drivers-freeworld'])
        self.assertNotIn('mesa-va-drivers', fedora['packages'])
        self.assertIn('amd-gpu-firmware', fedora['packages'])
        self.assertNotIn('intel-gpu-firmware', fedora['packages'])
        self.assertNotIn('microcode_ctl', fedora['packages'])

    def test_hybrid_gpu_selection_is_independent_of_cpu(self):
        self.write('proc/cpuinfo', 'vendor_id : AuthenticAMD')
        self.pci('intel', '8086', '56a0', driver='xe')
        self.pci('amd', '1002', '73bf', driver='amdgpu')
        self.assertEqual(self.plan('fedora')['mediaPackages'], ['intel-media-driver', 'mesa-va-drivers-freeworld'])
        self.assertIn('amd-ucode-firmware', self.plan('fedora')['packages'])

    def test_legacy_and_unknown_intel_ids_do_not_get_ihd(self):
        self.pci('gpu', '8086', '0166', driver='i915')
        self.assertEqual(self.plan('fedora')['mediaPackages'], ['libva-intel-driver'])
        self.write('sys/bus/pci/devices/gpu/device', '0xffff')
        result = self.plan('fedora')
        self.assertEqual(result['mediaPackages'], [])
        self.assertTrue(any('Unrecognized Intel' in n for n in result['notes']))

    def test_proprietary_nvidia_is_preserved_with_review(self):
        self.pci('gpu', '10de', '2684', driver='nvidia')
        for distro in ('arch', 'fedora'):
            result = self.plan(distro)
            self.assertEqual(result['mediaPackages'], [])
            self.assertNotIn('vulkan-nouveau', result['packages'])
            self.assertTrue(any('NVIDIA' in n and 'Secure Boot' in n for n in result['notes']))

    def test_nouveau_and_virtual_gpu_paths(self):
        self.pci('gpu', '10de', '1c82', driver='nouveau')
        self.assertIn('vulkan-nouveau', self.plan('arch')['packages'])
        self.write('sys/bus/pci/devices/gpu/vendor', '0x1af4')
        self.assertEqual(self.plan('fedora')['mediaPackages'], [])
        self.assertTrue(any('Virtual' in n for n in self.plan('fedora')['notes']))

    def test_usb_wireless_firmware_and_redacted_detection(self):
        self.write('sys/bus/usb/devices/1-1/idVendor', '0bda')
        self.write('sys/bus/usb/devices/1-1/serial', 'private-device-serial')
        self.pci('wifi', '168c', '003e', '028000')
        result = self.plan('fedora')
        self.assertIn('realtek-firmware', result['packages']); self.assertIn('atheros-firmware', result['packages'])
        self.assertNotIn('private-device-serial', str(result)); self.assertNotIn('1-1', str(result))

    def test_missing_inventory_retains_general_firmware_without_guessing_gpu(self):
        result = self.plan('fedora')
        self.assertIn('linux-firmware', result['packages'])
        self.assertIn('realtek-firmware', result['packages'])
        self.assertEqual(result['mediaPackages'], [])
        self.assertTrue(result['notes'])

    def test_virtual_cpu_and_custom_kernel_do_not_replace_host_dependencies(self):
        self.write('proc/cpuinfo', 'vendor_id : GenuineIntel\nflags : fpu hypervisor sse')
        self.write('proc/sys/kernel/osrelease', '6.20.0-custom')
        result = self.plan('fedora')
        self.assertNotIn('microcode_ctl', result['packages'])
        self.assertNotIn('kernel-modules', result['packages'])
        self.write('proc/sys/kernel/osrelease', '6.20.0-1.fc44.x86_64')
        self.assertIn('kernel-modules', self.plan('fedora')['packages'])

    def test_configured_service_alternatives_and_full_ffmpeg_are_preserved(self):
        def runner(arguments, **kwargs):
            return Mock(returncode=0 if arguments in (
                ['systemctl', 'is-enabled', 'systemd-timesyncd.service'],
                ['systemctl', 'is-active', 'ufw.service'], ['rpm', '-q', 'ffmpeg']) else 1)
        result = hp.system_preferences(self.plan('fedora'), runner)
        for package in ('chrony', 'firewalld', 'ffmpeg-free'):
            self.assertNotIn(package, result['packages'])
        self.assertIn('libavcodec-freeworld', result['packages'])

    def test_inaccessible_services_keep_default_dependencies(self):
        result = hp.system_preferences(self.plan('fedora'), Mock(side_effect=PermissionError))
        self.assertIn('chrony', result['packages']); self.assertIn('firewalld', result['packages'])


if __name__ == '__main__':
    unittest.main()
