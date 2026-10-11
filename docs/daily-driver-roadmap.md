# Daily-driver Settings roadmap

Recorded 2026-10-09. Updated 2026-10-11.

Goal: make Hyprshell usable every day by beginners and intermediate users,
with common tasks available through Settings rather than editing Lua.

Standing design preference: keep system resource use low while retaining a
modern, beautiful, functional desktop. Reuse existing native services and the
shared Settings design. Load optional controls on demand, avoid background
polling where manual refresh is sufficient, and add dependencies only when they
provide a needed capability. Idle desktop cost matters alongside feature coverage;
do not claim resource savings without measurements.

Existing foundations: Wi-Fi, Bluetooth pairing, audio output selection,
screenshots, editable shortcuts, screen locking, cleanup, and GitHub config sync.

## Priorities

1. **Displays** — resolution, refresh rate, scaling, monitor arrangement,
   rotation, and timed rollback for unconfirmed changes. Implemented 2026-10-09;
   physical monitor testing remains because the agent session cannot access desktop IPC.
2. **Mouse, touchpad and keyboard** — pointer speed, natural scrolling,
   tap-to-click, keyboard layouts, repeat speed, and layout switching. Implemented
   2026-10-10; physical device testing remains.
3. **Power and battery** — dim/off timers, automatic suspend, lid behavior,
   brightness, and supported power profiles. Implemented 2026-10-10; locking
   remains separate. Physical suspend/lid/wake testing remains.
4. **Notifications** — optional popups, Do Not Disturb, per-app preferences,
   and critical alerts. Implemented 2026-10-10; popups default off.
   Physical delivery and popup placement testing remains.
5. **Sound improvements** — microphone device selection, input meter,
   test sound, and per-app volume. Implemented 2026-10-10; physical audio
   and device persistence testing remains.
6. **Default apps and startup** — browser, file associations, startup toggles,
   and GTK/Qt theme, font, and cursor controls. Implemented 2026-10-10;
   physical app-opening, next-login startup, and appearance testing remains.
7. **Updates and recovery** — guided full system upgrades, useful failure
   messages, configuration restore, and personal-file backup status.
   Implemented 2026-10-10 for saved Settings and completed 2026-10-11 with
   complete personal-configuration checkpoints and opt-in local personal-file
   snapshots, scheduling and checksum verification. GitHub config sync does not
   back up documents. Physical upgrade/restore and mounted-drive testing remains.
8. **Advanced networking** — saved-network management, hidden Wi-Fi,
   enterprise connections, VPN, and access to advanced connection settings.
   Implemented 2026-10-11 through an on-demand Network page and NetworkManager's
   connection editor. Physical authentication, hidden/enterprise Wi-Fi, and VPN
   testing remains; provider-specific VPN plugins are optional.
9. **Accessibility and regional settings** — larger text, high contrast,
   reduced motion, language, timezone, and date/number formats. Implemented
   2026-10-11; application locale changes apply at the next login.
10. **Help and diagnostics** — Settings search, first-run guide, useful service
    errors, and privacy-conscious diagnostic reports. Super+K already provides
    a shortcut guide. Implemented 2026-10-11 with a first-use guide and manual
    service checks/redacted local reports.

Intermediate-user controls implemented 2026-10-11: window rules and behavior,
workspace preferences, clipboard history, and printing/scanning access. Separate
AC/battery timer policies and the recovery/backup follow-ups are also implemented.

**Implementation status:** all ten priorities and the recorded implementation
follow-ups are complete. Physical acceptance remains separate: monitor rollback,
input devices, lid/suspend/wake, audio routes, notification delivery, network/VPN
credentials, printer/scanner hardware, backup-drive disconnects, next-login
persistence and actual upgrades/restores must be checked in the desktop session.
Sandbox socket restrictions prevent those checks here.

Optional clipboard capture, automatic personal-file backups and printing setup
remain disabled until selected. Existing personal preferences are preserved.
Current personal automatic-lock timeout is 60 minutes; shorter presets are available.

