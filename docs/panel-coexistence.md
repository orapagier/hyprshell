# Panel coexistence — Phase 7 menu slice

Implemented 2026-10-16. Existing independent system-item selections already
provide workspaces, tray, clock/calendar, notifications and Settings in Hyprbar
and Hyprdock. Selecting an item there continues to preserve Hyprpane's selection.
This increment completes the menu coexistence slice, not the whole phase.

An open menu previously covered the inward part of the screen with its input
mask, including another panel on an adjacent or opposite edge. The other panel
could become unreachable until the menu was dismissed. Both app menus and
status dropdowns now exclude the neighbouring panel's edge band and constrain
their cards to the remaining area. This covers Hyprpane + Hyprdock, Hyprpane +
Hyprbar and Hyprdock + Hyprbar on distinct edges. Single-panel geometry is
preserved. Horizontal panels continue to own corners; side rails yield their
top and bottom ends to visible horizontal panels.

`DockModel.js` derives these bounds from the existing monitor/workspace visibility
rules, dimensions, edge margins and window gaps. Auto-hide/dodge neighbours keep
their edge band reachable even when hidden, preserving the 3 px reveal surface
and room for the revealed panel without resizing the menu repeatedly. This is
deliberately conservative: a compact neighbour protects its whole edge band,
including unused space along that edge. It does not reserve extra compositor
space or alter saved preferences.

Opening a hover app picker/launcher now coordinates with other panel menus just
like a click. Tray activation dismisses shell menus first. Workspace and available
area changes dismiss stale menus; removing a status item also closes its menu.
Variants still follow `Quickshell.screens`, and bounds are calculated from current
output dimensions rather than retained output geometry. One ApplicationService,
DesktopServices, tray and notification owner remain shared; no timer or polling
service was added. The width passed for a vertical Hyprpane now uses its width,
so adjacent menus do not treat the rail's full height as its thickness.

## Validation and limits

- Qt 6 `tst_PanelCoexistence.qml`: all 36 pair/edge arrangements, both owners'
  card/input bounds, monitor filtering, workspace overrides, hide modes,
  changed output dimensions and empty intersections.
- Existing Qt 6 suite: panel menus, vertical layouts, app actions, overflow,
  status selection, corner insets and hide/reveal state tests pass. The combined
  run passed 301 checks, including the 40 new coexistence checks.
- Native Quickshell dock and taskbar tests pass with isolated preferences;
  they cover launch/pin transactions, window grouping/filtering and four edges.
- Backend pair/edge/conflict tests pass. Configuration recovery additionally
  rejects a conflicting panel backup with a valid checksum before changing any
  live configuration. Existing shortcut transaction tests preserve the saved
  layout and backup set when a visibility toggle would cause a conflict.

The focused Python run passed 60 tests across configuration recovery, panel
configuration, settings, native dock/taskbar and panel styling. All changed QML
files also passed Qt's parser. The Qt suite retains pre-existing dock fixture
initialization warnings; the isolated native dock/taskbar checks report no
TypeError or ReferenceError.

Layer-shell input delivery, native tray menus, exclusive-zone placement,
fullscreen, scaling and physical monitor hotplug still need an accessible
compositor. `hyprctl -j monitors` reports `Couldn't set socket timeout (2)` in
this agent session. Offscreen Quickshell cannot load PanelWindow (`No PanelWindow
backend loaded`), so native composition tests use ordinary windows and Qt tests
exercise geometry independently. These checks do not establish physical acceptance.

Show Desktop remains unexposed. The [Hyprland dispatcher reference](https://wiki.hypr.land/configuring/core/dispatchers/)
does not provide a dedicated Show Desktop operation. This session cannot verify
a reversible substitute with the compositor. Moving windows to a special
workspace would require verified restoration across window closure, output
changes and shell restart, while switching to an empty workspace alone leaves
pinned windows visible. Neither is offered as a finished Show Desktop control.
Phase 7 remains open for this action and physical coexistence acceptance; Phase
8 retains settings previews/presets and the final persistence/deployment matrix.

Changed QML/JS source is applied to both the checkout and matching installed
copies after focused validation, with the previous installed files backed up.
Panel visibility, selected edges and personal settings are preserved.
