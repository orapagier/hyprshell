# Hyprshell Glass login and startup appearance

SDDM uses the same dark glass background, lavender/cyan lighting, gently floating
Fedora lettering, and pulsing title glow as the Plymouth splash. The taller
card holds the user picker (also accepts a typed username), masked password,
desktop session, keyboard layout, and power actions. Enter signs in; failed
authentication clears the password and returns focus to its field. The theme
requires SDDM's Qt 6 greeter and Qt Quick Controls, with no compositor or
third-party QML effects.

![Hyprshell Glass login preview](assets/login-preview.png)

On a machine already running Hyprshell, install the login theme and replace the
early kernel-image logo together:

```bash
sudo python3 ~/repos/hyprshell/tools/install_login_theme.py --with-boot-splash --dry-run
sudo python3 ~/repos/hyprshell/tools/install_login_theme.py --with-boot-splash
```

The combined helper inspects both plans before writing and includes SDDM changes
in the boot helper's backup/rollback transaction. It installs the login assets
under `/usr/share/sddm/themes/hyprshell-glass/` and changes only `Current` and
`ThemeDir` in `/etc/sddm.conf`, the final SDDM configuration layer. Authentication,
autologin, cursor, and display-server settings remain in place. Existing changed
files are backed up under `/var/lib/hyprshell/appearance-backups/<timestamp>/`.
Neither SDDM nor the desktop is restarted. The login theme takes effect at the
next greeter startup; check the complete startup sequence after a successful
rebuild and reboot.

For a login-only installation, omit `--with-boot-splash`. It does not rebuild
kernel images. To preview the animation in your desktop without changing login
configuration:

```bash
sddm-greeter-qt6 --test-mode --theme ~/repos/hyprshell/config/sddm/hyprshell-glass
```

Full `./setup.sh` restores this theme when the login manager is SDDM, including
fresh installs where setup installs SDDM. Another login manager is preserved.
Use `--skip-login-theme` to retain its existing appearance. `--config-only`
does not write system login or boot files. Pre-rendered artwork is bundled, so
installation needs no renderer. To regenerate it after editing the splash SVGs
or `config/sddm/hyprshell-glass/sources/card.svg`, run:

```bash
python3 tools/render_boot_theme.py
python3 tools/render_login_theme.py
```

These rendering commands require `rsvg-convert`, Noto Sans, and, for the BMP,
`ffmpeg`. Both animation implementations reuse the rendered title, glow, footer,
and background; the login card uses the same glass gradients with extra room
for controls.

## Where the animation starts

The installed systemd-boot menu remains unchanged. systemd-boot provides a text
menu and cannot render this background with boot choices. After selecting Linux,
the EFI stub can display a **static** matching splash embedded in the unified
kernel image (UKI). This replaces the preset's `splash-arch.bmp`; Plymouth then
animates the splash during Linux startup, and SDDM presents the animated login
card. The UKI artwork is a 1920×1080, 24-bit BMP; the stub centers it without
scaling, and firmware with a smaller graphics mode may reject it. Plymouth and
SDDM scale their own scenes to the display.
Their animation clocks are separate, and graphics initialization can cause a
brief blank frame. There is no artificial delay or guarantee of a frame-perfect
handoff. Firmware's own logo is outside these themes.

The boot helper edits active UKI preset options and rebuilds the images, while
preserving unrelated preset options and inactive fallback definitions. It does
not install, replace, update, or reconfigure systemd-boot. Set `uki_splash` to
`false` in `config/boot/plymouth.json` if the static image should be managed
manually; doing so leaves the existing preset splash setting untouched.

If installation fails, edited configuration and assets are restored. A failed
kernel-image rebuild may have changed generated images; complete a successful
`sudo mkinitcpio -P` before rebooting. See [boot splash details](boot-splash.md).
To undo a successful login change, restore the previous `/etc/sddm.conf` from
the printed backup directory. If that file did not previously exist, remove the
new file so SDDM resumes using its prior defaults/drop-ins. There is no need to
restart the display manager to prepare either change.

Validation uses isolated installer and rollback tests, QML tests with mock login
models, and the real SDDM greeter in offscreen test mode. Real PAM authentication
and the firmware/Plymouth/SDDM handoff still require testing on the machine.

References: [SDDM theme API](https://github.com/sddm/sddm/wiki/Theming),
[systemd-boot menu](https://github.com/systemd/systemd/blob/main/man/systemd-boot.xml),
[EFI splash rendering](https://github.com/systemd/systemd/blob/main/src/boot/splash.c).

## Lock and logout

Lock uses Hyprlock with the same background, glass card, and Fedora title as
the login theme. Enter your password and press Enter to resume your open apps.
The password field highlights Caps Lock and failed authentication. Logout ends
the session and returns to SDDM.

The power menu and Super + Shift + M share `quickshell/settings/session.py`.
It uses `uwsm stop` for a managed session, or terminates the current logind
session when UWSM is inactive. Missing session information and inaccessible
manager checks report an error. The helper never restarts SDDM.

The bundled lock config and artwork live under `config/hypr/` and are restored
by the existing config installer. Run `python3 tools/render_lock_theme.py` after
changing the login artwork. The default `hyprlock` command is launched by the
settings backend with the config's `hypr` folder as its working directory, so
relative images work with custom XDG config roots. To launch this config directly,
run Hyprlock from that folder. Custom locker commands retain their working directory.
Lock command edits require **Apply lock command**; typing does not change the
active locker. A replacement executable must exist before it can be saved.

## Fedora branding

The saved bar logo is Fedora’s symbol, and the boot/login artwork says Fedora
with a `HYPRSHELL / FEDORA LINUX` footer. These are saved artwork choices.
On Fedora, apply the boot and login assets together from a normal terminal:

```bash
sudo python3 ~/repos/hyprshell/tools/install_login_theme.py --with-boot-splash
```

This restores SELinux labels and rebuilds Fedora initramfs images with dracut.
Boot entries require root access even for a dry run. The bar QML can be applied
in the user session; boot and SDDM assets require administrator access.
