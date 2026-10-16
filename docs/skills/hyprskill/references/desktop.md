# Desktop map

**Hyprpane** is the existing status/menu panel on any edge (formerly hyprbar).
**Hyprdock** is the planned app dock; **Hyprbar** is the planned classic taskbar.
Legacy `bar` keys, file names and IPC still target Hyprpane. See
`docs/panel-configuration.md` in the checkout for the Phase 1 compatibility mapping.

Paths below are relative to the resolved config/state roots or checkout. Prefer actual local source over upstream examples: this checkout uses Hyprland 0.56+ Lua APIs.

| Concern | Live config / source in checkout |
| --- | --- |
| Desktop entry point | `hypr/hyprland.lua` / `config/hypr/hyprland.lua`; loads editable sections, then generated overrides |
| Monitors, programs, appearance, layouts, input, shortcuts, window rules, startup | `hyprshell/hyprland/*.lua` / `config/hyprshell/hyprland/*.lua`; section filenames describe their purpose |
| GUI display/appearance overrides | `hypr/hyprland-gui.lua`, required at end of main Lua file |
| Displays / HDMI TV | `quickshell/ProjectorWindow.qml`, `quickshell/SettingsDisplays.qml`, `settings/displays.py`, `hyprshell/displays.{json,lua}`; Super+P opens a compact centered overlay with only Duplicate and Extend; each applies/saves immediately and closes; Escape/outside click dismisses it; Settings → Displays retains per-screen mirror sources and advanced controls; Alt+S opens Settings and Super+Shift+P toggles pseudotiling; Settings Displays Apply / Keep uses a 15-second rollback, and confirmed connector preferences persist through setup/sync |
| Saved appearance, bar items, locking | `hyprshell/settings.json` / `config/hyprshell/settings.json` |
| Shell composition and bar | `quickshell/shell.qml`, `Bar.qml`, `DesktopServices.qml` |
| Hyprview / virtual projector | `quickshell/Hyprview.qml`; Super+V projects the active window with no visible controls/decorations or copied cursor; external projection uses an Overlay layer with OnDemand keyboard focus to fill an enabled non-mirrored external display (HDMI preferred) without moving a toplevel/focusing that output; follows hotplug, floating fallback with one screen; Super+Shift+V closes via an explicit `hl.exec_cmd` callback and `bar.closeHyprview` (user verified the live callback); F11 fullscreen and Escape leave fullscreen/close when viewer focused; view only, capture released on close; `tests/test_hyprview.py` covers key events, close routing, offscreen lifecycle, output routing and stretch-to-fill sizing; physical pointer/video checks need a live compositor |
| Menus | `quickshell/*Menu.qml`, `MenuController.qml`, `MenuPopover.qml` |
| Shortcut guide / Super+K | `quickshell/KeybindingsMenu.qml`, `KeybindingsGuide.js`; preserves every runtime binding, with submap/trigger labels plus scoped shell controls and configured Kitty copy/paste; independent of the narrower Settings editor; `tests/test_keybindings_guide.py` audits Lua registration/remaps without executing actions |
| Notifications | `quickshell/NotificationInbox.qml`, `NotificationCard.qml`; Quickshell owns `org.freedesktop.Notifications`; inbox history uses `Quickshell.statePath("notifications.json")` |
| Settings UI / search | `quickshell/Settings*.qml`, `SettingsModel.js`, `SettingsStore.qml`; `settings/search.py` indexes static headings/subheadings/control captions from page/component sources and helper metadata without loading pages; source-map coverage and native matching/navigation in `test_settings_search*.py` |
| Settings transactions and schema | `quickshell/settings/backend.py`, `defaults.json`; checkout `docs/settings.md` explains inheritance and extension points |
| Application colors, font, cursor | `SettingsTheme.qml`, `quickshell/settings/theme.py`, `hyprshell/theme.json`; GTK 3/4, GSettings, UWSM environment, and live cursor update |
| Default apps and login startup | `SettingsApplications.qml`, `quickshell/settings/applications.py`, `hyprshell/applications.json`; GIO discovery, MIME associations, XDG autostart overrides; setup restores saved IDs and skips missing apps |
| Accessibility / regional / help | `SettingsAccessibility.qml`, `SettingsRegional.qml`, `SettingsHelp.qml`, `style/Theme.qml`; validated settings, `settings/regional.py` UWSM locale/timezone preferences, `settings/diagnostics.py` manual redacted checks; first-use completion and reports stay local |
| Firewall | `SettingsFirewall.qml`, `quickshell/settings/firewall.py`; one short authenticated job per action (no per-command password prompts), On/Off, Add/Edit/Remove rule forms, apply-and-save with edit rollback, automatic zone selection, collapsed help/details and website-name blocks with a per-rule subdomains toggle (On for new rules), optional one-action NetworkManager dnsmasq/resolved bridge and restore controls, plus DNS modes (Automatic DNS from network or manually entered custom IPv4/IPv6, without provider presets; legacy saved addresses display as Custom DNS), revision-checked apply/rollback and local-only DNS state; system block lists stay outside sync; system rules stay outside sync |
| Advanced networking | `SettingsNetwork.qml`, `quickshell/settings/network.py`; on-demand NetworkManager metadata, hidden Wi-Fi and saved-profile activation in a detached `nmcli --ask` terminal, inactive-profile forget confirmation, and `nm-connection-editor` for enterprise/VPN/IP/DNS settings; no new applet or status polling |
| Audio / spectrum | `SettingsSound.qml`, `SoundVolume.qml`, `AudioMenu.qml`, `AudioInputMeter.qml`, `SoundTest.qml`, `AudioRoute.qml`, `AudioSpectrum.qml`, `AudioSpectrumBars.qml`, `helpers/audio-spectrum.c`; shared native helper links libpulse and FFTW; input capture requires an explicit `--source` argument |
| Wallpaper | `hypr/wallpaper-start.sh`, `wallpaper-cycle.sh`; awww; `$HOME/Pictures/Wallpapers` |
| Locking | `quickshell/LockingController.qml`, `hypr/hyprlock.conf`; generated `hyprshell/hypridle.conf` belongs to Hyprshell |
| Cleanup / reset | `SettingsCleanup.qml`, `SettingsCleanupTargets.qml`, `SettingsFactoryReset.qml`, `settings/{cleanup,system_cleanup}.py`; existing `hyprshell/cleanup.json` user timer retained; manual per-directory categories, impact descriptions, file exclusions/pages and expiring previews; administrator plans private under `/var/lib/hyprshell-system-cleanup/<uid>`; backed-up settings-only reset and clean-install guidance, never disk erasure; see `docs/settings.md` and `test_system_cleanup*.py` |
| Workspaces / rules | `SettingsBehavior.qml`, `settings/behavior.py`, `hyprshell/behavior.{json,lua}`; literal app classes, validated compositor rules, backed-up apply/rollback; setup/sync regenerate Lua |
| Clipboard / peripherals | `ClipboardController.qml`, `SettingsClipboard.qml`, `SettingsPeripherals.qml`, `settings/{clipboard,peripherals,optional_tools}.py`; capture off by default, local bounded cliphist history, manual printing/scanning tools, explicit optional installation and CUPS socket setup |
| Setup backup / personal files | Settings → Backup & restore (`-23`), `SettingsConfigurationRecovery.qml`, `SettingsPersonalBackup.qml`, `settings/{configuration,personal_backup}.py`; dated/timezone-stamped manual setup backups and before-restore backups under `state/hyprshell/setup-backups` are protected from cleanup; picker/preview/checksum/undo, legacy configuration checkpoints retained; opt-in personal-file snapshots/checksums and timer remain separate; all backup/history state and personal paths excluded from sync |
| Updates / recovery | `quickshell/SettingsRecovery.qml`, `quickshell/settings/recovery.py`; explicit checkupdates with a separate database, detached interactive full upgrade, validated settings checkpoints/restore; local state `hyprshell/{upgrade-last,personal-backup,recovery-preview}.json` |
| Portals | `xdg-desktop-portal/hyprland-portals.conf` |
| Launch helpers | `$HOME/.local/bin/{start-quickshell-bar,hyprshell-settings,app-launcher}` / checkout `bin/` |
| Install / package lists | checkout `setup.sh`, `tools/install_configs.py`, Arch `packages.txt` / `packages-apps.txt`, Fedora `packages-fedora.txt` / `packages-apps-fedora.txt`; `docs/fedora.md` covers the Fedora Everything port and validation limits; `docs/daily-driver.md` covers base apps/firmware, system-service preservation, and `tools/check_daily_driver.py --after-login` |
| Boot splash | checkout `config/boot/plymouth.json`, `config/boot/hyprshell/`, Arch `tools/install_boot_splash.py`, Fedora `tools/install_boot_splash_fedora.py`, `docs/boot-splash.md`; root-owned live Plymouth and initramfs settings; Fedora uses dracut with SELinux label restoration, preserving BLS/kernel parameters; `docs/boot-splash-preview.html` previews it without starting Plymouth |
| Login appearance / early UKI splash | checkout `config/sddm/hyprshell-glass/`, `config/boot/uki-splash.bmp`, `tools/install_login_theme.py`, `docs/login-appearance.md`; root-owned `/etc/sddm.conf` and `/usr/share/sddm/themes/hyprshell-glass/`; installer `--with-boot-splash` includes the replacement for the preset's Arch BMP and rebuilds mkinitcpio, without changing systemd-boot; no greeter restart; use SDDM Qt 6 test mode for preview |
| App autostart overrides | `autostart/*.desktop` / checkout `config/autostart/*.desktop`; installer copies managed entries individually; `nm-applet.desktop` hides the duplicate network tray icon |
| Sync | `quickshell/settings/github_sync.py`; Sync to GitHub captures desktop/checkout edits, commits locally, then pushes |

