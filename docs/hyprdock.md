# Hyprdock — core, utilities and visibility

Enable **Settings → Hyprpane & panels → Hyprdock → Enable Hyprdock**. Choose a
screen edge different from Hyprpane, then adjust dock thickness, icon size and
spacing. The existing layout stays unchanged until you enable the dock. A
conflicting choice leaves the previous valid saved layout intact and keeps the
Settings draft available for correction.

**Dock transparency** adjusts the background from opaque (0%) to transparent
(100%), keeping app icons and indicators readable. **Dock distance from screen
edge** sets the outside gap (0–100 px) on any selected edge. Both save automatically;
existing preferences retain their previous background opacity and edge distance.

Hyprdock shows the launcher, ordered pins, then running unpinned applications.
A line marks running apps; the active app has a purple background and indicator.
App icons have no hover tooltip. Missing applications retain their pin,
use a fallback icon and can be unpinned.
Hover the launcher to open Applications, or a running app to preview its windows.
Menus use Hyprpane's hover delay, stay open across the pointer bridge, switch when
hovering another icon, and close shortly after leaving. Clicking the launcher or
a multi-window app pins its menu until dismissed; focusing or launching a single
window app and dragging a pin dismiss previews.
Click an app with one window to focus
it on its workspace without moving the pointer. Dock picker and preview
activation also keep the pointer in place. The focus operation temporarily
suppresses Hyprland cursor warps and restores the original options in the same
compositor event, including error paths; desktop focus shortcuts retain their
existing behavior. Apps with multiple windows open a strip containing
only window previews and an × close button on each. Click a preview to focus that
exact window on its workspace, or × to close it. Previews stack vertically for left
and right docks and horizontally for top and bottom docks; scroll along that axis
when the strip overflows. Visible previews capture live window content when available, with a title
fallback when capture is unavailable.
Click an unopened pinned app to launch it from the current workspace. Right-click
opens the context menu with window titles, workspaces and outputs. Each
window has its own Focus and Close actions. Middle-click opens a new instance
when the app is installed. Right-click an app for pin/unpin, new instance,
window selection, close, or app identity/pin management.

Pin an installed app from the launcher with **right-click → Pin to Hyprdock**.
Keyboard users can select an app with the existing search and arrow keys, then
press **Ctrl+P** for the pin menu. The launcher’s right-click / Ctrl+P menu uses
the shared wallpaper-tinted glass surface, rounded highlights and translucent
rim, in both Hyprpane and Hyprdock launchers. App context menu → App matching and pins retains the complete
shared/separate pin and identity-correction controls from Phase 3.

Drag one pinned app over another to reorder it. Dragging near an overflow edge
scrolls the list. With keyboard focus in the dock, use the orientation's arrow
keys, Home/End, Enter/Space, and Menu or Shift+F10 for context actions. Ctrl plus
an orientation arrow moves a pin earlier/later. Tab reaches individual controls
and picker buttons; Escape dismisses the menu. Existing desktop shortcuts are
unchanged. Focus enters the dock on pointer interaction; this phase does not
assign a new global dock shortcut.

Short edges scroll with the arrows, mouse wheel, trackpad or keyboard. Targets
stay at least 36 logical pixels; a large configured icon expands effective
thickness instead of clipping. The dock backdrop remains compact even though
its transparent layer surface spans the edge for reliable reserved space. Its
input mask covers only the compact dock. Empty stretches pass pointer input
through to the desktop. Popovers open inward beside the triggering app and
clamp to the screen; the existing menu container scrolls long content.

## Configuration and integration

The Phase 1 `panels.hyprdock` settings now render a dock. Existing defaults remain
unchanged: disabled, Bottom, 56 px requested thickness, 32 px icons, 4 px spacing.
`background: inherit` follows Hyprpane's background setting. Existing output and
workspace visibility selections are honored. On adjacent edges, horizontal
components own the corners; vertical components are inset by each visible
horizontal component's effective thickness, edge margin and window gap. Disabled
or workspace/output-hidden components add no inset. A lone Hyprpane retains its
existing geometry.

`shell.qml` creates one `DockWindow` per output and shares the Phase 3
`ApplicationService`. `Dock.qml` owns orientation, input, indicators, overflow
and drag ordering. `DockPopup.qml` reuses `MenuPopover`, `LauncherMenu`,
`ApplicationManager` and `DockActions` for one inward menu per dock. Opening a
pane or dock menu dismisses the other component's menus. No extra notification
owner, application poller or settings store is created.

Pins still use the existing locked, backed-up settings transaction. Reordering
updates the active shared or independent Hyprdock list. Enabling, edge and size
controls use the existing Settings draft/autosave/conflict flow and are searchable.
There is no schema version change or new persistence file. Setup copies the new
components; normal settings backup and GitHub sync keep the saved preferences.

## Utilities and visibility — Phase 5

Settings → Hyprpane & panels → Hyprdock now includes optional Files, Settings
and Trash shortcuts. They default off to retain the existing arrangement.
Files opens your home folder with the default file manager; Settings opens the
existing Settings window. Clicking Trash opens `trash:///` in the file manager.
Right-click Trash (or Menu / Shift+F10 with it focused) for its status and
**Empty Trash…**, then **Confirm empty Trash**. Cancel or dismiss to abandon
confirmation. Opening Trash never empties it. The empty/full icon refreshes every
15 seconds while enabled and when opening its context menu. One shared utility
service handles all outputs. Unavailable Trash reports an error and disables
emptying; a failed empty operation never claims success.

