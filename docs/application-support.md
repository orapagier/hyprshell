# Shared applications and windows — Phase 3

Right-click any application in a panel's launcher to choose **Pin to Hyprdock**
or **Pin to Hyprbar**. Keyboard users can select an app and press **Ctrl+P**.
Open **Hyprdock app context menu → App matching and pins…** to manage shared
application preferences. [Phase 4](hyprdock.md) now renders Hyprdock; classic Hyprbar arrives later.
Neither phase automatically enables a new panel.

Choose Hyprdock or Hyprbar pins, select an installed application, and press **Pin**.
**Shared pins** uses the same ordered list for both components. Turning it off
selects each component's independent saved list; switching modes retains all three
lists. Use the arrows to reorder, **Unpin** to remove, or the app button to launch
a pin. An uninstalled pin stays in its saved position, marked “not installed,”
and can still be removed. Pinning and ordering save immediately through the
existing settings transaction, with backups and conflict protection.

The running-window list includes titles, workspace names and output names.
Select a window to focus it, close it, or move it to workspace 1–99 without
following it. **Pin app** uses its matched desktop ID. **New instance** uses the
same desktop-entry launch path as the launcher; single-instance applications may
choose to reuse an existing window. For an unmatched or incorrectly matched
window, select the correct installed app in the chooser, then **Match to chosen
app**. **Automatic match** removes the correction for that window's class/app ID.
Corrections apply to all windows with the same identity, persist in
`pins.matches`, and travel with settings backups and sync.

No new minimize/restore or Show Desktop controls are exposed. Existing Super+H /
Super+Shift+H behavior stays unchanged. This phase's focus action does not promise
to restore a window hidden on a special workspace; the existing restore shortcut
remains available. A durable, shared hidden-window recovery policy is required
before adding those controls to app panels.

## Shared contract

`shell.qml` creates one `ApplicationService` and passes it to the launcher.
`ApplicationModel.js` contains desktop-ID normalization, launch argv generation,
matching, grouping and validated window dispatcher arguments. `AppIcons.qml`
provides the existing theme/catalog/fallback lookup, now shared by the service.
Standalone launcher instances retain their compatible launch and icon fallback.

Matching first honors explicit case-sensitive identity corrections, then compares
case-insensitive full desktop IDs, StartupWMClass, and the final desktop-ID
segment, in that priority order. Current Wayland app ID, class and initial class
are considered. Ambiguous matches remain unmatched instead of guessing from
window titles. Unknown classes group together; windows without a class/app ID
remain separate. Missing icons use the existing generic fallback. Explicit
corrections to uninstalled apps retain their ID and can be corrected again.

`service.groups(component)` returns pins in saved order followed by running
unpinned apps. Each group exposes its desktop ID, installed entry, name/icon,
pinned/active/urgent flags and window rows. Rows include address, title,
workspace ID/name, output, focus/urgency and the native handle. Multiple windows
of one app share a group. The service uses Quickshell's compositor objects and
coalesced compositor events, without periodic client-list polling. Multiwindow
`activate(group)` emits `windowSelectionRequested(group)` so future panels can
present a picker; the current manager selects individual window rows directly.
Every dispatched action rechecks that the addressed window is still present.

Normal application IDs launch with `uwsm app -t service -- ID.desktop`, retaining
Terminal, working-directory and field-code handling. Unusual filenames keep the
existing `DesktopEntry.execute()` fallback: Quickshell handles Exec/working
directory but does not provide UWSM's Terminal/field-code semantics. This phase
does not change that existing limitation.

`backend.py --app-action-json` supports pin/unpin/reorder, pin mode and identity
corrections. Each operation reads the latest configuration under the existing
settings lock, validates, backs up and atomically saves through the normal
transaction. It does not submit a stale whole-settings snapshot. An already-open
Settings draft retains its usual conflict detection. No new state file or sync
allowlist is required; old version-1 settings inherit empty corrections.

Window-to-application matching runs through `Qt.callLater`, after native
Hyprland property notifications finish. Matching directly inside a QML binding
reproduced a startup segmentation fault in `Qt::endPropertyUpdateGroup()` with
Quickshell 0.3.2 / Qt 6.11.2 and real installed apps/windows. App and window
signals queue a coalesced rebuild; dock grouping consumes the cached rows so it
does not repeat native matching inside a binding. Title, focus, urgency,
workspace/output, app metadata and identity-correction updates remain reactive;
this adds no periodic polling.

The deferred-matching fix passed 33 focused model, service, dock and launcher
checks, including QObject property updates and cached grouping without reading
native windows. The user confirmed full live shell startup and notification
ownership on 2026-10-16. This startup confirmation does not certify every
compositor action described below.

## Validation — 2026-10-16

- Qt 6 QML suite: 198 passed, including matching ambiguity, multiple-window
  grouping, lifecycle metadata, unknown apps, missing pins and dispatcher guards.
- Application support: six isolated backend/native tests cover ordered pins,
  shared/separate modes, persistence, identity edits, validation, rollback safety,
  stale Settings drafts, live QML model updates and the native save/reload path.
- Launcher: three checks pass, covering keyboard search/Up/Down/Enter and UWSM
  dispatch both standalone and through the shared service, plus installed
  terminal desktop-entry resolution. Native launcher/service/manager sources
  load without QML binding/type errors.
- Panel configuration: seven passed; settings: 33; configuration backup/restore:
  nine; sync: 13; settings search: six. Setup: 17 passed, one platform skip.
  Recovery backend: 15 passed. The separate native recovery smoke test still
  fails to produce its completion marker with an IPC socket error; the same
  failure was reproduced on an isolated unchanged HEAD baseline.
- Live `hyprctl configerrors` is inaccessible (`Couldn't set socket timeout (2)`).
  Full shell instantiation also needs a PanelWindow backend unavailable offscreen.
  Real-window launching/matching, focus, close and workspace moves therefore need
  physical-session confirmation; offscreen tests do not certify these actions.
  Matching runtime files are deployed after validation; existing saved settings
  are not rewritten. Quickshell's watcher handles QML reload when accessible.