## Displays acceptance criteria

- Discover connected monitors and advertised modes; show actionable errors.
- Edit resolution/refresh, scale, rotation and logical X/Y positions.
- Explicit Apply; keep changes only after confirmation within 15 seconds.
- Restore previous live layout on timeout, cancellation or UI shutdown.
- Save confirmed preferences, back up replaced files and detect concurrent edits.
- Preserve installer and GitHub sync behavior; retain automatic fallback for new hardware.
- Test transactions in isolated environments; test native QML and verify Lua.
- Physical monitor behavior must be checked in an accessible desktop session.

## Handoff for tomorrow

Displays now has advertised resolution/refresh controls, scale, rotation, automatic
arrangement, relative placement buttons, and precise X/Y fields. Apply previews the
layout; Keep commits it, with a 15-second backend timeout and rollback. Installer
and sync preserve confirmed settings. See `docs/settings.md` for implementation
limits and usage.

First check the Displays page on the real laptop (and an external screen if
available): confirm a change, allow a timeout, then check restart persistence.
The automated suite uses isolated settings and simulated compositor responses.
Priority 2 is now implemented; see the input handoff below.

Validation: 11 display checks passed (including native QML and real Lua parsing),
140 existing Qt tests passed, and native Settings lifecycle/autosave checks passed.
The broader Python run passed 81 of 82 checks; the unrelated shortcut-recording
check references a missing `config/quickshell/tests/ShortcutRecording.qml` fixture.
Native runtime dependency checks passed. Live monitor IPC was inaccessible.

Displays follow-up: fixed `hyprctl eval` rejecting a leading Lua comment as a CLI
flag. Runtime snippets now start with executable Lua; saved files keep their
header. Errors remain red after automatic refresh and command-help dumps are
replaced by concise messages. All 13 display regression checks pass, including
real CLI argument parsing in an isolated runtime. Physical preview still needs
verification in the desktop session.

The 5-percentage-point scale slider was reverted after physical testing showed
errors at values such as 105% and 110%. Scaling uses the previous preset dropdown. The laptop panel's kernel mode list reports only
1920×1080; resolution choices continue to use advertised modes.

Application theme is now available separately from topbar appearance: Dark/Light
updates desktop and GTK preferences and enables GTK integration for newly opened
Qt applications. Saved mode travels through setup and GitHub sync. Native toggle
and transaction checks cover failure recovery and unchanged bar preferences.

Launcher follow-up: desktop entries now launch through UWSM services so they
inherit the updated Qt theme environment and honor Terminal=true. UWSM's default
terminal selection chose Kitty's URL launcher; xdg-terminals.list now prefers the
real Kitty terminal. Real command generation resolves Vim to `kitty -- vim`.
Vim opened normally in an isolated PTY. GParted's installed wrapper expects
xhost, which is absent; xorg-xhost was added to packages.txt. Live installation
requires `sudo pacman -S --needed xorg-xhost` from the user's terminal because the
agent session cannot elevate privileges. Confirm remaining light apps by name.

Confirmed light apps: GParted and About Xfce. Both link GTK 3. Scoped themed
launcher entries now read the saved mode on each launch. About Xfce gets an
explicit GTK variant; GParted gets it after normal administrator authentication,
with temporary root-only display access and the upstream wrapper preserved.
Automated tests cover dark/light, argument boundaries, cancellation/error cleanup,
and preservation of existing display permissions. Check visual results by fully
closing and reopening these apps from the launcher in the desktop session.

## Input handoff — 2026-10-10

Settings → Mouse & keyboard now includes pointer speed, independent mouse and
touchpad natural scrolling, tap-to-click, disabling touchpad while typing,
common/custom keyboard layouts, layout-switch shortcuts, repeat speed/delay,
and a temporary typing test field. Preferences inherit existing input config
until edited, and each override can be removed. Device-specific rules can
still take priority. Switching overrides the existing XKB options; variants
remain configured in input.lua.

