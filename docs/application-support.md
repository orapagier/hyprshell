# Applications and windows

`shell.qml` creates one `ApplicationService` for application discovery, launcher
icons and UWSM launches. `ApplicationManager.qml` retains window actions and
explicit application identity corrections.

The running-window list includes titles, workspace names and output names.
Select a window to focus it, close it, or move it to workspace 1–99 without
following it. **New instance** uses the
same desktop-entry launch path as the launcher; single-instance applications may
choose to reuse an existing window. For an unmatched or incorrectly matched
window, select the correct installed app in the chooser, then **Match to chosen
app**. **Automatic match** removes the correction for that window's class/app ID.
Corrections apply to all windows with the same identity, persist in
`pins.matches`, and travel with settings backups and sync.

Existing Super+H / Super+Shift+H behavior remains independent. Pending Show
Desktop restores retain their journal and IPC recovery; see [recovery](show-desktop.md).

## Shared contract

`shell.qml` creates one `ApplicationService` and passes it to the launcher.
`ApplicationModel.js` contains desktop-ID normalization, launch argv generation,
matching and validated window dispatcher arguments. `AppIcons.qml`
provides the existing theme/catalog/fallback lookup, now shared by the service.
Standalone launcher instances retain their compatible launch and icon fallback.

Matching first honors explicit case-sensitive identity corrections, then compares
case-insensitive full desktop IDs, StartupWMClass, and the final desktop-ID
segment, in that priority order. Current Wayland app ID, class and initial class
are considered. Ambiguous matches remain unmatched instead of guessing from
window titles. Missing icons use the existing generic fallback. Explicit
corrections to uninstalled apps retain their ID and can be corrected again.

The service keeps cached window rows with address, title, workspace ID/name,
output, focus/urgency and native handles. It uses compositor objects and coalesced
events without periodic client-list polling. Actions recheck window liveness.

Normal application IDs launch with `uwsm app -t service -- ID.desktop`, retaining
Terminal, working-directory and field-code handling. Unusual filenames keep the
existing `DesktopEntry.execute()` fallback: Quickshell handles Exec/working
directory but does not provide UWSM's Terminal/field-code semantics. This phase
does not change that existing limitation.

`backend.py --app-action-json` supports identity corrections. Each operation reads the latest configuration under the existing
settings lock, validates, backs up and atomically saves through the normal
transaction. It does not submit a stale whole-settings snapshot. An already-open
Settings draft retains its usual conflict detection. No new state file or sync
allowlist is required; old version-1 settings inherit empty corrections.

Window-to-application matching runs through `Qt.callLater`, after native
Hyprland property notifications finish. Matching directly inside a QML binding
reproduced a startup segmentation fault in `Qt::endPropertyUpdateGroup()` with
Quickshell 0.3.2 / Qt 6.11.2 and real installed apps/windows. App and window
signals queue a coalesced rebuild; the window manager consumes the cached rows so it
does not repeat native matching inside a binding. Title, focus, urgency,
workspace/output, app metadata and identity-correction updates remain reactive;
this adds no periodic polling.

The deferred-matching fix passed focused model, service and launcher
checks, including QObject property updates and cached rows without reading
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
