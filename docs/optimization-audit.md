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

## Concrete implementation plan

**Objective:** reduce total Hyprshell CPU use, wakeups, and proportional memory
while preserving every feature, visual effect, animation cadence, and interaction
behavior. Keep Quickshell/QML and existing Python/JavaScript unless a measured
component warrants a targeted replacement. Bash migration and a whole-shell
language rewrite are excluded from this plan. This section defines future work;
the historical measurements above do not establish a new baseline or completed
results.

Complete Phase 0 first, then reassess priority. Icon fan-out is the default first
code change; move Phase 2 attribution ahead of it if baseline evidence makes
memory the dominant concern. Each implementation is a separate checkpointed,
measured change using the safe workflow below. Do not bundle unrelated changes.

### Phase 0 — reproducible baseline and acceptance criteria

1. Record checkout, live/repo differences, display configuration, media state,
   enabled features, process tree, and session age. Restart cleanly and check
   for old helper processes using the documented procedure.
2. Sample idle CPU for 60–300 seconds, three times. Record shell and helper PSS
   separately, total process-tree PSS, threads, and FDs. Collect deltas from
   `/proc/<pid>/task/<tid>/status` voluntary/nonvoluntary context-switch counters
   and, where available, `/proc/<pid>/task/<tid>/schedstat` runtime, run-queue wait,
   and timeslice counters for shell and helper threads. Track thread/process
   creation and exit; mark incomplete samples. These are scheduling proxies, not
   direct wakeup counts; process-leader counters alone miss other threads.
   RSS is supporting evidence, not the memory acceptance metric.
3. Repeat with playback and a fixed interaction sequence: launcher open/close
   20 times, Settings 10 times, then each drawer and representative menus.
   Build a workload driver using verified Quickshell IPC and hyprctl interfaces;
   record the exact menu list, action order, dwell times, readiness assertions,
   timeouts, and settling interval. Wait for observable state and fail on timeout
   rather than relying only on sleeps. Use the same driver and fixtures before
   and after, restore initial UI state, and isolate measurement-driver overhead.
   Record first icon-miss cost separately from subsequent opens.
4. Capture frame-swap intervals with opt-in FrameTiming during the same animations
   before and after each UI-affecting change. Compare median, p95/p99, and long
   frame counts; report that these measure swap intervals, not GPU render time.
   Disable observers afterward. Verify visually on the live desktop as well.
5. Retain before/after artifacts with scenario and commands. Accept a change only
   when its intended metric improves reproducibly beyond baseline variation,
   other resource metrics have no unexplained material regression, and functional
   and animation checks pass. An inconclusive result is not a demonstrated gain.

Use these initial decision gates; they are project acceptance policies, not
predicted savings or statistical confidence guarantees:

- Report median of at least three matched runs. Define variation as max minus min
  within each set; require improvement greater than twice the larger before/after
  variation and above measurement resolution. Extend noisy/borderline cases to at
  least five runs and longer sampling; unresolved results remain inconclusive.
- Phase 1 batching: target at least 20% lower first-miss CPU time plus the variation
  gate. Record rebuild counts and icon-ready latency; reject a repeatable latency
  regression beyond baseline variation. Skip the timer if this cannot be achieved.
- Phase 1 watcher replacement: target removal of at least 70 catalog-attributed
  threads and 140 FDs from the documented 75/~150 overhead, counting replacement
  helpers too. Rebase these targets if Phase 0 finds a different fan-out. Report
  PSS/CPU separately; resource-count success does not prove memory savings.
- Phase 2 fixes: require at least 5 MiB lower settled process-tree PSS or at least
  20% lower reproduced per-cycle growth, plus the variation gate. A growth fix
  must also demonstrate a bounded plateau over repeated workload blocks.
- Phase 3 replacements: require at least 5 MiB and 25% lower helper-tree PSS,
  plus the variation gate, without a reproducible CPU or responsiveness regression.
  If baseline helper PSS leaves insufficient room, skip a memory-driven rewrite.
- For animations, record display frame budget T (16.67 ms at 60 Hz), sample count,
  p95/p99 intervals, and fraction exceeding 1.5T during active animations. Compare
  identical animation windows; reject repeatable regressions beyond baseline
  variation or any visible stutter. Short samples cannot establish tail latency.

Deliverable: baseline artifacts, workload driver, and a recorded go/no-go decision
for each applicable gate. If a gate needs revision, document the reason before
implementation rather than relaxing it after seeing an unfavorable result.

### Phase 1 — eliminate icon catalog redundant work and watcher fan-out

1. Reproduce a first theme lookup miss and confirm the thread/FD increase before
   editing. Instrument signal requests, actual rebuilds, timestamps, and event-loop
   turns. Existing `Qt.callLater(icons.rebuild)` already coalesces requests within
   a turn; distinguish those requests from rebuilds across asynchronous load turns.
2. Trial a short single-shot timer only if cross-turn rebuilds are significant.
   Measure rebuild count, first-miss CPU, and icon-ready latency; preserve prompt
   initial discovery and live updates. Skip the delay if it fails the Phase 0 gate.
3. Replace the persistent per-directory model fan-out with a bounded scan and
   cached catalog if measurements confirm the documented cost. Define and test
   invalidation for application installs/removals, theme changes, and icon-file
   changes, including changes that do not alter DesktopEntries. Use consolidated
   event watching where needed; do not silently discard live update behavior.
4. Preserve lookup order, absolute paths, generic fallback, launcher/dock icons,
   and missing-directory recovery. Use the application and launcher checks listed
   under target 1 plus a live install/remove or equivalent controlled fixture.