Repository and live Quickshell payloads are updated together. Setup regenerates
GUI overrides from saved settings, including input and appearance preferences,
so the existing GitHub snapshot is restorable. Physical input testing remains
because desktop IPC is inaccessible from the agent session.

Next: check input controls on the laptop. Priority 3 is now implemented below.
Validation: 21 settings backend checks, 15 installer checks, 147 Qt checks,
3 native Settings lifecycle/autosave checks, and native runtime dependencies.

## Power handoff — 2026-10-10

Settings → Power & battery now has battery status, live backlight adjustment,
dim/off/suspend timers, dimmed brightness, session lid behavior, and supported
power-profile preferences. Timers default off; lid and profile default to system
control. Existing personal locking settings are preserved. Power and locking
share one Hypridle process; closing Settings leaves them running. AC/battery
specific timer policies are a follow-up.

Managed dimming restores previous brightness on activity, settings changes, or
normal shell shutdown, while preserving manual adjustments. Screen-off uses
Lua DPMS and wakes on activity. Custom lid behavior uses a session logind
inhibitor with hardware-adaptive kernel lid discovery, without administrator
configuration changes. Saved timers/lid/profile choices travel through setup
and GitHub sync; immediate brightness changes and temporary snapshots do not.

Validation: 17 power helper/supervisor checks, 1 native power UI/controller
check, 21 settings checks, 6 locking checks, 1 native locking-controller check,
3 native Settings checks, 15 installer checks, 10 GitHub-sync checks, and 147 Qt
checks passed. Native Hypridle parsing and runtime dependency checks passed.
Live backlight and lid-sensor discovery succeeded. Power-profile D-Bus and
Hyprland IPC remain inaccessible in the agent session.

Next: test brightness restoration, display wake, suspend/resume and lid choices
on the real laptop, then priority 4, Notifications. Check profile selection in
the desktop session. No live dimming, screen-off or suspend test was performed.

Power activation follow-up: a live reload raced the new component copy and
failed with “SettingsPower is not a type”, retaining the old Settings interface.
After confirming all files were present, touching the live shell.qml triggered
a successful reload, verified by the active instance's Configuration Loaded log.
Future payload updates must create dependencies before replacing consumers and
verify activation in the live log.


## Notifications handoff — 2026-10-10

Settings → Notification delivery now offers optional popups, Do Not Disturb,
critical bypass, popup duration, and per-app Follow defaults / Inbox only / Off.
Popups remain disabled by default. Critical alerts can bypass quiet mode when
popups are enabled; explicit per-app choices take precedence. The inbox labels
critical alerts and preserves history when popups close or time out. One top-right
stack shows at most three recent alerts. Critical alerts have no automatic timer;
overflow remains available in the inbox.

Saved preferences use the existing settings transaction, backups, conflict checks,
autosave, installer, and GitHub sync. Reload does not replay tracked notifications
as new popups. Repository and live payloads are updated together, dependencies
before consumers. Notification history was not read or copied to the repository.

Validation: 3 notification backend/native lifecycle checks, 22 settings checks,
153 Qt checks, 3 native Settings lifecycle/autosave checks, 15 installer checks,
10 GitHub-sync checks and native runtime dependencies. Desktop-session D-Bus delivery
and Wayland placement remain untested because the sandbox blocks socket access.

Live activation: the running shell logged Configuration Loaded after the payload
update. No popup preference was enabled during installation.

Next: enable popups on the laptop, send normal and critical alerts with Do Not
Disturb on/off, test per-app preferences, actions, and restart persistence. Then
continue with priority 5, Sound improvements, or Recovery from the suggested order.


## Sound handoff — 2026-10-10

Settings → Sound now includes default output/input selection, master/microphone
volume and mute, a microphone input meter, test sound, and per-application playback
and recording stream volumes. Microphone selection is also in the topbar Audio
menu. A microphone test runs only after starting it and stops on navigation, window
close, or device change. Test sound plays a short quiet tone on the selected output
only when clicked; output changes, page/window close, Stop, and a five-second
watchdog cancel it. No sound or microphone test starts during installation.

