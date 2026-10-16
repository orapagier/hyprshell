# Panel configuration — Phase 1

Hyprpane is the existing status/menu panel on any edge. Phase 1 established the
compatible configuration and placement rules below. [Phase 4](hyprdock.md) now
renders Hyprdock and provides its basic Settings controls; it still defaults to
disabled. [Phase 6](hyprbar.md) renders the classic Hyprbar taskbar, also disabled by default.
Settings → Hyprpane & panels retains all existing Hyprpane controls.

## Compatibility and storage

Schema version remains 1. Missing sections inherit defaults, and no migration
rewrites the user's settings on startup. The canonical payload remains
`config/hyprshell/settings.json`; `settings/defaults.json` supplies omitted fields.
Save, setup, sync, recovery and configuration restore use backend validation.
Invalid writes leave the previous saved settings intact; failed Settings drafts
remain available for correction. Direct edits with conflicting placements are
rejected by the QML merge, retaining the last readable settings.

| Public component preference | Stored source |
| --- | --- |
| Hyprpane enabled / monitor selection | `panels.hyprpane.enabled`, `.monitors` |
| Hyprpane edge | `bar.position` |
| Hyprpane workspace visibility | `bar.visible`, `.workspaceScope`, `.workspaceList`, `.workspaceOverrides` |
| Hyprpane dimensions | `bar.height`, `.marginTop` (edge margin), `.marginSide` (end margins), `.paddingBottom` (window gap) |
| Hyprpane styling and item layout | Remaining `bar` fields and `items`, unchanged |
| Hyprpane hide mode | `panels.hyprpane.hideMode`: `always` in Phase 1; workspace hiding stays independent |
| Hyprdock / Hyprbar | Independent `panels.hyprdock` / `panels.hyprbar` objects |

`Bar.qml`, `SettingsBarEditor.qml`, IPC target `bar`, `toggleBar`, backend
`--toggle-bar WORKSPACE`, and the `topbar` shortcut helper remain compatibility
identifiers for Hyprpane. Alt+T retains its existing action and any personal
shortcut remapping. The enabled flag is a master gate; workspace overrides still
take priority over `visible` and selected-workspace defaults inside that gate.
The monitor list defaults empty (all outputs), and otherwise contains connector
names such as `eDP-1` or `HDMI-A-1`. Disconnected names are retained for hotplug.
The runtime honors Hyprpane's enabled flag and monitor list.

Hyprdock and Hyprbar each define `enabled`, `monitors`, `position`, `visible`,
`workspaceScope`, `workspaceList`, `workspaceOverrides`, `thickness`, `marginEdge`,
`marginEnds`, `windowGap`, `iconSize`, `spacing`, `background`, and `hideMode`.
All four positions are supported by the contract. Background is `inherit`, `on`,
or `off`; hide mode is `always`, `auto-hide`, or `dodge`. Hyprdock renders with
these dimensions and saved visibility selections in Phase 4. Phase 5 implements automatic hide modes. Phase 6 renders Hyprbar
with independent task grouping, title presentation and window filters.
Auto-hide and dodge components count toward layout limits even while hidden,
because their reveal zones and visible state still need an unoccupied edge.

## Pins

`pins.mode` is `shared` (default) or `separate`. The ordered `pins.shared` list is
used by both app components in shared mode; in separate mode use `pins.hyprdock`
and `pins.hyprbar`. Switching mode retains all three lists. Each entry is a
unique desktop application ID including `.desktop`, for example
`org.gnome.Nautilus.desktop`; use desktop filenames rather than display names or
launch commands. Paths are rejected.
Missing installed apps retain their IDs. Phase 3 adds discovery, matching and pin
controls through Launcher → Apps & windows; see [application support](application-support.md).
Desktop filenames with spaces, Unicode or plus signs are accepted too, allowing
any discoverable installed app to be pinned. IDs remain filenames ending in
`.desktop`, without paths or control characters. They are never executed as shell
commands. `pins.matches` stores explicit class/app-ID → desktop-ID corrections.
Hyprpane has no app-pin list.

## Placement and corner policy