Quickshell owns the bar, menus, notification inbox, and optional Hypridle child. Notification popups default off; Settings → Notification delivery controls popups, Do Not Disturb, critical bypass, and per-app delivery. The bell inbox keeps history. Locking is managed while Quickshell runs, not by a separate Hyprshell lock service. Cleanup is separately scheduled with a systemd user timer. Sound device defaults and volumes use PipeWire/WirePlumber state; Settings → Sound provides device selection, an opt-in input meter, a test tone, and per-stream volumes. GitHub config sync does not export sound-system state. Sound device defaults and volumes use PipeWire/WirePlumber state; Settings → Sound provides device selection, an opt-in input meter, a test tone, and per-stream volumes. GitHub config sync does not export sound-system state. Audio uses PipeWire/PipeWire Pulse and WirePlumber; network uses NetworkManager; Bluetooth uses BlueZ; battery uses UPower, also selecting optional AC/battery timer policies without extra polling. Session startup uses UWSM and hyprpolkitagent.

Settings are version 1 JSON with defaults and inheritance. Inspect `backend.py`'s CLI before using `--save-json` / `--expected-json`; preserve its validation, backups, conflict detection, and rollback. Hyprland settings overrides are managed by this backend; avoid competing writes to generated blocks. Adding a preference requires checking defaults, backend validation, UI model, and consumers. Read `docs/settings.md` only for settings work.

