# Settings implementation

Locking → Your lock screen includes Background transparency (0–100%, default
85%). It controls the tint over the desktop snapshot and softens the
password field while retaining its contrast. The bundled theme uses a drawn
avatar rather than a font glyph. Changes apply on the next lock through the
existing manual, idle and sleep paths; adjusting appearance does not restart the
idle timer. Background blur passes (0–4, default 2) independently controls the
glass effect; 0 gives a clear snapshot. Background blur strength (1–20, default 8)
sets the size of each pass and is disabled while passes are 0, retaining its value.
These controls are separate from window glass settings and apply on the next lock.
The backend renders only the bundled theme's named appearance tokens to
`state/hyprshell/hyprlock.conf` when locking. Custom locker commands, explicit
`hyprlock --config` commands and themes without those tokens stay untouched.

**Hyprpane** means Hyprshell's status/menu panel on any edge. This document also
uses “bar” and “topbar”; IPC methods and configuration keys keep their existing names.

Hyprpane → Default appearance includes Individual pill transparency, Group pill
transparency, and Full pill transparency (0–100%). Explicit values set absolute
background transparency: 0% is opaque and 100% is transparent, including borders
and shine. Icons/text retain their opacity. These controls override theme and item
background alpha while keeping their colors and saved preferences. Reset (the
default, stored as -1) restores the original theme/item backgrounds. Group
transparency also applies to grouped circles on side panels.

With wallpaper adaptation enabled, individual, shared and full pills choose a
light or dark accent-tinted surface for local contrast. Glyphs adapt to the
composite of the wallpaper and visible pill layers, retaining explicit color
choices. Hyprknots sample the same wallpaper with full/shared pill layers and
recalculate when their colors, transparency or geometry change. A narrow opposing
edge keeps links and knots visible on mixed light/dark textures. Transparency
values and manual adaptation/color overrides remain respected.

Hyprpane includes a schematic layout preview and four edge presets. Selecting
previews without saving; Apply layout preset changes the edge while retaining
appearance and visibility. See [panel layout settings](panel-layout-settings.md).

The settings app is part of the existing Quickshell process. `SettingsWindow.qml`
is created on demand by `SettingsController.qml` through the `bar settings` IPC
method; `bin/hyprshell-settings` and the desktop entry provide normal
application-launcher access. No web server,
browser, or additional GUI framework is required.

Hyprsettings uses charcoal surfaces, a muted mint accent, generous spacing, and
short transitions. `style/SettingsTheme.qml` owns its palette and control sizes;
it inherits text scaling, high contrast and reduced motion from `style/Theme.qml`.
Desktop menus retain their independent wallpaper-aware palette. The window title
remains `Hyprshell Settings` for existing compositor placement rules.

Navigation groups pages under **Personalize**, **Devices & connections**,
**Preferences**, and **System**. Groups expand on demand and automatically reveal
the selected page. Search stays above the scrolling navigation, and matching
pages are visible even in collapsed groups. The shorter
sidebar labels **Appearance**, **Windows**, **Applications**, **Keyboard shortcuts**,
and **Cleanup** lead to the existing application theme, Hyprland, default apps,
keybindings, and system cleanup controls. **Hyprpane items** expands individual module
editors and opens automatically when a preview item is selected. Search matches
page labels, related terms, card headings and control captions,
including collapsed bar items and pages that have never been opened.
Explanatory subtitles, descriptions and sentence-style help text are excluded,
so a word in instructions alone does not make a page match.
For example, **System updates** finds Updates & recovery, and **Popdown glass**
finds Hyprpane and individual bar-item editors. Matching ignores case and
repeated whitespace. **Ctrl+F** focuses search; **Up/Down** select a result;
**Enter** opens the selected match;
**Escape** or the clear button clears the query. Browsing and searching do not
write preferences. Each page keeps its scroll position within the current window.

Settings opens on an overview with direct links to Appearance, Hyprpane, Displays,
Sound, Network, and Bluetooth, plus search, the getting-started guide, and setup
backups. Tiles become a single column in narrow windows. The **Overview** entry
and window branding return home and clear the query. All existing pages and
individual panel-item editors remain available in navigation. Page transitions
use one short fade/slide, honoring reduced motion and disabled desktop animations.
Failed drafts and direct display-settings navigation retain their routes.

**Bluetooth** adds radio power, visibility to nearby devices, saved devices,
connection state, and available battery levels. Device details expose trust,
wake permission, blocking, and a confirmation before forgetting. These controls
use the existing native BlueZ API; they do not add preferences to GitHub sync.
Opening the page does not scan or start a pairing agent. **Find a device** loads
the existing pairing UI, including PIN/passkey confirmation and its bounded scan.
Done, power-off, navigation away, or closing Settings releases the pairing UI.
Unavailable adapters disable hardware actions. Native tests inject radio/device
objects and isolate D-Bus; physical pairing still needs a desktop hardware check.

Short preference sections start expanded across Settings. Only sections with more
than 1,000 logical pixels of control content start collapsed, including advanced
blur and large cleanup forms. The shared card measures its
actual laid-out content, including loaded rows, so the rule also covers other
pages and adapts to text size and available width. Appearance, Clipboard history,
Printing & scanning, Applications, Notifications, Displays, and Network keep their
short sections open. Click a section heading, or focus it with Tab and press Enter
or Space, to open or close it. A manual choice takes precedence over the automatic
default; focusing a section’s controls keeps it open if its rows grow while editing.
Sections open independently and retain their values, unsaved edits, and current
expansion state while the page remains loaded. Collapsed controls leave the tab
order; closing a section keeps focus on its heading. Search opens sections whose
headings or control captions match, including controls inside a closed section.
Folding is scoped to the main settings pages; separate review dialogs retain
visible review details. Folding itself never writes preferences.

The bar preview appears within bar and item pages. Control feedback and the short
page fade honor an explicit disabled Hyprland animation preference.

`settings/search.py` reads captions from installed QML source and static helper
metadata once when Settings is created. It follows nested component sources,
including model-defined labels, without evaluating QML or importing/executing
page helpers. No matched page is instantiated merely by typing, and indexing
does not request administrator access, probe devices or read saved preference
values. Caption edits are picked up when Settings is recreated. Page names and
keywords remain available if indexing fails. The source ownership map covers
every navigation page and is checked by `test_settings_search.py`; native
`test_settings_search_ui.py` verifies both example searches, Enter navigation,
case/spacing normalization and unopened-page matches without preference writes.

**Devices → Network** manages NetworkManager's saved connections. It shows
active profiles and cached internet connectivity, filters by name/type, opens
profile editing, connects through a detached Kitty terminal with `nmcli --ask`,
and deactivates connections. Forget requires confirmation and an inactive
connection. UUIDs distinguish duplicate names; a metadata revision rejects
stale actions. Deactivation can be followed by NetworkManager automatically
reconnecting; disable automatic connection in Edit when needed.

Hidden Wi-Fi accepts an exact SSID and opens the same authentication terminal.
Add Wi-Fi opens `nm-connection-editor` for enterprise security and certificate
settings. Ethernet, VPN and WireGuard creation and advanced connection settings
also use this editor. Its connection chooser supports VPN import; provider VPNs
need their corresponding NetworkManager plugin. WireGuard support is built in.
The editor package is part of the desktop dependencies; no extra applet is started.

The Network page is created only when selected and released when leaving it,
after any short helper command completes. There is no Network-page timer or
background status process. Refresh reads metadata on demand; it does not force
a network scan or connectivity probe. Editor/connection windows survive closing
Settings; their results are reviewed there and status refreshed here. Passwords
are entered in NetworkManager's tools, never QML or helper arguments. Profiles,
certificates, and credentials remain outside Hyprshell's config payload and
GitHub sync. Installing the UI does not change this laptop's connections.

Network checks: `python3 -m unittest discover -s tests -p test_network.py -v`.
These exercise isolated commands and the native Settings page without touching
the real network. Physical network behavior requires a desktop-session check.

**Hyprpane → Layout & spacing → Screen edge** selects Top, Left, Right,
or Bottom. `bar.position` defaults to `top` for existing settings. On either
side edge, the left item group sits at the top, the center group stays centered,
and the right group sits at the bottom, keeping each group's existing order.
On Left and Right, Hyprpane shows icons only in circular pills. The calendar
uses a calendar icon; volume, battery and notification values appear in tooltips
and their menus. Workspace names become filled/hollow workspace icons with
identifying tooltips. The pane stays 40 logical pixels wide by default; explicit
thickness, icon/font sizes and inside padding still apply. **Edge margin** applies to
the chosen screen edge and **End margins** applies to the two ends. The existing
`height`, `marginTop`, and `marginSide` keys preserve these preferences.

Menus open toward the desktop from each edge; their glass connectors, hover
bridges, screen coordinates, and input region follow the bar. The portrait
Settings preview supports selecting and dragging items between Top, Center,
and Bottom groups, using the same saved `left`, `center`, and `right` IDs.
Position changes use the usual validated autosave and apply across monitors.

**Side panel length** selects **Full edge** (default) or **Compact** on Left/Right,
saved as `bar.verticalPresentation: "edge" | "compact"`. Full edge retains the
Top/Center/Bottom alignment groups and moves the middle group only as needed to
prevent collisions. Compact keeps those groups in order with deliberate gaps
and centers the shorter pane on its edge. No whole-edge background is added.
Existing per-item spacing, ordering, shared pills and explicit radii remain.
On side edges, shared pill backgrounds appear as individual circles while group
membership and ordering remain saved. Side circles override corner radii visually;
saved radii and labels apply again on Top/Bottom.

If the content exceeds the available height, the pane scrolls with a visible
scrollbar. Wheel over a status item, drag, use the scrollbar, or Tab to a control
to bring it into view. Workspace wheel switching and tray scroll actions retain
their existing behavior. The Settings preview supports scrolling and still maps
click/drag positions correctly. Tray targets use the same circular size as the
side controls and stack vertically. Saved tray labels return horizontally; icon
hiding remains supported. Enter activates a focused control or tray item;
the Menu key opens a tray context menu.

The calendar icon opens the existing calendar and shows the saved clock format
or custom text in its tooltip. Media uses five spectrum bars centered inside a
circular pill, with the complete title or custom label in the tooltip. Its saved
icon visibility setting still controls the spectrum. Notification counts stay
in the tooltip/inbox; the bell color signals unread notifications without digits.
Menu cards open inward beside their trigger, clamp to the available screen space,
and scroll their contents when necessary; keyboard focus reveals controls inside
the card. Top and Bottom keep their horizontal text, counts, spectrum and radii.

Bar layout follows each module's enabled setting and data availability, rather
than its inherited `Item.visible` value. Hiding the Settings preview or a
workspace-specific bar keeps module positions, shared pills, and height intact.
This avoids rebuilding the layout and repeatedly sampling wallpaper colors
during a page or workspace switch. Disabling an individual module still removes
its layout space, including while the whole bar is hidden.

![Hyprshell Settings, Windows page](assets/settings-preview.png)

`SettingsController.qml` owns a `LazyLoader` that is inactive at startup. Both
the cog and launcher activate the same controller. Closing the native window
flushes pending edits; the controller waits for the writer and debounce timer
to become idle before unloading all controls and the preview. If saving fails,
only the draft, original snapshot, selected section, and error are retained in
the controller, then restored on the next open. Reopening during a save keeps
the current window and draft alive. Saved settings and desktop services remain
in the always-loaded store and service components.