Device defaults and volumes use PipeWire/WirePlumber state instead of exporting
hardware names to Hyprshell settings. Setup and GitHub sync preserve the controls
and the packaged waveform; sound system state is not part of config sync. Existing
applications may keep their previous route after changing the default device.

Validation: 160 Qt checks, 2 native tone/waveform checks, 3 native Settings checks,
15 installer checks, 10 GitHub-sync checks, and native runtime dependency checks.
The sandbox cannot access PipeWire; real levels, audible playback, call routing,
and remembered devices/volumes remain untested.

Repository and live payloads are updated together. The running shell logged
Configuration Loaded after activation.

Next: check Sound on the laptop, try a USB/Bluetooth device if available, adjust
an app volume during playback, and check defaults after reconnect/restart. Then
priority 6, Default apps and startup; Recovery remains next in the suggested order.


Sound microphone follow-up — 2026-10-10: the user reported Test microphone did
not work. Replaced the Quickshell monitor with an explicit capture stream on the
selected source. PCM stays in memory; only levels reach the UI. Startup, connection,
and capture errors are now visible, with a five-second no-data startup timeout.
The existing opt-in, page-close, and device-change lifecycle is retained. Four
microphone regression checks cover PCM conversion, active capture arguments,
failures, the actual Loader source path, and process cleanup; Sound Qt and tone
checks pass. Physical microphone behavior still needs a laptop retest.


Microphone full-meter follow-up — 2026-10-10: the user reported a full, stationary
bar even after the capture change. Rendering tests show the bar follows changing
values. The meter now displays RMS average level instead of maximum sample level,
with a separate clipping warning and live percentage. A two-second no-new-data
watchdog clears stale readings and stops capture. Five microphone tests and eight
Sound Qt checks cover sparse spikes, changing rendered fill, clipping, and stalled
capture cleanup. The physical cause and laptop result are still unconfirmed.

## Default apps and startup handoff — 2026-10-10

Settings → Default apps & startup now selects installed apps for web links,
email, folders, PDF, text, images, music, videos, and another MIME type entered
manually. Groups show when their file types currently use different apps.
Changes preserve unrelated associations and reconcile higher-priority user
desktop-specific defaults. Existing shortcut commands remain independently
customizable in Keybindings.

Startup toggles use user overrides of XDG autostart entries, preserving system
entries and their desktop/application conditions. Add app creates a Hyprland
login entry launched through UWSM so terminal and working-directory metadata
are honored. These changes take effect at the next login; changing a toggle
does not start or stop an app now. The bar, wallpaper, power and authorization
services remain managed by the desktop.

Application theme now also offers installed fonts, font size, installed cursor
themes, and cursor size. The existing Dark/Light choice is retained. GTK 3/4
and GTK-integrated Qt apps share these choices; apps with independent settings
may need reopening. Cursor changes also attempt a live compositor update.

Saved choices use backups, conflict detection, and rollback. Setup and GitHub
sync preserve application IDs and startup choices without importing unrelated
custom startup commands. Restoration skips missing apps, startup entries,
fonts, or cursor themes, retaining the saved snapshot for later restoration.
The installer restores startup choices before the next session's generator runs.
Python GIO bindings are now an explicit desktop dependency.

Validation: 10 application checks (including real GIO default selection,
fresh-install restoration, and native UI failure recovery), 11 theme checks
(including native font/cursor controls), 3 native Settings checks, 15 installer
checks, 10 GitHub-sync checks, and 147 Qt checks passed. Native dependency checks
and Lua verification passed. Tests use isolated homes and do not launch startup
apps or change this laptop's defaults, fonts, or cursor preferences.

Repository and matching live payloads are updated together, dependencies before
consumers. The active Quickshell instance logged Configuration Loaded after
activation. Physical link/file opening, next-login startup, font appearance, and
cursor behavior still need laptop testing because desktop IPC/D-Bus is blocked
in the agent sandbox.

Next: check Default apps & startup and Application theme on the laptop, then
priority 7, Updates and recovery. Personal-file backup remains distinct from
GitHub configuration sync.

