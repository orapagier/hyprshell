"""Exercise Arch's full setup with isolated commands and no system mutations."""
import os
from pathlib import Path
import subprocess
import sys
import unittest

import test_fedora

ROOT = Path(__file__).resolve().parents[1]


class ArchInstallerTests(unittest.TestCase):
    setUp = test_fedora.FedoraInstallerTests.setUp
    program = test_fedora.FedoraInstallerTests.program
    read_calls = test_fedora.FedoraInstallerTests.read_calls

    def run_setup(self, *args):
        return subprocess.run(['bash', str(self.repo / 'setup.sh'), '--distro', 'arch', *args],
                              env=self.env, capture_output=True, text=True, timeout=45)

    @unittest.skipIf(os.geteuid() == 0, 'Installer correctly refuses root')
    def test_full_arch_flow_checks_media_and_installs_shared_features(self):
        self.repo = self.root / 'checkout'; self.repo.mkdir()
        release = self.root / 'os-release'; release.write_text('ID=arch\n')
        self.repo.joinpath('setup.sh').write_text(ROOT.joinpath('setup.sh').read_text()
            .replace('/etc/os-release', str(release))
            .replace('/etc/systemd/system/display-manager.service', str(self.root / 'absent-manager')))
        for name in ('config', 'tools', 'bin', 'assets', 'packages.txt', 'packages-apps.txt', 'compatibility.json'):
            (self.repo / name).symlink_to(ROOT / name)
        self.program('pacman', """if '-Q' in sys.argv: raise SystemExit(1)
if '-T' in sys.argv:
    print('\\n'.join(sys.argv[2:]))
    raise SystemExit(127)
raise SystemExit(0)""")
        runner = self.bin / 'qmltestrunner'
        self.program('qmltestrunner', 'raise SystemExit(0)')
        self.program('python3', f'''if sys.argv[1].endswith('/compatibility.py'): raise SystemExit(0)
if sys.argv[1].endswith('/system_plan.py'):
    sys.path.insert(0, {str(ROOT / 'tools')!r})
    import hardware_plan, system_plan
    hardware_plan.detect = lambda *args: {{'cpuVendors': ['GenuineIntel'], 'pci': [{{'vendor': '8086', 'device': '46a8', 'class': '030000', 'driver': 'i915'}}], 'usbVendors': [], 'battery': True, 'kernel': '6.20.0-arch1-1'}}
    system_plan.environment = lambda root: {{'discard': True, 'bluetooth': True, 'backlight': True, 'memoryKnown': True}}
    sys.argv = sys.argv[1:]
    system_plan.main()
    raise SystemExit(0)
if sys.argv[1].endswith('/check_runtime.py'):
    if '--qmltestrunner' in sys.argv: print({str(runner)!r})
    raise SystemExit(0)
os.execv({sys.executable!r}, [{sys.executable!r}, *sys.argv[1:]])''')
        for name in ('sudo', 'fc-cache', 'xdg-user-dirs-update'):
            self.program(name, 'raise SystemExit(0)')
        self.program('ffmpeg', "print(' VFS..D h264 H264 decoder' + ('' if os.environ.get('MISSING_HEVC') else '\\n VFS..D hevc HEVC decoder'))")
        self.program('Hyprland', "print(json.dumps({'version': '0.56.2'}) if '--version-json' in sys.argv else 'config ok')")

        # Missing software fallback stops setup before any config deployment.
        self.env['MISSING_HEVC'] = '1'
        failed = self.run_setup('--extra')
        self.assertNotEqual(failed.returncode, 0, failed.stdout)
        self.assertIn('hevc software decoder verification failed', failed.stderr)
        self.assertFalse(self.home.exists())
        self.env.pop('MISSING_HEVC'); self.calls.unlink()

        result = self.run_setup('--extra')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        calls = self.read_calls()
        self.assertIn(['sudo', 'flatpak', 'remote-add', '--system', '--if-not-exists', 'flathub',
                       'https://dl.flathub.org/repo/flathub.flatpakrepo'], calls)
        self.assertIn(['sudo', 'flatpak', 'install', '--system', '--noninteractive', '-y',
                       'flathub', 'com.brave.Browser'], calls)
        browser_index = next(i for i, call in enumerate(calls) if call[:3] == ['sudo', 'flatpak', 'install'])
        config_index = next(i for i, call in enumerate(calls) if call[0] == 'python3' and call[1].endswith('/install_configs.py'))
        self.assertLess(browser_index, config_index)
        self.assertFalse(any('chromium' in call for call in calls))
        transaction = next(call for call in calls if call[:3] == ['sudo', 'pacman', '-Syu'])
        self.assertIn('--needed', transaction)
        for package in ('quickshell', 'hyprlock', 'ffmpeg', 'intel-media-driver', 'intel-ucode',
                        'cups', 'simple-scan', 'gnome-keyring', 'deja-dup', 'restic', 'rclone',
                        'flatpak', 'cosmic-files', 'distrobox', 'podman', 'cmatrix', 'sddm'):
            self.assertIn(package, transaction)
        self.assertNotIn('amd-ucode', transaction)
        media_index = next(i for i, call in enumerate(calls) if call[0] == 'ffmpeg')
        config_index = next(i for i, call in enumerate(calls) if call[0] == 'python3' and call[1].endswith('/install_configs.py'))
        self.assertLess(calls.index(transaction), media_index)
        self.assertLess(media_index, config_index)
        self.assertIn(['sudo', 'systemctl', 'enable', '--now', 'power-profiles-daemon.service'], calls)
        self.assertIn(['sudo', 'python3', str(self.repo / 'tools/configure_daily_driver.py'), '--plan-stdin'], calls)
        self.assertIn(['sudo', 'python3', str(self.repo / 'tools/install_login_theme.py')], calls)
        self.assertIn(['sudo', 'python3', str(self.repo / 'tools/install_boot_splash.py')], calls)
        self.assertFalse(any('dnf' in call or 'dracut' in call for call in calls))
        self.assertTrue((self.home / 'data/fonts/hyprshell/GoMonoNerdFont-Regular.ttf').is_file())
        self.assertTrue((self.home / 'config/quickshell/helpers/audio-spectrum').is_file())
