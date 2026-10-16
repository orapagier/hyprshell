# Hyprdock core — Phase 4

Enable **Settings → Hyprpane & panels → Hyprdock → Enable Hyprdock**. Choose a
screen edge different from Hyprpane, then adjust dock thickness, icon size and
spacing. The existing layout stays unchanged until you enable the dock. A
conflicting choice leaves the previous valid saved layout intact and keeps the
Settings draft available for correction.

Hyprdock shows the launcher, ordered pins, then running unpinned applications.
A line marks running apps; the active app has a purple background and indicator.
App icons have no hover tooltip. Missing applications retain their pin,
use a fallback icon and can be unpinned. Click an app with one window to focus
it on its workspace. Apps with multiple windows open a horizontal strip containing
only window previews and an × close button on each. Click a preview to focus that
exact window on its workspace, or × to close it. Scroll horizontally when the strip
overflows. Visible previews capture live window content when available, with a title
fallback when capture is unavailable.
Click an unopened pinned app to launch it from the current workspace. Right-click
opens the context menu with window titles, workspaces and outputs. Each
window has its own Focus and Close actions. Middle-click opens a new instance
when the app is installed. Right-click an app for pin/unpin, new instance,
window selection, close, or app identity/pin management.

Pin an installed app from the launcher with **right-click → Pin to Hyprdock**.
Keyboard users can select an app with the existing search and arrow keys, then
press **Ctrl+P** for the pin menu. Launcher → Apps & windows retains the complete
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

This phase always shows a workspace-visible dock and reserves its effective
thickness plus the configured window gap. The Phase 1 `auto-hide` and `dodge`
hide-mode values remain reserved until Phase 5; they currently render as always
visible. Utilities, automatic hiding, fullscreen policy and additional appearance
controls remain Phase 5 work. Classic Hyprbar and full three-component placement
validation remain in their planned phases. Minimize/Show Desktop remain deferred.

## Validation — 2026-10-16

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
