# October 27 audit follow-up

This implements the local follow-ups from [the audit](audit-2026-10-27.md).
The user confirmed the updated desktop interactions work after reload and published
the desktop-app release. Its downloaded assets are verified and the local installer
pin is updated. Collecting active-workload measurements remains a follow-up.

## Implemented

- **Notification persistence:** a bounded 150 ms window combines updates into
  one serialization/write. Continuous arrivals do not keep postponing the save.
  Writes are atomic; failed saves retain pending changes and retry. A reload
  handoff flushes the previous generation and transfers its latest rows. The
  shell also flushes before Alt+Q's hard reload and during root teardown.
  No history retention limit was added. Forced process termination or power
  loss can still lose the current batching window.
- **Notification rendering:** one ListView virtualizes group headers and cards.
  The drawer keeps its media controls, DND, independently expanded groups,
  notification details/actions, read state, dismissal and keyboard navigation.
  The shared popover supplies a viewport cap only to pages requesting one.
- **Wallpaper updates:** a persistent Python/inotify watcher invalidates queries
  when awww's cache or runtime socket changes; screen hotplug also invalidates
  them. A 30-second watchdog covers uncached changes, missed events and commands
  such as clear. If the event helper fails, two-second polling resumes, with
  the existing failure backoff. This is a hybrid implementation: awww's installed
  CLI does not expose a complete change subscription. Uncached changes may take
  up to 30 seconds to detect. The watcher adds a small persistent process.
- **Measurements:** `tools/measure_shell.py` records shell CPU and RSS. Its
  optional `--frames` mode starts a temporary frame-swap observer for the panels
  and both drawers, via the `performance` IPC target. No observers run normally.
  Captures stop automatically, reject overlap, detect replacement/reload, and
  cap each window at 10,000 intervals.
- **Release preparation:** the packager now accepts `--manifest-output`, allowing
  assets and a candidate checksum manifest to be reviewed before changing the
  installer's download pin. Following publication and verification of the
  downloaded assets, the installer manifest now names v1.0.1.

The shutdown implementation uses Quickshell's
[FileView write completion](https://quickshell.org/docs/v0.2.1/types/Quickshell.Io/FileView/)
and a reloadable Scope. The transfer passes a QObject reference and serializes
once at handoff because JS arrays cannot move directly between QML engines.

## Evidence

- A native synthetic history containing **10,000 notifications** instantiated
  **12 cards** in a 354×664 viewport. The final row remained reachable, expanded
  state survived scrolling out and back, and keyboard focus reached its header.
- **25 updates to 10,000 rows produced one history write.** This measures write
  coalescing, not elimination of all per-update row processing.
- Native tests verify pending arrivals and dismissals across soft reload,
  explicit hard reload, and immediate exit.
- Real inotify tests cover absent cache directories, output-file replacement,
  cache deletion/recreation, and daemon socket events. Native integration verifies
  event-triggered queries, watchdog updates and event-helper failure.
- Frame tests verify real Qt frame-swapped signals, idle inactivity, bounded
  duration and percentile/gap accounting. These use offscreen software rendering,
  not physical monitor presentation measurements.
- Python suite: **645 tests evaluated**. The first run had 19 missing QML debug
  success-marker failures and one unavailable compositor check. All 19 affected
  tests passed with `QT_LOGGING_RULES=qml.debug=true`; the compositor check was
  skipped with the inaccessible session variable removed. Together with the
  installer-environment skip, **643 passed and 2 skipped** across these runs.
- Native Qt suite: **464 passed**. Runtime dependency and QML syntax checks passed.
- Weather: **5 Rust tests passed**, with an offline locked release build. Matrix:
  **39 tests passed, 1 ignored**, with an offline locked release build. Monitor:
  **18 tests passed, 1 ignored** after correcting a test-only assumption that
  `/proc/stat` advances between rapid calls; the test now supplies a known earlier
  CPU counter. No monitor runtime behavior changed. All three apps built offline
  with locked dependencies. Release assets have checked SHA-256 sums and measured
  minimum glibc requirements.
- Eight payload files were deployed individually after validation, compared with
  the checkout, and entered into the matching local sync baseline.
- A user-run 30-second idle sample before deployment measured **12.600% of one
  CPU core**, **343.621 MiB median RSS** and **344.457 MiB peak RSS**. After reload,
  the same-duration sample measured **6.333%**, **336.293 MiB** and **340.430 MiB**.
  These are observations from one pair of samples; reload and workload differences
  prevent attributing the entire reduction to these changes. Child processes and
  GPU memory are excluded.
- The user confirmed that the activity drawer, notification details/actions and
  wallpaper changes work normally after deployment.
- The after-idle frame capture contained four gaps over 250 ms and no short frame
  intervals. A mostly static panel does not provide an animation benchmark.

For a complete repeat of the isolated Python suite in an agent sandbox:

```sh
env -u HYPRLAND_INSTANCE_SIGNATURE QT_LOGGING_RULES='qml.debug=true' \
  python3 -m unittest discover -s tests -v
```

Do not remove the session variable when deliberately testing the real compositor
from the desktop terminal.

## Further performance measurements

The basic desktop check and before/after idle captures are complete. Animation,
playback and multi-monitor measurements still require interaction in the desktop.

Run each measurement while doing the named activity; keep power mode and monitor
configuration comparable between repetitions. Use a new filename for each run.

```sh
python3 ~/repos/hyprshell/tools/measure_shell.py --frames --seconds 30 \
  --label drawers --output ~/hyprshell-drawers.json
# Repeatedly open/close both drawers during the capture.

python3 ~/repos/hyprshell/tools/measure_shell.py --frames --seconds 30 \
  --label playback --output ~/hyprshell-playback.json
# Play audio and exercise the media drawer during the capture.

python3 ~/repos/hyprshell/tools/measure_shell.py --frames --seconds 30 \
  --label monitors --output ~/hyprshell-monitors.json
# If applicable, connect/disconnect the external monitor during the capture.
```

Frame results are millisecond-resolution **frame-swap intervals**, not GPU render
time. Gaps above 250 ms are counted separately because a window may simply be idle;
that category can also contain long stalls. Compare like-for-like activity and
refresh rates. An empty interval series is not evidence of zero frame latency.

## Published release and installer pin

The user published [v1.0.1](https://github.com/orapagier/hyprshell/releases/tag/v1.0.1)
at source revision `d03c425f25e6c8d7092ec22d305e0091b5c70036`, uploading all three
executables and `SHA256SUMS`. All three user-downloaded executables match the
checksums in the originally prepared bundle; the downloaded checksum file also
matches. Verification copies were moved out of the checkout into
`~/Downloads/hyprshell-v1.0.1-verified/` without changing their bytes.

`app-releases.json` now pins v1.0.1 and these verified checksums. Hyprmonitor and
Hyprmatrix require glibc 2.43; Hyprweather requires glibc 2.39. The installed
executables already match, so no live binary replacement is needed. The manifest
commit must be pushed before GitHub-based setup/update consumers receive the pin.
The 10 app-release regression tests passed. Isolated staging accepted all three
verified downloads, checked executable modes, and reused all three installed
executables without network or live writes. ELF architecture and glibc requirements
were checked against the downloaded files. Fresh Arch app runtime acceptance
remains unverified.

Private checkpoints, the combined rollback script and measurement files remain
outside the repository; their paths are supplied in the completion message.
