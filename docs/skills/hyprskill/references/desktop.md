# Desktop map

**hyprbar** is the user's name for Hyprshell's top bar, also called the bar
or topbar in existing settings and code.

Paths below are relative to the resolved config/state roots or checkout. Prefer actual local source over upstream examples: this checkout uses Hyprland 0.56+ Lua APIs.

| Concern | Live config / source in checkout |
| --- | --- |
| Desktop entry point | `hypr/hyprland.lua` / `config/hypr/hyprland.lua`; loads editable sections, then generated overrides |
| Monitors, programs, appearance, layouts, input, shortcuts, window rules, startup | `hyprshell/hyprland/*.lua` / `config/hyprshell/hyprland/*.lua`; section filenames describe their purpose |
| Chromium popup placement | `chromium-flags.conf` / `config/chromium-flags.conf`; XWayland exposes popup roles so Hyprland floats website popups at map time; fully exit and reopen Chromium after changing the backend |
| GUI display/appearance overrides | `hypr/hyprland-gui.lua`, required at end of main Lua file |
| Saved appearance, bar items, locking | `hyprshell/settings.json` / `config/hyprshell/settings.json` |
| Shell composition and bar | `quickshell/shell.qml`, `Bar.qml`, `DesktopServices.qml` |
| Menus | `quickshell/*Menu.qml`, `MenuController.qml`, `MenuPopover.qml` |
| Notifications | `quickshell/NotificationInbox.qml`, `NotificationCard.qml`; Quickshell owns `org.freedesktop.Notifications`; inbox history uses `Quickshell.statePath("notifications.json")` |
| Settings UI | `quickshell/Settings*.qml`, `SettingsModel.js`, `SettingsStore.qml` |
| Settings transactions and schema | `quickshell/settings/backend.py`, `defaults.json`; checkout `docs/settings.md` explains inheritance and extension points |
| Application colors, font, cursor | `SettingsTheme.qml`, `quickshell/settings/theme.py`, `hyprshell/theme.json`; GTK 3/4, GSettings, UWSM environment, and live cursor update |
| Default apps and login startup | `SettingsApplications.qml`, `quickshell/settings/applications.py`, `hyprshell/applications.json`; GIO discovery, MIME associations, XDG autostart overrides; setup restores saved IDs and skips missing apps |
| Advanced networking | `SettingsNetwork.qml`, `quickshell/settings/network.py`; on-demand NetworkManager metadata, hidden Wi-Fi and saved-profile activation in a detached `nmcli --ask` terminal, inactive-profile forget confirmation, and `nm-connection-editor` for enterprise/VPN/IP/DNS settings; no new applet or status polling |
| Audio / spectrum | `SettingsSound.qml`, `SoundVolume.qml`, `AudioMenu.qml`, `AudioInputMeter.qml`, `SoundTest.qml`, `AudioRoute.qml`, `AudioSpectrum.qml`, `AudioSpectrumBars.qml`, `helpers/audio-spectrum.c`; shared native helper links libpulse and FFTW; input capture requires an explicit `--source` argument |
| Wallpaper | `hypr/wallpaper-start.sh`, `wallpaper-cycle.sh`; awww; `$HOME/Pictures/Wallpapers` |
| Locking | `quickshell/LockingController.qml`, `hypr/hyprlock.conf`; generated `hyprshell/hypridle.conf` belongs to Hyprshell |
| Cleanup | `hyprshell/cleanup.json`, `quickshell/settings/cleanup.py`; user `hyprshell-cleanup.timer` / `.service`; state `hyprshell/cleanup-last.json` |
| Updates / recovery | `quickshell/SettingsRecovery.qml`, `quickshell/settings/recovery.py`; explicit checkupdates with a separate database, detached interactive full upgrade, validated settings checkpoints/restore; local state `hyprshell/{upgrade-last,personal-backup,recovery-preview}.json` |
| Portals | `xdg-desktop-portal/hyprland-portals.conf` |
| Launch helpers | `$HOME/.local/bin/{start-quickshell-bar,hyprshell-settings,app-launcher}` / checkout `bin/` |
| Install / package lists | checkout `setup.sh`, `tools/install_configs.py`, `packages.txt`, optional `packages-apps.txt` |
| Boot splash | checkout `config/boot/plymouth.json`, `config/boot/hyprshell/`, `tools/install_boot_splash.py`, `docs/boot-splash.md`; root-owned live Plymouth, mkinitcpio, and bootloader settings; full setup restores Hyprshell Glass with animated text and progress while preserving local disk/encryption options; `docs/boot-splash-preview.html` previews it without starting Plymouth |
| Login appearance / early UKI splash | checkout `config/sddm/hyprshell-glass/`, `config/boot/uki-splash.bmp`, `tools/install_login_theme.py`, `docs/login-appearance.md`; root-owned `/etc/sddm.conf` and `/usr/share/sddm/themes/hyprshell-glass/`; installer `--with-boot-splash` includes the replacement for the preset's Arch BMP and rebuilds mkinitcpio, without changing systemd-boot; no greeter restart; use SDDM Qt 6 test mode for preview |
| App autostart overrides | `autostart/*.desktop` / checkout `config/autostart/*.desktop`; installer copies managed entries individually; `nm-applet.desktop` hides the duplicate network tray icon |
| Sync | `quickshell/settings/github_sync.py`; copies live configs **into** checkout, stages allowed project paths, commits and pushes |