Deliverable: measured reduction in rebuild work and persistent catalog threads/
FDs, with correct first-use and live-update behavior. Do not count lazy activation
alone as eliminating the steady-state cost.

### Phase 2 — attribute and reduce retained memory

1. Establish a fresh baseline at the chosen priority point (repeat it after any
   intervening code change). Run each Phase 0 workload separately
   and measure settled PSS after each block; repeat blocks to distinguish bounded
   cache warm-up from continuing retention.
2. Include wallpaper switches, notification history, and playback start/stop.
   Record history size so intentional retained notifications are not mistaken
   for a leak. Separate anonymous/private growth from file-backed mappings where
   the available tools permit it.
3. Identify a specific retaining object, cache, image buffer, or lifecycle path
   before changing it. Release unnecessary transient objects or duplicate decoded
   data while preserving instant-opening surfaces and image quality.
4. Repeat the triggering workload, then perform a comparable long-session check
   (approximately 22 hours for comparison with the historical observation).

Deliverable: attributed growth and before/after repeated-workload measurements.
If memory plateaus as an intentional cache, document that result; do not label
unattributed growth a leak or impose a notification retention limit.

### Phase 3 — selective persistent-helper optimization

1. Rank helpers by measured PSS, CPU, scheduling activity, and restart frequency. Measure
   enabled feature scenarios explicitly; an inactive helper is not free when used.
2. Evaluate the wallpaper event bridge first if interpreter memory is material.
   Check the installed Quickshell API and existing dependencies for a consolidated
   watcher or an existing event bridge (for example inotifywait) before writing a
   native helper. Verify recursion, replacement/recreation handling, output parsing,
   and failure recovery; include dependencies and all child processes in costs.
   This is not a Bash migration and must not introduce shell polling loops.
   Prototype a small native helper only when simpler options are unsuitable and
   baseline PSS leaves room to meet the Phase 0 replacement gate;
   choose Rust or C/C++ according to integration and maintenance needs, not a
   blanket language migration. Preserve its protocol, event-driven waiting,
   cache/socket recreation handling, retries, and fallback behavior.
3. Compare the complete process tree, including any replacement child commands.
   Adopt the prototype only if it passes the acceptance criteria and existing
   wallpaper watcher checks plus live recovery checks.
4. Evaluate lid/idle watchers separately only if remaining measurements justify
   it. Test lid policy, AC/battery transitions, timer resets, suspend/resume, and
   locker handoff. Keep process separation unless a measured consolidation gain
   justifies the larger failure domain and all behavior can be preserved.

Deliverable: one justified helper change at a time, or a documented decision to
retain existing helpers. Keep short-lived settings/install scripts and in-process
QML JavaScript unless profiling identifies a relevant cost. Do not move UI logic
into external command processes or replace event subscriptions with polling.

### Phase 4 — conditional lower-priority work

- Verify Wi-Fi probe activation first. Evaluate NetworkManager connectivity state
  only if it provides equivalent online/offline semantics and freshness; preserve
  the icon and tooltip and test disconnect/reconnect and captive-network behavior.
- Profile wallpaper query wakeups. Prefer equivalent event coverage; retain the
  existing watchdog interval if increasing it would slow uncached-change detection.
- Revisit palette decoding only for measured remaining image-memory cost. Require
  the existing 62 checks and visual comparisons; retain the current cap if smaller
  decodes change contrast, extrema, or appearance.
- Narrow PipeWire tracking only if a profile identifies it as significant and
  hotplug, mpv/non-MPRIS playback, silent playback, and stream transitions remain
  correct. Otherwise leave it intact.

Deliverable: measured, behavior-preserving changes only. A responsiveness or
visual tradeoff requires separate user authorization and is not part of this plan.

### Completion and reporting

For each phase, report changed files, baseline and resulting measurements,
functional/frame-timing checks, uncertainties, and rollback instructions. Run
only relevant tests and the required runtime checks; review and deploy matching
payload changes, advance the sync baseline, and commit as described below.
Documentation-only edits require no live deployment or restart. After accepted
changes, update this audit with the new commit and measured scenarios, retaining
historical baselines. Stop optimizing a path when remaining cost is intentional
or no reproducible improvement is demonstrated.

## Open optimization targets

Ranked by measured impact and risk. Treat all as hypotheses until reproduced.

### 1. Icon catalog fan-out — highest leverage

**Evidence.** The first call to `AppIcons.source()` that misses the theme lookup
activates 75 `FolderListModel` delegates: 5 data roots × (8 hicolor sizes +
`pixmaps`) plus 30 Pop/Adwaita directories. After that first miss the live
process has 75 `FileInfoThread`s and roughly 150 extra inotify/eventfd
descriptors for the rest of the session. At 22 h: 121 threads / 230 FDs versus
45 / 75 at a fresh start.

**Second issue.** Every delegate schedules `icons.rebuild()` through
`Qt.callLater` on `statusChanged`, `countChanged`, and object creation. This
already coalesces same-turn requests, but not requests across asynchronous load
turns. `rebuild()` scans every folder and every entry. During the initial
asynchronous load this can rebuild the whole catalog many times. A ~2.36 s CPU burst was observed around the time the catalog
appeared; attribution is plausible but not instrumented.

**Options, least invasive first:**

1. Coalesce rebuilds with one short single-shot timer (for example 200–500 ms)
   only if instrumentation shows redundant rebuilds across event-loop turns.
   Existing `Qt.callLater` already batches same-turn signals. Check icon-ready
   latency; keep live icon updates and the existing model structure.
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
