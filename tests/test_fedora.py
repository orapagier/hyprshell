"""Fedora package and boot workflows; all privileged commands are mocked."""
import io
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import MagicMock, Mock, patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'config/quickshell/settings'))
sys.path.insert(0, str(ROOT / 'tools'))
import install_boot_splash as boot
import install_boot_splash_fedora as fedora_boot
import optional_tools
import power
import recovery
import system_packages


class FedoraPackagesTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(); self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        env = patch.dict(os.environ, HOME=str(self.root), XDG_CONFIG_HOME=str(self.root / 'config'),
                         XDG_STATE_HOME=str(self.root / 'state'), HYPRLAND_INSTANCE_SIGNATURE='')
        env.start(); self.addCleanup(env.stop)
        distro = patch.object(system_packages, 'distribution', return_value='fedora')
        distro.start(); self.addCleanup(distro.stop)

    def test_dnf_update_checks_handle_updates_empty_errors_and_malformed_output(self):
        data = {'Available upgrades': [{'name': 'kernel', 'arch': 'x86_64', 'evr': '6.20-1.fc44', 'repository': 'updates'}]}
        for code, output in ((100, json.dumps(data)), (0, ''), (1, ''), (100, 'invalid')):
            with patch.object(recovery.shutil, 'which', return_value='/usr/bin/dnf'), patch.object(recovery.subprocess, 'run', return_value=Mock(returncode=code, stdout=output)) as run:
                if code == 1 or output == 'invalid':
                    with self.assertRaises(ValueError): recovery.check_updates()
                else:
                    self.assertEqual(len(recovery.check_updates()['packages']), 1 if code == 100 else 0)
                self.assertEqual(run.call_args.args[0], ['dnf', '--refresh', '--quiet', 'check-upgrade', '--json'])
                self.assertEqual(run.call_args.kwargs['env']['LC_ALL'], 'C')
                self.assertNotIn('sudo', run.call_args.args[0])

    def test_interactive_upgrade_and_optional_tools_use_dnf(self):
        process = MagicMock(); process.__enter__.return_value = process
        process.stdout = ['Complete!\n']; process.wait.return_value = 0
        with patch('builtins.input', side_effect=['y', '']), patch.object(recovery.subprocess, 'Popen', return_value=process) as launch, patch('sys.stdout', io.StringIO()):
            self.assertEqual(recovery.upgrade_terminal(), 0)
            self.assertEqual(launch.call_args.args[0], ['sudo', 'dnf', 'upgrade', '--refresh'])
        with patch.object(optional_tools.shutil, 'which', return_value='/bin/kitty'), patch.object(optional_tools.subprocess, 'run', return_value=Mock(returncode=0)) as run:
            optional_tools.install('printing')
            args = run.call_args.args[0]
            self.assertIn('dnf', args); self.assertIn('sane-backends', args)
            self.assertNotIn('pacman', args); self.assertNotIn('sane', args)
        self.assertEqual(system_packages.install_command(['github-cli']), ['sudo', 'dnf', 'install', 'gh'])
        self.assertEqual(system_packages.metadata()['name'], 'Fedora')

    def test_tuned_profiles_use_dbus_without_powerprofilesctl(self):
        with patch.object(power, 'power_profile_property', side_effect=[
                [{'Profile': 'balanced'}, {'Profile': 'power-saver'}, {'Profile': 'unsupported'}], 'balanced']):
            self.assertEqual(power.profiles(), {'available': ['balanced', 'power-saver'], 'active': 'balanced'})
        with patch('backend.read_power', return_value={'profile': 'power-saver'}), patch.object(
                power, 'profiles', return_value={'available': ['balanced', 'power-saver'], 'active': 'balanced'}), patch.object(
                power, 'power_profile_property') as setter, patch.object(power, 'command') as command:
            power.apply_profile()
            setter.assert_called_once_with('ActiveProfile', 'power-saver')
            command.assert_not_called()

    @unittest.skipUnless(importlib.util.find_spec('gi'), 'GIO bindings are required for Fedora power profiles')
    def test_tuned_dbus_property_arguments_unpacking_and_errors(self):
        from gi.repository import Gio, GLib
        connection = Mock()
        rows = GLib.Variant('aa{sv}', [{'Profile': GLib.Variant('s', 'balanced')}])
        connection.call_sync.return_value = GLib.Variant('(v)', (rows,))
        with patch.object(Gio, 'bus_get_sync', return_value=connection):
            self.assertEqual(power.power_profile_property('Profiles'), [{'Profile': 'balanced'}])
            args = connection.call_sync.call_args.args
            self.assertEqual(args[:4], ('net.hadess.PowerProfiles', '/net/hadess/PowerProfiles', 'org.freedesktop.DBus.Properties', 'Get'))
            self.assertEqual(args[4].unpack(), ('net.hadess.PowerProfiles', 'Profiles'))
            self.assertEqual(args[7], 5000)
            power.power_profile_property('ActiveProfile', 'power-saver')
            args = connection.call_sync.call_args.args
            self.assertEqual(args[3], 'Set')
            self.assertEqual(args[4].unpack(), ('net.hadess.PowerProfiles', 'ActiveProfile', 'power-saver'))
            connection.call_sync.side_effect = GLib.Error('Access denied')
            with self.assertRaisesRegex(ValueError, 'tuned-ppd'):
                power.power_profile_property('ActiveProfile')


class FedoraBootTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(); self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        for name, text in {'etc/fedora-release': 'Fedora 44', 'usr/lib64/plymouth/script.so': '',
                           'boot/vmlinuz-6.20': 'kernel', 'boot/initramfs-6.20.img': 'image',
                           'boot/loader/entries/local.conf': 'options root=UUID=local rd.luks.uuid=local rhgb quiet\n'}.items():
            target = self.root / name; target.parent.mkdir(parents=True, exist_ok=True); target.write_text(text)

    def test_dracut_plan_preserves_kernel_parameters_and_rolls_back_on_failure(self):
        entry = self.root / 'boot/loader/entries/local.conf'
        before = entry.read_bytes()
        plan, commands, outputs = fedora_boot.build_plan(self.root)
        self.assertEqual(commands[-1], ['dracut', '--regenerate-all', '--force'])
        self.assertEqual(commands[0][:2], ['restorecon', '-RF'])
        self.assertEqual(outputs, {self.root / 'boot/initramfs-6.20.img'})
        self.assertNotIn(entry, plan)
        self.assertIn('plymouth', plan[self.root / 'etc/dracut.conf.d/90-hyprshell-plymouth.conf'])
        runner = Mock(side_effect=[Mock(returncode=0), subprocess.CalledProcessError(1, commands[-1])])
        with patch('sys.stdout', io.StringIO()), self.assertRaises(subprocess.CalledProcessError):
            boot.apply_plan(plan, commands, outputs, self.root / 'backups', runner=runner)
        self.assertEqual(entry.read_bytes(), before)
        self.assertFalse((self.root / 'etc/plymouth/plymouthd.conf').exists())
        self.assertEqual([call.args[0] for call in runner.call_args_list], commands)

    def test_atomic_custom_boot_and_symlinked_targets_are_rejected(self):
        atomic = self.root / 'run/ostree-booted'; atomic.parent.mkdir(); atomic.touch()
        with self.assertRaises(boot.UnsupportedBoot): fedora_boot.build_plan(self.root)
        atomic.unlink()
        directory = self.root / 'etc/dracut.conf.d'; directory.symlink_to(self.root / 'boot')
        with self.assertRaises(boot.UnsupportedBoot): fedora_boot.build_plan(self.root)
        directory.unlink()
        (self.root / 'boot/initramfs-6.20.img').unlink()
        with self.assertRaises(boot.UnsupportedBoot): fedora_boot.build_plan(self.root)

    def test_boot_cli_distinguishes_unsupported_layout_from_rebuild_failure(self):
        with patch('sys.argv', ['install_boot_splash_fedora.py']), \
             patch.object(fedora_boot, 'build_plan', side_effect=boot.UnsupportedBoot('custom layout')), \
             patch('sys.stderr', io.StringIO()), self.assertRaises(SystemExit) as skipped:
            fedora_boot.main()
        self.assertEqual(skipped.exception.code, 10)
        with patch('sys.argv', ['install_boot_splash_fedora.py']), \
             patch.object(fedora_boot, 'build_plan', return_value=({}, [], set())), \
             patch.object(fedora_boot.os, 'geteuid', return_value=0), \
             patch.object(fedora_boot, 'apply_plan', side_effect=subprocess.CalledProcessError(1, ['dracut'])), \
             patch('sys.stderr', io.StringIO()), self.assertRaises(SystemExit) as failed:
            fedora_boot.main()
        self.assertEqual(failed.exception.code, 1)


class FedoraInstallerTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(); self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name); self.home = self.root / 'isolated home'
        self.bin = self.root / 'commands'; self.bin.mkdir()
        self.calls = self.root / 'calls.jsonl'
        self.env = dict(os.environ, HOME=str(self.home), XDG_CONFIG_HOME=str(self.home / 'config'),
                        XDG_STATE_HOME=str(self.home / 'state'), XDG_DATA_HOME=str(self.home / 'data'),
                        PATH=str(self.bin) + os.pathsep + os.environ['PATH'])
        self.repo = ROOT
        self.program('systemctl', 'raise SystemExit(0)')
        self.program('rpm', 'raise SystemExit(1)')

    def program(self, name, body):
        target = self.bin / name
        target.write_text('#!' + sys.executable + '\nimport json, os, sys\n'
                          f'with open({str(self.calls)!r}, "a") as log: log.write(json.dumps([{name!r}] + sys.argv[1:]) + "\\n")\n' + body + '\n')
        target.chmod(0o755)

    def run_setup(self, *args):
        return subprocess.run(['bash', str(self.repo / 'setup.sh'), '--distro', 'fedora', *args],
                              env=self.env, capture_output=True, text=True, timeout=45)

    def read_calls(self):
        return [json.loads(line) for line in self.calls.read_text().splitlines()]

    def test_preview_selects_fedora_packages_without_mutation(self):
        result = self.run_setup('--dry-run', '--extra', '--copr', 'lionheartp/Hyprland')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('Full Fedora upgrade', result.stdout)
        self.assertIn('NetworkManager-wifi', result.stdout); self.assertIn('tuned-ppd', result.stdout)
        self.assertIn('hyprland-uwsm', result.stdout); self.assertIn('chromium', result.stdout)
        self.assertNotIn('firefox', result.stdout); self.assertNotIn('pacman-contrib', result.stdout)
        self.assertIn('dracut', result.stdout)
        self.assertFalse(self.home.exists())
        self.assertTrue(all(call[0] in ('rpm', 'systemctl') for call in self.read_calls()))

    @unittest.skipIf(os.geteuid() == 0, 'Installer correctly refuses root')
    def test_full_fedora_flow_and_preflight_failure_with_mocked_system_commands(self):
        # Distro detection uses an isolated os-release fixture. The actual
        # config installer builds its helper and copies payload into a temp home.
        self.repo = self.root / 'checkout'; self.repo.mkdir()
        release = self.root / 'os-release'; release.write_text('ID=fedora\nVERSION_ID=44\n')
        (self.repo / 'setup.sh').write_text((ROOT / 'setup.sh').read_text().replace('/etc/os-release', str(release)))
        for name in ('config', 'tools', 'bin', 'assets', 'packages.txt', 'packages-fedora.txt', 'packages-apps-fedora.txt', 'compatibility.json'):
            (self.repo / name).symlink_to(ROOT / name)
        real_python = sys.executable
        runner = self.bin / 'qmltestrunner-qt6'
        self.program('qmltestrunner-qt6', 'raise SystemExit(0)')
        self.program('python3', f'''if sys.argv[1].endswith('/compatibility.py'): raise SystemExit(0)
if sys.argv[1].endswith('/check_runtime.py'):
    if '--qmltestrunner' in sys.argv: print({str(runner)!r})
    raise SystemExit(0)
os.execv({real_python!r}, [{real_python!r}, *sys.argv[1:]])''')
        for name in ('sudo', 'dnf', 'fc-cache', 'xdg-user-dirs-update'):
            self.program(name, "raise SystemExit(1 if os.environ.get('FAIL_PREFLIGHT') and '--downloadonly' in sys.argv else 0)")
        self.program('Hyprland', "print(json.dumps({'version': '0.56.2'}) if '--version-json' in sys.argv else 'config ok')")
        self.env['FAIL_PREFLIGHT'] = '1'
        result = self.run_setup('--copr', 'lionheartp/Hyprland')
        self.assertNotEqual(result.returncode, 0); self.assertFalse(self.home.exists())
        self.assertFalse(any(call[:3] == ['sudo', 'dnf', 'upgrade'] for call in self.read_calls()))
        self.env.pop('FAIL_PREFLIGHT'); self.calls.unlink()
        result = self.run_setup('--copr', 'lionheartp/Hyprland')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        calls = self.read_calls()
        self.assertIn(['sudo', 'dnf', 'copr', 'enable', '-y', 'lionheartp/Hyprland'], calls)
        self.assertIn(['sudo', 'dnf', 'upgrade', '--refresh', '-y'], calls)
        manager = Path('/etc/systemd/system/display-manager.service')
        if manager.exists() or manager.is_symlink():
            self.assertNotIn(['sudo', 'dnf', 'install', '-y', '--setopt=install_weak_deps=False', 'sddm', 'sddm-x11'], calls)
        else:
            self.assertTrue(any(call[:3] == ['sudo', 'dnf', 'install'] and 'sddm' in call and 'sddm-x11' in call for call in calls))
        self.assertIn(['sudo', 'systemctl', 'enable', '--now', 'tuned.service', 'tuned-ppd.service'], calls)
        self.assertIn(['sudo', 'python3', str(self.repo / 'tools/configure_daily_driver.py')], calls)
        service_index = next(i for i, call in enumerate(calls) if call[:4] == ['sudo', 'systemctl', 'enable', '--now'])
        validation_index = next(i for i, call in enumerate(calls) if call[0] == 'python3' and call[1].endswith('/check_runtime.py'))
        self.assertLess(service_index, validation_index)
        self.assertIn(['sudo', 'python3', str(self.repo / 'tools/install_boot_splash_fedora.py')], calls)
        self.assertFalse(any('pacman' in call or 'mkinitcpio' in call for call in calls))
        self.assertTrue((self.home / 'data/fonts/hyprshell/GoMonoNerdFont-Regular.ttf').is_file())
        self.assertTrue((self.home / 'config/quickshell/helpers/audio-spectrum').is_file())

    def test_invalid_repository_names_fail_without_files(self):
        for repo in ('../unsafe', 'owner/repo;command', '-owner/repo', 'missing-slash'):
            self.assertNotEqual(self.run_setup('--dry-run', '--copr', repo).returncode, 0)
        self.assertFalse(self.home.exists())

    def test_default_repository_and_explicit_opt_out_are_preview_only(self):
        default = self.run_setup('--dry-run')
        self.assertEqual(default.returncode, 0, default.stderr)
        self.assertIn('COPR: lionheartp/Hyprland', default.stdout)
        opted_out = self.run_setup('--dry-run', '--no-copr')
        self.assertEqual(opted_out.returncode, 0, opted_out.stderr)
        self.assertIn('COPR: preserve enabled repositories', opted_out.stdout)
        self.assertFalse(self.home.exists())
        self.assertTrue(all(call[0] in ('rpm', 'systemctl') for call in self.read_calls()))

    @unittest.skipIf(os.geteuid() == 0, 'Installer correctly refuses root')
    def test_older_hyprland_is_rejected_before_config_replacement(self):
        self.program('Hyprland', "print(json.dumps({'version': '0.55.0'}))")
        result = self.run_setup('--config-only')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('Hyprland 0.56+', result.stderr)
        self.assertFalse(self.home.exists())


if __name__ == '__main__':
    unittest.main()
