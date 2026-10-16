# Hyprpane, Hyprdock, and Hyprbar: phased implementation plan

Status: Phases 1–6 implemented on 2026-10-16 at the user’s request. Phase 7's
menu slice and Phase 8's settings preview/preset slice are implemented; remaining
acceptance work requires a later task. Each phase should leave a usable
desktop and a reviewable result. See [Phase 1 configuration](panel-configuration.md)
for the compatibility contract and validation record. Phase 3 behavior and
validation limits are recorded in [Shared applications and windows](application-support.md).
Phase 4–5 behavior and validation limits are recorded in [Hyprdock](hyprdock.md).
Phase 6 behavior and validation limits are recorded in [Classic Hyprbar](hyprbar.md).
Phase 7's menu coexistence slice is implemented; its remaining acceptance work
is recorded in [Panel coexistence](panel-coexistence.md).

## Names and agreed behavior

| Name | Meaning |
| --- | --- |
| Hyprpane | The existing status/menu panel, formerly called hyprbar or the top bar |
| Hyprdock | An app dock with pinned apps, running apps, a launcher, and optional utilities |
| Hyprbar | A new classic taskbar with window buttons and optional desktop/status controls |

All three support Top, Bottom, Left, and Right. Names describe their function,
not their screen position. In particular, hyprpane can be vertical.

Any pair can coexist: hyprpane + hyprdock, hyprpane + hyprbar, or hyprdock +
hyprbar. At most two components may be visible on a given monitor and workspace,
and they must occupy different edges. A single component is also supported. Validate these
rules for each monitor and workspace, including saved visibility overrides.
All three may be enabled globally and use the same edge on disjoint workspaces:
for example Hyprpane Bottom on workspace 1, Hyprdock Bottom on workspace 2 and
Hyprbar Bottom on workspace 3. Settings exposes independent all/individual
workspace visibility controls for each component; only simultaneous visibility
on the same monitor/workspace imposes the pair and distinct-edge limits.
Do not silently move or disable an existing component when a setting conflicts;
explain the conflict and let the user choose another edge or disable a component.

Keep the existing desktop arrangement during migration. Later presets may offer
hyprpane at Top with hyprdock at Bottom, or a standalone classic hyprbar, but
choosing a preset is explicit and must not discard personal settings.

## Existing foundation and preservation

The current shell uses Qt 6 Quickshell. `shell.qml` creates per-monitor panel
windows, `Bar.qml` renders the existing panel, `LauncherMenu.qml` discovers and
launches desktop applications, and Hyprland toplevels provide window tracking.
Settings already cover all four edges, per-workspace visibility, appearance,
menus, and installation/sync persistence.

Before every phase, inspect repository status and relevant live/repository
differences. Preserve existing controls, shortcuts, item customization,
notifications, locking, launcher behavior, and workspace visibility. Use focused
patches; do not turn this project into an unrelated shell rewrite.

The new public names do not require immediately renaming `Bar.qml`, the saved
`bar` settings key, or existing IPC methods. Introduce a compatible mapping first.
If an internal rename becomes necessary, migrate and test every consumer,
including setup, sync, backup/restore, settings search, and documentation.

## Phase 1 — Naming and configuration design

- Update current UI terminology to Hyprpane and reserve Hyprbar for the new
  classic taskbar. Update active documentation and skill references when the
  terminology becomes implemented; mark historical plans as historical where
  needed instead of changing their meaning indiscriminately.
- Define separate configuration for each component: enabled state, edge,
  monitor selection, workspace visibility, dimensions, styling, and hide mode.
- Preserve all current panel preferences, including Alt+T behavior, through a
  documented compatibility mapping. Keep the existing shortcut targeting
  hyprpane unless the user explicitly changes it.
- Define shared pins and an optional separate-pins mode. Pin identity uses
  desktop application IDs rather than display names or shell command strings.
- Add conflict validation and a settings layout explaining the two-component,
  different-edge rule. Establish how adjacent edges share corners and space.

Acceptance: existing preferences load with the same desktop behavior; new names
are unambiguous; invalid combinations are rejected without losing settings.

## Phase 2 — Polish vertical Hyprpane

Use the user's 2026-10-16 screenshot as the visual reference for current problems:
the tall narrow panel has awkwardly wrapped date/time text, oversized rounded
groups, uneven density, and large unused stretches between small controls.