## Updates and recovery handoff — 2026-10-10

Settings → Updates & recovery now checks available repository updates using
checkupdates with a separate temporary database, links Arch news, and opens a
detached interactive terminal for the full `sudo pacman -Syu` upgrade. Authentication
and package confirmation happen in that terminal, which survives closing Settings.
Settings shows completion/cancellation/failure, with guidance for common failures.
AUR/foreign packages need separate review. No upgrade starts during installation.

Desktop settings recovery offers checkpoints and existing pre-change backups,
previews changed sections, and restores through the validated Settings transaction
with a fresh undo backup and rollback. It covers bar/items, compositor appearance,
input, power, locking, and notification delivery. Displays, application theme/defaults/
startup, keybindings, manual Lua edits, and shell files remain outside this restore.
Previews expire and reject changed backups or concurrent edits. Checkpoints stay
local and follow System cleanup retention.

Personal backup status records a folder and the user's latest explicit backup
check, with current folder availability. It does not copy documents or verify
their contents. This record, update results, and recovery history stay outside
GitHub config sync. pacman-contrib and sudo are explicit installer dependencies.
Installer headless checks now clear the desktop Qt platform theme; installer tests
distinguish legitimate application-preference backups from replaced config backups.

Validation: 15 recovery checks (including the native confirmation/error workflow),
22 settings checks, 3 native Settings lifecycle/autosave checks, 15 installer checks,
10 GitHub-sync checks, and 147 Qt checks passed. Native dependencies and shell syntax
checks passed. Live discovery found valid saved settings backups. Repository and
matching live payloads are updated together, dependencies before consumers; the
active Quickshell instance logged Configuration Loaded at 08:20:13. No live upgrade,
settings restore, or personal backup confirmation was performed during validation.

Next: check update preview and terminal cancellation on the laptop, make a checkpoint,
change a bar preference, preview and restore it, and record a checked personal backup.
Run a full system upgrade only when ready after reading Arch news. Then priority 8,
Advanced networking. Wider config recovery and a real backup engine are follow-ups.

## Advanced networking handoff — 2026-10-11

Settings → Devices → Network now lists and filters saved connections, marks
active profiles, shows cached connectivity status, and offers Connect, Disconnect,
Edit and confirmed Forget for inactive profiles. Actions target UUIDs rather than
names; stale name/type/active-state snapshots are rejected. Automatic reconnection
is controlled in Edit. Hidden Wi-Fi accepts an exact SSID and requests its password
in a detached terminal. Enterprise authentication/certificates, Ethernet, VPN,
WireGuard, IP/DNS and provider VPN import use the installed connection editor.
Provider VPN plugins remain optional; no duplicate network applet is started.

The page is instantiated only when selected, then released after any short helper
finishes. There is no background timer, network scan, or forced connectivity probe.
Metadata refresh is explicit. Authentication and editor windows survive closing
Settings; complete their workflow, then refresh status. Passwords stay in the
NetworkManager tools. Network profiles and credentials are outside GitHub config
sync. The installer now explicitly includes the already-installed editor package.
Repository and live Quickshell payloads are updated together, dependencies first.
The live files match the repository. Touching the live shell entry point produced
no new activation-log entry in this agent session, so live reload is unconfirmed.

Validation: 10 network checks including the native page's lazy lifecycle,
confirmation/cancellation, duplicate profile names, errors/recovery, narrow layout,
and closing during a helper command passed. Five available native Settings checks,
16 installer checks, 10 GitHub-sync checks, and native runtime dependencies passed.
The broader Qt run passed 150 checks with one existing IconSizes expectation
failure (18 px vs 12 px); this also stops the full installer smoke test. Both
failures were reproduced from the committed baseline in an isolated checkout.
The remaining native bar-position check references a fixture already absent from
HEAD (`SettingsBarPosition.qml`). These validation follow-ups remain open.