Quickshell owns the bar, menus, notification inbox, and optional Hypridle child. Notification popups default off; Settings → Notification delivery controls popups, Do Not Disturb, critical bypass, and per-app delivery. The bell inbox keeps history. Locking is managed while Quickshell runs, not by a separate Hyprshell lock service. Cleanup is separately scheduled with a systemd user timer. Sound device defaults and volumes use PipeWire/WirePlumber state; Settings → Sound provides device selection, an opt-in input meter, a test tone, and per-stream volumes. GitHub config sync does not export sound-system state. Sound device defaults and volumes use PipeWire/WirePlumber state; Settings → Sound provides device selection, an opt-in input meter, a test tone, and per-stream volumes. GitHub config sync does not export sound-system state. Audio uses PipeWire/PipeWire Pulse and WirePlumber; network uses NetworkManager; Bluetooth uses BlueZ; battery uses UPower. Session startup uses UWSM and hyprpolkitagent.

Settings are version 1 JSON with defaults and inheritance. Inspect `backend.py`'s CLI before using `--save-json` / `--expected-json`; preserve its validation, backups, conflict detection, and rollback. Hyprland settings overrides are managed by this backend; avoid competing writes to generated blocks. Adding a preference requires checking defaults, backend validation, UI model, and consumers. Read `docs/settings.md` only for settings work.

Settings → Bar & layout → Layout & spacing → Screen edge selects Top, Left,
Right, or Bottom (`bar.position`, default `top`). On either side, saved left
items sit at the top and right items sit at the bottom, with upright labels and
vertical workspaces/tray icons. Edge margin is `marginTop`; end margins are
`marginSide`. Menus open inward from the selected edge; the Settings preview
and item alignment labels follow the orientation.

Alt+T toggles hyprbar only on the focused monitor's active numbered workspace.
Settings → Bar & layout → Bar visibility provides Show on all / Hide on all
(clearing individual choices) and a workspace selector with an individual switch.
Saved `bar.workspaceOverrides` booleans take priority over the legacy visibility
and selected-workspace defaults. The CLI toggle requires a workspace number:
`backend.py --toggle-bar WORKSPACE`; keep toggles in the existing transaction.

Default-app choices affect links and file associations; explicit shortcut commands
remain configurable independently. Startup toggles take effect at the next login,
without starting or stopping apps immediately. Sync stores validated application
IDs and startup booleans, not unrelated custom launch commands. Font/cursor choices
share application-theme transactions; app-owned appearance preferences can win.

## Focused verification

Settings recovery imports validated `settings.json` only; it does not restore
manual Lua, display layouts, application choices/theme, or keybindings. Existing
transactions provide undo backups and rollback. Personal-backup status is a user
confirmation plus folder readability, not a backup engine or content verification.
These records and recovery history stay outside GitHub sync. Use `tests/test_recovery.py`
for isolated checks; never start a real upgrade or restore preferences just to
validate the UI. Upgrades remain opt-in, interactive `sudo pacman -Syu` in Kitty.

Run commands in the checkout (or use absolute paths), choosing checks for the change:

```bash
python3 tools/check_runtime.py --native
python3 -m unittest discover -s tests -v
Hyprland --verify-config --config "$PWD/config/hypr/hyprland.lua"
QT_QPA_PLATFORMTHEME= QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software /usr/lib/qt6/bin/qmltestrunner -input config/quickshell/tests
python3 config/quickshell/tests/test_spectrum.py
```

Use the corresponding `tests/test_settings.py`, `test_locking*.py`, `test_cleanup.py`, `test_github_sync.py`, or `test_setup.py` for narrow backend changes. Runtime checker inspects dependencies; it does not prove live desktop health. Qt's unqualified qmltestrunner may be Qt 5; use the Qt 6 path above.

In an accessible desktop session, query only relevant evidence: `hyprctl -j monitors`, `hyprctl configerrors`, `quickshell list --all --json`, `wpctl status`, `nmcli device status`, `bluetoothctl show`, or service status. Bound logs with `tail -n 80 <state>/quickshell/bar.log` or `journalctl --user -b -n 80 --no-pager` with the relevant unit. Avoid reading notification history for routine diagnostics.

After validation, main Hyprland config changes use `hyprctl reload`; permissions marked restart-only in Lua require a new session. Quickshell watches QML changes. If a restart is actually needed, inspect and use `<config>/quickshell/install-and-activate.sh` (it can install Quickshell if missing). Do not kill every Quickshell process indiscriminately.

Installer replacements are backed up under `<state>/hyprshell/backups/<timestamp>`. `setup.sh --config-only` still copies whole directories, compiles the audio helper, and restores saved repo preferences. Compare live files first. Full setup uses `pacman -Syu`; avoid Arch partial upgrades. GitHub sync includes `docs/`, so this skill travels with existing sync without changing its allowlist.