Latest user refinement (2026-10-16): Left/Right must be icon-only, with a
calendar icon and circular pills. This supersedes the earlier character-column
request. Preserve saved labels for tooltips and horizontal layouts; fit the
media spectrum to a circular sidebar item. Implemented behavior and
review screenshots: [Vertical Hyprpane](vertical-hyprpane.md).

- Design an intentional vertical layout rather than squeezing horizontal items
  into a narrow column. Keep icons and labels upright.
- Establish consistent widths, padding, icon sizes, hit areas, and group gaps.
  Allow compact or full-edge presentation without forcing a stretched backdrop.
- Give date/time an explicit vertical design with readable, deliberate lines;
  prevent accidental word wrapping, clipping, and crowded calendar labels.
- Balance top, middle, and bottom groups. Preserve configurable alignment and
  item ordering while making spacing deliberate rather than arbitrary.
- Fit notification counts, volume, network, Bluetooth, battery, tray, and power
  controls cleanly; use tooltips or popovers for detail that cannot fit legibly.
  Retain existing label and icon visibility controls.
- Make menus open inward on the correct side, stay within the screen, align to
  the trigger, and support pointer and keyboard interaction.
- Check Left and Right independently, including small displays and scaling.
  Verify Top and Bottom retain their current functionality and customization.

Acceptance: review screenshots of Left and Right layouts with realistic item
sets, notification badges, long dates, and tray overflow. No accidental wrapping,
overlapping controls, clipped popovers, or removed functionality.

## Phase 3 — Shared application and window support

- Build shared app discovery, icon resolution, desktop-ID matching, and launching
  from the existing launcher behavior, retaining UWSM launch semantics.
- Track running windows, focus, workspace, output, title, and app grouping through
  the shell's existing compositor integration; avoid redundant polling.
- Handle app-ID/class mismatches, applications with several windows, unknown
  applications, missing icons, and pinned apps that are no longer installed.
  Allow any discoverable installed app to be pinned; provide a way to correct
  identity matches when automatic matching fails.
- Persist pin/unpin and ordering changes using existing settings transactions.
- Implement focus, new instance, window selection, close, and workspace actions.
  Verify Hyprland support before exposing minimize/restore or Show Desktop;
  define reversible behavior and a reliable way to recover hidden windows.

Acceptance: representative installed apps launch and map to their windows;
multiple windows group correctly; pins survive restart; desktop-entry launch
behavior and existing launcher keyboard navigation remain intact.

## Phase 4 — Hyprdock core

- Build a compact dock supporting all four edges, with horizontal or vertical
  orientation, configurable sizing, and styling consistent with Hyprpane.
- Show pinned apps and running unpinned apps, active/running indicators, tooltips,
  and an application-launcher button.
- Click to launch or focus; offer a window picker for apps with several windows.
  Provide context actions to pin/unpin, open a new instance, and close a window.
- Support pinning from the launcher and running apps, plus drag-to-reorder pins.
- Handle overflow on short edges without shrinking targets into unusable sizes.

Acceptance: daily app launching, switching, pinning, and reordering work on every
edge with keyboard and pointer input, including overflow and multiple windows.

## Phase 5 — Hyprdock utilities and visibility

- Add optional Files and Settings shortcuts and a Trash item with empty/full
  state. Open Trash in the file manager; confirm before emptying it.
- Add always-visible and auto-hide modes, then hide-when-overlapped behavior.
  Keep reveal areas usable and keep the dock open while interacting with menus,
  window pickers, drag operations, or keyboard navigation.
- Configure edge margins, alignment, icon size, spacing, background, indicators,
  animation, and monitor/workspace filtering. Respect reduced-motion settings.
- Define fullscreen behavior and reserved space explicitly for each hide mode.

Acceptance: reveal/hide does not flicker or strand menus; fullscreen apps behave
as configured; utilities work; opening Trash never empties it.

## Phase 6 — Classic Hyprbar core

User refinement after Phase 6 (2026-10-16): Hyprbar app buttons are icon-only like
Hyprdock, with no tooltips. A customizable trailing section defaults to the
existing Hyprpane right-side items, reusing their controls and menus. This
supersedes the original title-presentation requirement below and implements the
item-selection slice of Phase 7; full coexistence validation remains pending.
The subsequent styling refinement uses Hyprpane's center glass pill and symbols
for Hyprdock, and one continuous edge pill for Hyprbar without nested status
backgrounds. Current sizing is 32 px with 15 px icons, including narrow side rails.

