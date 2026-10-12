"""Exercise boot restoration in isolated filesystems, never touching real boot files."""
import importlib.util
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import Mock, patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('boot_splash', ROOT / 'tools/install_boot_splash.py')
boot = importlib.util.module_from_spec(spec)
spec.loader.exec_module(boot)
PREFERENCE = json.loads((ROOT / 'config/boot/plymouth.json').read_text())


class BootSplashTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix='hyprshell-boot-test-')
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.put('/etc/mkinitcpio.conf', 'MODULES=(i915)\nHOOKS=(base udev autodetect kms keyboard encrypt lvm2 block filesystems fsck)\n')
        self.put('/etc/plymouth/plymouthd.conf', '# keep this comment\n[Daemon]\nTheme=bgrt\nShowDelay=0\n')
        self.put('/etc/mkinitcpio.d/linux.preset', 'ALL_kver="/boot/vmlinuz-linux"\nPRESETS=(\'default\')\ndefault_uki="/boot/EFI/Linux/arch-linux.efi"\ndefault_options="--splash /usr/share/systemd/bootctl/splash-arch.bmp"\n')
        self.put('/etc/kernel/cmdline', 'root=UUID=this-machine rw cryptdevice=UUID=encrypted:root resume=UUID=swap loglevel=7\n')
        self.put('/boot/EFI/Linux/arch-linux.efi', 'existing image')

    def test_cli_distinguishes_unsupported_layout_from_rebuild_failure(self):
        with patch('sys.argv', ['install_boot_splash.py']), patch.object(Path, 'is_file', return_value=True), \
             patch.object(boot, 'build_plan', side_effect=boot.UnsupportedBoot('custom layout')), \
             patch('sys.stderr', io.StringIO()), self.assertRaises(SystemExit) as skipped:
            boot.main()
        self.assertEqual(skipped.exception.code, 10)
        with patch('sys.argv', ['install_boot_splash.py']), patch.object(Path, 'is_file', return_value=True), \
             patch.object(boot, 'build_plan', return_value=({}, [], set())), \
             patch.object(boot.os, 'geteuid', return_value=0), \
             patch.object(boot, 'apply_plan', side_effect=subprocess.CalledProcessError(1, ['mkinitcpio', '-P'])), \
             patch('sys.stderr', io.StringIO()), self.assertRaises(SystemExit) as failed:
            boot.main()
        self.assertEqual(failed.exception.code, 1)

    def path(self, name):
        return self.root / name.lstrip('/')

    def put(self, name, text):
        target = self.path(name)
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text)
        return target

    def plan(self):
        return boot.build_plan(self.root, PREFERENCE)

    def apply(self, runner=None):
        plan, commands, outputs = self.plan()
        boot.apply_plan(plan, commands, outputs, self.path('/backups'), runner or Mock())
        return plan

    def classic_preset(self):
        self.put('/etc/mkinitcpio.d/linux.preset', 'ALL_kver="/boot/vmlinuz-linux"\nPRESETS=(default fallback)\ndefault_image="/boot/initramfs-linux.img"\nfallback_image="/boot/initramfs-linux-fallback.img"\nfallback_options="-S autodetect"\n')

    def test_uki_preserves_local_disk_encryption_modules_and_hooks(self):
        plan, commands, outputs = self.plan()
        self.assertEqual(commands, [['mkinitcpio', '-P']])
        self.assertEqual(outputs, {self.path('/boot/EFI/Linux/arch-linux.efi')})
        hooks = plan[self.path('/etc/mkinitcpio.conf')]
        self.assertIn('MODULES=(i915)', hooks)
        self.assertIn('udev plymouth autodetect', hooks)
        self.assertIn('keyboard encrypt lvm2 block filesystems fsck', hooks)
        cmdline = plan[self.path('/etc/kernel/cmdline')]
        self.assertEqual(cmdline, 'root=UUID=this-machine rw cryptdevice=UUID=encrypted:root resume=UUID=swap quiet splash loglevel=3\n')
        self.assertIn('Theme=hyprshell\nShowDelay=0', plan[self.path('/etc/plymouth/plymouthd.conf')])

    def test_systemd_encryption_and_multiline_hooks_are_preserved(self):
        self.put('/etc/mkinitcpio.conf', 'HOOKS=(\n base systemd # encrypted installation\n autodetect kms keyboard sd-vconsole sd-encrypt filesystems fsck\n)\n')
        plan, _, _ = self.plan()
        hooks = plan[self.path('/etc/mkinitcpio.conf')]
        self.assertIn('base systemd plymouth autodetect', hooks)
        self.assertIn('sd-vconsole sd-encrypt filesystems', hooks)

    def test_hook_dropins_are_updated_without_losing_their_settings(self):
        self.put('/etc/mkinitcpio.conf.d/10-local.conf', 'HOOKS=(base systemd autodetect kms keyboard sd-encrypt filesystems)\nCOMPRESSION="zstd"\n')
        plan, _, _ = self.plan()
        self.assertIn('systemd plymouth autodetect', plan[self.path('/etc/mkinitcpio.conf.d/10-local.conf')])
        self.assertIn('COMPRESSION="zstd"', plan[self.path('/etc/mkinitcpio.conf.d/10-local.conf')])

    def test_fresh_uki_uses_current_machine_cmdline_only_when_no_file_exists(self):
        self.path('/etc/kernel/cmdline').unlink()
        self.put('/proc/cmdline', 'BOOT_IMAGE=/vmlinuz-linux initrd=/initramfs-linux.img root=UUID=new-laptop rw\n')
        plan, _, _ = self.plan()
        self.assertEqual(plan[self.path('/etc/kernel/cmdline')], 'root=UUID=new-laptop rw quiet splash loglevel=3\n')

    def test_custom_uki_cmdline_and_inactive_fallback_are_handled(self):
        preset = self.path('/etc/mkinitcpio.d/linux.preset')
        preset.write_text(preset.read_text() + 'default_cmdline="/etc/kernel/local-cmdline"\nfallback_uki="/boot/fallback.efi"\n')
        self.put('/etc/kernel/local-cmdline', 'root=UUID=custom rw\n')
        plan, _, outputs = self.plan()
        self.assertNotIn(self.path('/etc/kernel/cmdline'), plan)
        self.assertIn('root=UUID=custom rw quiet splash', plan[self.path('/etc/kernel/local-cmdline')])
        self.assertNotIn(self.path('/boot/fallback.efi'), outputs)

    def test_uki_replaces_arch_logo_preserves_options_and_leaves_loader_untouched(self):
        preset = self.path('/etc/mkinitcpio.d/linux.preset')
        preset.write_text('PRESETS=(default)\ndefault_uki="/boot/EFI/Linux/arch-linux.efi"\ndefault_options="-S autodetect --splash=/usr/share/systemd/bootctl/splash-arch.bmp"\nfallback_uki="/boot/fallback.efi"\nfallback_options="--splash /local/fallback.bmp"\n')
        loader = self.put('/boot/loader/loader.conf', 'default arch-linux.efi\ntimeout 5\n')
        plan, commands, _ = self.plan()
        options = boot.preset_values(plan[preset])
        self.assertEqual(options['default_options'], '-S autodetect --splash /usr/share/hyprshell/uki-splash.bmp')
        self.assertEqual(options['fallback_options'], '--splash /local/fallback.bmp')
        self.assertNotIn(loader, plan)
        self.assertEqual(commands, [['mkinitcpio', '-P']])
        bmp = plan[self.path('/usr/share/hyprshell/uki-splash.bmp')]
        self.assertEqual(bmp[:2], b'BM')

    def test_uki_options_array_and_splash_path_with_spaces_are_preserved(self):
        text = 'PRESETS=(default)\ndefault_uki="/boot/linux.efi"\ndefault_options=(\n-S autodetect --splash "/local/old splash.bmp"\n)\n'
        updated, used = boot.uki_splash_options(text, boot.preset_values(text), ['default'])
        self.assertTrue(used)
        self.assertEqual(boot.preset_values(updated)['default_options'], '-S autodetect --splash /usr/share/hyprshell/uki-splash.bmp')

    def test_uki_splash_can_be_disabled_and_malformed_options_stop_before_writes(self):
        preference = dict(PREFERENCE, uki_splash=False)
        plan, _, _ = boot.build_plan(self.root, preference)
        self.assertNotIn(self.path('/etc/mkinitcpio.d/linux.preset'), plan)
        self.assertNotIn(self.path('/usr/share/hyprshell/uki-splash.bmp'), plan)
        for options in ('--splash', '--splash -S autodetect'):
            text = 'PRESETS=(default)\ndefault_uki="/boot/linux.efi"\ndefault_options="' + options + '"\n'
            with self.assertRaises(boot.UnsupportedBoot):
                boot.uki_splash_options(text, boot.preset_values(text), ['default'])

    def test_grub_preserves_existing_default_and_encryption_options(self):
        self.classic_preset()
        self.put('/etc/default/grub', 'GRUB_TIMEOUT=3\nGRUB_CMDLINE_LINUX="cryptdevice=UUID=local:root"\nGRUB_CMDLINE_LINUX_DEFAULT="resume=UUID=swap loglevel=7 splash"\n')
        self.put('/boot/grub/grub.cfg', 'existing grub configuration')
        plan, commands, _ = self.plan()
        self.assertEqual(commands[-1], ['grub-mkconfig', '-o', str(self.path('/boot/grub/grub.cfg'))])
        grub = plan[self.path('/etc/default/grub')]
        self.assertIn('GRUB_TIMEOUT=3', grub)
        self.assertIn('GRUB_CMDLINE_LINUX="cryptdevice=UUID=local:root"', grub)
        self.assertIn("GRUB_CMDLINE_LINUX_DEFAULT='resume=UUID=swap quiet splash loglevel=3'", grub)

    def test_systemd_boot_updates_only_entries_using_our_kernel_and_initramfs(self):
        self.classic_preset()
        for mount in ('/boot', '/efi', '/boot/efi'):
            self.put(mount + '/loader/entries/arch.conf', 'title Arch Linux\nlinux /vmlinuz-linux\ninitrd /intel-ucode.img\ninitrd /initramfs-linux.img\noptions root=UUID=this-install rw\n')
        other = self.put('/boot/loader/entries/other.conf', 'title Other Linux\nlinux /vmlinuz-other\ninitrd /initramfs-other.img\noptions root=UUID=other\n')
        plan, commands, _ = self.plan()
        self.assertNotIn(other, plan)
        self.assertNotIn(self.path('/etc/kernel/cmdline'), plan)
        self.assertEqual(commands, [['mkinitcpio', '-P']])
        for mount in ('/boot', '/efi', '/boot/efi'):
            self.assertIn('options root=UUID=this-install rw quiet splash loglevel=3',
                          plan[self.path(mount + '/loader/entries/arch.conf')])

    def test_unknown_bootloader_is_rejected_before_writes(self):
        self.classic_preset()
        before = self.path('/etc/mkinitcpio.conf').read_bytes()
        with self.assertRaises(boot.UnsupportedBoot):
            self.plan()
        self.assertEqual(self.path('/etc/mkinitcpio.conf').read_bytes(), before)

    def test_dynamic_hooks_and_custom_presets_are_rejected(self):
        for content in ('HOOKS=($LOCAL_HOOKS)\n', 'HOOKS+=(plymouth)\n', 'HOOKS="base udev"\n'):
            with self.subTest(content=content):
                self.put('/etc/mkinitcpio.conf', content)
                with self.assertRaises(boot.UnsupportedBoot):
                    self.plan()
        self.put('/etc/mkinitcpio.conf', 'HOOKS=(base udev filesystems)\n')
        for content in ('ALL_config="/etc/custom-mkinitcpio.conf"\n',
                        'default_options="--cmdline /etc/custom"\n',
                        'if true; then\n default_uki="/boot/custom.efi"\nfi\n'):
            with self.subTest(content=content):
                original = self.path('/etc/mkinitcpio.d/linux.preset').read_text()
                self.path('/etc/mkinitcpio.d/linux.preset').write_text(original + content)
                with self.assertRaises(boot.UnsupportedBoot):
                    self.plan()
                self.path('/etc/mkinitcpio.d/linux.preset').write_text(original)

    def test_cmdline_dropins_and_symlinked_config_are_rejected(self):
        dropin = self.put('/etc/cmdline.d/local.conf', 'loglevel=7\n')
        with self.assertRaises(boot.UnsupportedBoot):
            self.plan()
        dropin.unlink()
        cmdline = self.path('/etc/kernel/cmdline')
        saved = cmdline.read_text()
        cmdline.unlink()
        target = self.put('/etc/kernel/managed-cmdline', saved)
        cmdline.symlink_to(target)
        with self.assertRaises(boot.UnsupportedBoot):
            self.plan()
        self.assertEqual(target.read_text(), saved)

    def test_apply_backs_up_originals_and_rerun_makes_no_changes(self):
        original = self.path('/etc/kernel/cmdline').read_text()
        runner = Mock()
        self.apply(runner)
        runner.assert_called_once_with(['mkinitcpio', '-P'], check=True)
        backups = list(self.path('/backups').glob('*/**/cmdline'))
        self.assertEqual(len(backups), 1)
        self.assertEqual(backups[0].read_text(), original)
        runner.reset_mock()
        self.apply(runner)
        runner.assert_not_called()
        self.assertEqual(len(list(self.path('/backups').iterdir())), 1)

    def test_failed_rebuild_restores_configuration_and_removes_created_files(self):
        self.path('/etc/kernel/cmdline').unlink()
        self.put('/proc/cmdline', 'root=UUID=local rw\n')
        original = self.path('/etc/mkinitcpio.conf').read_text()
        runner = Mock(side_effect=subprocess.CalledProcessError(1, ['mkinitcpio', '-P']))
        with self.assertRaises(subprocess.CalledProcessError):
            self.apply(runner)
        self.assertEqual(self.path('/etc/mkinitcpio.conf').read_text(), original)
        self.assertFalse(self.path('/etc/kernel/cmdline').exists())
        self.assertIn('Theme=bgrt', self.path('/etc/plymouth/plymouthd.conf').read_text())

    def test_readonly_boot_destination_stops_before_writes(self):
        original = self.path('/etc/mkinitcpio.conf').read_text()
        runner = Mock()
        with patch.object(boot.os, 'access', return_value=False):
            with self.assertRaises(OSError):
                self.apply(runner)
        runner.assert_not_called()
        self.assertFalse(self.path('/backups').exists())
        self.assertEqual(self.path('/etc/mkinitcpio.conf').read_text(), original)

    def test_quoted_kernel_values_are_preserved(self):
        value = 'root=UUID=local rw acpi_osi="Windows 2020" quiet loglevel=7'
        self.assertEqual(boot.add_parameters(value, PREFERENCE['kernel_parameters']),
                         'root=UUID=local rw acpi_osi="Windows 2020" quiet splash loglevel=3')

    def test_bundled_assets_are_installed_and_asset_changes_trigger_rebuild(self):
        runner = Mock()
        self.apply(runner)
        title = self.path('/usr/share/plymouth/themes/hyprshell/title.png')
        self.assertEqual(title.read_bytes(),
                         (ROOT / 'config/boot/hyprshell/title.png').read_bytes())
        self.assertFalse(self.path('/usr/share/plymouth/themes/hyprshell/sources').exists())
        title.write_bytes(b'old title')
        runner.reset_mock()
        self.apply(runner)
        runner.assert_called_once_with(['mkinitcpio', '-P'], check=True)
        backups = list(self.path('/backups').glob('*/**/hyprshell/title.png'))
        self.assertEqual([item.read_bytes() for item in backups], [b'old title'])

    def test_failed_rebuild_restores_binary_assets_and_selected_theme(self):
        self.apply()
        title = self.path('/usr/share/plymouth/themes/hyprshell/title.png')
        title.write_bytes(b'original binary\x00\xff')
        runner = Mock(side_effect=subprocess.CalledProcessError(1, ['mkinitcpio', '-P']))
        with self.assertRaises(subprocess.CalledProcessError):
            self.apply(runner)
        self.assertEqual(title.read_bytes(), b'original binary\x00\xff')
        self.assertIn('Theme=hyprshell', self.path('/etc/plymouth/plymouthd.conf').read_text())

    def test_symlinked_theme_directory_is_rejected_before_writes(self):
        theme = self.path('/usr/share/plymouth/themes/hyprshell')
        theme.parent.mkdir(parents=True)
        destination = self.path('/other-theme')
        destination.mkdir()
        theme.symlink_to(destination, target_is_directory=True)
        with self.assertRaises(boot.UnsupportedBoot):
            self.plan()
        self.assertEqual(list(destination.iterdir()), [])


if __name__ == '__main__':
    unittest.main()
