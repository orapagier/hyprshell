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
8's [settings previews/presets](panel-layout-settings.md) slice is implemented;
the automated persistence/deployment transaction matrix is now covered in
[panel persistence](panel-persistence.md). Physical acceptance remains pending.

Changed QML/JS source is applied to both the checkout and matching installed
copies after focused validation, with the previous installed files backed up.
Panel visibility, selected edges and personal settings are preserved.

## Live geometry increment (2026-10-17)

Live Hyprland IPC now works in the agent session. The installed shell is running
and `hyprctl configerrors` is empty. The earlier socket failure above describes
the original validation session.

Run `python3 tools/check_panel_live.py --run` to repeat this bounded check.
It creates a temporary headless output and a separate minimal Quickshell fixture
using the production `DockWindow`, `Dock`, and status/menu composition. Settings
and state are isolated in a temporary directory. It does not start another
notification owner, launch apps, or write the user's saved preferences. The
existing shell may create its usual panels on the added output. The fixture
uses empty app/window inputs, so this checks placement rather than app lifecycle.
The fixture process stops before the virtual output is removed, including on
failure; unrelated outputs and shell processes are preserved.

The live run passed all 12 distinct-edge Hyprdock/Hyprbar arrangements on a
1920×1080 virtual output at scale 2 (960×540 logical pixels). Each arrangement
passed two samples of compositor-reported layer geometry: both surfaces exist,
have the expected 32 logical-pixel thickness, remain inside the output near
their selected edges, and do not overlap. Five isolated verifier tests cover
scaled coordinates, output offsets, wrong edges, out-of-bounds surfaces, and
adjacent-corner overlap/clearance.

This increment does not validate Hyprpane pairs, menu input delivery, native tray
menus, pointer/keyboard behavior, auto-hide, fullscreen, actual window actions,
physical hotplug, or other scale factors. It does not independently certify
exclusive-zone sizes. Physical acceptance and Show Desktop remain pending, and
Phases 7 and 8 remain open. No panel runtime deployment or reload is needed for
this verifier/documentation increment.

### All-pairs continuation (2026-10-17)

The verifier now extracts the three panel `Variants` blocks directly from
`shell.qml`, replacing only their screen models with the temporary-output filter.
This exercises the production Hyprpane `PanelWindow`, Bar, dropdown and corner
placement together with both app panels, without duplicating their layout code.
Shared app/window inputs and status services remain fixture data; notification,
locking and other desktop services are not started. The fixture fails explicitly
if the expected production composition boundaries or screen models change.

All 36 distinct-edge arrangements passed live at scale 2: Hyprpane + Hyprdock,
Hyprpane + Hyprbar and Hyprdock + Hyprbar. Each pair passed two geometry samples.
Full-output menu surfaces are excluded from rail measurements; the expected
component namespaces must occur exactly once each. Hyprpane thickness is allowed
to fit its default controls (32–80 logical pixels), while app rails must be 32.
Bounds, selected-edge proximity and non-overlap are checked for all three pairs.
Eight verifier tests now include both Hyprpane pairs, missing/duplicate component
rejection and production-fixture extraction, alongside the earlier coordinate
and overlap checks.

The earlier Hyprpane-pair limitation above is resolved for this geometry slice.
Menu input, pointer/keyboard interaction, auto-hide, fullscreen, workspace
transitions, window actions, physical hotplug and additional scales remain
unverified. Exclusive-zone sizes and visual polish still need separate checks.
Phases 7 and 8 remain open. The installed shell, saved preferences and physical
display layout are preserved; the temporary fixture and output are removed.

## Live visibility and reservations (2026-10-17)

`python3 tools/check_panel_live.py --run --checks behavior` runs the next isolated
acceptance slice; `--checks all` includes the 36-case geometry matrix first.
The default command retains geometry-only behavior. The fixture loads commands
from a temporary JSON file and reports the production `DockVisibility` state
after the 500 ms hide delay. Reports carry command IDs so stale observations
cannot satisfy a later scenario. The controller and assertions live in
`tools/panel_live_behavior.py`.

For both Hyprdock and Hyprbar on every edge, the matrix covers always-visible,
auto-hide, opening/dismissing the production launcher to hold/release visibility,
dodge with clear/overlapped geometry, dodge menu interaction, fullscreen Hide/Show
policies, and hiding/restoring the current workspace through saved overrides.
It checks actual compositor reservation deltas against the installed shell's
baseline, including the configured edge margin and window gap, and confirms
3 logical-pixel reveal surfaces exist only when eligible and unsuppressed in a
hiding mode. Always-visible has an exclusive zone; auto-hide and dodge have none,
including while their menus hold the panel open.

Overlap and fullscreen are injected app-service window metadata on the real
virtual output, not physical toplevel actions. Workspace cases change only the
isolated settings override for that output's current workspace; they do not
switch the user's workspace. Menu methods are invoked programmatically, so this
does not establish pointer/keyboard delivery, reveal-hover usability, native tray
menus or real fullscreen acceptance. Actual workspace transitions, physical
hotplug, other scales and Show Desktop remain pending.

