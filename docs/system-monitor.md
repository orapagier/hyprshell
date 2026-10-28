# Hyprmonitor task manager

Hyprmonitor is a standalone Rust application in `apps/hyprmonitor-rs`, installed
as `~/.local/bin/hyprmonitor`. Its window workspace was rewritten using the
[official TMOG screenshots](https://tmog.org/) as references, with a compact
Windows Task Manager style process table and nine resource destinations.

The new workspace includes colored resource graphs, logical CPU mini graphs,
sortable/searchable process columns, row selection, keyboard navigation,
Pause/Resume and identity-checked End task confirmation. All original system,
hardware, filesystem, network and power readings remain accessible. See the
[application README](../apps/hyprmonitor-rs/README.md) for sampling semantics,
controls, process-action safety and feature limits.

Alt+I retains `hyprmonitor --toggle-workspace`; other desktops can bind
`hyprmonitor --toggle`. Right-click or the Settings button opens native settings.
Preferences remain in `~/.config/hyprmonitor/config.toml`. Window mode uses the
new workspace; explicit overlay mode retains the configurable desktop dashboard.
No Quickshell, settings payload or global shortcut changes are required.

Validation covers native unit tests, process identity rejection and termination
of a test-owned child, strict Clippy, release compilation, and rendered previews.
Desktop-session interaction cannot be verified from an isolated agent environment.
