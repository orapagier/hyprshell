# Hyprmonitor

A standalone Linux system monitor written in Rust. The application owns its
collector, renderer, settings UI, configuration, process lifecycle and local IPC.
It does not use a Quickshell controller, QML window, Python collector or Lua UI.
Hyprshell can install and launch it, but is not required to run it.

## Task-manager window

The window workspace has been rewritten around the official
[TMOG summary and process screenshots](https://tmog.org/) (reviewed October 28,
2026), with a compact Windows Task Manager style process table. It is a separate
renderer from the optional legacy desktop overlay, not that dashboard inside a
window. Nine destinations expose Summary, Processes, CPU, Memory, Disks, Network,
GPU & thermals, Power, and System info.

Summary uses colored instrumentation panels, live resource histories and CPU
leaders. Dedicated resource pages combine history with scrollable hardware
readings. CPU also shows logical-processor mini graphs (up to two rows, with all
processors listed in the readings below). Disk throughput, GPU utilization and
battery power now have bounded histories as well as CPU, memory and network.
Unavailable samples break graph lines. GPU/power readings refresh at the configured
sensor interval; other counters use the main update interval.

Processes is a compact, aligned table with name, PID, CPU, resident memory,
threads and disk read/write rates. Click the column headers to sort or reverse;
click the search field to filter by name/PID. Click a row to inspect its parent
and kernel state. Arrow keys, Page Up/Down, Home and End navigate processes;
scrolling explores the table. Pause/Resume is available on every page; Space also
freezes/resumes the displayed snapshot while collection continues. Hiding still
suspends collection. Escape clears an active search, cancels an End task prompt,
closes settings, or otherwise closes the app.

End task requires a selected row and a second confirmation click. It sends
SIGTERM without requesting elevated permissions, reports errors in the UI, and
protects PID 1 and the monitor itself. A Linux pidfd is opened before checking
`/proc/PID/stat` creation time, so PID recycling cannot retarget an action. The
app never falls back to signalling a bare PID. SIGTERM requests termination; a
process may handle or ignore it. There is no automatic escalation to SIGKILL.

CPU uses 100% per logical CPU for processes and 0–100% system-wide. RSS includes
shared memory. First samples and inaccessible counters show an em dash. Process
updates use the existing configurable interval (six seconds by default). Sensor
availability and process visibility depend on permissions and the host system.

This is a TMOG-inspired Linux task manager, not TMOG or full feature parity.
Startup/service management, connection ownership, trace replay and benchmarks
are not part of the window UI. The existing collection-only CLI benchmark remains.
All original hardware readings and the optional overlay remain available.

## Desktop support

- `auto` mode first tries the native Wayland `wlr-layer-shell` overlay. When the
  compositor does not expose that protocol, it opens a normal window instead.
- `overlay` requires a compositor supporting `wlr-layer-shell`, such as Hyprland
  or Sway. It places the widget beneath application windows, reserves no desktop
  space and uses premultiplied alpha for translucent cards.
- `window` uses winit and softbuffer for an ordinary Linux Wayland or X11 window,
  suitable for desktops without layer-shell. It uses native window management
  for moving, resizing and minimizing, plus the dedicated task-manager workspace and native settings UI.

"Any desktop" here means an intended Linux Wayland/X11 fallback, not Windows or
macOS support: the collector reads Linux `/proc`, sysfs and optional system D-Bus
services. These desktop modes still require live validation after the build.
Actual background blur is compositor-dependent. The overlay can use Hyprland's
blur rule. The task-manager window uses an opaque instrument workspace; opacity and desktop
geometry remain overlay settings. Text size, accent, histories and sampling
intervals also apply to the window.

## Right-click settings

Right-click anywhere inside the monitor to open its own settings menu. Left-click
an entry to change it. For numerical settings use the minus/value area to decrease
and the plus area to increase. Scroll to reach additional entries; right-click
again or choose Close settings to dismiss it. Escape also closes it in window mode.

The menu provides:

- Independent switches for all seven detailed sections and for history graphs.
- Background opacity while retaining opaque text, text size and accent colors.
- Data, process and sensor update intervals and bounded history length.
- Auto/overlay/window selection, applied after restarting.
- Show/hide on all workspaces, reset size/position, and quit.

Settings save atomically to `$XDG_CONFIG_HOME/hyprmonitor/config.toml`, normally
`~/.config/hyprmonitor/config.toml`. A custom `--config` path remains the save
location. Saving validation failures preserves the previous file and displays
an error. At least one section must remain visible. CLI `--settings` can reopen
settings on a running hidden monitor.

If its own configuration does not exist, the app reads the legacy
`hyprshell/settings.json` monitor section once at load time, importing saved
visibility, workspace choices, transparency and geometry. The next native save
persists those values in the application's own file; it does not write back to
Hyprshell. Existing `workspaces = [...]` configuration remains accepted as an
optional filter.

