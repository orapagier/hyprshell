---
name: hyprskill
description: Diagnose, customize, or maintain this user's Linux machine and desktop, including requests about my system, laptop, display, shortcuts, hyprbar (the top bar), bar, menus, notifications, wallpaper, audio, Wi-Fi, Bluetooth, locking, or desktop settings. Knows the local Hyprshell setup without the user naming it. Excludes unrelated application or repository work.
---

# Hyprskill

This machine currently uses Fedora 44, Hyprland **Lua** configuration, and Hyprshell's native Qt 6 Quickshell desktop. Do not assume hyprland.conf, Waybar, Rofi, or a separate notification daemon.

The user calls Hyprshell's top bar **hyprbar**. Treat “hyprbar”, “top bar”,
“topbar”, and “bar” as the same desktop component.

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
