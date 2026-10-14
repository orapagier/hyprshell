# Installation and reviewed updates

Hyprshell remains an installable desktop project. Fedora/Arch own OS updates;
Hyprshell owns the shell and its user configuration.

## Operations

| Command or control | Effect |
| --- | --- |
| `./setup.sh` | Install/upgrade system dependencies and integration; deploy desktop files; preserve existing user preferences |
| `./setup.sh --config-only` | Check platform/runtime compatibility, deploy desktop files and compile the helper; validate saved JSON/Python/Lua; no package or service changes |
| `./setup.sh --update` | As above, with compatibility, staged Hyprland and offscreen Qt checks |
| Settings → Sync to GitHub | Capture the live desktop, commit locally, then push to your authenticated account |
| Settings → Sync from GitHub | Fetch updates from the developer’s `orapagier/hyprshell` repository, review, validate and apply to this checkout and the installed desktop |

Fresh installations use the single configuration in `config/`, including the
author's personal preferences.
The monitor fallback uses preferred mode and automatic positioning/scaling;
confirmed display choices still depend on the available hardware.

Manual desktop changes remain live and uncommitted until **Sync to GitHub**.
Agents commit only successfully completed and validated tasks locally, with
meaningful descriptions. Questions and tasks needing follow-up do not trigger
commits. Publishing preserves existing commit subjects and bodies. The button
reconciles live and checkout edits, validates, commits locally, then pushes. No
background timer commits changes. Failed publishing retains the local commit.
Only `assets/wallpapers/default.jpg` is tracked and installed; other wallpapers
remain local. Configure a Git commit identity on fresh clones.

**Sync from GitHub** previews without changing the desktop, checkout or committed
history. Conflicts display both full-file versions and a diff (minus for local,
plus for developer). Select **Keep your local version** or **Use developer’s
version** with the checkboxes for every conflict, then **Review choices**. Only
one version per file can be selected. The rebuilt review is
bound to the same GitHub revision and your current files; later edits invalidate
it. Review compatibility, acknowledge the limitations and choose **Sync now**.
Choices apply to entire files, including deletion. Validation and backups still
run before deployment. Local edits retained in an update remain uncommitted.
Already committed branch histories can produce a merge commit independently of
unsynced edits; existing commits are never rewritten.

Existing settings, user Lua sections, the optional GUI Lua overrides, terminal
preferences, shortcuts, display, theme, application, cleanup and regional
preferences survive ordinary updates. Optional preferences absent from the
repository payload survive too. Current JSON schemas fill in newly introduced
optional defaults and reject unsupported versions; the updater blocks a schema
change without a supported migration. It never resets malformed settings.

## Preview and apply

The GitHub icons in the Settings header distinguish the two directions. The
right-hand **Sync from GitHub** button opens a preview. It checks the developer’s
`https://github.com/orapagier/hyprshell.git` repository on `main` for commits not
yet included in the local checkout. The window explicitly identifies the
developer source and branch. Fetching uses that URL directly, regardless of the
checkout's origin or tracking branch, and does not change either. The public
update repository needs no authentication. Authentication for publishing remains
available in Sync to GitHub.

The preview shows:

- incoming commit subjects, changed files and optional `CHANGELOG.md`;
- added/removed package requirements and missing installed packages;
- Fedora/Arch release, architecture, Hyprland, Quickshell, host Qt 6 base package and UWSM versions;
- detected graphics vendors, known limitations and the release acceptance record;
- local code conflicts and whether a history-preserving merge is needed.

Minimum versions are installation requirements, not a promise that all newer
versions work. Versions outside the recorded baseline get a warning. Hardware
behavior is never declared certified from version/vendor detection alone.
The user acknowledges these limitations before **Sync now** becomes available.
Unsupported systems, missing dependencies, incompatible schemas and unresolved conflicts
prevent applying until you choose a version. System package upgrades and root-owned boot/login changes are
separate from this user-level update.

When required packages are missing, the preview lists them and shows a copyable
installation command. After resolving file conflicts and other review issues,
select the separate package-installation consent and choose **Install in terminal**.
Hyprshell opens Kitty with `sudo dnf install …` on Fedora or
`sudo pacman -Syu --needed …` on Arch. Arch consent explicitly includes a full
system upgrade, avoiding partial upgrades. Normal authentication and package-manager
confirmation remain interactive; the terminal shows the complete transaction,
including transitive dependencies and any additional changes. No automatic yes
flag is used and no repositories are enabled by this action.

Opening the terminal does not mean installation succeeded and never applies the
desktop update. Finish or cancel the transaction, then choose **Check again**.
The old preview becomes unusable after launching installation; the new preview
checks current packages and runtime versions before offering **Sync now**.
If installation fails, is cancelled or the enabled repositories cannot supply a
package, the missing requirements remain visible and the desktop update stays
blocked. If Kitty is unavailable, run the displayed command manually and recheck.