Settings → Hyprpane & panels → Layout & spacing → Screen edge selects Top, Left,
Right, or Bottom (`bar.position`, default `top`). On either side, saved left
items sit at the top and right items sit at the bottom. Side panels use centered icons
in circular pills (28 px at the default 32 px panel width).
The calendar is an icon; its menu has a live clock/date header and Sunday-first
weeks. Hyprpane item, workspace, media and tray tooltips are disabled.
Workspaces retain their numbers/names. Hovering a workspace opens a miniature
wallpaper/window layout without activating it; hovering the media spectrum opens
Now playing with a matched window capture, artwork, or spectrum and track details.
Both use the existing inward hover popdown on all four edges. Captures run only
while their preview is open; unavailable workspace captures retain window titles.
`PreviewCapture.qml`, `WorkspacePreview.qml`, `MediaPreview.qml` and
`PreviewModel.js` own preview rendering/matching. `tst_HoverPreviews.qml` checks
four-edge hover/anchors and matching; `tests/test_hover_previews.py` validates
native loading/geometry and idle capture cleanup offscreen. Live compositor
capture still requires an accessible desktop session.
Workspaces/tray icons stack vertically. Side panel length (`bar.verticalPresentation`)
selects Full edge (`edge`, default) or Compact (`compact`, centered shorter rail).
Overflow scrolls, and focus reveals controls. Media uses five spectrum bars
centered in a circle. Icon hiding, item order and group
membership remain saved. Side groups draw
individual circles; saved labels and radii return on Top/Bottom. Edge margin is `marginTop`; end margins are
`marginSide`. Menus open inward from the selected edge; the Settings preview
and item alignment labels follow the orientation.

Alt+T toggles Hyprpane only on the focused monitor's active numbered workspace.
Settings → Hyprpane & panels → Hyprpane visibility provides Show on all / Hide on all
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

