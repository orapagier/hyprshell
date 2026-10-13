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
Hyprshell. Public setup initializes generic defaults and preserves existing
preferences; `setup.sh --profile personal` on a fresh supported laptop restores
the saved personal desktop. Personal snapshots live in `profiles/personal/`. For future customizations, update the repository payload and installer
as needed, then apply the matching live change. Keep hardware-specific settings
adaptable and credentials outside the repository. Do not promise identical
hardware behavior on a different laptop.

The user authorizes local Git commits as a standing preference. After each
completed, validated Hyprshell change, commit the task's repository changes
with a meaningful subject describing the result; add a body when the reason,
behavior, or validation needs explanation. Stage only task-related changes,
preserve unrelated work and staged files, and report the local commit. Include
documentation and installer changes when needed to restore the setup. Apply
matching live payload changes before committing so Settings sync does not
replace them with older installed copies. Do not create empty commits.

Settings → Sync to GitHub pushes existing local commits with their original
subjects and bodies. Keep that history intact: do not squash, amend, or replace
agent commits with a generic sync message. Its generic timestamped commit is
for remaining uncommitted manual edits captured by the live snapshot. Local
commit authorization does not authorize a push; let the user trigger Settings
sync unless they explicitly request a push. If committing fails, retain the
changes and report the failure instead of claiming completion.

Read only the reference needed:
- [Desktop map](references/desktop.md): ownership, exact paths, settings workflow, checks, logs, and reloads.
- [Machine facts](references/machine.md): this laptop's observed hardware and personal configuration; read for hardware or machine-specific questions.

Use targeted reads and bounded logs; do not inventory packages or read the entire README on every request. Verify changing facts only when relevant. Session socket/D-Bus access failures in an agent sandbox do not establish that the desktop or services are broken. Report inaccessible checks precisely; do not guess socket paths or bypass sandbox restrictions.

Do not run the full installer for a small edit: it upgrades packages and config-only deploys owned files and preserves preferences; explicit profile restoration replaces saved preferences. Validate the affected component before reloading. Pushing, cleanup deletion, and ending the session require task authorization; local commits are authorized by the standing preference above. Keep credentials, notification contents, and unrelated personal files out of repository documentation. Update these references when a verified setup change makes them stale.