Validate every monitor selection and numbered workspace (1–99), including saved
visibility overrides and monitors that are currently disconnected. Unnumbered
workspaces use the ordinary scope defaults without numbered overrides. At most
two enabled, workspace-visible components may share an output, and they must
have different edges. The check also covers any unspecified/hotplug monitor when
selection is all outputs. Disjoint output or workspace selections can reuse an
edge. No validation path silently disables a component or moves it elsewhere.
Shortcut reveals are revalidated inside the transaction before writing.

All three components may be enabled and reuse the same edge when they appear on
separate workspaces. For example, Hyprpane Bottom on workspace 1, Hyprdock Bottom
on workspace 2, and Hyprbar Bottom on workspace 3 is valid. The two-panel limit
applies to panels visible together on one monitor/workspace, not to the number
enabled globally. A workspace override that reveals another panel on the same
edge is rejected before changing saved preferences.

In Settings → Hyprpane & panels, each app panel now has **workspace visibility**
controls matching Hyprpane: **Show on all**, **Hide on all**, an individual
workspace selector and a visibility switch. To make the example layout, first
hide each panel on all workspaces, then turn Hyprpane on for workspace 1,
Hyprdock for 2, and Hyprbar for 3. Set each edge to Bottom and enable the app
panels after assigning visibility. Each selector supports workspaces 1–99;
repeat the switch on any additional workspaces. The app panels' Enable switches
remain master gates, and Alt+T still targets Hyprpane only.

Show/Hide on all clears individual overrides and returns to all-workspace scope;
an individual switch changes only that workspace override. Existing selected
workspace lists and window-source filters remain available. These visibility
controls preserve all appearance, app pins, utilities and window filtering.

Native Settings coverage saves the example with the real backend in an isolated
home, checks forward/return workspace visibility and ensures hidden neighbours
do not reserve menu space. Qt and backend checks cover all four shared edges,
both selected lists and overrides, and rejection of overlapping visibility.
Physical compositor input and exclusive-zone behavior still require live-session
acceptance.
This increment passed 320 Qt checks and 58 focused Python tests across panel
configuration, native workspace controls, layout presets, styling, settings
transactions and search. All three changed QML components passed Qt's parser.

For adjacent edges, Top/Bottom own the corners. Left/Right will be inset by each
visible horizontal component's thickness, edge margin and window gap, in addition
to their own end margins. Opposite edges keep their own end margins. Phase 4
applies these insets to Hyprpane/Hyprdock geometry and reserved space;
popovers open inward. Reveal-zone geometry and full pair/hotplug validation
remain in their planned phases. A single Hyprpane's
current margins and reserved space remain unchanged during Phase 1.

## Validation record — 2026-10-16

- Qt 6 QML suite: 177 passed, including the new model tests and existing editor,
  preview, visibility, keybinding-guide and orientation coverage. The focused
  model tests also pass after preserving the no-active-workspace fallback.
- Focused backend/settings/search/recovery tests: 60 passed, covering all allowed
  edge pairs, conflicts on workspace 99, disjoint selections, rejected shortcut
  writes, legacy preferences, pin storage and restore previews.
- Native caption search: passed with the new Hyprpane labels. Setup: 18 checks,
  one skipped; sync: 13 passed; configuration recovery: 9 passed; skill: 3 passed.
- Hyprland configuration parser: config ok. Installed source files matched their
  repository baseline before applying focused changes; saved settings are not
  rewritten. The personal Alt+X remap of the Alt+T action is preserved.
- Native save/lifecycle/recovery and shortcut-recording smoke scenarios did not
  emit their completion markers in this environment. Quickshell reported IPC
  socket failures. Representative position-save and recovery scenarios failed
  identically on an isolated unchanged HEAD baseline; no cause or live-session
  breakage is inferred from those failures. These native scenarios and physical
  desktop interaction are not claimed as passed.
- Matching files were applied to the live config with a dated backup. Hyprctl
  reload and configerrors queries returned `Couldn't set socket timeout (2)`;
  compositor reload and live activation could not be confirmed from this session.
  Quickshell's existing file watcher handles QML changes when accessible.
