# October 27 audit follow-up

This implements the local follow-ups from [the audit](audit-2026-10-27.md).
The user confirmed the updated desktop interactions work after reload. Publishing
the desktop-app assets and collecting active-workload measurements remain separate
completion steps.

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
  installer's download pin. The working installer manifest still names v1.0.0
  until the replacement release is published.

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

## Finish the release

The candidate bundle is `~/Downloads/hyprshell-v1.0.1/`: three executables,
`SHA256SUMS`, `RELEASE-NOTES.md`, and a candidate `app-releases.json`. Binaries stay
outside Git. The source revision and glibc requirements are in the release notes.
This agent session could not reach GitHub's API, so tag availability has not been
verified and no release, tag or push was performed.

After reviewing/committing the local changes and explicitly authorizing publication:

1. Check that v1.0.1 is unused; never replace existing release assets in place.
2. Push the reviewed source branch so GitHub has the revision in the release notes.
3. Create the release at that revision, uploading all three executables plus
   `SHA256SUMS`, with the staged notes. Publish the assets before updating the pin.
4. Verify the published downloads against the candidate checksums. Then apply
   the candidate `app-releases.json` to the checkout, test app-release installation,
   and commit/push that manifest update.

Until step 4, full setup/reviewed deployment can still install the older pinned
weather executable. The already-fixed local weather helper is unchanged by this
follow-up. Fresh Arch app runtime acceptance also remains unverified.

Private checkpoints, the combined rollback script and measurement files remain
outside the repository; their paths are supplied in the completion message.
