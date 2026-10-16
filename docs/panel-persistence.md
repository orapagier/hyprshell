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
the limited dock/taskbar virtual-output geometry matrix were subsequently verified
on 2026-10-17; see [panel coexistence](panel-coexistence.md#live-geometry-increment-2026-10-17).
A clean Fedora VM install and system-level
update/recovery acceptance also remain separate, as described in
[acceptance](acceptance.md). Show Desktop remains pending under
[panel coexistence](panel-coexistence.md). Phases 7 and 8 remain open.
