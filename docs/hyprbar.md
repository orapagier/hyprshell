# Classic Hyprbar — Phase 6

Hyprbar is the classic window taskbar. Enable it in Settings → Hyprpane & panels
→ Hyprbar after choosing an available edge. It defaults off, preserving the
existing arrangement. Placement validation still permits at most two visible
components on an output/workspace, on different edges; it never moves or disables
another component to make room.

The taskbar fills its edge and includes an application menu, ordered app pins,
and running-window buttons. It shares the existing ApplicationService, desktop-ID
matching, launch semantics and settings transactions with Hyprdock and the
launcher. Shared/separate pin lists remain available in Apps & windows.

- Click an idle pin to launch, a single-window button to focus, or a grouped
  button to choose a window. Focus preserves the pointer position.
- Right-click or press Menu / Shift+F10 for new instance, pin/unpin, focus, close,
  and a destination-workspace selector with an explicit Move button (1–99).
  Middle-click opens another instance of an installed app.
- Grouping is optional. Ungrouped buttons retain individual window addresses.
  Groups show the active window title, or their first window title, plus a count.
- Titles can be disabled. Left/Right use stacked rows, upright truncated titles,
  configurable width and full-title tooltips. Top/Bottom use configurable button
  widths. Active and urgent windows retain visible emphasis.
- Filters select current/all workspaces and current/all monitors independently.
  Filtering precedes grouping, so pickers and active emphasis describe only the
  included windows. Pins remain available when their windows are filtered out.
- Overflow scrolls with wheel/buttons; arrows, Home/End and Tab provide keyboard
  access. Enter/Space activates and Escape dismisses. Pins retain drag reorder
  and Ctrl+arrow ordering through the existing pin transaction.

Preferences live in `panels.hyprbar`. New fields are `grouped`, `showTitles`,
`buttonWidth` (80–400), `verticalWidth` (80–400), `windowWorkspaceScope` and
`windowMonitorScope` (`current` or `all`). Existing placement, visibility,
dimensions and hide-mode fields remain supported. Missing fields inherit defaults
without rewriting saved preferences. Vertical reserved width follows the saved
side-panel width; horizontal panels own adjacent corners.

Implementation uses the existing Dock/DockWindow/DockPopup surfaces with an
explicit component selector; their default remains Hyprdock. `TaskbarModel.js`
owns task filtering and grouping, and `SettingsTaskbarEditor.qml` owns the new
controls. No additional discovery service, notification owner or periodic client
polling is created. Geometry sampling remains limited to eligible dodge panels.

Minimize/restore remains unavailable: Phase 3 did not establish a recoverable
compositor implementation. Optional status controls, Show Desktop, full
coexistence/hotplug acceptance, and layout previews/presets remain Phases 7–8.

## Validation — 2026-10-16

The Qt 6 suite passed 248 checks, including four-edge taskbar pointer/keyboard
activation, grouped/ungrouped models, title layout, overflow and Move actions.
The native Quickshell taskbar test passed with the real ApplicationService and
isolated preferences: output/workspace filtering, grouping, close/title/focus
updates and orientation changes. The existing native dock launch/pin/reorder
check and Settings search checks passed. Backend coverage checks inherited
preferences, invalid taskbar fields, allowed pairs and conflict rejection.

Layer-shell placement, compositor actions, physical input and fullscreen/output
transitions need an accessible desktop session. `hyprctl -j monitors` returned
`Couldn't set socket timeout (2)` here. Offscreen Quickshell has no PanelWindow
backend, so the native taskbar test uses a regular window and does not claim
layer-shell placement passed. Live configuration files are copies; matching
source changes are deployed with a dated backup, leaving saved preferences intact.