The live scale-2 run passed eight always-visible baselines and 88 subsequent
transitions. Eleven verifier tests, nine Qt visibility checks and native panel
layout/workspace settings tests passed. No runtime QML or real saved preferences
changed. The temporary shell/output are removed and the original shell remains.

## Real session and Show Desktop (2026-10-17)

`python3 tools/check_panel_session.py --run --wtype /path/to/wtype` loads
production panel composition with native toplevel tracking on a temporary output.
It creates two disposable windows and isolates settings and recovery state.
Actual fullscreen Hide/Show policies, workspace switches and panel restoration
pass. Pointer reveal on every edge and Escape dismissal of the production
launcher pass for both Hyprdock and Hyprbar. Escape is sent only after the
fixture reports its own exclusive keyboard focus. Focus, pointer and temporary
output cleanup are restored afterward.

The production Show Desktop button and shared controller pass a hide/restore
round trip. Real pinned/fullscreen windows restore across controller restart;
closed hidden windows and removal of their virtual output recover successfully.
These checks found and fixed stale monitor workspace state after focus restoration
and null output access during hotplug teardown. The helper journals origins
before moving windows and retains partial failures for retry; see
[Show Desktop](show-desktop.md) for recovery and scope. Both app-panel controls
default off, and existing shortcuts are preserved.

The 36-case production geometry matrix passes at scales 1, 1.25 and 2. Optional
`--screenshots DIR` records local evidence. The separately running installed
Hyprpane can appear on the temporary output in these isolated screenshots; they
are not independent visual sign-off of every pair. Test state and screenshots
remain outside Git.

`python3 tools/check_panel_tray.py --run` registers a private, harmless tray
provider. Production Hyprpane routing reaches its native D-Bus menu and retrieves
its layout. A programmatic request did not produce a visible menu in the captured
image, so visible native tray popups and their input remain unverified. This
diagnostic does not certify Escape delivery or the Hyprbar tray path.

Physical connector hotplug, external-display interaction, native tray input and
fresh Fedora install/update/recovery remain open. Virtual outputs cannot certify
those conditions. Phases 7 and 8 remain open for these gates and the baseline
required-check failures recorded in [panel persistence](panel-persistence.md).

The reviewed runtime changes are applied to the checkout and matching live
`~/.config/quickshell` files. Prior copies and a checksum manifest are under
`state/hyprshell/backups/desktop-panels-20261016T223424Z`. Saved personal settings
were byte-for-byte preserved. The existing shell reload action loaded the new
`bar.restoreDesktop` method; `bar.ready` returns true and `hyprctl configerrors`
is empty. The original shell process and physical monitor layout remain intact.

## External display and plan closure (2026-10-17)

At the user's request, final acceptance used the connected HDMI-A-1 monitor at
1440×900, scale 1, positioned beside eDP-1. These commands reuse the output and
never change its mode or remove it:

```bash
python3 tools/check_panel_live.py --run --output HDMI-A-1
python3 tools/check_panel_session.py --run --output HDMI-A-1 --wtype /path/to/wtype --screenshots /local/evidence
```

All 36 production pair/edge geometries passed. On an unused temporary workspace,
real fullscreen Hide/Show policies, workspace visibility restoration, pointer
reveal and Escape dismissal on all four edges of both app panels passed. The
production Show Desktop button restored its disposable windows; pinned/fullscreen
state, controller restart and closure of a hidden window also passed. Existing
windows were left on their original workspaces. The original external workspace
2, laptop workspace 1, focus and pointer were restored. The physical output was
kept connected; cable unplug/replug cycling was not performed.

This check exposed a startup race: Quickshell can detect Lua IPC support after
its initial legacy queries, leaving monitors/workspaces unresolved. The shared
ApplicationService now refreshes workspace/monitor data at startup and after Lua
detection, and continues coalescing later events. The new native
`tests/test_panel_monitors.py` confirms initial workspace resolution on both
outputs without a workspace-switch event. After deployment/reload, installed
panels correctly respect saved scopes: only Hyprpane appears on current workspaces
1 and 2, and both outputs reserve only their expected 37 px top band. The shell
reports ready and Hyprland reports no configuration errors.

The startup regression, six adjacent application-service checks and eleven live
verifier checks passed. Current Python sources compile and `git diff --check`
passes. External-output images remain in local acceptance state, outside Git.
The service update was backed up under
`state/hyprshell/backups/panel-monitor-startup-20261016T225544Z` and applied to both
checkout and live config; saved personal settings and physical modes are retained.

The user requested ending the plan and committing after this external-display
check. Phases 7 and 8 are therefore signed off for this desktop with the remaining
native tray-input, cable-cycle, fresh-VM and baseline full-suite issues explicitly
deferred. Earlier open-gate statements above describe the preceding checkpoints.
These deferred checks are not reported as passes or as release certification.