`settings/defaults.json` defines schema version 1 and the built-in module IDs:
launcher, settings, workspaces, media, calendar, tray, notifications, audio, wifi,
bluetooth, battery, power. `SettingsStore.qml` merges saved preferences with
defaults, watches changes, and retains the last readable configuration when
JSON parsing fails. `SettingsModel.js` is shared by the window and the bar.

The preview captures click and drag gestures through `PreviewLayoutEditor.qml`.
Clicking selects an item's editor. Dragging shows an insertion marker; dropping
reorders within a group or moves between left, center, and right. Empty preview
space uses the corresponding third of the bar. Dropping outside cancels.
`SettingsModel.reorder` preserves appearance settings and hidden items while
assigning unique orders. The tray uses a sample icon so it can be rearranged too.
Changes enter the normal autosave flow only on drop.

**Reset item** restores the last successfully saved appearance and position,
using saved neighbours after drag operations renumber a group. It never loads
bundled item defaults. The button waits for any in-flight save to finish.
Because edits autosave, already saved edits become the new reset point.

**Hyprpane → Default appearance → Random vibrant item colors** gives
inheriting item icons and labels distinct bright colors. The shuffled palette
reshuffles when the wallpaper image changes, while staying stable during edits
and matching the preview to the live bar on the same screen. Returning to a
wallpaper restores its palette for the current session. Pill backgrounds become darker
and more opaque where needed for contrast. With pills hidden, vibrant accents
become darker on light wallpaper and lighter on dark wallpaper to stay readable.
Restarting the shell reshuffles the palette. Turning it off restores the current
theme. Manual text/icon colors and explicit item adaptation on/off choices take
priority. Pill backgrounds adapt with the vibrant accent for contrast, and tray artwork remains
application-provided. The preference defaults to off on existing installations.

Background controls use an explicit **Show background pill** switch: switching
off removes the pill immediately in the preview and saves that choice. The
general control affects all inheriting items; each item can set its own switch
or choose **Use general setting** to follow the global choice again.
**Show shared (common) pills** controls named group backgrounds separately and
defaults to following the general background switch. Select any member and use
**Shared pill → Show this shared pill** to override the whole group; the choice
is saved on every member, so hiding or reordering members preserves it. Joining
a group adopts its existing shared background choice. Hiding a shared background
keeps the group's layout, padding, spacing, and individual actions.

With backgrounds hidden, icons and text use smooth Qt glyph rendering and a
subtle contrasting shadow, including manual colors. Wallpaper adaptation measures
bare colors against the area's darkest, brightest, and intermediate tones,
including in vibrant mode. When a textured area cannot provide enough contrast
with one color, a thin opposing edge protects the glyph silhouette. The same
protection covers the media spectrum, glass launcher/cog, and notification count;
uniform areas retain the softer shadow. Manual color choices remain overrides.
Wallpaper sampling retains fine details at screen resolution (bounded at 4096
columns and 160 rows) so small bright patches are not averaged out first.
An accent underline marks a hovered or
selected control and the active workspace without restoring a background pill.

The footer describes each page's saving behavior. Bar appearance, desktop
appearance, input, accessibility, notifications, clipboard capture, and idle
timers save automatically. Custom keyboard layout text enters that draft while
typing, without needing to leave the field. Application colors/defaults/startup
save immediately; sound and hardware controls use their existing services.

Display layouts still require Apply and the timed Keep confirmation. Lock command,
font/cursor, keyboard shortcuts, cleanup schedules, language/region, workspace
rules, and backup plans require their explicit Save or Apply button. Typed lock
commands cannot replace the active locker before Apply, and nonexistent commands
are rejected. Deletion, restore, upgrades and other actions retain their separate
confirmation flows.

Unapplied manual edits survive navigation and closing/reopening Settings within
the running shell. The footer highlights these edits and disables GitHub sync
until they are applied or discarded. Drafts are not written to disk on close and
do not survive a shell restart or logout. Clean pages still unload normally;
hidden dirty pages retain their controls without starting polling. Display
previews continue to revert when leaving their page. Changing application colors
preserves unapplied font/cursor choices. Cleanup preview waits for schedule edits
to be saved or discarded, so its preview uses the settings shown on screen.

The editor keeps a draft and saves it automatically after 200 ms without an
edit. Hyprpane appearance, placement, visibility and item edits preview immediately
on the running panel, including while a previous snapshot is saving. Previews do
not replace the saved snapshot used for conflict detection; failed saves revert
the running panel to saved preferences. Incomplete color input retains the saved
color until a valid color is entered. Closing keeps the preview until the pending
save finishes. Identical writer/file-watcher snapshots do not refresh the panel
again, and save completion does not request a redundant file reload.
A bottom status message names the settings in the successfully saved
snapshot (for example, “Bluetooth settings saved!”) and clears after two seconds.
Opening the window shows no save confirmation; save errors remain visible.
Closing the window flushes pending edits. Native window closes also reset
the requested visibility, so subsequent launches remap it correctly. Opening
an already visible Settings window requests focus by its existing window address
without resetting the draft or its tiled/floating state. Each save invokes
`settings/backend.py` with an argument array, without shell
interpolation. The backend validates all values and rejects unknown settings,
duplicate module IDs, malformed colors, unsupported schema versions, and
out-of-range numbers. A file lock serializes writes, and comparison with the
editor's initial snapshot prevents overwriting settings changed by another
window or tool. Malformed stored files must be repaired before saving.
The editor captures the submitted snapshot separately from the current draft:
edits made during a write queue another save after that write completes. Invalid
values are not saved; correcting the input retries automatically. Errors do
not cause a continuous retry loop. A Reset unsaved changes button appears
when validation or saving fails.

`GlassSymbol.qml` provides a reflective vector fill and edge, shared by
`GlassLogo.qml` and `GlassCog.qml`. The cog has a rounded gear silhouette and
transparent center. Both retain the original menu hit areas and feedback;
their default pill backgrounds are hidden. Offset glass silhouettes add depth,
with a bright front rim and a smooth reflective face. The cog uses a standard
settings silhouette with an open hub.

The top-level keys are `version`, `bar`, `items`, `hyprland`, `locking`, `power`, and `notifications`. Item entries
are keyed by `id`; missing entries/properties inherit bundled defaults.
`side` accepts `left`, `center`, or `right`; `order` sorts within that side.
The three groups are positioned independently, so unusually wide custom text
or an overcrowded center group can overlap adjacent groups. Shorten overrides,
reduce font size, hide modules, or distribute items between groups in that case.

`bar.spacing` sets the general gap between visible items. Select a module in
the sidebar or preview and use its **Item spacing** card to adjust **Space before adjustment** and **Space after adjustment** independently of that global gap.
Reset either slider to restore the global gap on that side. Each item's
`spacingLeft` and `spacingRight` adjust space outside its pill by −200–200 px; negative values reduce gaps,
positive values add space, and the final gap is clamped at zero to avoid overlap.
Outer group margins are also clamped at zero;
these margins also count toward group alignment. For example, general spacing
of 5 plus Wi-Fi's `spacingRight: 10` leaves 15 px before Bluetooth (with
Bluetooth's left spacing at 0). Hidden items contribute no spacing.

`bar.background` accepts `inherit`, `on`, or `off`. Inherit preserves each
component's original background; on/off shows/hides all item pills. Individual
`background` overrides take priority; inherit follows the global choice.
`bar.sharedBackground` and item `sharedBackground` accept `inherit`, `on`, or
`off`. The item setting controls its named group's background, then inherits
the bar shared choice, then the general background choice. Inherit preserves
visible shared backgrounds when the general choice is also inherit. The first
visible group member supplies the background colors, opacity, and radius.

`adaptiveColors` and `background` on items accept `inherit`, `on`, or `off`.
Empty text/icon/color strings inherit original values. `hideText` and
`hideIcon` explicitly hide those parts. `backgroundOpacity: -1`, `radius: -1`,
and `fontSize: 0` follow the item's size (original text size at the default scale). Manual color fields override
adaptive results without disabling adaptation for the other fields. Colors
are RGB; alpha comes from the separate opacity controls. Font glyphs use the
installed Nerd Font; image files are not accepted as custom icons yet.
For controls whose original glyph is in the text field (Wi-Fi, Bluetooth,
notifications, power), use the text/glyph override to replace it. Icon color
also colors these original glyphs. Launcher icon color colors the glass logo;
media icon color colors the spectrum, and Hide icon hides the spectrum.
Tray artwork remains application-provided; text/icon overrides do not replace it.

`Bar.qml` keeps existing component identities and service connections while
computing each item's position from its group, order, visibility, and width.
Menu anchors read those coordinates directly. Each popdown card is centered
under its trigger and clamped to 12px screen margins, so moving or reordering
an item updates both the card and connector, including while pinned open. `Pill.qml` implements reusable appearance
overrides; a null sampler selects original static colors. Notifications and
other shared services are independent of status-item visibility.

Hyprland controls are explicit overrides, not a full configuration editor.
The app never assumes the visible numbers in a user's Lua file are the effective
runtime values. An empty field means unmanaged, including on first launch.
`backend.py` contains a whitelist mapping GUI keys to Hyprland configuration
paths. It generates Lua tables or traditional config options; user strings
never become executable Lua. The Lua source hook in the bundled config runs
after `hyprland-gui.lua`, so the settings app's explicit overrides take priority.
Other users' main configs receive a source hook only on their first Hyprland
appearance change. Hyprland source integration assumes the conventional
`$XDG_CONFIG_HOME/hypr/hyprland.lua` or `hyprland.conf` path.

To extend the app with another built-in module, add its defaults, register its
component in `Bar.moduleItems`, bind visibility/position/appearance, and add its
display name in `SettingsWindow.qml`. Extend backend validation and regression
checks when adding a setting. Supporting another Quickshell shell requires an
adapter that implements these settings against that shell's components; parsing
arbitrary QML is not a reliable substitute.

Checks:

```sh
python3 -m unittest discover -s tests -v
QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
  /usr/lib/qt6/bin/qmltestrunner -input config/quickshell/tests
```

Python checks isolate XDG directories and exercise validation, concurrent edits,
backups, Lua/conf source integration, and rollback after reload/write failures.
Native UI checks also close/reopen real windows and exercise on-demand loading,
queued writes during close, destruction after saving, failed-draft restoration,
and reopening during a write.
QML checks cover visibility/layout changes, ordering, menu anchors, global and
per-item adaptation, manual style overrides, and hidden media lifecycle, alongside
the existing service/component regression suite.

The Hyprland appearance page groups controls into transparency, glass and blur,
window geometry, and motion/depth cards. The bar preview is hidden on this page
to leave room for the compositor controls. Cards use two columns on wider
windows and stack controls at narrower widths. Sliders support dragging, clicking,
and keyboard arrows. Transparency is displayed as 0–100% and saved as inverse
opacity (25% transparency means `activeOpacity: 0.75`).

