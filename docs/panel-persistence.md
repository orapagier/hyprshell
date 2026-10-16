# Panel persistence — Phase 8 transaction acceptance

This increment checks panel preferences through the existing installer, update,
sync and recovery machinery. It adds integration coverage without changing the
settings schema, saved defaults or running desktop configuration.

`tests/test_panel_persistence.py` uses temporary homes and real staged deployment,
JSON/Lua validation and audio-helper compilation. Git sync and reviewed updates
use temporary local remotes. No network, package installation, desktop reload or
real preference restore is involved.

## Acceptance matrix

| Workflow | Panel-specific checks |
| --- | --- |
| Fresh deployment | All 36 distinct-edge arrangements of the three allowed pairs; all three panels enabled on the same edge on disjoint workspaces, for each of four edges; matching panel runtime sources installed |
| Installer entry point | `tools/install_configs.py` restores the saved pair, then retains a different live workspace-specific layout on rerun |
| Ordinary update and deployment rollback | Live preferences preserved across source updates and explicit rollback, on all four edges |
| Legacy settings | Missing panel/pin sections inherit defaults while saved Hyprpane preferences remain intact |
| Conflicting imported configuration | A reviewed same-edge conflict fails staged validation before any installed file changes |
| Settings recovery | Checkpoint, preview, restore and undo preserve complete customized settings on all four edges |
| Setup backup | Dated/checksummed backup, preview, restore and before-restore undo preserve the same preferences |
| Sync to GitHub | Capture live changes, commit and publish to a local test remote; fresh deployment restores each published four-edge layout |
| Reviewed Sync from GitHub | A panel configuration conflict requires an explicit file choice; both Keep local and Use GitHub deploy the selected preferences; kept local preferences remain uncommitted |

Fixtures include separate and inactive shared pin lists, desktop-ID match
corrections, missing pinned apps, monitor lists, selected workspaces and individual
overrides, compact Hyprpane, custom dimensions/spacing/opacity, hide/fullscreen
policies, utilities, independent status selections and ungrouped task buttons.
Assertions compare the entire saved settings object, including unrelated
notification, accessibility and item preferences.

Existing `test_updates.py`, `test_setup.py`, `test_settings.py`,
`test_panel_configuration.py`, `test_configuration.py` and `test_recovery.py`
provide adjacent checks for installer entry points, atomic replacement failure,
stale previews, settings conflicts, invalid backups and transaction rollback.

Validation on 2026-10-16 passed all eight new integration tests, including the
40 fresh-deployment cases, across focused runs. Another 125 checks passed across
panel configuration (15), setup backups (10), updates/deployment (39) and settings,
backend recovery and sync (61). Python compilation and `git diff --check` passed.
The existing native recovery UI check could not start Quickshell's IPC socket
in this sandbox and did not reach its success marker; its unchanged backend
recovery tests passed. This is recorded as unavailable UI acceptance, not a
passing native UI result.

## Scope and remaining acceptance

These are isolated persistence checks. Reviewed-update tests substitute synthetic
compatibility evidence and use non-native staged validation; they do not certify
the current compositor or physical hardware. The panel runtime and UI are
unchanged, so this increment requires no live-file deployment or reload.

Physical layer-shell placement/input, all pairs on screen, fullscreen, scaling,
workspace transitions and monitor hotplug remain pending. The compositor socket
was inaccessible during the original persistence-check session. Live IPC and
the limited all-pairs virtual-output geometry matrix were subsequently verified
on 2026-10-17; see [panel coexistence](panel-coexistence.md#live-geometry-increment-2026-10-17).
A clean Fedora VM install and system-level
update/recovery acceptance also remain separate, as described in
[acceptance](acceptance.md). Show Desktop remains pending under
[panel coexistence](panel-coexistence.md). Phases 7 and 8 remain open.

## Native settings and recovery retest (2026-10-17)

The native Settings layout-preset and workspace-visibility tests now pass in
isolated homes. The recovery UI check also passes, covering invalid confirmation,
preview, the unsaved-edit gate, confirmed restore and the restored signal. Its
Quickshell invocation now explicitly enables `qml.debug` so the success marker
is visible, and asserts a clean exit without QML binding/type errors. This changes
the verifier only, not the installed recovery runtime. All 16 recovery tests
passed, including the backend case preserving panel/pin preferences.

The original unavailable native-UI result above remains a historical record;
this retest supplies current native-UI evidence. It does not perform a real
desktop restore, system upgrade or fresh-VM install. The separate live panel
visibility/reservation slice is documented in
[panel coexistence](panel-coexistence.md#live-visibility-and-reservations-2026-10-17).
Phases 7 and 8 remain open for their remaining physical and system acceptance.

## Final software validation (2026-10-17)

The persistence matrix passed all eight tests again with Show Desktop enabled
in both app-panel fixtures, including 40 fresh-deployment layouts. Its default
is false; legacy configurations inherit that value. Sixteen panel configuration
checks, twelve backend/native Show Desktop checks and native runtime validation
passed. The full Qt run passed 280 tests; after four new Dock cases were added,
the focused Dock run passed all 42 tests.

With `QT_LOGGING_RULES=qml.debug=true`, the broad Python discovery run executed
544 tests with three failures, one error and one skip. All four unsuccessful
cases were reproduced from unchanged HEAD in a temporary checkout:

- Daily-driver first-run guide completion fixture failed.
- Settings search/navigation fixture failed (the failing step varies).
- System-plan manifest package categorization failed.
- Projector UI fixture could not load the missing `ProjectorNative.qml`.

These existing issues remain outside this panel change; the full required suite
is not green. Local logs are in `state/hyprshell/panel-acceptance/full-tests.log`.
Current real-window, scaling and Show Desktop evidence supersedes the earlier
pending statements for those checks; see [real-session checks](panel-coexistence.md#real-session-and-show-desktop-2026-10-17).
Physical external-display, native tray-input and fresh-VM acceptance still remain.


## Desktop sign-off (2026-10-17)

The connected external-display continuation passed; see
[external acceptance](panel-coexistence.md#external-display-and-plan-closure-2026-10-17).
The user requested plan closure and a local commit after that check, accepting
the remaining validation limits. The four reproduced baseline suite issues above,
fresh-VM install/update/recovery, native tray-input and physical cable-cycle checks
are deferred follow-up, rather than blockers for this desktop plan. All eight
implementation phases are signed off under that scope; no full-suite or fresh-OS
pass is claimed.
