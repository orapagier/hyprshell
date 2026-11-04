# Hyprshell optimization audit

Verified 2026-11-05 against checkout `d8088d4`. The resource measurements and
code review cover `01b360f` ("Reduce idle audio polling and wallpaper/icon
memory"); the later `d8088d4` only updates behavior/settings preferences. This
is a working reference for agents optimizing Hyprshell. Re-measure before acting: this
machine has one display, one user session, and results depend on media playback,
open drawers, Wi-Fi, and how long the shell has run.

## Scope and rules

This audit covers the native Quickshell desktop in `config/quickshell/`: its
process model, always-on and on-demand work, measured resource use, completed
optimizations, and open targets. It is not a dependency-advisory or security
audit. See the [October 26](audit-2026-10-26.md),
[October 27](audit-2026-10-27.md), and
[follow-up](audit-2026-10-27-followup.md) audits for reliability and security
work.

Optimization must not remove or downgrade features. Animations, shortcuts,
settings, panel geometry, menu behavior, notification actions, clipboard,
locking, wallpaper adaptation, spectrum rendering, and the retained layer
surfaces are part of the product. Prefer reducing wakeups, duplicate decoding,
and transient allocations over disabling behavior.

## Verified environment

| Item | Value |
| --- | --- |
| OS | Fedora Linux 44 |
| Compositor | Hyprland 0.56.2, Lua configuration |
| Shell | Quickshell 0.3.2 (Fedora COPR), Qt 6.11.2 |
| Display | single `eDP-1`, 1920x1080 @ 60 Hz |
| Checkout | `/home/ramlej/repos/hyprshell` |
| Live config | `/home/ramlej/.config/quickshell` (copies, not symlinks) |
| State root | `/home/ramlej/.local/state/hyprshell` |
| Clock tick | `CLK_TCK=100` (one CPU tick = 10 ms) |
| Profiling limits | `perf_event_paranoid=2`, no `strace`; `/proc` and `smaps_rollup` are available |

Live QML is hot-reloaded after copies change, but a clean process restart is
required for a fair measurement. Helpers started by a previous generation can
survive a reload; always check for orphaned children before measuring.

## Desktop process model

`shell.qml` is the root `ShellRoot`. It owns:

- `SettingsStore` preferences, `PanelVisibilityController`, `ApplicationService`.
- `Dashboard` and `Activity` drawer windows, projector/presentation/Hyprview.
- `SettingsController` (Settings window is lazily created).
- `ClipboardController`, `LockingController`, `PowerController`.
- `DesktopServices` (Hyprland, PipeWire, MPRIS, UPower, Networking, Bluetooth).
- `NotificationInbox`, `NotificationPopups`, `Tray`, `WallpaperWatcher`.
- One `Bar`/Hyprpane and one `Hyprdock` object per screen, plus `MenuController`
  and lazily loaded menu pages.
- IPC targets `performance` and `bar`, the root clock, and opt-in `FrameTiming`.

`DesktopServices.qml` keeps event-driven bindings for sinks, streams, MPRIS
players, battery, Wi-Fi, and Bluetooth. `MediaActivity.qml` derives playback
state; `AudioSpectrum.qml` starts the native capture helper only while media is
playing. `WallpaperWatcher.qml` owns the persistent wallpaper event helper and a
slow query fallback. Menu and Settings pages create their helpers on demand.

## Baselines

All values are the whole Quickshell process unless noted. PSS is the better
comparison because RSS counts shared libraries. CPU is percent of one core from
`utime + stime`. Helpers are separate processes and are not included.

| Scenario | RSS | PSS | Threads | FDs | CPU |
| --- | ---: | ---: | ---: | ---: | ---: |
| Pre-optimization, long session (~46 h) | 299.6 MB | 226.6 MB | 120 | 237 | 4.40% / 20 s |
| Pre-optimization, fresh restart | 274.7 MB | 204.2 MB | 120 | 233 | 4.45% / 20 s |
| Post-`01b360f`, fresh restart, media stopped | 251.9 MB | 181.3 MB | 45 | 75 | 0.250% / 60 s |
| Post-`01b360f`, media playing | 244.0 MB | 173.7 MB | 52 | 81 | ~0.8–1.2% / 30 s |
| Same process after ~22 h of normal use, media stopped | 370.7 MB | 284.4 MB | 121 | 230 | 0.067% / 30 s |

Reading these numbers:

- The fresh-restart optimization reduced idle CPU by roughly 18x and saved about
  23 MB RSS / 23 MB PSS.
- At the sub-percent level, one tick per 30 s is 0.033%, so short samples are
  dominated by quantization. Use 60–300 s and repeat three times.
- Earlier idle samples ranged from 0.25% to about 1.0% depending on background
  events. A one-off burst of roughly 2.36 s CPU was observed around the time the
  icon catalog first activated; it was not reproducible in a later 70 s sample,
  and the cause was not instrumented.
- The 22 h session has 76 extra threads and 155 extra FDs. This is fully
  consistent with the icon catalog: 75 `FileInfoThread`s and about 150
  inotify/eventfd descriptors. RSS/PSS growth is **not** explained by threads
  alone and still needs attribution (see open targets).
- An empty Quickshell instance measured earlier at about 110 MB RSS / 41 MB PSS,
  so most residual memory is the real desktop: surfaces, QML, services, and
  caches.

## Always-on processes

Observed persistent children and gated on-demand helpers at audit time
(PID 32205, about 22 h uptime). RSS is `ps` resident size; shared pages mean the
sum overstates unique memory. A dash means the process was not running in this
idle session, not that it is unused.

| Child | RSS | Gate | Purpose |
| --- | ---: | --- | --- |
| `helpers/wallpaper-events.py` | 12.9 MB | always | inotify bridge for awww cache/socket; prints `ready`/`change` |
| `pactl subscribe` | 5.4 MB | always | jack/output-port changes for `AudioRoute`; 5 s reconnect on exit |
| `systemd-inhibit … power.py --watch-lid` | 6.6 MB | `lidAction != system` | blocks lid handling and keeps the lid watcher alive |
| `power.py --watch-lid` | 17.6 MB | same | applies the saved lid action |
| `backend.py --idle` | 19.9 MB | locking or any idle timer enabled | dim/off/suspend/lock timers |
| `clipboard.py --watch` | — | clipboard history enabled | not running in this session |
| `helpers/audio-spectrum` | — | media playing | FFT capture; stops when playback stops |
| `helpers/dashboard-status.py --watch` | — | dashboard/dock dashboard open | 2 s counters; terminates on close |
| `helpers/hyprweather` | — | weather card requests | search/select/weather one-shots |
| `sqlite3` | — | notification load/save | one-shot history read/write |
| `curl` | — | Wi-Fi connection key present | 30 s internet-availability probe; not observed in a 35 s sample |

The persistent helper set totals about 62 MB RSS across five processes. Their
gates are user features; do not disable them to win a benchmark. Consolidating
or replacing them is a larger change with real failure modes.

## Timer and polling inventory

| Source | Cadence | Gate / notes |
| --- | --- | --- |
| Root clock (`ClockSchedule.js`) | next minute boundary | 1 s only if the Qt format contains unquoted `s`/`z` |
| `WallpaperWatcher.poll` | 30 s | 2 s when the event helper is unavailable; 4→30 s backoff after failed queries |
| `WallpaperWatcher` event helper | inotify | persistent; restart retry 30 s |
| `BatteryCapacityReader` | 60 s | reloads the battery `uevent` file |
| `WifiInternet` probe | 30 s | only with a non-empty Wi-Fi connection key |
| `AudioRoute` reconnect | 5 s | only after `pactl subscribe` exits |
| Keybindings guide | 1.5 s | only while the guide is loaded (popup open or dock section active); 5 s per-query timeout |
| Dashboard status helper | 2 s | only while the dashboard is open |
| Calendar clock | 1 s | only while the calendar menu is visible |
| Notification save | 150 ms debounce | 5 s retry after a failed save |
| Notification expiry | per notification | one-shot per visible notification |
| Bluetooth scan | 20 s timeout | only while scanning |
| Microphone test | 2 s stale / 5 s startup | only while the test runs |
| Display countdown | 1 s | only during a Settings display countdown |
| Media marquee | next character | only playing and title > 28 code points; 2 s opening pause, 300 ms steps |
| Spectrum capture | 5 coalesced frames/s | only while playing; hidden spectra stop binding/animating |
| `FrameTiming` | opt-in IPC | no observer runs normally |

`Validate.qml` and `Preview.qml` are test/preview entry points, not part of the
running shell. Settings pages add their own short-lived processes and timers
only while open.

## Event-driven paths

These are preferred over polling and should stay event-driven:

- Hyprland workspaces, monitors, toplevels, config reloads, and IPC dispatch.
- PipeWire nodes, links, defaults, and stream peak changes. The peak monitor is
  enabled only while a non-MPRIS output stream is linked; `PwObjectTracker` and
  `PwNodeLinkTracker` remain active so new audio is detected without polling.
- MPRIS play state and metadata.
- UPower battery and AC state.
- NetworkManager and BlueZ state.
- Wallpaper changes via the inotify helper, with queries as a correctness
  fallback.
- Notification server signals and DBus actions.
- Tray StatusNotifier items.

## Completed optimizations

| Date / commit | Change | Evidence |
| --- | --- | --- |
| 2026-10-26 | Media title scheduling switched from a 67 ms repeating timer to the next character boundary. | 89 → 13 timer firings in a 6 s synthetic comparison (about 85% fewer). |
| 2026-10-27 | Dashboard CPU sampling reads only the aggregate `/proc/stat` line; activity wallpaper uses a 96x64 buffer. | 44.6 → 18.6 µs per helper sample (isolated); 704,000 → 24,576 bytes per activity buffer (about 96.5% smaller). |
| 2026-10-27 follow-up | Notification batching, virtualized list, wallpaper event watcher and 30 s watchdog, `tools/measure_shell.py`. | 25 updates to 10,000 rows produced one history write; 10,000 rows instantiated 12 cards. |
| Spectrum work | Native helper coalesces speaker FFT frames to 5/s; QML applies frames directly; hidden spectra stop binding/animating. | Removes about 57.5 JSON parses/s during playback; capture stops when playback stops. |
| `01b360f` (2026-11-04) | Peak monitor gated on a linked non-MPRIS stream; wallpaper palette decode capped at 1024 px; icon catalog made lazy. | Idle 4.45% → 0.250% of one core; fresh RSS 274.7 → 251.9 MB, PSS 204.2 → 181.3 MB; threads 120 → 45, FDs 233 → 75. |

`docs/media-performance.md` is the user-facing summary of media scheduling.
Note that the 1024 px palette cap preserves Canvas output sizes and leaves the
800 px test fixture at full decode; it is a decode-working-copy reduction, not a
rendering change.

## Open optimization targets

Ranked by measured impact and risk. Treat all as hypotheses until reproduced.

### 1. Icon catalog fan-out — highest leverage

**Evidence.** The first call to `AppIcons.source()` that misses the theme lookup
activates 75 `FolderListModel` delegates: 5 data roots × (8 hicolor sizes +
`pixmaps`) plus 30 Pop/Adwaita directories. After that first miss the live
process has 75 `FileInfoThread`s and roughly 150 extra inotify/eventfd
descriptors for the rest of the session. At 22 h: 121 threads / 230 FDs versus
45 / 75 at a fresh start.

**Second issue.** Every delegate can call `icons.rebuild()` on `statusChanged`,
`countChanged`, and object creation. `rebuild()` scans every folder and every
entry. During the initial asynchronous load this can rebuild the whole catalog
many times. A ~2.36 s CPU burst was observed around the time the catalog
appeared; attribution is plausible but not instrumented.

**Options, least invasive first:**

1. Coalesce rebuilds with one short single-shot timer (for example 200–500 ms)
   instead of rebuilding per delegate signal. Keeps live icon updates and the
   existing model structure.
2. Build the catalog in one scan (a small helper or one `FolderListModel` pass),
   cache it, and re-scan only when `DesktopEntries.applications` changes.
3. Tear down the `Instantiator` once the catalog is stable and re-arm it on
   application/theme changes. This removes the 75 Threads/FDs but gives up
   continuous per-directory watching.

Preserve themed-icon priority, the generic `application-x-executable` fallback,
absolute paths, launcher and dock icons, and newly installed applications.
Measure first-miss CPU, steady threads/FDs, and launcher/dock behavior.
Relevant checks include `test_applications.py`, `test_application_support.py`,
the launcher tests (`test_launcher.py`, `test_launcher_popup.py`,
`test_launcher_routing.py`), and the launcher QML tests.

### 2. Long-session residual memory growth

**Evidence.** PSS grew from 181 MB (fresh) to 284 MB after ~22 h, while threads
and FDs are explained by the icon catalog. The extra ~100 MB private memory
needs profiling, not guesswork.

**Candidate contributors:**

- QML compilation/type caches after opening Settings and many menu pages.
- `QQuickPixmapCache` entries for launcher/dock/tray icons.
- Wallpaper `Image` + `Canvas` buffers retained by the six samplers.
- Notification history kept in memory (there is intentionally no retention
  limit; rendering is virtualized).
- Graphics driver/LLVM pages loaded on first heavier scene graph use; these
  inflate RSS more than PSS.

**Method.** Restart cleanly, measure, then apply one workload at a time
(launcher open/close ×20, Settings open/close ×10, each drawer, playback) and
record PSS after each. Use `tools/measure_shell.py`. If `heaptrack`, `massif`, or
Qt pixmap-cache logging is available, use it; do not assert a leak from RSS
alone. Fix only a reproduced retention path.

### 3. Wallpaper palette decode

The 1024 px long-edge cap is shared through Qt's image cache and leaves Canvas
output sizes unchanged. Going to 768 or 512 px would save roughly 1.2–1.8 MB of
shared decode plus Canvas working memory, but palette contrast/extrema could
shift on detailed wallpapers. Validate with `tst_WallpaperColors.qml` (62
checks) plus visual checks on light, dark, and high-contrast wallpapers. Do not
lower the bare-glyph sampling resolution or change the sampled regions.

### 4. Wallpaper watchdog queries

The event helper handles the normal awww cache/socket path, but a `poll` query
still runs every 30 s because `awww clear`/disabled cache need not leave a cache
event. Raising it to 60 s halves process spawns at the cost of slower detection
of uncached changes. Keep the 4→30 s failure backoff and the 2 s fallback when
the helper is down. Only change this with a test for clear/disable and a measured
wakeup benefit.

### 5. Wi-Fi internet probe

`WifiInternet.qml` runs `curl` to `nmcheck.gnome.org` every 30 s when a
connection key exists. No probe was observed during a 35 s sample, so verify
that `connectedWifi.device`/name actually populate on this Quickshell version
before optimizing. Options: use NetworkManager connectivity state, lengthen the
interval, or reuse a cached result. Preserve the online/offline icon and the
"No internet access" tooltip.

### 6. Persistent Python helper footprint

Four helpers account for about 62 MB RSS. Replacing the wallpaper inotify bridge
with a tiny native helper, or folding the lid and idle watchers together, could
reduce that, but each carries feature risk (awww cache recreation, lid policy,
idle timers, locker handoff). Keep them separate unless memory is the explicit
target, and measure PSS per process before proposing a merge.

### 7. PipeWire tracker scope

`PwObjectTracker { objects: Pipewire.nodes.values.filter(n => !!n.audio) }` and
the link-group tracker keep all audio nodes bound. Narrowing this could reduce
wakeups but risks losing mpv/non-MPRIS streams and device hotplug. The peak
monitor is already gated; leave link tracking intact unless a profile proves it
is hot.

### 8. Intentional costs — do not remove without user approval

- Panel, dock, and drawer surfaces stay mapped for instant opening and reliable
  IPC timing. Hiding them saves memory but changes interaction latency.
- Keybindings polling (1.5 s), dashboard sampling (2 s), and calendar updates
  (1 s) only run while open; they keep live values correct.
- Notification history has no retention limit by user choice. Do not add one as
  an optimization.
- MPRIS playback stays active during silence; non-MPRIS streams keep the 900 ms
  grace period. Do not make silent playback disappear.
- Spectrum cadence, 12 bands, attack/release, and 300 ms marquee steps are
  visual contracts.

## Measurement methodology

Use a stable scenario: media stopped (`playerctl -a status`), no spectrum helper,
no drawers open, and one shell instance. Record the scenario in the report.

```sh
pid=$(pgrep -x quickshell | head -1)

# CPU, RSS, threads, FDs over 60 s
read -r _ _ _ _ _ _ _ _ _ _ _ _ _ ut st _ < /proc/$pid/stat
a=$((ut+st)); sleep 60
read -r _ _ _ _ _ _ _ _ _ _ _ _ _ ut st _ < /proc/$pid/stat
b=$((ut+st)); ticks=$((b-a))
awk -v t=$ticks 'BEGIN { printf "%.3f%% of one core\n", t/100/60*100 }'
awk '/^Rss:/{rss=$2}/^Pss:/{pss=$2}END{print "RSS "rss" kB  PSS "pss" kB"}' /proc/$pid/smaps_rollup
printf 'threads=%s fds=%s\n' "$(ls /proc/$pid/task | wc -l)" "$(ls /proc/$pid/fd | wc -l)"
```

Per-thread attribution:

```sh
ps -L -p "$pid" -o tid,pcpu,rss,comm --sort=-pcpu | head -15
# or sample utime+stime per /proc/$pid/task/*/stat
```

Children and orphan check:

```sh
ps -o pid,ppid,rss,pcpu,etime,args --ppid "$pid"
ps -eo pid,ppid,args | grep -E 'wallpaper-events|pactl subscribe|audio-spectrum|dashboard-status|settings/(backend|power|clipboard)'
```

FD and inotify inventory:

```sh
ls -l /proc/$pid/fd | awk '{print $NF}' | sed 's/[0-9]//g' | sort | uniq -c | sort -rn
# /proc/$pid/fdinfo/* contains "inotify wd:... ino:..." watch lists
```

Desktop health after a restart:

```sh
hyprctl layers | grep -E 'namespace: hyprshell|Monitor'
quickshell ipc --path /home/ramlej/.config/quickshell call bar ready   # expect true
```

`tools/measure_shell.py` automates CPU/RSS sampling and optionally captures
frame-swap intervals through the opt-in `performance` IPC target:

```sh
python3 tools/measure_shell.py --seconds 60 --label idle --output /tmp/opencode/idle.json
```

Its frame mode measures frame-swap intervals, not GPU render time. Do not leave
observers running.

## Validation gates

Focused Python checks used by the last optimization:

```sh
python3 -m unittest discover -s tests -p 'test_media_activity.py' -v
python3 -m unittest discover -s tests -p 'test_resource_scheduling.py' -v
python3 -m unittest discover -s tests -p 'test_wallpaper_events.py' -v
python3 -m unittest discover -s tests -p 'test_dashboard_wallpaper.py' -v
```

QML checks (offscreen; use the runtime-selected runner):

```sh
runner=$(python3 tools/check_runtime.py --qmltestrunner)
for t in tst_WallpaperColors.qml tst_MediaActivity.qml tst_Bar.qml; do
  QT_QPA_PLATFORMTHEME= QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
    "$runner" -input "config/quickshell/tests/$t"
done
```

Native/runtime prerequisites:

```sh
python3 tools/check_runtime.py --native
```

For tests that wait on `console.log` markers, set
`QT_LOGGING_RULES=qml.debug=true`; Quickshell suppresses debug output by
default. Missing markers alone are not a UI failure.

## Known traps and pre-existing failures

- **Pre-existing test failure.** `tests/test_settings_wallpaper_ui.py` fails at
  `QtQuickTest::fail tryCompare` (`Check.qml:91`). It reproduces on a clean
  worktree at `56add8e` and after `01b360f`; do not attribute it to new work.
- **Hot reload leaves helpers.** Reloading QML can leave `wallpaper-events.py`
  and `pactl subscribe` children from the previous generation. Kill only this
  task's orphans and do one clean kill/wait/start before measuring.
- **Restart teardown crash.** Rapidly restarting while the old instance tears
  down can segfault in `WlrLayershell`/`ProxyWindowContentItem` destruction.
  Kill one instance, wait for exit, then start the new one.
- **Live files are copies.** A repo edit does not change the desktop. Deploy only
  the changed payload files and verify with `cmp`.
- **Sync baseline.** After changing payload paths, run
  `scripts/sync_baseline.py` before the local commit. Docs and the root README
  are not payload.
- **Log noise.** The malformed Swappy desktop-entry warning repeats hundreds of
  times, and notification-server registration can report duplicates. These are
  known and not evidence of a regression. A single `SystemMonitorView` undefined
  `QString` warning has also been seen.
- **No `perf`/`strace`.** Use `/proc`, `smaps_rollup`, per-thread stat, `ps -L`,
  and fdinfo. Do not install profiling tools or change kernel settings for an
  audit.
- **Process names.** The binary is usually `quickshell`; `qs` may be a symlink.
  Use `quickshell list --all --json` to identify instances and `--pid`/`--path`
  with `quickshell kill` rather than killing all matches.
- **`bar ready` semantics.** It checks that panels exist and shown backing
  windows are visible; a true result does not prove every menu or helper works.

## Safe optimization workflow

1. Read this audit, `docs/media-performance.md`, and the relevant prior audit.
2. Reproduce the baseline in a stated scenario; keep media and drawers consistent.
3. Create a Hyprskill checkpoint covering every repo and live path you may touch,
   including planned new paths. Record the baseline and recovery command.
4. Make the smallest repo edit that addresses the measured cost. Do not refactor
   adjacent code or remove features.
5. Run focused Python/QML checks, then `check_runtime.py --native`.
6. Deploy only changed payload files to `~/.config/quickshell`, verify with
   `cmp`, and restart cleanly once.
7. Confirm all layer surfaces, `bar ready`, menus, launcher, notifications, audio,
   and the affected feature. Measure the same scenario as the baseline.
8. Advance the sync baseline for changed payload paths.
9. Review the full diff, commit locally with measurements and validation, and do
   not push without explicit authorization.

Rollback must restore both repo and live copies, then restart:

```sh
python3 /home/ramlej/.config/opencode/skills/hyprskill/scripts/checkpoint.py restore <checkpoint>
/home/ramlej/.config/quickshell/install-and-activate.sh
```

## Documentation drift

`config/quickshell/README.md` still describes a two-second wallpaper query and a
16 ms spectrum update. Current code uses the inotify watcher plus a 30 s query
fallback and 5 coalesced spectrum frames per second. Use this audit and
`docs/media-performance.md` for current timings. That README is a deployed
payload file; if it is corrected, deploy it and advance the sync baseline too.

## Related documents

- [Media background work](media-performance.md)
- [October 26 daily-driver audit](audit-2026-10-26.md)
- [October 27 security, reliability and efficiency audit](audit-2026-10-27.md)
- [October 27 follow-up](audit-2026-10-27-followup.md)
- Hyprskill `references/desktop.md` and `references/rollback.md` in
  `~/.config/opencode/skills/hyprskill/` (local agent guidance, outside this repo)