Settings-only recovery imports validated `settings.json`. Complete configuration
checkpoints additionally cover personal desktop Lua, display/app/theme/shortcut
preferences and application integration files; restoration parses Lua without
executing it, regenerates GUI files and requires next-login activation. Manual setup
backups have dates/times/checksums in `setup-backups`, outside cleanup targets;
legacy `backups/configuration-*` checkpoints remain selectable. Personal
backup status remains a self-report for external tools. The optional personal-file
engine has manual/scheduled snapshots and checksum verification; it defaults off.
All history, schedules, destinations and documents stay outside GitHub sync.
Use `tests/test_{recovery,configuration,personal_backup,optional_daily_driver}.py`
and native `test_{daily_driver,setup_backup}_ui.py`; never start real upgrades, restore laptop
preferences or copy documents just to validate controls. Upgrades remain explicit
interactive `sudo pacman -Syu` in Kitty on Arch. Fedora uses
`sudo dnf upgrade --refresh`; `settings/system_packages.py` owns package
commands and update-help links. Fedora power profile controls call tuned-ppd's
D-Bus API directly; Arch retains powerprofilesctl. Runtime checks discover the
Qt 6 test runner with `python3 tools/check_runtime.py --qmltestrunner`.

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

After validation, main Hyprland config changes use `hyprctl reload`; permissions marked restart-only in Lua require a new session. Alt+Q (`bar.reload`) reloads Hyprland with a 15-second limit, then Quickshell, retaining shell reload if the compositor command fails. Quickshell watches QML changes. If a restart is actually needed, inspect and use `<config>/quickshell/install-and-activate.sh` (it can install Quickshell if missing). Do not kill every Quickshell process indiscriminately.

Installer replacements are backed up under `<state>/hyprshell/backups/<timestamp>`. `setup.sh --config-only` stages owned files, compiles the helper, validates preferences and retains existing settings. `--update` adds compatibility and native validation. Compare live files first. Full setup uses `pacman -Syu`; avoid Arch partial upgrades. GitHub sync includes `docs/`, so this skill travels with existing sync without changing its allowlist.

Daily-driver installer update (2026-10-13): base manifests include media controls,
Mousepad, archives, clipboard-history tools (capture remains off), printing/scanning,
GNOME Keyring, firmware/microcode and Mesa drivers. Saved media defaults use mpv.
Full setup enables an existing disabled login manager, or installs SDDM when none
is installed; it prepares services before native/QML validation. Fedora defaults
to the lionheartp/Hyprland COPR; --no-copr keeps existing repositories only.
Time-sync/firewall alternatives and existing firewall zones are preserved;
fstrim, CUPS socket and Avahi are enabled. The base monitor fallback is automatic.
Readiness reports are local and redacted; neither a package test nor a sandbox
service-access failure establishes real boot/hardware health.

Hardware-aware installer (2026-10-14): `tools/hardware_plan.py` reads CPU,
PCI/USB vendors, bound GPU drivers, battery presence and kernel identity. Package
manifests remain supersets; `setup.sh` selects matching microcode, firmware and
Arch GPU dependencies and preserves configured service alternatives. Fedora
media setup selects Intel iHD/i965 or AMD Mesa Freeworld, keeps Fedora's codec
package alongside Freeworld, and resolves driver transactions before upgrades.
Installed providers are checked and Fedora rechecks after upgrading. Virtual CPUs,
custom kernels, unknown GPUs and proprietary NVIDIA receive conservative handling
and review notes. Config-only skips selection. See README's hardware/media section
and `tests/test_hardware_plan.py`; no full installer or hardware certification is
implied by the mocked checks.

Whole-system preflight (2026-10-14): `tools/system_plan.py` wraps hardware
selection with provider-aware package inventory and service-policy decisions for
every dependency group. Main setup consumes one plan for packages, media and
service activation. Existing power backends and configured network/audio
migrations are reviewed before sudo; Bluetooth starts when detected, trim runs
only for detected discard support, and TTY user-audio activation stays supported.
`check_runtime.py` treats power controls as optional when an external policy owns
them. `configure_daily_driver.py --plan-stdin` applies planned trim without
changing encryption/discard options. See `tests/test_system_plan.py` and README's
whole-system table. Apps/runtime dependencies follow saved desktop choices,
not an inferred hardware performance ranking.


Reviewed GitHub updates (2026-10-13): `SettingsGithubUpdate{,Review}.qml`,
`settings/{github_update,compatibility,deployment}.py`, root `compatibility.json`.
All preferences and code live in `config/`. Successfully completed, validated
agent tasks are committed locally with meaningful descriptions; unfinished tasks
and questions do not trigger commits. Manual desktop edits remain uncommitted
until Sync to GitHub captures them and creates a local commit. Sync pushes
existing commits with their original subjects and bodies intact. There is no background
Git saver. Sync from GitHub presents conflict choices before continuing. Sync from GitHub previews the tracking source and candidate
before confirmation, preserves preferences/history, and runs a detached worker.
See `docs/updates.md` and `docs/acceptance.md`. No public release or physical
hardware certification should be inferred from isolated tests.