- Build a classic taskbar with application menu, pinned shortcuts, running-window
  buttons, active-window emphasis, and optional app grouping.
- Support icon-and-title or icon-only presentation. On Left/Right use stacked
  rows with upright titles, configurable width, truncation, and tooltips.
- Add focus/window selection and context actions, including move to workspace.
  Include minimize/restore only after Phase 3 establishes recoverable behavior.
- Provide current/all-workspace and current/all-monitor window filters.
- Support all edges and overflow while keeping window buttons readable.

Acceptance: task buttons follow window lifecycle, focus, output, and workspace
changes accurately; grouped and ungrouped modes work in every orientation.

## Phase 7 — Classic Hyprbar controls and coexistence

Progress (2026-10-16): independent status controls were already implemented in
Phase 6 refinements. The menu coexistence slice now protects neighbouring panel
edges and reveal strips from menu input masks, bounds popovers to the available
area, coordinates hover/tray menus, and closes stale menus on workspace/layout
changes. Automated coverage exercises all three pairs across 36 distinct-edge
arrangements. Show Desktop and physical layer-shell/hotplug acceptance remain
pending; Phase 7 is intentionally not checked off. See [validation and scope](panel-coexistence.md).

- Add optional workspace switcher, system tray, clock/calendar, notifications,
  Settings, and Show Desktop using existing services and controls where possible.
- Give each component independent item visibility so users can choose where
  status controls appear without automatically removing them elsewhere.
- Finish common placement and corner handling: reserved space, margins, inward
  popovers, auto-hide reveal zones, and monitor hotplug behavior.
- Exercise all three allowed pairs, each with distinct edges, including adjacent
  edges and mixed horizontal/vertical layouts. Apply conflict rules consistently
  in Settings, backend validation, restore, and imported configurations.

Acceptance: every allowed pair works without overlap or competing menus; a
conflicting configuration is explained and leaves the previous valid layout
intact. Shared services do not create duplicate notification owners or timers.

## Phase 8 — Settings, persistence, and final validation

Progress (2026-10-16): searchable schematic placement previews and six explicit
presets are available in Settings → Hyprpane & panels. Previewing is read-only;
Apply layout preset submits component enablement and selected edges together
through the existing settings transaction. Personal styling, pins, items,
monitor/workspace scopes and overrides survive. See [layout settings](panel-layout-settings.md).
The final persistence/deployment matrix and physical acceptance remain pending;
this slice does not mark Phase 7 or Phase 8 complete.

- Finish searchable settings for Hyprpane, Hyprdock, and Hyprbar, including live
  layout previews and explicit presets that retain personal customizations.
- Validate defaults, schema compatibility, transaction rollback, installation,
  updates, GitHub sync, and backup/restore for the new preferences.
- Add focused behavioral tests for app matching/pins, lifecycle/grouping,
  layout validation, visibility, and preference migration. Use native QML checks
  for orientation, overflow, and interactions where practical.
- Perform live visual/input checks on all four edges, all allowed component
  pairs, workspace transitions, fullscreen, scaling, and monitor changes.
  Record checks that need a physical session rather than claiming they passed.
- Update desktop documentation and the installed Hyprskill references to reflect
  the completed names, settings, shortcuts, and troubleshooting paths.

Acceptance: a fresh setup restores the chosen layout, ordinary updates preserve
preferences, all required checks pass, and remaining limits are documented.

## Working increment and completion policy

Implement one phase or a smaller named slice per task. Begin with its intended
behavior and affected files; end with a diff review, focused validation, and a
concise description of what is usable and what remains. Mark checklist progress
below only after the corresponding acceptance criteria are met.

Apply matching authorized changes to the checkout and live configuration without
overwriting unrelated differences. Reload only after validation. Create a local
commit at each successfully completed implementation-task boundary; do not push
without explicit authorization. Saving this plan is a documentation-only task.

- [x] Phase 1: Naming and configuration design
- [x] Phase 2: Vertical Hyprpane polish
- [x] Phase 3: Shared applications and windows
- [x] Phase 4: Hyprdock core
- [x] Phase 5: Hyprdock utilities and visibility
- [x] Phase 6: Classic Hyprbar core
- [ ] Phase 7: Classic Hyprbar controls and coexistence
- [ ] Phase 8: Settings, persistence, and final validation
