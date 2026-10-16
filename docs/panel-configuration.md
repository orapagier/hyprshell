# Panel configuration — Phase 1

Hyprpane is the existing status/menu panel on any edge. Hyprdock is the future
app dock; Hyprbar is the future classic window taskbar. Phase 1 implements names,
configuration storage and placement validation. It does not render a dock or
classic taskbar. Both default to disabled; their stored options reserve the
contract for later phases. Settings → Hyprpane & panels explains these roles and
contains all existing panel controls. Later phases add the dock/taskbar editors.

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
or `off`; hide mode is `always`, `auto-hide`, or `dodge`. Those hide modes and
rendering are reserved for later phases. Enabling a reserved component through
JSON validates its planned placement but does not create its window yet.
Auto-hide and dodge components count toward layout limits even while hidden,
because their reveal zones and visible state still need an unoccupied edge.

## Pins

`pins.mode` is `shared` (default) or `separate`. The ordered `pins.shared` list is
used by both app components in shared mode; in separate mode use `pins.hyprdock`
and `pins.hyprbar`. Switching mode retains all three lists. Each entry is a
unique desktop application ID including `.desktop`, for example
`org.gnome.Nautilus.desktop`; display names, paths and shell commands are rejected.
Missing installed apps retain their IDs; discovery, matching and pin controls
arrive in Phase 3. Hyprpane has no app-pin list.

## Placement and corner policy

Validate every monitor selection and numbered workspace (1–99), including saved
visibility overrides and monitors that are currently disconnected. Unnumbered
workspaces use the ordinary scope defaults without numbered overrides. At most
two enabled, workspace-visible components may share an output, and they must
have different edges. The check also covers any unspecified/hotplug monitor when
selection is all outputs. Disjoint output or workspace selections can reuse an
edge. No validation path silently disables a component or moves it elsewhere.
Shortcut reveals are revalidated inside the transaction before writing.

For adjacent edges, Top/Bottom own the corners. Left/Right will be inset by each
visible horizontal component's thickness, edge margin and window gap, in addition
to their own end margins. Opposite edges keep their own end margins. The same
insets must apply to reserved space and reveal zones; popovers open inward within
the resulting available rectangle. Full corner geometry and multiple component
windows are implemented and visually verified in Phase 7. A single Hyprpane's
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
