# Standalone Rust Hyprmonitor

The monitor now owns its UI and settings instead of using a Quickshell
controller. Its source is in `apps/hyprmonitor-rs`; see that project's README
for the detailed readings, configuration, desktop support and build instructions.

Right-click anywhere in the monitor to open its native Rust settings menu.
Configuration lives in `~/.config/hyprmonitor/config.toml`. Legacy Hyprshell
monitor preferences are imported when no standalone configuration exists.

The native executable is installed directly to `~/.local/bin/hyprmonitor`.
Hyprland startup launches it independently of Quickshell. Alt+I invokes
`hyprmonitor --toggle-workspace` directly. On other Linux desktops, configure a
shortcut for `hyprmonitor --toggle` or `hyprmonitor --settings` as desired.

The app selects a layer-shell overlay when available and otherwise uses a normal
Wayland/X11 window. Background blur is compositor-dependent; the portable RGB
window uses glass-styled cards on a dark background. NetworkManager and Bluetooth
metadata come from native Rust D-Bus calls, with no Qt service bridge.

The previous QML monitor renderer, Python collector, Quickshell controller and
monitor settings card are removed from the source payload. Legacy settings
validation remains for migration compatibility. Other Hyprshell settings and
panels are unaffected.

The standalone executable builds and passes all 16 native unit tests plus strict
Clippy checks. The monitor migration is installed locally: Alt+I now targets the
Rust executable in the on-disk shortcuts file. Run `hyprctl reload` from the
Hyprland terminal to activate the binding if it has not reloaded automatically.
The agent sandbox could not reach compositor IPC; interactive native backend and
settings behavior still need live verification. Other desktops use the normal
window fallback and their own shortcut configuration.
