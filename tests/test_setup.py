"""Exercise actual config installs in isolated homes; never invoke pacman or sudo."""
import json
import os
from pathlib import Path
import subprocess
import shutil
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class InstallerTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='hyprshell-test-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.home = self.root / 'desktop home'
        self.config = self.home / 'custom config'
        self.state = self.home / 'custom state'
        self.env = dict(os.environ, HOME=str(self.home), XDG_CONFIG_HOME=str(self.config),
                        XDG_STATE_HOME=str(self.state), PYTHONDONTWRITEBYTECODE='1')

    def run_setup(self, *args, check=True):
        env = self.env
        if '--config-only' in args and not shutil.which('Hyprland', path=env['PATH']):
            # Config-copy tests also run in CI without a native desktop runtime.
            version_bin = self.root / 'version fixture'
            version_bin.mkdir(exist_ok=True)
            hyprland = version_bin / 'Hyprland'
            hyprland.write_text("#!/bin/sh\nprintf '%s\\n' '{\"version\":\"0.56.2\"}'\n")
            hyprland.chmod(0o755)
            env = dict(env, PATH=str(version_bin) + os.pathsep + env['PATH'])
        return subprocess.run(['bash', str(ROOT / 'setup.sh'), '--distro', 'arch', *args],
                              env=env, text=True, capture_output=True, check=check)

    def test_config_only_rejects_old_hyprland_before_copying_on_both_distros(self):
        self.mock_package_database()
        mock_bin = Path(self.env['PATH'].split(os.pathsep)[0])
        hyprland = mock_bin / 'Hyprland'
        hyprland.write_text("#!/bin/sh\nprintf '%s\\n' '{\"version\":\"0.55.0\"}'\n")
        hyprland.chmod(0o755)
        for distro in ('arch', 'fedora'):
            result = subprocess.run(['bash', str(ROOT / 'setup.sh'), '--distro', distro,
                                     '--config-only'], env=self.env, text=True, capture_output=True)
            self.assertNotEqual(result.returncode, 0)
            self.assertIn('Hyprland 0.56+ is required', result.stderr)
            self.assertFalse(self.home.exists())

    def install(self):
        return self.run_setup('--config-only')

    def installer_backups(self):
        # Saved app choices may legitimately create a preference transaction
        # backup on a fresh machine, independently of installer replacements.
        root = self.state / 'hyprshell/backups'
        return [path for path in root.iterdir() if not path.name.startswith('applications-')] if root.exists() else []

    def test_preview_has_no_side_effects_for_both_modes_and_option_orders(self):
        for args in (('--dry-run',), ('--config-only', '--dry-run'),
                     ('--dry-run', '--config-only')):
            result = self.run_setup(*args)
            self.assertIn('Preview only', result.stdout)
            self.assertFalse(self.home.exists())

    def test_boot_splash_preview_and_opt_out(self):
        self.mock_package_database()
        result = self.run_setup('--dry-run')
        self.assertIn('Boot splash: restore saved Hyprshell Glass Plymouth theme', result.stdout)
        result = self.run_setup('--dry-run', '--skip-boot-splash')
        self.assertIn('Boot splash: leave boot configuration unchanged', result.stdout)
        result = self.run_setup('--config-only', '--dry-run')
        self.assertNotIn('Boot splash:', result.stdout)

    def test_login_theme_preview_and_opt_out(self):
        self.mock_package_database()
        result = self.run_setup('--dry-run')
        self.assertIn('Login appearance: restore Hyprshell Glass when SDDM', result.stdout)
        result = self.run_setup('--dry-run', '--skip-login-theme')
        self.assertIn('Login appearance: leave the existing theme unchanged', result.stdout)
        result = self.run_setup('--config-only', '--dry-run')
        self.assertNotIn('Login appearance:', result.stdout)
        self.assertFalse(self.home.exists())

    def test_disabled_login_manager_is_selected_without_installing_a_competitor(self):
        self.mock_package_database()
        mock_bin = Path(self.env['PATH'].split(os.pathsep)[0])
        controller = mock_bin / 'systemctl'
        controller.write_text('#!/bin/sh\nprintf "gdm.service disabled disabled\\n"\n')
        controller.chmod(0o755)
        repo = self.root / 'checkout'
        repo.mkdir()
        # Ignore the host's manager alias so the disabled-manager fixture wins.
        text = (ROOT / 'setup.sh').read_text().replace('/etc/systemd/system/display-manager.service', str(self.root / 'absent-manager'))
        (repo / 'setup.sh').write_text(text)
        for name in ('config', 'tools', 'packages.txt'):
            (repo / name).symlink_to(ROOT / name)
        result = subprocess.run(['bash', str(repo / 'setup.sh'), '--distro', 'arch', '--dry-run'], env=self.env, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('enable gdm.service', result.stdout)
        self.assertNotIn('install and enable SDDM', result.stdout)
        self.assertFalse(self.home.exists())

    def mock_package_database(self, missing=()):
        mock_bin = self.root / 'package commands'
        mock_bin.mkdir()
        calls = self.root / 'package-calls.jsonl'
        pacman = mock_bin / 'pacman'
        pacman.write_text(
            '#!/usr/bin/env python3\nimport json, sys\n'
            f'with open({str(calls)!r}, "a") as log:\n'
            '    log.write(json.dumps(sys.argv[1:]) + "\\n")\n'
            'if sys.argv[1] == "-Q": raise SystemExit(1)\n'
            'if sys.argv[1] != "-T": raise SystemExit("unexpected mutation")\n'
            f'missing = set({list(missing)!r})\n'
            'result = [p for p in sys.argv[2:] if p in missing]\n'
            'if result: print("\\n".join(result))\n'
            'raise SystemExit(127 if result else 0)\n')
        pacman.chmod(0o755)
        self.env['PATH'] = str(mock_bin) + os.pathsep + self.env['PATH']
        return calls

    def test_fresh_install_preview_checks_core_first_and_reports_missing_packages(self):
        calls = self.mock_package_database(('hyprland', 'quickshell', 'upower', 'wpa_supplicant'))
        result = self.run_setup('--dry-run')
        queries = [json.loads(line) for line in calls.read_text().splitlines()]
        self.assertIn(['-T', 'hyprland'], queries)
        self.assertIn(['-T', 'quickshell'], queries)
        self.assertIn('hyprland: missing', result.stdout)
        self.assertIn('quickshell: missing', result.stdout)
        self.assertIn('Missing desktop packages: hyprland quickshell wpa_supplicant upower', result.stdout)
        targets = queries[-1][1:]
        for required in ('hyprpolkitagent', 'qt6-wayland', 'gcc', 'libpulse', 'fftw',
                         'pipewire-pulse', 'upower', 'wpa_supplicant', 'ttf-go-nerd', 'cosmic-files', 'plymouth', 'chromium'):
            self.assertIn(required, targets)
        for unrelated in ('brave-bin', 'firefox', 'yay', 'waybar', 'mako',
                          'rofi', 'fuzzel', 'cosmic-greeter', 'base-devel',
                          'thunar', 'thunar-volman', 'thunar-archive-plugin'):
            self.assertNotIn(unrelated, targets)
        self.assertIn('Timezone: unchanged', result.stdout)
        self.assertIn('Login screen:', result.stdout)
        self.assertFalse(self.home.exists())

    def test_satisfied_dependencies_and_providers_are_kept(self):
        self.mock_package_database()
        result = self.run_setup('--dry-run')
        self.assertIn('hyprland: installed', result.stdout)
        self.assertIn('quickshell: installed', result.stdout)
        self.assertIn('All desktop packages are installed.', result.stdout)
        self.assertNotIn('Missing desktop packages:', result.stdout)

    def test_timezone_requires_explicit_option(self):
        calls = self.mock_package_database()
        result = self.run_setup('--dry-run',
                                '--timezone', 'Europe/London')
        targets = json.loads(calls.read_text().splitlines()[-1])[1:]
        self.assertIn('Login screen:', result.stdout)
        self.assertIn('Timezone: Europe/London', result.stdout)
        self.assertNotIn('brave-bin', result.stdout)
        self.assertFalse(self.home.exists())

    def test_package_database_failure_stops_before_installing(self):
        self.mock_package_database()
        mock_pacman = Path(self.env['PATH'].split(os.pathsep)[0]) / 'pacman'
        mock_pacman.write_text('#!/bin/sh\nexit 1\n')
        result = self.run_setup('--dry-run', check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Could not query', result.stderr)
        self.assertFalse(self.home.exists())

    def test_daily_driver_apps_are_included_and_shared_packages_are_unique(self):
        calls = self.mock_package_database(('hypridle', 'wl-clipboard'))
        result = self.run_setup('--dry-run', '--extra')
        targets = json.loads(calls.read_text().splitlines()[-1])[1:]
        for package in ('distrobox', 'hyprlock', 'hypridle', 'cmatrix', 'man-db',
                        'man-pages', 'bash-completion', 'unzip', 'zip', '7zip',
                        'file-roller', 'pacman-contrib', 'wl-clipboard', 'playerctl',
                        'xdg-utils', 'gvfs-mtp',
                        'mpv', 'loupe', 'papers', 'mousepad'):
            self.assertIn(package, targets)
        self.assertEqual(len(targets), len(set(targets)))
        self.assertIn('Missing desktop packages: hypridle wl-clipboard', result.stdout)
        self.assertFalse(self.home.exists())

    def test_config_only_with_apps_does_not_query_or_plan_packages(self):
        calls = self.mock_package_database()
        result = self.run_setup('--dry-run', '--config-only', '--extra')
        self.assertFalse(calls.exists())
        self.assertNotIn('Full Arch upgrade', result.stdout)
        self.assertFalse(self.home.exists())

    @unittest.skipUnless(Path('/etc/arch-release').is_file() and os.geteuid() != 0
                         and Path('/usr/lib/qt6/bin/qmltestrunner').is_file(),
                         'Full installer smoke test needs Arch, Qt 6, and a normal user')
    def test_full_install_with_mocked_packages_and_services_and_no_user_bus(self):
        self.mock_package_database(('hyprland', 'quickshell', 'wpa_supplicant', 'upower'))
        mock_bin = Path(self.env['PATH'].split(os.pathsep)[0])
        calls = self.root / 'system-calls.jsonl'
        # Never execute privileged operations, start services, or alter font caches.
        for name in ('sudo', 'systemctl', 'fc-cache', 'xdg-user-dirs-update', 'cosmic-files'):
            program = mock_bin / name
            program.write_text(
                '#!/usr/bin/env python3\nimport json, sys\n'
                f'with open({str(calls)!r}, "a") as log:\n'
                f'    log.write(json.dumps([{name!r}] + sys.argv[1:]) + "\\n")\n'
                'raise SystemExit(1 if sys.argv[1:] == ["--user", "daemon-reload"] else 0)\n')
            program.chmod(0o755)
        result = self.run_setup()
        commands = [json.loads(line) for line in calls.read_text().splitlines()]
        installs = [c for c in commands if c[:2] == ['sudo', 'pacman']]
        self.assertEqual(installs[0], ['sudo', 'pacman', '-Syu', '--needed', '--noconfirm',
                                     'hyprland', 'quickshell', 'wpa_supplicant', 'upower'])
        if ['sudo', 'pacman', '-S', '--needed', '--noconfirm', 'sddm'] in installs:
            self.assertIn(['sudo', 'systemctl', 'enable', 'sddm.service'], commands)
        self.assertIn(['sudo', 'systemctl', 'enable', '--now',
                       'NetworkManager.service', 'bluetooth.service'], commands)
        self.assertIn(['sudo', 'systemctl', 'start', 'upower.service'], commands)
        self.assertIn(['sudo', 'python3', str(ROOT / 'tools/install_boot_splash.py')], commands)
        self.assertIn(['systemctl', '--user', '--root=/', '--no-reload', 'enable',
                       'pipewire.socket', 'pipewire-pulse.socket', 'wireplumber.service'], commands)
        self.assertFalse(any('timedatectl' in c or 'cosmic-greeter' in c for c in commands))
        self.assertIn('will start at the next login', result.stdout)
        self.assertIn('Setup complete', result.stdout)
        self.assertTrue((self.config / 'quickshell/helpers/audio-spectrum').is_file())
        self.assertIn('float-modal-dialogs', (self.config / 'hyprshell/hyprland/windows.lua').read_text())

    def test_fresh_install_restores_saved_input_and_power_preferences(self):
        # A portable saved snapshot, installed into a completely isolated home.
        repo = self.root / 'saved repo'
        (repo / 'config/hyprshell').mkdir(parents=True)
        for entry in (ROOT / 'config').iterdir():
            if entry.name != 'hyprshell':
                (repo / 'config' / entry.name).symlink_to(entry)
        for entry in (ROOT / 'config/hyprshell').iterdir():
            if entry.name not in ('settings.json', 'behavior.json', 'behavior.lua'):
                if entry.is_dir():
                    shutil.copytree(entry, repo / 'config/hyprshell' / entry.name)
                else:
                    (repo / 'config/hyprshell' / entry.name).symlink_to(entry)
        saved = json.loads((ROOT / 'config/hyprshell/settings.json').read_text())
        saved['hyprland'].update(pointerSpeed=0.25, tapToClick=False,
                                 keyboardLayouts='us,gb', layoutSwitch='grp:alt_shift_toggle')
        saved['power'] = {'dimMinutes': 3, 'dimPercent': 20, 'offMinutes': 5, 'suspendMinutes': 10, 'lidAction': 'system', 'profile': 'system'}
        (repo / 'config/hyprshell/settings.json').write_text(json.dumps(saved))
        behavior = {'version': 1, 'general': {'layout': 'master'}, 'workspaces': [], 'rules': []}
        (repo / 'config/hyprshell/behavior.json').write_text(json.dumps(behavior))
        (repo / 'config/hyprshell/behavior.lua').write_text('error("do not install stale rules")')
        for name in ('bin', 'assets'):
            (repo / name).symlink_to(ROOT / name)
        subprocess.run(['python3', str(ROOT / 'tools/install_configs.py'), str(repo)],
                       env=self.env, capture_output=True, text=True, check=True)
        restored = json.loads((self.config / 'hyprshell/settings.json').read_text())
        self.assertTrue(all(restored['power'][key] == value for key, value in saved['power'].items()))
        self.assertIn('layout = "master"', (self.config / 'hyprshell/behavior.lua').read_text())
        self.assertNotIn('stale rules', (self.config / 'hyprshell/behavior.lua').read_text())
        generated = (self.config / 'hyprshell/overrides.lua').read_text()
        self.assertIn('sensitivity = 0.25', generated)
        self.assertIn('tap_to_click = false', generated)
        self.assertIn('kb_layout = "us,gb"', generated)
        if shutil.which('Hyprland'):
            verified = subprocess.run(['Hyprland', '--verify-config', '--config',
                                       str(self.config / 'hypr/hyprland.lua')],
                                      env=self.env, capture_output=True, text=True, timeout=15)
            self.assertIn('config ok', verified.stdout.lower(), verified.stdout + verified.stderr)

    def test_installs_current_payload_without_legacy_configs(self):
        self.install()
        import importlib.util
        spec = importlib.util.spec_from_file_location('installed_settings', self.config / 'quickshell/settings/backend.py')
        installed = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(installed)
        saved = json.loads((self.config / 'hyprshell/settings.json').read_text())
        self.assertEqual((self.config / 'hyprshell/overrides.lua').read_text(),
                         installed.render_hypr(saved['hyprland'], True))
        self.assertTrue(os.access(self.config / 'hypr/wallpaper-start.sh', os.X_OK))
        self.assertTrue((self.config / 'quickshell/shell.qml').is_file())
        self.assertEqual((self.config / 'kitty/kitty.conf').read_bytes(),
                         (ROOT / 'config/kitty/kitty.conf').read_bytes())
        self.assertEqual((self.config / 'kitty/clipboard_paste.py').read_bytes(),
                         (ROOT / 'config/kitty/clipboard_paste.py').read_bytes())
        for payload_file in ('SettingsSound.qml', 'SoundVolume.qml', 'SoundTest.qml', 'AudioInputMeter.qml', 'AudioSpectrumBars.qml', 'helpers/audio-spectrum.c', 'sounds/test.wav', 'SettingsRecovery.qml', 'settings/recovery.py'):
            self.assertEqual((self.config / 'quickshell' / payload_file).read_bytes(),
                             (ROOT / 'config/quickshell' / payload_file).read_bytes())
        self.assertEqual((self.config / 'autostart/nm-applet.desktop').read_bytes(),
                         (ROOT / 'config/autostart/nm-applet.desktop').read_bytes())
        self.assertIn('uwsm app -- cosmic-files',
                      (self.config / 'hyprshell/hyprland/programs.lua').read_text())
        for section in (ROOT / 'config/hyprshell/hyprland').iterdir():
            self.assertEqual((self.config / 'hyprshell/hyprland' / section.name).read_bytes(),
                             section.read_bytes())
        if shutil.which('Hyprland'):
            verified = subprocess.run(['Hyprland', '--verify-config', '--config',
                                       str(self.config / 'hypr/hyprland.lua')],
                                      env=self.env, capture_output=True, text=True, timeout=15)
            self.assertIn('config ok', verified.stdout.lower(), verified.stdout + verified.stderr)
        self.assertTrue(os.access(self.config / 'quickshell/helpers/audio-spectrum', os.X_OK))
        for script in ('app-launcher', 'start-quickshell-bar'):
            self.assertTrue(os.access(self.home / '.local/bin' / script, os.X_OK))
        for name in ('waybar', 'mako', 'rofi', 'fuzzel'):
            self.assertFalse((self.config / name).exists())
        self.assertEqual(len(list((self.home / 'Pictures/Wallpapers').glob('*.jpg'))), 1)
        self.assertEqual((self.home / 'Pictures/Wallpapers/default.jpg').read_bytes(),
                         (ROOT / 'assets/wallpapers/default.jpg').read_bytes())
        self.assertIn('Wallpapers/default.jpg',
                      (self.config / 'hypr/wallpaper-start.sh').read_text())
        self.assertEqual(len(self.installer_backups()), 1)
        self.assertEqual((self.state / "hyprshell/repository").read_text().strip(), str(ROOT))

    def test_rerun_keeps_identical_configs_without_unnecessary_backups(self):
        self.install()
        result = self.install()
        self.assertIn('Unchanged:', result.stdout)
        self.assertNotIn('Installed:', result.stdout)
        self.assertEqual(len(self.installer_backups()), 1)
        self.assertEqual((self.state / "hyprshell/repository").read_text().strip(), str(ROOT))

    def test_local_code_conflict_stops_without_overwriting_unrelated_files(self):
        self.install()
        style = self.config / 'hypr/hyprland.lua'
        style.write_text('-- user customization\n')
        unrelated = self.config / 'unrelated-app/settings'
        unrelated.parent.mkdir()
        unrelated.write_text('keep me')
        result = self.run_setup('--config-only', check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Local edits conflict', result.stderr)
        self.assertEqual(style.read_text(), '-- user customization\n')
        self.assertEqual(unrelated.read_text(), 'keep me')

    def test_symlink_config_requires_resolution_without_modifying_target(self):
        self.config.mkdir(parents=True)
        original = self.root / 'original hypr'
        original.mkdir()
        (original / 'hyprland.lua').write_text('keep original')
        (self.config / 'hypr').symlink_to(original, target_is_directory=True)
        result = self.run_setup('--config-only', check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('symbolic link', result.stderr)
        self.assertEqual((original / 'hyprland.lua').read_text(), 'keep original')
        self.assertTrue((self.config / 'hypr').is_symlink())

    def test_invalid_options_fail_before_installing(self):
        for args in (('--wat',), ('--timezone',)):
            self.assertNotEqual(self.run_setup(*args, check=False).returncode, 0)
        self.assertFalse(self.home.exists())


if __name__ == '__main__':
    unittest.main()
