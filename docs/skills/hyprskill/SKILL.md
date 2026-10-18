---
name: hyprskill
description: Diagnose, customize, or maintain this user's Linux machine and desktop, including requests about my system, laptop, display, shortcuts, Hyprpane (the status panel), Hyprdock, Hyprbar (the planned taskbar), bar, menus, notifications, wallpaper, audio, Wi-Fi, Bluetooth, locking, or desktop settings. Knows the local Hyprshell setup without the user naming it. Excludes unrelated application or repository work.
---

# Hyprskill

This machine currently uses Fedora 44, Hyprland **Lua** configuration, and Hyprshell's native Qt 6 Quickshell desktop. The entry point is `hypr/hyprland.lua`; Quickshell owns the bar, launcher, menus, and notifications.

**Hyprpane** is the existing status/menu panel on any edge, formerly called
hyprbar. **Hyprdock** is the app dock; **Hyprbar** is the
classic window taskbar. Legacy `bar` settings, `Bar.qml`, IPC and Alt+T still
target Hyprpane. Interpret older “top bar”/“topbar” references as Hyprpane;
use context to distinguish historical hyprbar from the new taskbar.

## Mandatory automatic checkpoints and rollback

For **every task that changes this machine or Hyprshell**, create and verify a
recoverable checkpoint **before the first mutation**, without waiting for the
user to request a backup or asking permission for routine local backups. This
applies to all agents using this skill, including delegated agents. Read-only
investigations need no checkpoint. Successful Git commits do not replace backups:
Git misses live files, untracked files, pre-existing edits, and runtime state.

- Read [Checkpoint and rollback procedure](references/rollback.md) before making
  changes. Use the bundled `scripts/checkpoint.py` for ordinary files. Capture
  each affected checkout and installed file independently, including planned new
  paths, generated outputs, and any files changed indirectly by a command.
- Record the task, baseline Git status/diffs, checkpoint location, validation
  plan, and exact recovery commands in the checkpoint directory. For service,
  package, database, privileged, or runtime changes, also capture the relevant
  prior state and use a suitable native backup/recovery method. A file checkpoint
  is not a whole-system snapshot. If a required recovery point cannot be created
  and verified, stop the dependent mutation and explain the concrete limitation.
- Expand the checkpoint before touching newly discovered paths. Keep the original
  pre-task baseline; never overwrite it with a later or already broken version.
  Coordinate ownership when delegating so agents do not back up or restore over
  one another's edits.
- Record the resulting file state immediately after each owned edit batch, before
  validation or reload. Validate before activation, then check affected live
  behavior. If the change fails, restore only this task's changes and validate
  recovery; do not leave the machine in a known broken state. Stop repeated
  activation attempts once recovery is needed. If restoration conflicts with
  newer work, preserve both versions and reconcile only your own changes.
- Keep checkpoints after success and failure, outside the checkout and ordinary
  cleanup targets. Do not prune them automatically. In the final response give
  the checkpoint location, copy changes, checks, and a usable rollback command;
  report partial recovery or checks that could not run precisely. Routine recovery
  of your own failed change is part of the task; destructive or unrelated actions
  still require their existing authorization.

These are standing instructions for agents that load Hyprskill, not a filesystem
hook or a guarantee that an agent bypassing the skill will make backups.

## Mandatory task scope and feature preservation

These rules apply to every agent using Hyprskill, including Codex, Claude Code,
OpenCode, and any delegated agents. Include these constraints and the exact task
scope in delegated work; the coordinating agent must review the combined changes.

- Before editing, identify the requested outcome and the files, code blocks, and
  settings needed to achieve it. Inspect existing diffs and relevant live/repo
  differences so pre-existing work and preferences remain intact.
- Modify only files and lines directly necessary for the requested task. A
  task-related file does not authorize changing unrelated code within it. Read
  dependencies as needed, but do not perform incidental cleanup, refactoring,
  formatting, renaming, dependency upgrades, or fixes outside the task.
- Preserve every unrelated feature and its behavior, UI controls, defaults,
  shortcuts, settings, and wiring. Never remove, hide, disable, simplify away, or
  replace an existing feature merely because it seems unused, redundant, broken,
  or inconvenient for the implementation. Remove or change it only when the user
  requested that change or explicitly authorized the necessary tradeoff.
