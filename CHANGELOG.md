# Changes

## Rolling — 2026-10-14

- Show missing update dependencies and an installation command; offer a separate
  confirmed terminal installation and require a new compatibility review afterward.
- Formalize one rolling channel for Arch and Fedora with per-platform evidence.
- Record the October 11 user-reported Arch test and LTS-kernel touchpad workaround;
  record the unresolved Fedora 44 Distrobox/container identity report.
- Track host Qt 6, support exact dependency exclusions, and share compatibility
  checks across full installation, config-only deployment and reviewed updates.
- Add daily CI checks and downloadable dependency snapshots for both platforms.
- Show deployed build identity in Help and diagnostics; preserve upstream identity
  separately from local commits and include build metadata in rollback backups.

## Development candidate — 2026-10-13

- Add GitHub icons and a Sync from GitHub button beside Sync to GitHub.
- Review incoming commits/files, dependencies, supported versions and graphics
  findings before confirming Sync now. Hardware behavior still needs testing.
- Preserve current preferences during updates; make saved personal profiles opt-in.
- Stage and validate desktop updates, detect local conflicts and retain recovery
  copies. Preserve local Git history when incoming changes merge cleanly.
- Record supported Fedora/desktop versions and add a fresh-install/hardware
  acceptance procedure. Real VM and physical acceptance remain pending.