**Dock visibility** selects:

- **Always visible**: reserve effective thickness plus window gap (and the
  layer surface's outside margin), as in Phase 4.
- **Auto-hide**: reserve no space; reveal from a 3 px strip at the physical
  screen edge, aligned with the dock even when an outside margin is saved.
- **Hide when overlapped**: reserve no space; hide when a window intersects
  the dock on the active workspace, including pinned windows. Windows on other
  workspaces do not hide it. Reveal from the same edge strip.

Hiding waits 500 ms so the pointer can cross an outside margin or return from a
menu. Menus, window pickers, pin drags and keyboard navigation hold the dock open.
Escape releases keyboard retention and dismisses its menu. Pointer focus alone
does not keep an auto-hide dock open. Workspace/output filtering immediately
suppresses both dock and reveal strip and closes menus. The existing application
service samples compositor geometry every 350 ms only while a visible dodge dock
needs it; it uses the shared toplevel model, not a second application service.
Fullscreen/workspace events also refresh that model for all hide modes.

**Dock in fullscreen** defaults to hiding the dock and its reveal strip, with no
reservation. Choose **Show over fullscreen** to retain the selected hide mode;
the dock and reveal strip use the overlay layer. Maximized windows participate
in overlap hiding but are not treated as fullscreen.

Placement controls now include Start / Center / End alignment, end margins and
window gap, alongside edge distance, icon size and spacing. Background may follow
Hyprpane or be On / Off; transparency remains independent. Running indicators
and fade animation can be disabled. Accessibility → Reduced motion disables the
fade without changing the saved animation preference. Connector names restrict
outputs (empty means all); selected workspace numbers use the existing validated
workspace filter and overrides. Invalid settings retain the last saved layout.
New fields inherit defaults when loading old preferences and use the existing
transaction, setup, backup/restore and sync paths; no new settings file is added.
Classic Hyprbar and full three-component placement remain in later phases.
Minimize/Show Desktop remain deferred.

## Phase 5 validation — 2026-10-16

- Qt 6: 240 passed, including four-edge utility routing and nine visibility /
  confirmation checks covering delayed hiding, reentry, interaction retention,
  fullscreen/eligibility suppression, overlap coordinates and pinned windows.
- Native dock and utility checks pass. The utility check uses a stub file manager
  and verifies status/open commands without touching or deleting personal files.
  Backend utility tests verify that only the explicit confirmation action empties
  Trash and that failed status checks cannot report an empty Trash.
- Placement/schema: nine passed; Settings: 33; Settings search including native
  navigation: seven; shared application support: six. Setup: 17 passed, one
  platform skip. Native runtime dependencies pass. QML lint has no syntax errors;
  existing Quickshell PanelWindow/Margins metadata warnings remain.
- Live `hyprctl configerrors` cannot reach the session socket (`Couldn't set
  socket timeout (2)`). Physical reveal/bridge interaction, layer-shell reserved
  space, fullscreen stacking, scaling and monitor hotplug remain unverified and
  belong to the live checks in Phase 8. Offscreen state checks do not establish
  compositor behavior. Runtime files are deployed with a dated backup; saved
  personal settings are not rewritten.

## Phase 4 validation — 2026-10-16

- Qt 6 suite: 215 passed, including 17 dock checks for Top/Bottom/Left/Right,
  mouse launch/context/middle-click, actual pointer drag reordering, keyboard
  focus/activation/reordering, overflow, minimum targets, picker actions,
  missing pins, settings controls, corner visibility and inward popover geometry.
- Native Quickshell dock check passes with real icon lookup, multiple-window
  grouping, a stub UWSM launch and a persisted reorder reflected back in the
  dock. App icons and orientation/popover screenshots were reviewed offscreen.
- Three launcher checks pass, including existing navigation/UWSM behavior and
  Ctrl+P → pin menu → saved desktop ID. Six shared app-support tests pass.
- Settings: 33 passed; placement configuration: seven; caption search: six.
  Setup: 17 passed, one platform skip, including the new dock dependencies.
  Native runtime dependencies pass. QML lint reports no syntax errors; the
  existing Quickshell plugin metadata leaves PanelWindow/Margins warnings.
- `hyprctl configerrors` returns `Couldn't set socket timeout (2)` in this
  session. Layer-shell placement/reserved space, multi-monitor hotplug, native
  compositor focus/close and physical input remain unverified here. Offscreen
  checks are not a certification of live compositor behavior. Matching runtime
  files are deployed with a dated backup; saved settings are not rewritten.

## Launcher menu and pointer polish — 2026-10-16

The launcher pin menu is rendered inside the existing popup surface, using
`GlassSurface` colors and the parent launcher's wallpaper/translucency. Keyboard
navigation and both pin destinations remain available. Dock focus passes an
explicit pointer-preservation flag; other application-manager focus actions keep
their prior behavior. A single Lua evaluation saves the cursor-warp options,
focuses the chosen window with warping suppressed, and restores those options
even if the focus dispatcher throws. App launching retains UWSM desktop IDs.

Validation: 240 Qt checks, three native launcher checks, native dock composition,
six shared-app checks, and the Lua restoration check pass. The launcher check
verifies rounded glass and alpha as well as Ctrl+P and pin persistence. The Lua
check exercises both original no-warp settings, forced workspace warping and
error paths with a mocked compositor. The glass render was reviewed offscreen.
Physical cursor behavior remains unverified because this agent cannot access
the live compositor socket; no global cursor preference is changed.