## Displayed information

The Rust dashboard restores the original seven detailed sections and retains
bounded CPU/RAM/network history:

| Section | Readings |
| --- | --- |
| System | OS, machine model, kernel, estimated OS age from filesystem birth time, uptime, output resolution/refresh/scaling |
| Processor | CPU model, physical/logical topology, usage, frequency, load/tasks, package temperature, throttle counters, every logical CPU percentage, five top CPU processes |
| Graphics & cooling | GPU model/driver, exposed utilization/memory/temperature/clock, every readable hwmon temperature and fan |
| Memory | Used/total/percentage, available memory, cache, swap used/total, kernel stall pressure, five top resident-memory processes |
| Storage | Root/home usage and available space, drive temperatures, optional SMART status, disk throughput/activity |
| Network | Connection and Wi-Fi strength, physical traffic/totals, Bluetooth state, each interface's addresses/state/rates/link information |
| Power | Every exposed battery's charge/state/time/draw/health/cycles, energy now, full/design capacity with matching units |

Unavailable counters remain unavailable. Process RSS includes shared pages and
is not additive private RAM. Process CPU uses 100% per logical CPU; total CPU is
0–100%. The maximum thermal counter avoids summing mirrored siblings. Battery
zero-cycle counters are labeled as reported, not independently verified.

NetworkManager and BlueZ are queried directly through Rust D-Bus bindings; they
are optional services, not desktop requirements. Slow/unavailable service queries
have a bounded caller wait and at most one outstanding query worker. Interface
addresses use the OS network interface API. Optional `iw` and standby-aware
read-only `smartctl` queries run without a shell and have deadlines. They perform
no scans, Internet queries, self-tests, privilege requests or package installation.
Missing utilities and inaccessible devices are reported rather than fabricated.

## Resource behavior

Data collection runs off the UI thread. Static backgrounds and font glyphs are
cached; histories are bounded. A latest-snapshot slot coalesces updates so the
UI cannot accumulate a backlog of metric frames. There is no animation loop,
wallpaper pixel scanning, web view or GPU renderer. Hidden collection blocks
on a control channel; the window backend also pauses collection when notified
that the window is occluded. The settings menu is drawn only in response to
input or incoming readings.

## Build after review

Rust 1.86 or newer and Cargo are required. New windowing and native D-Bus
capabilities add dependencies that were not in the previous fetch. Fetching
updates the lockfile; it is separate from compilation.

```sh
cd ~/repos/hyprshell/apps/hyprmonitor-rs
cargo fetch
cargo fmt --check
cargo test
cargo clippy --all-targets -- -D warnings
cargo build --release --locked
./target/release/hyprmonitor --preview /tmp/hyprmonitor.png
./target/release/hyprmonitor
```

To install independently of Hyprshell:

```sh
cargo install --path . --locked
hyprmonitor --window
```

Hyprshell's installer instead puts the native executable directly in
`~/.local/bin/hyprmonitor`. There is no shell controller or launcher wrapper.

```sh
hyprmonitor --overlay
hyprmonitor --settings
hyprmonitor --show
hyprmonitor --hide
hyprmonitor --toggle
hyprmonitor --quit
hyprmonitor --once
hyprmonitor --watch
hyprmonitor --benchmark 60
hyprmonitor --benchmark-collector 60
```

## Optional desktop integration

Hyprland's Alt+I binding calls `hyprmonitor --toggle-workspace` directly; the app
queries its native IPC and owns its saved workspace overrides. Other desktops
can bind `hyprmonitor --toggle` or `hyprmonitor --settings` through their shortcut
settings. The app does not claim automatic global shortcut registration on every
Wayland compositor. Global shortcuts and blur are desktop policy, not features
that the Rust language makes universally available.

The Hyprshell source migration removes the old monitor-specific settings card,
QML renderer, Python collector and Quickshell IPC controller. Other Quickshell
panels, menus and settings remain separate and unchanged in purpose. The standalone binary is deployed independently of the Quickshell configuration.

## Comparison and validation

[Conky](https://github.com/brndnmtthws/conky) provides a much broader object/script
and platform ecosystem. This implementation takes its desktop presentation,
meters/history and configurable updates, and retains those features in the optional overlay. The window workspace is a
separate task-manager design.
It does not claim Conky feature parity or better performance without a measured
comparison using equivalent metrics and intervals.

Native tests cover accounting, counter resets, process parsing and I/O availability,
search/sort behavior, grouped section preservation, settings, bounded history,
and all window pages at minimum/default sizes with empty and populated samples.
Live Wayland/X11 interaction and scaling still require desktop-session validation.