Preview reads candidate data without running its Python, Lua or QML. At apply,
the backend verifies the preview token, checkout, developer source and live file
fingerprints. Previews expire after one hour. It installs the exact reviewed
revision, even if GitHub changes later; use Check again to review newer changes.
A clean merge is computed in Git objects for users with local commits, then
recorded as a merge commit at apply. Conflict choices are reviewed in Settings before continuing. No
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
Sync from GitHub always reviews the developer’s `orapagier/hyprshell` `main`
branch, including when you cloned your fork or track a personal branch. No
upstream remote or tracking-branch change is needed. Your fork and publishing
destination stay as configured. Unrelated histories cannot be automatically
combined.

## Recovery

Local records are under `${XDG_STATE_HOME:-$HOME/.local/state}/hyprshell/`:
`deployed.json`, `installed-release.json`, `update-preview.json`,
`update-status.json`, `update-worker.log` and `last-deployment.json`.
These are excluded from GitHub sync. They contain no credentials or
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
Preferences changed by external application integration on first installation use those helpers' own backups. Normal updates do not reapply MIME
associations or regional settings.

## Rolling support policy

Hyprshell has one rolling channel, `main`, for both distributions. Development
should use branches and pull requests, merging only after the required checks
pass. Repository owners must configure GitHub branch rules to enforce this;
the local workflow alone does not prevent a direct push of failing code.
There are no separate Fedora and Arch editions or maintained numbered branches.

`compatibility.json` is the support record. Fedora support covers explicitly
listed traditional DNF-based releases (currently 44); Atomic/OSTree remains
unsupported. Arch targets a fully updated rolling system, not an installation
ISO version. New Fedora releases require validation before adding support.

`minimum` lists dependency minimums; `required_major.qt6` requires Qt 6 without
inventing an untested minor-version floor. `incompatible` maps component names
to exact versions and reasons, for example `{"hyprland": {"0.57.1": "reason"}}`.
No versions are currently excluded. Unknown/missing or known incompatible
dependencies block deployment; newer unrecorded versions generate warnings.
The rolling manifest uses format 2 so older update checkers cannot silently
ignore the new Qt/exclusion rules. On an older installation, first bring the
checkout up to date while preserving local work, review it, then run
`./setup.sh --update` once to bootstrap the checker. Subsequent Settings updates
use the normal preview flow. The new checker still accepts format 1 manifests.
Per-platform `versions` are dependency evidence, not interchangeable Fedora/Arch
certification. An empty Arch version record deliberately preserves that distinction.
Qt detection records the distro's Qt base package, not a custom SDK or proof that
a custom Quickshell binary was built against that same Qt. Staged native checks
remain necessary for ABI and QML compatibility.

Automated Arch and Fedora checks run on pushes, pull requests, manual requests
and a daily schedule. Each distro job uploads dated JSON dependency evidence
including the tested commit and package versions. Consult the job result for
test success; a snapshot alone is not a passing test. CI never automatically
changes the published support record or declares physical hardware certified.

Keep acceptance text honest: dependency inspection, automated tests, VM login
and physical checks are different evidence. Use [acceptance.md](acceptance.md)
for fresh-install and hardware testing, and `CHANGELOG.md` for rolling changes.

### Reported platform issues

- **Arch — last reported working October 11, 2026:** the user's touchpad did
  not work with the kernel previously used; installing and booting an LTS kernel
  resolved it. Exact kernel/dependency versions and the tested Hyprshell commit
  were not captured. This is a machine-specific report, not a requirement to
  replace every Arch user's kernel. The installer preserves custom kernels.
- **Fedora 44 — Distrobox identity:** the user reports that an installed Ubuntu
  container environment still reports Fedora 44, making it appear that no
  container was entered. Reproduction and cause remain unverified. Verify
  identity inside the entered container separately from host installation
  detection. This rolling-policy change records the issue; it does not fix it.

### Installed build and recovery

Settings → Help & diagnostics shows the deployed rolling build's date and
commit, also included in diagnostic reports. `deployed.json` stores build
metadata alongside owned files. Reviewed updates record the developer's exact
upstream commit separately from any local merge commit and flag local changes.
Direct setup records the local checkout commit and dirty state; it does not
guess which developer commit a fork contains. Older installs show “build not
recorded” until deployed again.

Each changed-file backup includes the previous ownership manifest and build
record, so the rollback command above restores both. It does not downgrade
system packages, switch kernels or reset Git history. `installed-release.json`
is an update history record; `deployed.json` describes the currently restored
desktop. The date identifies the source commit, not the last hardware test.
