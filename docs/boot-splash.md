# Hyprshell Glass boot splash

Full `./setup.sh` installs Plymouth and restores the preference in
`config/boot/plymouth.json`: the bundled `hyprshell` script theme, with
`quiet splash loglevel=3`. The splash starts during Linux boot and continues
toward the login screen. Firmware and bootloader screens are separate; a brief
message or transition can still appear. Press Esc to see Plymouth boot details.

Active UKI presets also receive a static matching glass BMP instead of the Arch
logo embedded by `--splash .../splash-arch.bmp`. The existing systemd-boot menu
and bootloader stay unchanged. SDDM can use the same animated artwork; see
[login and startup appearance](login-appearance.md) for combined installation
and the limits of the handoff.

![Hyprshell Glass preview](assets/boot-splash-preview.png)

The theme matches the shell's dark glass menus: a translucent rounded card,
lavender/cyan lighting, a fine reflective rim, gently floating and breathing
Fedora lettering, and the description “A calm space. A fluid desktop.”
The bar follows Plymouth's estimated boot progress with smooth interpolation
and a moving highlight. It adds no artificial wait and displays no invented
percentage. Passwords are masked; question prompts and boot messages remain
visible. Shutdown uses “Until next time.”

Glass and typography are rendered into small PNG layers ahead of time. No
desktop compositor, wallpaper service, or session font is needed during boot.
The theme scales with the display and uses the same assets at other resolutions.
Open [the animated preview](boot-splash-preview.html) locally to review the
motion and prompt layouts without starting a real Plymouth daemon.

The boot helper supports standard **mkinitcpio** configurations with:

- Unified kernel images (UKIs), including this laptop's setup. Parameters go
  into `/etc/kernel/cmdline` or an explicitly configured preset command-line file.
- GRUB using `/etc/default/grub` and `/boot/grub/grub.cfg`.
- systemd-boot entries under `/boot`, `/efi`, or `/boot/efi`, where both the
  kernel and initramfs match the local mkinitcpio presets.

It inserts `plymouth` immediately after `udev` or `systemd`, retaining the
machine's other hooks, graphics modules, root disk, encryption, resume, and
other kernel parameters. Boot settings are derived on the destination machine;
disk UUIDs, partition IDs, generated boot images, and encryption details are
never copied into Git. The existing bootloader remains in place.

Run this on an already configured machine without reinstalling the desktop:

```bash
sudo python3 tools/install_boot_splash.py --dry-run
sudo python3 tools/install_boot_splash.py
```

The helper inspects the complete plan before writing, backs up changed files
under `/var/lib/hyprshell/boot-backups/`, and runs `mkinitcpio -P`. For GRUB it
also regenerates `/boot/grub/grub.cfg`. A rerun with unchanged configuration
does not rewrite files or rebuild images.

Bundled theme files go into `/usr/share/plymouth/themes/hyprshell/` before the
rebuild, in the same backup/rollback transaction as the configuration. Changed
PNG or script assets also trigger a rebuild. Sources under
`config/boot/hyprshell/sources/` stay in the repository; they are not installed
in the initramfs. To edit the artwork, change the SVG sources and run
`python3 tools/render_boot_theme.py` (requires `rsvg-convert` and Noto Sans).
Then rerun the boot helper to install the updated assets and rebuild the image.
Run `python3 tools/render_login_theme.py` as well to refresh shared login assets
and the static UKI BMP (requires `ffmpeg`). The BMP is installed under
`/usr/share/hyprshell/uki-splash.bmp`; it is embedded by mkinitcpio rather than
copied into the Plymouth theme.

The helper requires administrator access. A sandbox that only allows home
directory writes can prepare and preview this change, but cannot activate the
root-owned theme or regenerate the kernel image. Run the install command in a
normal terminal, wait for a successful rebuild, and check the handoff on reboot.

If rebuilding fails, the edited configuration is restored. Generated images
may have been partially updated: complete `sudo mkinitcpio -P` successfully
before rebooting, and regenerate GRUB if its rebuild failed. The original
configuration files remain in the printed backup directory.

Other initramfs generators such as dracut, other bootloaders, dynamic shell
presets/hooks, custom mkinitcpio config paths, symlinked config files, and UKI
command-line drop-in directories need manual integration. These layouts stop
before any boot configuration is written. To install the desktop while leaving
boot configuration unchanged:

```bash
./setup.sh --skip-boot-splash
```

`--config-only` also leaves system boot configuration unchanged. A new Arch
installation needs an already working bootloader, a writable boot partition,
and graphics drivers supporting early modesetting. The actual animation and
handoff should be checked after reboot on each machine.

Upstream references: [Plymouth](https://wiki.archlinux.org/title/Plymouth),
[silent boot](https://wiki.archlinux.org/title/Silent_boot), and
[unified kernel images](https://wiki.archlinux.org/title/Unified_kernel_image).
