# Installation, profiles and reviewed updates

Hyprshell remains an installable desktop project. Fedora/Arch own OS updates;
Hyprshell owns the shell and its user configuration.

## Operations

| Command or control | Effect |
| --- | --- |
| `./setup.sh` | Install/upgrade system dependencies and integration; deploy desktop files; preserve existing user preferences |
| `./setup.sh --config-only` | Deploy desktop files and compile the helper; validate saved JSON/Python/Lua; no package or service changes |
| `./setup.sh --update` | As above, with compatibility, staged Hyprland and offscreen Qt checks |
| `./setup.sh --config-only --profile personal` | Explicitly restore the saved personal profile over current preferences |
| Settings → Sync to GitHub | Save the live portable profile and shared code changes; commit and push to your authenticated account |
| Settings → Sync from GitHub | Fetch, review, validate and apply an incoming update to this checkout and the installed desktop |

Fresh installations use the public preferences in `config/hyprshell/` and the
schema defaults in `config/quickshell/settings/defaults.json`. Saved personal
preferences live under `profiles/personal/config/`. They are opt-in, including
saved display settings; review them before restoring onto different hardware.
The public monitor fallback uses preferred mode and automatic positioning/scaling.

Existing settings, user Lua sections, the optional GUI Lua overrides, terminal
preferences, shortcuts, display, theme, application, cleanup and regional
preferences survive ordinary updates. Optional preferences absent from the
public payload survive too. Current JSON schemas fill in newly introduced
optional defaults and reject unsupported versions; the updater blocks a schema
change without a supported migration. It never resets malformed settings.

## Preview and apply

The GitHub icons in the Settings header distinguish the two directions. The
right-hand **Sync from GitHub** button opens a preview. It fetches the branch
configured as the current branch's upstream (or `origin` with the current branch
name when no upstream is configured). The exact GitHub URL and branch are shown.
Public HTTPS repositories do not require authentication; private repositories
need Git credentials. Authentication remains available in Sync to GitHub.

The preview shows:

- incoming commit subjects, changed files and optional `CHANGELOG.md`;
- added/removed package requirements and missing installed packages;
- Fedora/Arch release, architecture, Hyprland, Quickshell and UWSM versions;
- detected graphics vendors, known limitations and the release acceptance record;
- local code conflicts and whether a history-preserving merge is needed.

Minimum versions are installation requirements, not a promise that all newer
versions work. Versions outside the recorded baseline get a warning. Hardware
behavior is never declared certified from version/vendor detection alone.
The user acknowledges these limitations before **Sync now** becomes available.
Unsupported systems, missing dependencies, incompatible schemas and code conflicts
block the update. System package upgrades and root-owned boot/login changes are
separate from this user-level update.

Preview reads candidate data without running its Python, Lua or QML. At apply,
the backend verifies the preview token, checkout, tracking source and live file
fingerprints. Previews expire after one hour. It installs the exact reviewed
revision, even if GitHub changes later; use Check again to review newer changes.
A clean merge is computed in Git objects for users with local commits, then
recorded as a merge commit at apply. Conflicts require manual resolution. No
history is squashed, rewritten or force-pushed.

The approved candidate is extracted to an isolated directory. Preferences are
validated and generated Lua is rebuilt; the audio helper is compiled; Python,
Lua, Hyprland and Qt checks run before live file replacement. Candidate code is
executed during this approved validation, so use a repository you trust.
Installation uses a tracked file manifest and backups. Unmanaged files are
retained. Locally modified shared files that conflict with the candidate stop
installation instead of being silently replaced.

The worker runs separately from Quickshell so replacing QML does not kill the
update. After a UI reload, open Sync from GitHub → Update status. Log out and back
in after completion to activate the whole session. An interrupted worker is
reported as interrupted, not successful.

## Forks and update sources

Sync to GitHub keeps `origin` unchanged and pushes explicitly to your account.
A clone of the project therefore continues receiving project updates even after
you save a profile to your own fork. If you cloned your fork, its tracking branch
is the default update source. To follow project updates instead, explicitly set
an upstream remote and the tracking branch, then verify the URL in the preview:

```bash
git remote add upstream https://github.com/orapagier/hyprshell.git
git fetch upstream
git branch --set-upstream-to=upstream/main main
```

If `upstream` already exists, inspect it with `git remote -v` instead of adding it
again. Use the branch names appropriate to your checkout. Unrelated histories
cannot be automatically combined.

## Recovery

Local records are under `${XDG_STATE_HOME:-$HOME/.local/state}/hyprshell/`:
`deployed.json`, `installed-release.json`, `update-preview.json`,
`update-status.json`, `update-worker.log` and `last-deployment.json`.
These are excluded from GitHub profile sync. They contain no credentials or
notification/clipboard history.

Changed files are saved in `backups/update-<timestamp>-<id>/`, with a transaction
journal. Ordinary write/validation failures retain or restore the previous
files. A machine crash/power loss is not an atomic filesystem transaction; use
the journal to inspect an interrupted update. Rollback restores the desktop
files and ownership manifest, not system RPMs or Git history:

```bash
python3 tools/install_configs.py "$PWD" --rollback /absolute/path/to/the/update-backup
```

Rollback refuses to overwrite files edited after the update. Resolve those files
manually using the saved copies. Keep the checkout at the new revision or choose
an appropriate recovery branch yourself; rollback does not reset commits.
Preferences changed by external application integration on an explicit profile
restore use those helpers' own backups. Normal updates do not reapply MIME
associations or regional settings.

## Release discipline

`compatibility.json` is the version/support record. Keep its acceptance text
honest: implemented features, automated test results, VM login and physical
hardware checks are different evidence. Tag releases only after the checklist
in [acceptance.md](acceptance.md) is complete for the advertised target. Keep
release notes in `CHANGELOG.md`; don't advertise a release tag that has not been
created. Current work is a development candidate, not a certified release.
