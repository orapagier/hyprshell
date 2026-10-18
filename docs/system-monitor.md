# Desktop system monitor

The click-through system dashboard appears at the upper right of the first
Quickshell output, below application windows, without reserving screen space.
It uses Hyprpane's `WallpaperColors` and `AdaptiveColors` implementation:
wallpaper-region contrast, hue-preserving text and contrasting outlines on
textured backgrounds. No continuous visual animations or blur are added.

Toggle it for the current shell session:

```sh
quickshell -p ~/.config/quickshell ipc call bar toggleSystemMonitor
```

The monitor starts visible after a shell restart. Hiding stops its collector.
No independent service or package is installed. The existing wallpaper watcher
and native network, Bluetooth and UPower services are reused.

One Python standard-library process reads kernel counters every three seconds.
Storage usage and CPU temperatures refresh every 30 seconds. Hardware identity
is collected once at startup. Network totals/rates cover physical links visible
in the collector's network namespace; virtual links are excluded to avoid
double counting. Disk throughput sums physical whole-device counters, excluding
partitions and virtual mappings. Tasks means kernel scheduling tasks (threads),
not a process count. CPU frequency is an average of available cpufreq policies;
CPU temperature is the hottest available package sensor. Missing sensors show
Unavailable. GPU identity/driver is shown; privileged Intel GPU profiling,
SMART probing, package scans and process scans are deliberately not polled.

OS age is explicitly an **estimate from root filesystem creation** (`stat %W /`).
Reinstalls, snapshots and restored filesystems can make this differ from actual
installation. No birth timestamp means Unknown, rather than a fabricated date.
Root and home can show the same capacity on a shared filesystem.

Checks: `python3 -m unittest discover -s tests -p test_system_monitor.py`.
The native check loads both monitor components and renders the view at desktop
and small-screen heights without changing the active desktop.