Glass controls map `blurSize` (1–20), `blurPasses` (1–4), and `blurVibrancy`
(0–1, displayed as a percentage) to `decoration.blur.size`, `.passes`, and
`.vibrancy`. These ranges provide bounded controls for the options documented in
[Hyprland's blur reference](https://wiki.hypr.land/0.54.0/Configuring/Variables/#blur).
Blur sliders are disabled when blur is explicitly off; their saved values remain
available when it is enabled again. Translucency is needed to see blur behind
otherwise opaque windows; application-specific opacity rules can take priority.

Unmanaged sliders read “Use config” and show a suggested thumb position, not
an inferred runtime value. They do not write an override until interacted with.
Each reset arrow removes just that override and restores configuration inheritance.
Sliders use the same validated, debounced autosave and rollback path as other
settings. There are no new overrides on upgrade or when merely opening the page.

Item sizing is available in **Overview and bar** and each item's editor.
`bar.iconSize` sets icons to 8–48 px and scales labels proportionally from a
16 px icon baseline; `0` keeps original sizes. Each item's
`iconSize` overrides the global value, with `0` following the global setting.
Reset arrows restore original sizes globally or inheritance individually.
Glyph icons, the glass logo and cog, tray artwork, the media spectrum, workspace
numbers, the clock, percentages, media titles, and notification badges resize
in the live preview and the running bar. An explicit item `fontSize` overrides
automatic text scaling; reset **Text size** to follow item sizing again. Automatic
label sizes have an 8 px minimum. Larger content expands hit areas and bar height
to avoid clipping. Items without a built-in icon use this size for icon overrides.

Hidden pills preserve accent hue and saturation, adjusting lightness on uniform
wallpaper to provide at least 4.5:1 text contrast. Mixed regions retain colorful
fills with contrasting glyph edges. Sampling uses actual pixel luminance bounds,
including small wallpaper details; the glass logo and cog use richer, opaque
faces while their pills are hidden. Shared visible pills retain their glass style.
Old experimental motion preferences are ignored and removed on the next save;
popdowns use the original fade-and-slide transition.

All settings pages share the same preference-group structure and spacing. **Hyprpane**
groups layout sliders, default appearance, and clock formatting with a sample.
Item pages group visibility/position, text/icon overrides, colors/background,
and shape/transparency. Grids stack into one column below 600 px of editor
width; background switches and inheritance actions also stack in narrow cards.
The live bar preview scales to fit narrower windows. Sliders display pixel or
percentage units; reset arrows restore bundled bar defaults or the original item
appearance as appropriate. The final item restore action retains its existing
last-saved semantics. Hover, focus, and switch transitions use the shared native
controls; no new configuration keys or startup services are introduced.

## Screen locking

The Screen locking page selects a foreground Hyprland-compatible locker command, an idle
period (0–240 whole minutes; 0 disables the timer), and locking before sleep.
Automatic locking defaults to off. Existing preferences inherit these defaults.
Lock now runs the last saved command without enabling automatic locking.
Commands accept quoted arguments and `~` paths; no shell operators or environment
variable expansion is performed. Configure the chosen locker's appearance in
its own configuration file, for example `hypr/hyprlock.conf`.

`LockingController.qml` owns a Hypridle child while automatic locking is enabled,
restarting it only when locking preferences change. Closing Settings does not
stop locking or a manually started locker. The controller reports startup and
locker errors in Settings. Backend validation checks installed dependencies when
enabling/changing automatic locking. An existing Hypridle process is left alone
and reported as a conflict; disable its user service/autostart before enabling
Hyprshell management. The generated `hyprshell/hypridle.conf` belongs to Hyprshell;
`hypr/hypridle.conf` and locker configuration files are preserved. This controller
runs for the lifetime of the Hyprshell session.

When locking before sleep is enabled, Hypridle explicitly waits for the
compositor's lock notification (`inhibit_sleep = 3`); automatic detection cannot
recognize Hyprlock behind the Python backend. The locker supervisor retries
Hyprlock's exits against `hyprctl -j locked`. While the compositor confirms the
session is locked, recovery continues even after ten failures, slowing retries
to once every ten seconds. An unlocked session stops supervision. If compositor
state is unavailable, the previous bounded retry behavior remains. Custom
lockers retain their existing positive-exit handling. Resume also requests a
serialized locker recovery only if the compositor still reports a locked session,
even when no power timers are enabled. Locker output and retry reasons are saved
locally in `state/hyprshell/locker.log` (rotated between locker invocations above
1 MiB, with one previous log). These logs have owner-only permissions and stay
outside configuration sync. Custom locker output retains its existing handling.

The backend's `--lock` executes the configured argv directly and serializes
foreground locker requests. `--idle` generates Hypridle configuration with only
fixed helper commands; user commands are never interpolated into Hyprlang or Lua.
Automatic locking uses Hypridle's normal inhibitor handling and D-Bus sleep/lock
events. Custom lockers must support your session and remain in the foreground
until unlocked; test authentication with Lock now before relying on automation.

### System cleanup

Open **System cleanup** in Hyprshell Settings. Choose Off, Daily, Weekly, or
Monthly, select cleanup categories, then click **Save cleanup settings**. This
separate save manages `hyprshell-cleanup.timer` in your systemd user session.
Scheduling defaults to Off; the age limit defaults to 30 days and the newest
five Hyprshell backup sets are retained.

Cleanup includes old thumbnail cache files, your own regular files in `/tmp`
and `/var/tmp`, and old files in Hyprshell's configuration backup directory
(`$XDG_STATE_HOME/hyprshell/backups`, normally `~/.local/state/hyprshell/backups`).
Recently accessed, modified, or changed files are kept. Symlinks are skipped,
empty directories remain, and active configurations are excluded.

**Preview scheduled cleanup rules…** displays the eligible paths, individual sizes, and total
size using the saved choices. **Delete previewed files** confirms deletion;
if the eligible files changed, preview again. Scheduled runs apply the same
rules without prompting. Results are recorded in
`$XDG_STATE_HOME/hyprshell/cleanup-last.json` and the service journal.

The page also reports the existing system `paccache.timer` status. Its package
retention remains independent of the user cleanup schedule.

#### Manual file and system maintenance

**Clean now · your files**, shown first, adds per-directory switches for Chromium,
Firefox and Brave caches, user DNF metadata, npm download cache, thumbnails,
Flatpak download metadata, graphics/font/Qt caches, desktop Trash and older
Hyprshell recovery backups. Nothing is selected by default. Each switch names
the directory, affected component and consequences: rebuildable content,
troubleshooting history, recovery history or personal recovery copies. Application
profiles, cookies, saved logins, documents, installed software, cached OpenCode
tools, VM disks and container volumes remain outside automatic deletion.

User manual age defaults to zero, including recent files; administrator file
cleanup defaults to seven days. The scheduler retains its saved age. Keep newest
backup sets defaults to five, with at least one always retained. These choices
do not save or modify the existing scheduler. Browsers and package download
tools must be closed: an active related process skips that cache, and an activity
change invalidates the confirmation. Recently accessed, modified or changed
regular files are retained when an age is set. Symlinks, other users' files and
mounted child directories are skipped; empty directories remain.

**Backup / temporary copies in a chosen folder** accepts an existing non-hidden
folder below home, such as Documents or Downloads. Only `.bak`, `.backup`,
`.orig`, `.rej`, `.tmp` and names ending in `~` are candidates. Full home,
hidden folders, the `repos` folder, discovered Git/Hg/SVN repositories and
symlinked ancestors are refused or excluded. `.old` database files and editor
swap files are not classified as disposable. Even eligible copies can contain
valuable recovery data; review their paths before confirming.

**Analyze & preview** shows per-category sizes and impacts plus individual files
in pages of 200. Uncheck files to retain them; exclusions persist across pages.
Files on unvisited pages remain selected. **Open full file list** opens the local
text manifest for user cleanup. Confirmation checks the complete file identity
and eligibility again, expires after five minutes and cannot be reused after
cleanup starts. A changed preview fails before deletion. Each file is checked
again immediately before unlinking. Partial failures identify failed operations
and require a new preview before retrying. File contents are never read by the
scanner. Local previews, paths and results remain outside GitHub sync.

**System files · administrator access** has separate switches for package caches,
policy-expired `/tmp` and `/var/tmp` files, journal archives, old crash dumps and
older Hyprshell boot/login appearance recovery sets. Opening Settings/catalogs
does not authenticate, scan protected directories or mutate the machine. Each
system preview, file-list page and confirmed cleanup uses a short authenticated
`pkexec` job. Preview state is root-owned and private, separated by desktop UID;
there is no persistent administrator worker or password storage.

System commands are fixed by category; neither arbitrary directories nor shell
commands are accepted. Fedora uses `dnf clean all`; Arch uses `paccache -rk2`
(skipped if unavailable). Temporary cleanup invokes only `systemd-tmpfiles
--clean --prefix=/tmp --prefix=/var/tmp`, preserving configured exclusions and
avoiding boot-only removal or purge. Journal cleanup rotates logs and vacuums
archives to at most 14 days and 100 MiB; active logs may exceed that size. These
tools use their own retention policies, independent of the manual age control.
Their preview sizes are observed usage, not promises that every shown byte will
be reclaimed; journal growth does not invalidate the confirmed fixed policy.
Crash dumps and retained recovery files use the individual-file preview rules.

**Empty desktop Trash** delegates to `gio trash --empty`, including Trash on
mounted drives. Its displayed estimate covers home Trash only. Restoring trashed
files becomes impossible after emptying. Native Trash handling keeps its file
and metadata lifecycle consistent.

#### Reset and factory reset

**Reset Hyprshell settings** previews changes to the preferences in
`hyprshell/settings.json`, requires typing `RESET`, creates a recoverable desktop
settings checkpoint and uses the normal validated transaction with rollback.
It restores shipped defaults for the bar, item appearance, compositor overrides,
input, notifications, locking, power, accessibility and clipboard capture.
Unapplied Settings drafts must be saved or discarded first. Recover the previous
preferences from **Updates & recovery → Desktop settings recovery**. Separate
theme/display/shortcut/default-app preferences, manual desktop configuration,
installed apps and personal data are preserved. This is a settings reset, not a
clean OS installation. A checkpoint on the same disk does not survive formatting.

**Full factory reset / clean OS installation** explains preparing and verifying
an external backup, booting installation media, reviewing exact partitions before
formatting and reinstalling the OS. Formatting erases accounts, apps, settings,
documents, VM disks and containers on those partitions. Keeping home retains old
data and is not a complete reset. Hyprshell has no universal laptop factory image
and this panel does not execute disk erasure or an OS reinstall. Cache cleanup
cannot produce the same result.

Checks: `test_system_cleanup.py` uses temporary files and mocked system commands;
`test_system_cleanup_ui.py` drives actual native controls in an isolated home,
including preview/exclusions and checkpointed settings reset. Neither runs real
administrator maintenance, wipes disks or resets the laptop's preferences.


### GitHub sync

Use ** Sync to GitHub** in the settings header. Authenticate with GitHub; the
popup automatically finds `<your-account>/hyprshell` and displays that target.
Your GitHub username and account ID supply the commit identity using GitHub's
noreply email, so there are no name or email fields. Sync saves that identity
only in this checkout's Git config.

Both forks and standalone repositories named `hyprshell` work. If your account
has no accessible repository with that name, the popup offers **Fork Hyprshell**
and **Create repository** links. Finish creating it in your own account, then
click **Check again**. For a new standalone repo, leave README, license, and
.gitignore initialization unchecked so the first push can populate it. Sync is
enabled once the repository exists and the signed-in account has push access.

Authenticate opens Kitty with GitHub CLI browser sign-in and sets up its Git
credential helper. If GitHub CLI is missing, the terminal offers to install
`github-cli` through pacman. No password or token is entered into Hyprshell.
The account and repository are checked again on each sync, including after an
account switch. The checkout's origin remote is preserved; the push explicitly
targets the authenticated user's repository.

Manual changes remain live and uncommitted until **Sync to GitHub**. Completed,
validated agent tasks are committed locally with meaningful descriptions;
questions and unfinished tasks are not committed. The button captures
live `hypr/`, `quickshell/`, preferences and editable Lua into `config/`, reconciles
checkout edits, validates and commits locally before pushing. Existing commits
and messages remain intact. A failed push retains the local commit for retry.
There is no periodic Git saver. Staged changes or conflicting checkout/live
copies require resolution first. Configure a Git identity on fresh clones.

Managed portal files, autostart entries, utilities, application entries and only
`default.jpg` are included. Extra wallpapers, backup paths, history, credentials,
caches and logs are excluded. Setup records the checkout under
`$XDG_STATE_HOME/hyprshell/repository` (default `~/.local/state/hyprshell/repository`).
Fresh installs use the author's committed configuration; updates preserve local
customizations through a reviewed merge.

### Sync from GitHub

Checking does not commit or change local edits. Each conflicting file shows its
local and GitHub versions. Choose **Keep local** or **Use GitHub**, then **Review
choices**, acknowledge the resulting review, and **Sync now**. Choosing a version
keeps the whole file or its deletion. A changed choice requires another review;
editing your files after preview requires a fresh check. Unsynced edits kept
during updates remain uncommitted until Sync to GitHub.


The right-hand GitHub button opens `SettingsGithubUpdateReview.qml`, with process
coordination in `SettingsGithubUpdate.qml` and the backend in
`settings/github_update.py`. Preview fetches the tracking branch and shows commits,
file changes, package requirements, compatibility and hardware limitations.
The confirmation is disabled until blockers are resolved and the user acknowledges
the review. A token binds apply to the reviewed Git objects and live fingerprint.
The detached worker validates staged payloads with `settings/deployment.py`,
preserves preferences and history, and records recovery files. See
[updates.md](updates.md) for source selection, merges and recovery.

## Shared bar pills

Hyprpane → Default appearance includes **Enable Hyprknots**
(`bar.hyprknots`, default On) for the connector line and decorative knots.
Gaps touching an item without a background pill use only the connecting line;
decorative knots appear when both neighboring items have pills. This also follows
workspace buttons and shared-pill backgrounds on all four edges.
The gaps between left and center, and between center and right, always retain
decorative knots, even when their neighboring items have no pills.
**Hyprknots line thickness** adjusts the connecting line from 0.5–6 px
(`bar.hyprknotsLineWidth`, default 1.8). **Hyprknots knot size** scales the knots
from 50–200% (`bar.hyprknotsKnotSize`, default 100); large knots stay within their
available gap. Each slider resets independently and retains its value while
Hyprknots is disabled.
**Show full Hyprpane pill** (`bar.fullBackground`, default Off) draws one pill
behind every visible item, spanning the first through last item on any edge.
It uses the first visible item's colors, opacity and radius with the same
wallpaper adaptation as shared pills. Use **Follow background pills** to inherit
the global background switch, or choose On/Off independently. Individual and
shared backgrounds retain their own controls and can be hidden for a single
continuous pill. Item placement, grouping, clicks and menus are preserved.

Select a module and open **Shared pill**. Enter a group name to create a pill,
then select that name on any other modules to join it. Choose **Own pill** or
clear the name to remove a module. All built-in modules can share a pill;
there is no smaller membership limit. Modules remain individually clickable,
and their menus follow their positions. Hidden modules do not occupy space.

Members are kept together in their existing order. Joining a pill adopts its
alignment; changing a member's alignment moves the whole pill. Dragging a
member to another alignment removes it from its old pill. Dragging within the
same alignment retains membership. Use Earlier/Later or the preview to reorder.
**Hyprpane → Inside shared pills** sets the base gap between members;
individual before/after adjustments still apply. The regular gap separates
pills and standalone items.

The first visible member supplies the shared pill's background colors, opacity,
and radius. Individual backgrounds are suppressed while grouped, preserving
each module's stored appearance for removal. Named pills display a shared
background even when the global background switch is off. Group names
(`items[].pillGroup`, up to 40 characters) and internal spacing
(`bar.groupSpacing`, 0–30 px) use the normal validated autosave. Existing saved
settings default to separate pills.

Per-module **Padding inside pill** adjusts the left and right space inside
its click area. Increase the first member's left padding or the last member's
right padding to inset content from a shared pill's edges. Unlike gap adjustments,
this space is covered by the shared background. `paddingLeft` and `paddingRight`
are signed adjustments (−200–200 px) to original padding; final padding stops at
zero. Reset restores the original padding. Media keeps space for its spectrum.

Every Settings slider includes **−** and **+** buttons to change its displayed
value by one step (usually 1 px or one percentage point). Buttons stop at the
slider limits, follow disabled controls, and use the normal autosave path.
For inherited values, the first click adjusts the suggested value; reset
restores inheritance.

## Keybindings

Open **Keybindings** in Settings to browse a searchable shortcut list. Select an
action or click **+ New** to open the compact editor. Use **Record shortcut**
(or **Record again**) and press the desired combination; release all keys to
confirm. Escape cancels recording without changing the draft. Recording enables
Quickshell's Wayland `ShortcutInhibitor` on the Settings window and releases it
when recording ends, loses focus, or the page closes. If inhibition is unavailable,
recording reports that instead of pretending to capture compositor shortcuts.
**Enter manually** remains available for mouse buttons and unusual key names.

Action and command fields stay out of the recording focus path. Key combinations
appear as keycap badges; conflicts are shown inline before saving. Incomplete or
unchanged drafts cannot be saved. Save closes the editor with a brief confirmation;
Cancel discards the editor draft. Refresh and selecting another row wait until
an edited draft is saved or cancelled.

To add command shortcuts or edit the keys and labels of active desktop shortcuts,
select an action in the searchable list,
choose **Keep existing action** to preserve its Lua callback and flags, or
choose **Run a command instead**. **Save shortcut** validates and applies the
change immediately. Duplicate combinations are rejected. **Restore original**
removes a saved override; **Remove shortcut** removes a newly added command.
This page uses an explicit save so incomplete commands never become active.

The Super+K QML overlay reads active Hyprland bindings on opening and refreshes
every 1.5 seconds while open, preserving the current search. Its action labels
come from the binding description. It remains a centered layer-shell overlay
with keyboard focus, Escape dismissal, and dismissal on pointer movement outside.
Every returned registration is retained, including duplicate combinations with
different actions, submaps, extra modifiers, keycodes, mouse bindings and
release triggers. Context and trigger labels are searchable. Media keys have
readable labels while retaining their XF86 names for search. Local controls for
Settings, the launcher, menus, shortcut recording, standard shell navigation,
and this setup's Kitty copy/paste mappings are listed with their scope; these
are not global shortcuts. Application-provided defaults outside this setup are
owned by each application. The footer counts matching and total entries.
An IPC error stays visible even when local entries or a previous desktop list
remain available. No configured shortcuts are filtered through the narrower
Settings shortcut editor's remapping rules.

**Alt+Q** reloads Hyprland first, then Quickshell through the existing
`bar.reload` IPC action. This activates saved compositor shortcuts as well as
shell changes. Repeated requests while the compositor reload is running are
ignored. The compositor command has a 15-second limit; if it fails, the shell
still reloads and the failure is logged. The existing shortcut command remains
valid, so an older active Alt+Q binding gains the combined action once Quickshell
loads the updated shell code.

Preferences live in `hyprshell/keybindings.json`; the backend generates
`hyprshell/keybindings.lua`. The bundled `hypr/keybindings.lua` captures original
binding actions while loading the main Lua config, then applies overrides at
the end. Original Lua callbacks (such as the minimize stack) and bind flags are
preserved when remapped. Base configuration files are not rewritten by edits.
The editor lists ordinary bindings in the default submap; custom submap and
extra-modifier bindings remain configured in Lua.

The Python backend locks writes, checks for concurrent edits, backs up replaced
files, verifies the Lua configuration, reloads Hyprland, checks configuration
errors, and rolls back files if validation or reload fails. Commands are passed
as quoted Lua strings to `hl.dsp.exec_cmd` and run only on a shortcut press.
Hyprland's [binding API](https://wiki.hypr.land/configuring/core/binds/) supplies
the bind, unbind, and description behavior. GitHub sync captures the saved JSON
and regenerates its Lua payload; setup restores both along with the Lua hook.

## Hyprpane visibility

**Hyprpane → Hyprpane visibility** provides **Show on all** and **Hide on
all** buttons. Either button replaces the default visibility for all workspaces
and clears individual choices. Choose a workspace (1–99) in **Individual
workspace**, then toggle **Show Hyprpane on workspace …** to change only that
workspace. The selector initially follows the focused workspace; choosing a
number lets you edit another workspace without visiting it. Settings autosaves
these choices.

Alt+T always toggles only the active workspace on the focused monitor. For
example, with Hyprpane shown only on workspace 1, pressing Alt+T on workspace 3
shows it on 3 while leaving 1 visible and other workspaces hidden. Choices survive
shell restarts and travel with setup/GitHub settings sync. Global visibility is
changed through Settings. Hiding a panel releases its reserved space and closes
its popdowns; services and menu shortcuts remain available.

`bar.workspaceOverrides` maps workspace-number strings to booleans and takes
priority over the saved default. Older `bar.visible`, `bar.workspaceScope`
(`"all"` or `"selected"`), and `bar.workspaceList` remain the default for workspaces
without an override, preserving existing selected-workspace setups. Missing
overrides inherit an empty map. Each screen uses its own active workspace.

## Popdown glass

**Hyprpane → Popdown glass → Popdown translucency** controls the background
of all inheriting popdowns and Super+K. The default is 6% translucency (94%
opacity), keeping text and controls fully visible. Each module has its own
**Popdown glass** slider; reset follows the general setting. These controls are
separate from bar item and pill opacity. `bar.popdownTranslucency` accepts 0–1;
`items[].popdownTranslucency` accepts 0–1 or −1 for inheritance.

Popdowns and Super+K share a dark, wallpaper-tinted gradient and reflective rim.
They sample the wallpaper region behind the card and update when it changes.
Compositor layer blur supplies the frosted background.

### Bar and popdown shortcuts

Alt+T toggles saved topbar visibility for the active workspace only. Alt+C opens the calendar, Alt+S opens
Settings, Alt+N notifications, Alt+A audio, Alt+W Wi-Fi, Alt+V Bluetooth,
Alt+B battery, and Alt+P power options. Either Alt key works for these shortcuts. Menu shortcuts toggle their card
on the focused monitor and close menus on other monitors. Escape or an outside
click closes them. When the bar is hidden, cards appear detached at the top
center; showing the bar restores their item anchors and connectors.

The shortcuts call `hyprshell-shortcut`, installed with the other launch helpers.
Topbar toggles use the existing settings writer when Settings is loaded;
otherwise `backend.py --toggle-bar WORKSPACE` updates only that workspace’s
override under the settings lock, preserving concurrent changes and all other
preferences. The shell captures the focused workspace when the key is pressed
and queues repeated presses while the writer is busy.

Use **Super+Alt+L** to lock, **Super+Alt+X** to shut down, **Super+Alt+R** to
reboot, **Super+Alt+S** to sleep, or **Super+Alt+O** to log out. These are global
bindings, listed in Super+K and beside the corresponding power buttons. **Alt+P**
opens the power menu; **Escape** closes it. The menu does not handle bare action
letters, so Alt+P followed by a letter is not a power shortcut.

## Displays

Open **Displays** in Settings. Each active monitor shows its advertised resolutions
and refresh rates, scale, rotation (including flipped orientations), and position.
Press **Super+P** to open a compact, centered Projector options overlay with Duplicate
(mirror) and Extend (**Alt+S** still opens Settings). These are the only two
buttons: choosing either applies and saves immediately, then closes the popup.
The header identifies Projector options. Duplicate receives keyboard focus on
every open; use arrow keys to switch buttons and Enter to apply the focused choice.
Duplicate uses the laptop screen as the source when available. A failed change
restores the previous layout. Escape or clicking outside also closes
the overlay, which stays above tiled windows like Super+K. Settings → Displays retains the
resolution, scale, rotation, and placement controls.
Pseudotiling is available on **Super+Shift+P**. With a TV or another
screen connected, select your laptop under **Screen to duplicate** and click
**Duplicate (mirror)** to show the same desktop and cursor on both screens.
**Extend** restores separate desktops with automatic placement. Each screen also
has a **Use this screen as** dropdown for individual extended/mirrored layouts.
These buttons prepare edits: click **Apply changes…**, then **Keep changes**.
Confirmed mirror choices are restored on login and when that connector reconnects.
Different aspect ratios can stretch the mirrored picture. Resolutions remain
independent so each display can use its advertised modes.
**Recommended (automatic)** selects the preferred mode. Resolution choices come
from the monitor’s advertised modes; a panel advertising only 1920×1080 has
that resolution plus Recommended. Scale uses the preset dropdown: Automatic, 75%, 100%, 125%, 150%, 175%,
200%, 250%, 300%, and 400%. **Arrange automatically**
lets Hyprland position that output. For multiple screens, choose another output and
use **Left / Right / Above / Below**; the placement accounts for scale and rotation
and fixes both positions. Logical X/Y fields allow precise adjustment.

Click **Apply changes…**, inspect the screen, then click **Keep changes** within
15 seconds. **Revert**, timeout, leaving the page, stdin closure, or termination
of the preview helper restores the previous layout. The helper owns the countdown,
so UI event-loop stalls do not extend it. A hard kill of the helper or compositor
failure cannot guarantee rollback; saved preferences remain unchanged until kept.
An unavailable session socket is reported as an error rather than an empty screen list.

Confirmed preferences live in `hyprshell/displays.json`; the backend generates
`hyprshell/displays.lua`, loaded at the end of the main Lua config. Preview changes
use `hyprctl eval` and never write tentative preferences. Confirmed saves are atomic
per file, backed up under `hyprshell/backups/displays-*`, and restored on a write
failure. A nonblocking transaction lock prevents simultaneous previews; stale
preferences and hotplug require refreshing. Disconnected outputs retain saved
preferences. Outputs without a saved rule retain the base automatic fallback;
connector names identify screens, so review preferences when replacing hardware.

Setup restores both files when present. GitHub sync snapshots confirmed JSON and
regenerates its Lua payload. No additional packages or permanent service are needed.
The initial page manages active screens; disabling outputs, mirroring, HDR, ICC
profiles, and VRR remain in the base configuration. Rollback reloads that base
configuration before restoring the prior live geometry.

Display fields follow the official [Hyprland monitor API](https://wiki.hypr.land/configuring/core/monitors/).
Regression tests cover preview/confirm/revert, hotplug, stale writers, rejected modes,
file-write rollback, sync, and real Quickshell controls with a simulated backend.
Physical modes and authentication-free desktop IPC require an accessible live session.

## Application theme

The same page also offers installed application fonts (6–32 points), installed
XCursor themes, and cursor sizes (16–64 pixels). Choose them and click **Apply
font and cursor**. The helper merges the corresponding GTK 3/4 settings and
GSettings keys, propagates cursor environment values through UWSM, and attempts
`hyprctl setcursor` for the running desktop. GTK-integrated Qt apps use these
preferences too; application-owned fonts or themes can take precedence.
See [GTK Settings](https://docs.gtk.org/gtk3/class.Settings.html) for the GTK keys.

The saved version 1 theme snapshot accepts optional `font`, `cursorTheme`, and
`cursorSize` fields; existing snapshots keep working. Switching Dark/Light keeps
these fields. A revision covers the saved snapshot, GTK files, UWSM block, and
current desktop keys to reject edits made since opening the page. File or
GSettings failures restore the previous appearance. Restore skips missing fonts
and cursor themes while retaining their saved choices; reopening Settings lets
the user choose installed replacements.

Open **Application theme** and toggle **Dark theme**; off selects Light. The
change saves immediately, independently of topbar preferences. The backend sets
`org.gnome.desktop.interface` color-scheme and GTK theme (Adwaita/Adwaita-dark),
and merges theme keys into GTK 3/4 `settings.ini` while keeping unrelated keys.
The [libadwaita appearance API](https://gnome.pages.gitlab.gnome.org/libadwaita/doc/1.8/property.StyleManager.color-scheme.html)
defines how apps follow the system preference. Applications can override it.

New Qt apps launched through UWSM use the installed `gtk3` platform theme plugin.
The helper updates the user manager environment and a managed block in
`uwsm/env-hyprland`. Existing apps may need reopening. If user-manager access
fails, Qt integration takes effect on next login. Hyprshell's explicit topbar
colors are not edited by this setting. Apps with custom styles or their own
appearance choice may require selecting Follow system.

Confirmed preferences are saved in `hyprshell/theme.json`, captured by GitHub
sync, restored by setup, and reapplied at Hyprland session startup. Without a
saved preference, startup leaves application appearance alone. Writes are locked,
checked for stale preferences, backed up, and rolled back together with the
GSettings keys after failure. Reapplying an already matching theme creates no
new backup. Credentials and unrelated GTK preferences are not imported into Git.

The installer explicitly includes GTK 3, GLib's GSettings tools, and GNOME desktop
schemas. Tests isolate desktop preferences and files and exercise the native toggle,
failed saves, rollback, sync, and preservation of topbar settings.

## Default applications and login startup

Open **Default apps & startup** for web browser, email, file manager, PDF, text,
office documents, spreadsheets, presentations, image, music, and video associations.
Office groups cover modern, legacy, macro-enabled, and OpenDocument files, with
installed suites such as Microsoft Office via WinPodX and ONLYOFFICE available
when they advertise support. A group can contain several MIME types;
selecting an app sets it for all of them. Different existing apps are shown as
a mixed group. The choices list installed apps advertising support for at least
one type, plus any installed current default. **Find apps** adds an exact MIME
type such as `application/zip`. Changes save immediately without opening files
or launching applications. Explicit shortcut commands stay independently
editable in Keybindings.

The helper uses GIO for application discovery and effective defaults and merges
`mimeapps.list`, preserving other associations and removing conflicts for the
chosen app. Existing user desktop-specific defaults are reconciled because
they have higher precedence. See the
[MIME application specification](https://specifications.freedesktop.org/mime-apps/latest-single/).

**Start at login** lists user and system XDG autostart entries. A toggle writes
a user override of the same filename, retaining its launch command, desktop
restrictions, and application conditions; the system file is untouched.
Entries restricted to another desktop or missing their required program carry
an explanation. **Add app** creates `hyprshell-<desktop-ID>` for Hyprland,
using `uwsm app -t service -- <desktop-ID>` so the original app's terminal and
working-directory metadata are honored. Already enabled entries with the same
launch command are rejected to avoid duplicate starts. Toggles apply at the
next login and do not stop an app that is currently running. The desktop's own
bar, wallpaper, power, and authorization services are outside this list.
See the [XDG autostart specification](https://specifications.freedesktop.org/autostart/latest/)
and UWSM's installed XDG autostart session integration.

`hyprshell/applications.json` version 1 stores `defaults` as MIME → desktop-ID
and `startup` as filename → `{enabled, application?}`. Transactions use a lock,
revision checks, backups, and file-write rollback. A single edit applies only
its selected association or startup entry, keeping manual changes to other
saved choices. GitHub sync exports this validated snapshot; unrelated custom
startup commands and application configuration are not imported. Setup restores
choices against installed apps before the next login's startup generator runs.
Missing apps or startup entries are skipped while their preferences remain
saved. Session startup retries restoration for apps installed later.

Tests use isolated files/homes, real GIO resolution, native QML controls,
failed-save recovery, and fresh-install restoration. They do not start login
apps or open personal files. Physical opening and next-login behavior require
testing in the desktop session.

## Application launching and theme propagation

The launcher opens desktop entry IDs using `uwsm app -t service`. UWSM processes
Terminal, field codes and working directory metadata, and systemd starts the
application with the current user-manager environment. This carries the selected
Qt platform theme into new launcher apps even when Quickshell started before the
application-theme toggle was changed. Existing application processes may need
closing fully before relaunching (including background instances).

`xdg-terminals.list` selects `kitty.desktop` and excludes Kitty's URL launcher;
setup restores this managed file, and GitHub sync captures user edits to it.
The [Quickshell DesktopEntry API](https://quickshell.org/docs/v0.2.0/types/Quickshell/DesktopEntry/)
exposes terminal metadata, which the original direct launch path did not handle.

GParted's installed wrapper uses `xhost` to grant root temporary XWayland access
and revokes access when it exits. Hyprshell now includes `xorg-xhost` in its
package list; existing installations missing it must install that package before
using GParted. See [GParted's Wayland startup workaround](https://gparted.org/news.php?item=214).
No persistent display permission change or passwordless policy is configured.
Application-owned themes, terminal color schemes and elevated applications may
use separate preferences from the desktop color-scheme setting.

## Legacy GTK application exceptions

GParted and About Xfce have managed desktop entries that call
`hyprshell-themed-app`. The helper reads the saved application theme each time;
About Xfce receives a scoped `GTK_THEME=Adwaita:dark` or `Adwaita` override.
This uses GTK's documented [theme variant override](https://docs.gtk.org/gtk3/running.html)
only for these apps; it is not exported to every app or the topbar.

GParted authenticates normally through pkexec, then launches its upstream wrapper
with fixed theme and XWayland environment values. The authentication prompt may
identify `/usr/bin/env`, which passes those values to `/usr/bin/gparted`. Root's
HOME is retained. Only root is temporarily granted display access; the helper
revokes a grant it made when the command exits or authentication is cancelled.
Pre-existing access is preserved. Upstream singleton checks and automount
inhibition still run. No root configuration or authorization policy is edited.

Setup installs the helper and the two app entries, and GitHub sync captures them
as managed files. Entries use TryExec so absent applications are not advertised.
If no application theme has been saved, the helper uses the ordinary upstream
launch command. Close and reopen these apps from the launcher after a theme
change. The ordinary `/usr/bin/gparted` command uses its normal root preferences.

## Mouse, touchpad and keyboard

Open **Mouse & keyboard** for pointer sensitivity, separate mouse/touchpad
natural scrolling, tap-to-click, disabling the touchpad while typing, keyboard
layouts and switching, and key repeat rate/delay. Controls share the normal
validated autosave transaction, backups, conflict checks, and reload rollback.
Opening the page leaves existing configuration unchanged. **Use config** or
↺ removes only that explicit override. Slider positions are suggested values,
not readings from connected devices; per-device configuration can take priority.

Common layout presets have descriptive names. Custom input accepts one to four
comma-separated installed XKB layout codes (for example `us,gb`). Configured
variants remain inherited; variants and other advanced keyboard options can be
edited in `hyprshell/hyprland/input.lua`. Switching choices are Alt+Shift,
Super+Space, and Caps Lock. Choosing one replaces `kb_options`, including any
existing Compose/remapping options; Use config restores the original options.
The typing field is temporary and never saved.

Settings saves layout strings as quoted Lua data. The installer validates saved
preferences and regenerates `hyprshell/overrides.lua` before restoring them, so
GUI input and appearance preferences survive setup on another machine. GitHub
sync already captures the saved settings JSON. No device identifiers are saved.
The installed Hyprland Lua parser accepts `input.touchpad.tap_to_click`; native
config validation covers that spelling and every new input option.

Validation covers invalid/injected values, fractional sensitivity, settings
round trips, override removal, real Hyprland parsing, native UI interactions,
and fresh-install restoration. Physical devices still require checking in an
accessible desktop session: adjust/reset pointer speed and scroll direction,
toggle tapping, switch between two layouts, test held-key repeat, and check
restart persistence.

## Power and battery

Open **Power & battery** for the battery summary, live laptop brightness,
inactivity timers, session lid behavior, and supported power profiles. The
brightness slider changes hardware immediately and does not save a startup
brightness preference. It discovers a backlight on the current machine rather
than saving a device identifier. External monitors without a backlight interface
need their own controls. Hardware/service errors appear alongside the relevant
control; Refresh checks again without changing preferences.

Power preferences use the existing validated autosave, backups, and concurrent
edit protection. All timers default to disabled, and lid/profile defaults leave
system behavior in control. Timer values are 0–240 whole minutes; enabled timers
must increase in order: dim, screen off, then suspend. Dimmed brightness is
1–100%, defaulting to 20%. Dimming never increases an already darker screen.
Separate AC/battery policies are not implemented in this first version.

`LockingController.qml` owns one shared Hypridle supervisor for locking and
power timers. Power timers can work with locking disabled; enabling them does
not turn locking on. Existing locking preferences remain separate. Hypridle
uses its normal inhibitor handling. Generated screen-off/wake commands use
Hyprland's Lua DPMS dispatcher. The supervisor stops its Hypridle child and
restores managed screen state on settings changes or normal shell shutdown.

`settings/power.py` keeps a private, locked brightness snapshot under
`$XDG_STATE_HOME/hyprshell`. Activity restores the previous raw brightness only
if the backlight still matches the dimmed value. Manual slider adjustments clear
the snapshot, and brightness-key changes are preserved when their value differs
from the dimmed value. Returning activity wakes managed screen-off state.
PowerController also attempts recovery of stale managed state when the shell
starts. These temporary records are not part of GitHub sync.

**Use system behavior** leaves laptop lid handling to logind. **Suspend when
closed** and **Keep running when closed** use a session `handle-lid-switch`
inhibitor and read available kernel ACPI lid sensors once per second. The
inhibitor is acquired before the watcher starts and is released when it exits;
no administrator configuration is rewritten. Unsupported sensors or denied
inhibitor access are reported as runtime errors and leave system handling in
control. Custom behavior applies even with external displays attached. A shell
starting with its lid already closed does not trigger an immediate suspend;
suspend occurs on the next open-to-closed transition. Closing Settings leaves
session controls running. Custom lid behavior ends with Hyprshell.

Power profiles come from `powerprofilesctl`/`power-profiles-daemon`. The dropdown
contains only advertised profiles, and saves a preference applied when the shell
starts or the saved choice changes. Unsupported saved preferences on another
machine report an error; choose another supported profile or **Use system
setting**. That choice leaves the currently active profile in place. Profile
application errors do not undo the saved preference, and the page distinguishes
the preference from the active service profile. External profile changes are
left alone until the preference changes or Hyprshell restarts.

The core installer now includes Hypridle and power-profiles-daemon; Hypridle
moves out of the optional app list. Saved power preferences already travel in
the settings JSON through setup and GitHub sync. `check_runtime.py` checks the
new command dependencies. No timers, custom lid behavior, profile preference,
or existing locking preference are enabled by this upgrade.

Automated checks cover validation and timer ordering, backwards compatibility,
brightness restoration and manual adjustments, Lua DPMS commands, profile and
lid failures, actual supervisor termination, native Hypridle configuration
parsing without a compositor, native UI/controller interactions, and setup/sync.
Physical brightness, display wake, suspend/resume, inhibitors, and lid behavior
must still be checked from an accessible desktop session. The implementation
uses the documented [Hypridle listener/sleep hooks](https://wiki.hypr.land/Hypr-Ecosystem/hypridle/)
and [systemd lid-switch inhibition](https://www.freedesktop.org/software/systemd/man/latest/systemd-inhibit.html).

### Applying new Settings components to a running shell

Create new QML components and helpers before updating the QML files that refer
to them. A hot reload during a partial copy can fail with “SettingsPower is not
a type” and leave the previous interface running. After all matching live files
are present, update the modification time of the live `quickshell/shell.qml`
to trigger another watched reload, then verify the active instance's bounded
`quickshell log --id <id> --tail 20` output reports **Configuration Loaded**.
Do not infer activation merely from installed files or isolated UI tests.

On 2026-10-10, this recovered the failed Power & battery activation without
restarting the desktop session. Direct IPC was unavailable to the agent, but
the filesystem-triggered reload and its success were visible in the live log.


## Notification delivery

Settings → **Notification delivery** controls optional popups, Do Not Disturb,
critical alert bypass, popup duration (2–30 seconds), and application preferences.
Popups default off, preserving the existing bell inbox. Do Not Disturb suppresses
normal popups while keeping inbox entries and unread counts. Critical popups may
bypass Do Not Disturb only when popups are enabled and critical bypass is enabled.
The bell tooltip reports Do Not Disturb; critical entries are labelled in the inbox.

Applications use their desktop-entry ID when supplied, otherwise their exact app
name. Applications seen in inbox history appear automatically; IDs/names can also
be entered manually. **Follow defaults** removes the override. **Inbox only**
suppresses all popups from that app. **Off** ignores new notifications, including
critical alerts; existing history is retained. Changing preferences removes any
currently visible popup that no longer qualifies and does not replay old alerts.

One popup stack appears at the top right of Quickshell's selected/default screen,
with at most three recent alerts visible. Overflow remains in the inbox. Normal
popups use fixed deadlines so removing a neighbouring popup cannot extend their
lifetime. Critical popups have no timer, but can be displaced by newer alerts.
Closing a popup retains its inbox entry. Actions use the same tracked notification
as the inbox; app expiry can remove a popup sooner. Critical notifications do not
use the shell's automatic expiry timer. Reloaded tracked notifications restore
history without replaying popups. Popup summaries/bodies are bounded plain text;
the inbox retains complete details. Popup display deadlines are temporary and do
not enter saved settings or history.

Notification preferences use the existing validated, backed-up settings transaction,
autosave and conflict checks. Setup and GitHub sync carry them through settings.json;
notification history stays outside the repository. Native tests cover simulated
delivery, replacement, reload replay suppression, timeout, critical persistence,
quiet mode, and app blocking. Real notification D-Bus delivery and Wayland popup
placement require a desktop-session check; the agent sandbox cannot access those
sockets. To check manually, enable popups, send a normal notification, enable Do
Not Disturb and send another, then send a critical alert. Check the inbox in all
three cases, test an app's Inbox only/Off modes, and reopen Settings after restart.


## Sound

Settings → **Sound** offers default output/input selection, master and microphone
volume/mute, an input-level test, a short output test tone, and volume/mute controls
for running application streams. The topbar Audio menu also selects microphones.
Device and stream discovery use Quickshell's PipeWire service. Every audio node is
tracked before controls read/write volume. Application controls include playback
and recording streams across all outputs; one application may have multiple rows.
Inactive applications appear when they create an audio stream, and disconnected
streams/devices disappear automatically.

Device selection sets PipeWire's preferred default through WirePlumber. Already
running applications may retain their current route. Volumes and defaults belong
to the sound system's policy/state; they are not written into Hyprshell settings.json
or exported by GitHub config sync. This avoids restoring another laptop's device
names. The installer restores the Sound controls and packaged test tone, with each
machine discovering its own hardware. Remembered volumes/defaults depend on the
installed WirePlumber policy.

Muting the microphone displays an empty volume slider and a Muted label while
preserving its gain. Unmute restores the slider to the saved gain. Raising the
microphone slider while muted sets the new gain and unmutes it.

**Test microphone** opens an active recording stream through the existing
PipeWire PulseAudio service only while the Sound page is visible and the test is
enabled. It uses the same native FFT helper and rounded, centered spectrum bars
as the topbar media player: twelve logarithmic frequency bands from 40 Hz to
7.6 kHz, updated every 16 ms, with fast attacks, a smooth release, and 40 ms bar
animations. Each band responds to its actual frequency content; the display has
no idle or generated motion. Microphone capture requires an explicit `--source`
argument naming the selected input. The topbar still opens only its output monitor.
The microphone path removes DC offset and uses a -50 dBFS quiet-input floor.
It seeds the FFT window at the initial input bias to avoid a false startup pulse.
Full-scale raw samples trigger a separate clipping warning when they make up at
least 1% of a capture block, including constant clipped inputs.
Audio is not saved or played back. Stop, page navigation, window close, or input
device change destroys the capture process and closes its stream. Muting shows
flat, dim bars immediately while preserving its gain.
Startup and capture failures appear on the page; a five-second startup watchdog
stops a capture that supplies no data, and a two-second watchdog clears stalled
readings and stops capture.
**Play test sound** uses paplay from the existing libpulse dependency, with a
0.7-second stereo 440 Hz tone, fade in/out, and reduced stream volume. It targets
the current output by name, preserves the device volume/mute settings, and gives
an actionable message for unavailable, muted, zero-volume, failed or timed-out
playback. Repeated clicks stop the test instead of starting overlapping players.
Closing Settings or changing outputs stops the player. Playback starts only through
an explicit click; applying this update plays no sound and starts no microphone test.

Validation uses simulated device/stream objects for selection, hotplug, keyboard
and mouse volume control, mute, meter lifecycle, and narrow layouts. Native tests
load the input meter with capture disabled and stub paplay to check argument
boundaries, output choice, failure, timeout, and cancellation without touching audio
hardware. Real microphone levels, audible playback, call routing, and WirePlumber
persistence must be checked in the desktop session; the agent sandbox cannot access
the PipeWire socket.

Regression checks exercise the production Loader source path with a stub capture
helper, verify the selected source/record-stream arguments, and confirm capture
processes are gone after close, device changes, or stalled input. Real PCM passed
through the native FFT checks frequency placement, soft/loud response, quiet noise,
DC offset, clipping, silence, and speech onset. The output spectrum checks still
pass with the shared helper. Rendered checks cover independent frequency bands,
immediate flat bars on mute, saved
microphone gain on unmute, and volume adjustments while muted. These simulations
do not establish the physical cause of a persistently high input level.

## Updates and recovery

Settings → **Updates & recovery** provides explicit update checks, an interactive
full-system upgrade, Settings recovery, complete personal-configuration recovery,
and optional local personal-file backups. Opening the page does not contact package servers, run
an upgrade, change desktop settings, or inspect personal-file contents.

**Check for updates** runs `checkupdates --nocolor` from pacman-contrib against a
new temporary database. It never refreshes the live package database. Exit code 2
means no available repository updates; failures remain errors rather than showing
zero updates. The displayed package list includes its check time and is only a
preview: packages may change before the actual upgrade.
[checkupdates documentation](https://man.archlinux.org/man/checkupdates.8.en)

**Open full system upgrade** launches a detached Kitty window. It links Arch news,
asks whether to begin, and runs `sudo pacman -Syu` with interactive administrator
authentication and package confirmation. It does not use an unattended confirmation
flag or select individual packages. AUR/foreign packages require separate review.
Closing Settings leaves the terminal running; Settings polls its local completion
record while the page is visible. A lock prevents duplicate workflows. Lock,
signature, disk-space, mirror/network, and package-conflict failures receive useful
next steps. The terminal preserves the original output until dismissed. Completion
means pacman returned success; interruptions without a result are labelled unknown.
Settings never removes package locks, forces conflicting packages, or restarts the
machine. See [Arch system maintenance](https://wiki.archlinux.org/title/System_maintenance#Upgrading_the_system).

**Desktop settings recovery** lists up to 100 recent validated settings backups,
including automatic pre-change backups and explicit checkpoints. Restore imports
only validated `settings.json` data: bar layout/items, compositor appearance,
mouse/keyboard, power, locking, notification delivery, accessibility and clipboard
capture preferences. It does not restore
display layouts, application theme/defaults/startup, keybindings, manual Lua edits,
shell source code, packages, or personal files. Those remain separate controls or
the complete personal-configuration checkpoint below. It never executes backed-up Lua or QML.

Preview names the sections that would change. Confirmation expires after five
minutes and rejects changed backups, concurrent settings edits, and manual changes
to the compositor entry point/generated overrides. The existing backend creates
an undo backup, regenerates overrides, and rolls back failed writes or compositor
reloads. Restoring is disabled while Settings has unsaved edits. Checkpoints and
preview records live under the Hyprshell state directory; checkpoints use the
existing `backups/` directory and follow the configured cleanup retention policy.
The installer carries the page/helper; GitHub sync exports the current preferences,
not recovery history.

**External backup check** records the readable backup folder and the time
the user clicks **I checked my backup today**. It reports whether that folder is
currently readable and keeps the last confirmation when a drive is disconnected.
This is a self-report, not a backup engine, content verification, or proof that
a removable drive is mounted. Use a backup application and verify its results
before recording the check. Folder/date, update outcomes, and checkpoints stay
local under the state directory and are excluded from configuration sync. GitHub
configuration sync does not back up Documents, Pictures, or other personal files.

Isolated tests cover restore/undo, transaction rollback, stale previews and backup
contents, traversal/symlink rejection, personal-backup reporting, separate update
databases, detached launch arguments, full upgrade arguments, cancellation, and
failure guidance. A native Quickshell check exercises preview, disabled restoration
with unsaved changes, rejected tokens, and confirmation through the actual helper.
No live system upgrade or laptop settings restore is run during validation.

## Accessibility, language and help

Accessibility controls Settings text at 100–150%, high-contrast colors, and
reduced desktop motion. Shared reactive styles resize controls and show visible
focus borders. Reduced motion disables compositor and Settings animation while
retaining the user's Windows animation preference for restoration. Application
font/cursor size, display scale and bar sizes remain independently adjustable.
All preferences use the validated settings transaction and migrate from old files.

Language & region offers generated locales, separate date/number formats, a
personal timezone and previews. It saves a managed UWSM environment block for the
next login, preserves other blocks and rejects concurrent changes. System timezone
changes are separate, explicit, confirmed and authenticated through timedatectl.
Restoration skips locales missing on another laptop while keeping the saved choice.
The language choice affects apps that provide translations; Hyprshell currently
uses English. User-configured LC_ALL takes precedence.

Help & diagnostics appears on the first Settings launch until its guide is marked
complete. Completion stays local. Service checks run only on request; inaccessible
buses are shown as unavailable rather than a broken service. Redacted reports are
600-permission local files under state/hyprshell/diagnostics, with fixed service
states, tool availability and system/kernel/architecture. They contain no raw logs,
configuration, usernames, hostnames, IP/SSID, notification history or clipboard data.
Nothing is sent externally. Help, regional and Network controls use a shared lazy
loader and wait for short in-flight commands before unloading.


## Workspaces, window rules and optional peripherals

**Workspaces & rules** saves `hyprshell/behavior.json` and generated `behavior.lua`.
Unedited controls inherit personal Lua; applying an override never rewrites the
editable base modules. Workspaces use numbered IDs (1–99), optional names, layout
and persistence, with hardware-adaptive monitor assignment. Each workspace has a
**Floating windows** switch (off by default, including older preferences).
Enabling it floats existing windows on Apply, newly opened windows and windows
moved into that workspace, taking priority over application tiling rules.
Fullscreen remains available; fullscreen windows float when they leave fullscreen. Disabling or removing the preference stops automatic
floating; existing windows retain their placement, including when moved out.
Use the existing floating shortcut to tile them if desired.
**Pseudotiled windows** is a separate per-workspace switch, also off by default.
It tiles windows while retaining their preferred size; choose the Dwindle layout
for this behavior. Enabling floating or pseudotiling clears the other choice on
that workspace. Pseudotiling applies to existing, new and moved-in windows,
including previously floating windows, and waits for fullscreen to end.
Turning it off or moving a window out retains its current pseudotiling state;
Super+Shift+P remains available to toggle individual windows. Compositor Lua events
handle opening, workspace moves and reloads without polling or a shell watcher. Rules match exact
application classes, escaped as anchored expressions. Running-class discovery
reads only classes, not window titles. Placement/size rules affect newly opened
windows. Pinning and size require a floating rule. Every save validates schema,
parses generated rules with the installed compositor, rejects concurrent edits,
backs up files and rolls back failed activation. Installer and sync regenerate Lua
from validated JSON. With no desktop IPC, manual class entry remains available.
See [Hyprland workspace rules](https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/)
and [window rules](https://wiki.hypr.land/configuring/core/rules/window-rules/).

**Clipboard history** uses optional cliphist/wl-clipboard. Capture defaults off;
`ClipboardController.qml` supervises one event-driven wl-paste watcher only while
it is enabled. Text-only capture is the default, images optional. Each entry is
limited to 5 MiB; 10–200 entries are retained, trimmed on the next store. Sensitive,
clear and nil clipboard hints are skipped. Apps must supply sensitive hints;
disable capture for secrets whose app does not. Saved data is unencrypted and
private to the user under `state/hyprshell/clipboard`, outside GitHub sync.
Settings reads history only after **Show history**, with bounded plain-text
previews. Copy decodes bytes directly into wl-copy, keeping content out of command
arguments and logs. Remove uses a validated ID; Clear all requires confirmation.
Disabling capture preserves entries. The optional installer opens a detached
interactive `sudo pacman -Syu --needed …` terminal; no install runs automatically.
See [cliphist](https://github.com/sentriz/cliphist).

**Printing & scanning** has no polling or new service at startup. Open the printer
or Document Scanner app, or explicitly request queue/scanner discovery. Missing
tools can be installed in an interactive full-upgrade terminal. **Enable printing
on demand** separately confirms opening a terminal for `sudo systemctl enable
--now cups.socket`. No CUPS unit is enabled by Hyprshell installation. Hardware
may need optional SANE/manufacturer drivers; discovery has bounded timeouts.

**AC/battery timers** live in the existing Settings power section. The existing
UPower battery signal selects the timer policy and restarts the single Hypridle
supervisor only when effective timers change. Both sources keep the same locking
policy. Dim callbacks inherit the chosen battery policy; stopping the previous
idle worker restores managed brightness/DPMS before starting its replacement.
Battery timers default disabled, and separate policies default off. Hardware
status refresh on the Power page is manual.

## Complete configuration and personal-file backups

**Settings → Backup & restore** saves current Settings, display and
shortcut preferences, app/theme/regional/workspace choices, cleanup preferences,
manual desktop Lua/conf modules, GTK settings, UWSM environment, MIME associations,
terminal preference and XDG autostart entries. It excludes installed Quickshell
source, package/system configuration, network credentials and documents. Paths
are allowlisted, links refused, individual files bounded at 2 MB and each
backup at 10 MB. The same controls remain available in Updates & recovery.

**Back up Hyprshell now** creates a private local backup under
`$XDG_STATE_HOME/hyprshell/setup-backups/setup-<timestamp>/`. Every completed
backup records an ISO date/time with timezone, kind, file count, content size
and SHA-256 checksum in `metadata.json`; `files.json` holds the configuration.
Files are private and backup directories have mode 0700. A temporary staging
directory is published only after both files finish writing, so an interrupted
creation is not listed as a completed backup. New manual backups and before-restore
backups are outside all System cleanup targets. They remain until removed manually;
monitor their storage and copy the folder to another drive for disk-failure or
OS-reinstall protection. Backups and their contents are not exported to GitHub.

The **Choose a backup to restore** picker lists readable dates and times with
timezone, newest first, and distinguishes Manual backup, Before restore and
Legacy checkpoint. Selected-backup details show the date/time, file count and
size. Refresh preserves the selected backup when it still exists. Selecting
another backup dismisses its predecessor's restore confirmation. Existing
`backups/configuration-*` checkpoints remain selectable with dates decoded from
their original IDs; their existing cleanup retention remains unchanged.
Incomplete or invalid backup metadata is skipped and counted. New backup
contents must pass the recorded checksum before a restore can be previewed.
Manual Lua/startup entries can include your custom commands; restore only a
backup you trust. A configuration backup is not a disk image or a backup of the
installed shell source or OS packages.

Preview lists changed files and expires after five minutes. Confirmation checks
both the checkpoint and current-file hashes, regenerates GUI Lua from validated
JSON, parses Lua syntax without executing it, creates a selectable dated
before-restore backup and atomically restores/deletes files with rollback on write failure.
Generated monitor rules are not applied live without a display confirmation.
Settings runtime preferences reload now; log out and back in for restored
compositor and application files to take effect. The separate Settings-only
restore continues using immediate compositor validation and rollback.

**Personal-file backups** are a distinct optional engine, with local preferences
in `state/hyprshell/personal-files.json`. Choose existing non-hidden folders inside
your home and an existing writable destination. Source/destination nesting,
links and full-home/root selection are rejected. The saved destination device and
inode identify the selected mounted folder; changed/disconnected destinations
fail rather than creating a replacement path. After replacing a drive/folder,
save the intended destination again. Some mount identities may change after a
reboot, in which case resave after confirming the mounted target.

Manual backups run detached and are serialized. A snapshot becomes visible only
after all regular files are copied and a SHA-256 manifest is written. Links and
special files are skipped; empty directories are retained. Verified unchanged
backup copies can be hard-linked between snapshots; source originals are never
linked to a snapshot. Source changes during copying fail the new snapshot while
preserving earlier ones. Verification recomputes each recorded content hash and
reports missing/corrupt files. It does not establish application consistency for
files being actively edited, nor replace offline/offsite protection.

Daily/weekly schedules generate a systemd user timer/service only when enabled.
They use lower CPU/I/O priority and require the user manager and selected drive
to be available. Schedule changes roll back if service activation fails. Off
removes the managed timer and service; it does not remove snapshots. Status is
manual, and no backup starts merely by opening Settings. Snapshots are never
removed automatically; monitor free space. **Open snapshots / recover files**
opens ordinary files for recovery into a separate folder before replacing originals.
The older **I checked my backup today** record remains a separate self-report for
external backup applications. GitHub configuration sync excludes both engines'
state, schedules, destination paths and personal contents.

Tests use temporary synthetic files, inert hardware/tool stubs, actual Lua parsing
and native offscreen UI. They do not copy personal documents, install optional
packages, enable CUPS, run upgrades, restore laptop preferences, or exercise real
hardware/session IPC.

## Window edge spacing and launcher responsiveness

Windows → Window shape & spacing provides Top, Right, Bottom, and Left edge
overrides (0–100 px). Unset sides follow All screen edges, or 10 px when that
override is unset. Reset all four side controls to use only the uniform gap or
personal Lua configuration again. Generated Lua uses Hyprland's CSS gap table;
legacy configuration uses top,right,bottom,left order. Workspace rules can override
these gaps.

Hyprpane → Layout & spacing → Gap toward windows reserves
0–100 additional pixels toward the desktop, without moving the visible bar. For
a top bar this is bottom padding; for another edge it follows the bar inward.
Hidden bars reserve no space. Edge margin continues to move the bar itself.

Each screen keeps one prepared application launcher and icon catalog. Search
resets and receives focus on opening, and launcher entry transitions are immediate.
Other menu contents retain their lazy loading and animations. The Fedora launcher
mark uses solid blue with a white symbol to retain detail at small icon sizes.

Super+C and Super+V forward Copy and Paste to the focused application
(Ctrl+C/V, or Ctrl+Shift+C/V for Kitty, Alacritty, Foot, WezTerm and Ptyxis).
Super+Alt+V toggles floating windows. Application-specific shortcut preferences can
override the conventional forwarded keys.

## Firewall controls

**System → Firewall** has one On/Off switch and a Rules list with Add rule,
Edit and Remove actions. Add/Edit opens one form: allow a named service, allow a
port with TCP/UDP, block an IP address/network, or block a website name. Save applies the selected rule
now and saves it for restart. Common services appear first. Invalid input stays
in the form for correction; Refresh keeps a draft. Rules show whether they are
active, saved only or temporary. Remove and switching the firewall require a
short confirmation. Help and technical details are collapsed by default.

Each page action runs one short `pkexec /usr/bin/python3 settings/firewall.py`
job with the desktop authorization prompt. All reads, writes, rollback and
final status checks run inside that job, so individual firewall-cmd subprocesses
do not request separate passwords. The switch uses systemctl enable/disable
inside the already authenticated job. There is no persistent elevated process,
password storage or authorization-policy change. Refresh can ask for authorization
once; cancellation stops the job without an automatic retry. Turning off
preserves saved rules and keeps the firewall off after restart. Stopped, checking,
unknown and running states are distinct. Rule editing is available while running;
when off, the page explains that rules are kept and become available after turning
on. Neither opening Settings nor tests change the machine’s firewall state.

Single-active-zone selection strips firewalld’s ` (default)` display annotation.
Multiple active networks expose a network selector; all zones remain selectable
under Technical details. A removed/stale selected zone falls back to automatic
selection on Refresh. Selection never reassigns a network connection’s zone.

Each mutation validates arguments and the combined current/saved revision.
Edits add the replacement before removing the original, and undo completed steps
on failure without deleting a pre-existing replacement. Rollback failures are
reported as partial edits. Add/remove partial failures identify the saved change.
There is no reload or bulk overwrite. Custom rich rules can be inspected and
removed; only simple Hyprshell source-drop rules are editable as blocked addresses.
Complex rules retain their semantics. Other zone targets, forwarding and policies
can also affect traffic; full details remain available for inspection.

System firewall rules stay outside GitHub desktop sync. Drafts survive navigation
and closing Settings while the shell is running. firewalld and Polkit remain base
desktop dependencies. Live authentication/service transitions require a desktop
session. Tests simulate service state and commands rather than touching real rules.

Checks: `python3 -m unittest discover -s tests -p test_firewall.py -v`.
Tests use fake firewall commands and a native offscreen Settings window; no real
rule, administrator authentication or service activation is performed.

### Website names and subdomains in Firewall settings

**Add rule → Block a website** accepts a domain or an http/https link.
**Block all subdomains** defaults On for new rules. Off blocks the domain plus www
through managed IPv4/IPv6 hosts entries; On additionally routes all record types
in the whole suffix to dnsmasq’s NXDOMAIN local-domain rule. Old saved rules stay
exact-only until edited. The option is remembered on each rule and visible in the
list. Block lists and DNS setup state remain local and outside GitHub sync.

**Set up DNS filter** is one authenticated action. On Fedora it installs dnsmasq
if missing, configures NetworkManager’s local caching plugin and puts it upstream
of the existing systemd-resolved stub. It creates three managed snippets:
NetworkManager main settings, resolved fallback policy, and dnsmasq website
suffixes. The resolver symlink is recorded and points to NetworkManager’s
continuously updated resolver file, allowing resolved to import filtered DNS
and search domains through its compatibility path. nsswitch.conf, connection
profiles and service startup choices are preserved. In Automatic mode, NetworkManager keeps choosing connection/VPN
upstreams. Direct resolved per-link pushes are disabled to avoid bypassing the
filter. Global custom DNS, strict DNSSEC/DNS-over-TLS, connection TLS policies,
another DNS provider or an existing localhost DNS server require review rather
than silent replacement. The automatic bridge is specifically for an existing
NetworkManager + systemd-resolved stub; other setups are rejected.

DNS reload uses nmcli’s single `conf,dns-full` argument. Filter activation clears
old resolved link servers after NM updates; restoration restarts resolved first
and then lets NM repopulate normal per-link DNS. Failure responses include the
recovery receipt immediately. **Restore DNS setup** is always available in the
website form and Technical details, even when DNS status cannot be read.
DNS reloads are bounded and test filter/stub responses, retrying briefly while
services start. Setup failure removes its snippets and restores original DNS
configuration. Rule-update failure restores previous DNS rules and hosts entries.
**Technical details → Restore DNS setup** removes only verified managed
files, restores the original resolver symlink, and returns to the previous provider. Incomplete setup has a recovery
receipt; modified managed files require review. Restoration leaves exact hosts
blocks in place and shows wildcard rules as needing setup. On Arch install
missing dnsmasq with a full supported package transaction before setup; manifests
include dnsmasq for future fresh installs without enabling its standalone service.

**Firewall → DNS** offers two saved modes: **Automatic DNS (from network)**
uses network/VPN DNS, and **Custom DNS** accepts one to eight manually entered
numeric IPv4/IPv6 server addresses. Custom DNS starts with an empty address field;
there are no provider presets. Previously saved protection presets appear as
Custom DNS with their existing addresses, preserving the active configuration
until the user applies a change. Legacy receipt handling remains in the backend
for validation and rollback. This bridge uses ordinary DNS, without adding
DNS-over-HTTPS/TLS.

Custom DNS writes NetworkManager's `global-dns-domain-*`
configuration so connection/DHCP/IPv6/VPN DNS cannot remain an unfiltered fallback
for system lookups. It replaces private network/VPN DNS domains too, so private
names may require Automatic. Automatic removes the managed global override while
keeping the local filter and manual blocks. Restore DNS setup removes the bridge
and returns to the original configuration. Independent browser secure DNS,
VPN clients and proxies can bypass the system resolver.

Apply previews the selected mode and custom addresses, then performs one
administrator job under the website lock with revision checking. It checks the
effective NetworkManager config plus filter/stub DNS responses. Failures restore
the previous mode and receipt. An interrupted change records both managed
configurations so Restore remains possible. External config overrides and edited
managed files require review. DNS mode/server state stays local, outside GitHub
sync. Installing the UI does not select or activate a provider.

`settings/website_blocks.py` normalizes/validates names and IDNA, caps the list at
200, serializes website/DNS setup changes and checks hosts plus DNS revisions.
Only its marked hosts section changes; unrelated entries stay intact. The previous
hosts version is kept privately in `/etc/hosts.hyprshell-websites.bak`. Atomic
replacement retains ownership, mode and xattrs/SELinux labels. DNS receipts are
private under `/var/lib/hyprshell/website-dns`, with hashes detecting manual changes.
No query logging or browsing history collection is enabled.

The filter covers apps using system DNS. Independent DNS, proxies, cached
results and direct IP connections can bypass it. Restart browsers after changes
when needed. Website blocks stay independent of firewalld’s On/Off switch.
[Dnsmasq local-domain behavior](https://dnsmasq.org/docs/dnsmasq-man.html),
[NetworkManager DNS plugins](https://networkmanager.dev/docs/api/latest/NetworkManager.conf.html),
[hosts(5)](https://man7.org/linux/man-pages/man5/hosts.5.html).

Checks: `test_website_blocks.py`, `test_website_dns.py` and `test_firewall.py` use
synthetic hosts, snippets, services and DNS replies. Native tests cover the On
default, setup confirmation retaining the form draft, remembered edits and
website removal while firewalld is off, Custom/Family/Automatic application and
website draft preservation. Backend tests cover validation, stale revisions, mode
rollback, external overrides and interrupted changes. Actual package installation and live DNS
activation need a desktop-session check; simulated tests do not certify them.


## Window transparency and glass scope

**Windows → Effect workspaces** chooses all workspaces or a saved selection of
numbered workspaces (1–99). Pick each workspace and toggle **Apply effects**;
the summary lists the complete selection. An empty selection disables effects.
Switching back to all workspaces retains the selection for later. Existing
preferences remain unchanged until edited.

Focused, unfocused and fullscreen windows have separate transparency sliders.
**Glass & blur → Background blur** selects frosted glass or clear transparency.
**Blur applies to** selects both focus states, focused only or unfocused only.
Blur strength, passes and vibrancy remain adjustable. **Advanced glass & blur**
adds grain, contrast, brightness, dark-area vibrancy, opacity-independent blur,
optimizations, X-ray wallpaper blur, special-workspace blur, application popup
blur and input-method blur, with separate alpha thresholds. Each control can
return to **Use config**. All changes use the existing validated autosave,
conflict detection, backups and rollback; they are included in setup and sync
through the existing settings payload and override generator.

Hyprland shares blur strength and color parameters across windows/workspaces;
dynamic window rules restrict where the shared effect is visible. With selected
workspaces, unselected windows use compositor opacity 1 and no blur; selected
windows use the opacity choices (unset states default to 1 in this mode).
Application-owned transparency can remain, and application-specific rules can
take priority. Window opacity fades the entire app, including text; opaque text
over a transparent background requires support from the application itself.
Special-workspace and popup blur toggles are compositor-wide and do not have
per-focus or numbered-workspace filtering. Increasing passes or enabling special
workspace blur may increase GPU use. New controls do not change saved appearance
merely by opening the page.

Validation: `test_settings.py` checks schema rejection, generated scope/focus
rules, resetting scope, empty selections, Lua parsing with the installed
compositor and transaction rollback. `tst_SettingsAppearance.qml` exercises native
workspace selection, focus/style changes, retained choices, advanced sliders,
reset and narrow layouts. These checks do not establish live session rendering.

Hyprpane storage and compatibility names are documented in
[Panel configuration](panel-configuration.md).

### Hover popdowns by workspace

Settings → Hyprpane → Hover popdowns controls hover opening for
Hyprpane on each output's current workspace. Hover is enabled by default,
including when loading older saved settings. The default switch applies to
workspaces without an override. Select workspace 1–99 to enable or disable hover
there; **Use default on this workspace** removes that override.

When disabled, panel menus and app previews require clicks and hovering a neighbor
does not replace the open menu. Media becomes clickable; workspace left-click
opens its preview; clicking the preview switches to that workspace. Right-clicking
the workspace number switches directly. Clicking another workspace
number updates the open preview; clicking the same number again closes it. Existing app activation,
tray clicks, shortcuts, edge reveal, and menu dismissal controls remain available.
Changing workspace closes popdowns as before. Disabling hover cancels pending
hover timers and closes hover-opened menus while retaining click-opened menus.