- Use focused patches. Do not replace whole files or deploy entire config trees
  for a small change. Reconcile live/repo differences and apply only the relevant
  edits to each copy; never overwrite unrelated live customizations with a repo
  copy or unrelated repo work with a live copy. Generated files must retain
  unrelated settings and behavior.
- Necessary integration changes are in scope only when they support the requested
  outcome and preserve unrelated behavior. If completion requires changing an
  unrelated feature or discarding existing work, explain the concrete conflict
  and obtain explicit authorization before that change. Record unrelated issues
  without fixing them as part of this task.
- Before deployment and again before committing or reporting completion, review
  the full task diff, including deletions and newly created files, against the
  baseline. Every changed block must have a task-specific reason. Undo only your
  own accidental unrelated edits; never reset or restore over pre-existing work.
  Run focused checks for the requested behavior and any adjacent feature affected
  by shared code. Passing checks do not replace the scope and preservation review.

Resolve paths independently of the working directory:
- Config root: `${XDG_CONFIG_HOME:-$HOME/.config}`.
- State root: `${XDG_STATE_HOME:-$HOME/.local/state}`.
- Checkout: read `<state>/hyprshell/repository`; verify it contains `setup.sh` and `config/quickshell/shell.qml`. Fallback: `$HOME/repos/hyprshell`. If neither exists, ask for its location rather than searching the entire home directory.

For a machine request, start with the relevant installed config and focused runtime evidence. For a project implementation, inspect the checkout and `git status --short`. Installed configs are **copies**, not symlinks: compare the relevant live and repo files before editing. A desktop change should normally be preserved in the checkout and applied to the matching live file when authorized by the request; reconcile differing edits rather than overwriting either copy. State which copies changed.

The user's standing preference is to preserve desktop and machine setup in
Hyprshell. One canonical payload in `config/` includes the user’s personal taste.
Fresh setup restores it; ordinary updates preserve existing preferences. Extra
wallpapers are ignored; only `assets/wallpapers/default.jpg` is tracked.
For future customizations, update the repository payload and installer
as needed, then apply the matching live change. Keep hardware-specific settings
adaptable and credentials outside the repository. Do not promise identical
hardware behavior on a different laptop.

The user authorizes local Git commits after each successfully completed Hyprshell
agent task. Commit only when the requested outcome is achieved, required checks
pass, and no required implementation, validation, or follow-up remains. Questions,
read-only investigations, unfinished work, blocked work, and tasks needing
follow-up do not trigger commits. Never create an empty commit.

Use a meaningful subject describing the result; add a body explaining the reason,
behavior, and relevant validation when useful. Stage only task-related changes,
preserve unrelated edits and existing staged work, apply matching authorized live
changes before committing, and report the local commit. If committing fails,
retain the changes and report the failure. Manual desktop edits remain live and
uncommitted until the user chooses Sync to GitHub; there is no background saver.

Settings → Sync to GitHub captures the live configuration, commits it locally,
then pushes. Push completed agent commits with their original subjects and bodies
intact; do not amend, squash, replace, or recommit them under a generic sync
message. Create a new sync commit only for remaining uncommitted edits. A failed push
retains the local commit for retry. Do not push without explicit authorization.
Sync from GitHub previews conflicting files and lets the user choose Keep local
or Use GitHub before updating. Retained unsynced edits remain uncommitted;
merging already committed branch histories may create an update merge commit.

Read only the reference needed:
- [Desktop map](references/desktop.md): ownership, exact paths, settings workflow, checks, logs, and reloads.
- [Machine facts](references/machine.md): this laptop's observed hardware and personal configuration; read for hardware or machine-specific questions.

Use targeted reads and bounded logs; do not inventory packages or read the entire README on every request. Verify changing facts only when relevant. Session socket/D-Bus access failures in an agent sandbox do not establish that the desktop or services are broken. Report inaccessible checks precisely; do not guess socket paths or bypass sandbox restrictions.

Do not run the full installer for a small edit: it upgrades packages and config-only deploys owned files and preserves preferences. Validate the affected component before reloading. Pushing, cleanup deletion, and ending the session require task authorization; local commits are authorized only at the successful task boundary described above or by an explicit commit/Sync to GitHub request. Keep credentials, notification contents, and unrelated personal files out of repository documentation. Update these references when a verified setup change makes them stale.