No real connection, disconnection, forgetting, or credential entry was performed.
Desktop-session NetworkManager access is blocked in the agent sandbox, so physical
hidden/enterprise Wi-Fi, VPN/provider-plugin, editor and authentication results
still need laptop testing. Next implementation: priority 9, Accessibility and
regional settings, retaining the low-idle-cost design preference above.

## Accessibility, regional and help handoff — 2026-10-11

Priorities 9 and 10 now have native Settings controls. Settings text/contrast react
immediately; reduced motion shares validated compositor overrides. Language,
formats and personal timezone use a backed-up, conflict-checked UWSM environment
block at the next login. System timezone requires its separate confirmed action.
Help provides a local first-use guide and explicitly requested checks/reports.
No diagnostic checks or export run during installation or ordinary browsing.

Restored the bar-position fixture from its original feature commit and supplied
the missing shortcut recording fixture; the native shortcut check now isolates
Qt theme/runtime state. The proportional icon-size assertion matches the existing
18 px behavior. The full Qt suite now passes 151 checks. Accessibility transactions,
reactive native controls, regional save/preview/rollback, guide completion and
diagnostic privacy are tested in isolated profiles. Laptop-session behavior and
next-login language changes remain physical acceptance checks.


## Completion handoff — 2026-10-11

Workspaces & rules provides default tiling layout, border resizing, pointer focus,
workspace naming/layout/persistence, and literal application-class rules for
floating/tiling, workspace placement, pinning, animation and floating size. The
installed compositor validates generated Lua before a backed-up transaction;
failed live activation rolls back. Setup and sync regenerate saved rules.

Clipboard history defaults off. One wl-paste event watcher exists only while
capture is enabled. Text is the default; images are optional. Up to 10–200 entries
of at most 5 MiB each are stored locally, with lazy manual listing, copy, removal
and confirmed clearing. Sensitive-state hints are respected; arbitrary copied
secrets cannot be inferred. History and contents are excluded from sync.

Printing & scanning loads tool availability on demand, opens the existing printer
and document scanner apps, and provides explicit bounded queue/device checks.
Optional package installation uses an interactive full-upgrade terminal. Printing
socket activation requires a separate explicit choice; setup enables no CUPS unit.

Power reuses the existing UPower signal and one Hypridle process for AC/battery
policies, with independent locking. The Power page no longer polls hardware.

Updates & recovery now adds complete local configuration checkpoints with file
previews, stale-preview rejection, syntax-only Lua validation, regenerated GUI
Lua, atomic restoration and a selectable pre-restore checkpoint. Installed shell
source and network secrets are excluded. Settings preferences reload immediately;
log out/back in to activate restored compositor and application configuration.

Personal-file backups copy selected home folders to an existing local destination,
refuse changed/unmounted destinations, skip links/special files and preserve older
snapshots. Verified unchanged copies can be shared between snapshots; originals
are never hard-linked. Manual SHA-256 verification detects changed backup contents.
Daily/weekly user timers are opt-in; no worker or timer is installed while off.
Snapshots have no automatic deletion. Open snapshots to recover files into a
separate folder. Preferences, schedules and contents stay local.

All new controls use the shared native theme; text inputs, numeric inputs and
labels follow Settings text scaling and high contrast. Optional pages are lazy,
and no optional tool is installed or enabled during this update.

Validation: 240 full-suite Python checks passed, including mocked fresh/full
installation, sync preservation and native Settings workflows. An additional native
supervisor check confirms event watcher/idle restart and shutdown without overlap,
bringing the validated Python checks to 241. All 151 Qt checks passed; native
runtime dependencies and the actual Hyprland config parser passed. Offscreen
visual previews confirm the new pages use the shared dark Settings theme. Missing
legacy native fixtures were restored and headless tests isolated from the desktop
GTK platform theme.

Matching installed payloads are updated before the local commit. Desktop-session
IPC remains inaccessible, so automatic live reload and physical acceptance are
not asserted. The installer was exercised only in isolated mocked environments;
no real upgrade, document backup, CUPS activation, suspend or configuration restore
was performed.
