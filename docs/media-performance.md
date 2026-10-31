# Media background work

Media playback detection follows speaker peak changes rather than a repeating
67 ms timer. MPRIS playback remains active even during silent passages;
non-MPRIS streams retain the 900 ms silence grace period. The speaker peak
monitor remains enabled so new audio is detected without polling.

Only an actively playing title longer than 28 Unicode code points schedules
marquee updates, at the next character change. The two-second opening pause,
300 ms character steps, separator and wrap are unchanged. Title character arrays
are cached until metadata changes. Idle playback and short titles need no timer.

The native spectrum helper computes fixed band compensation once at startup.
FFT processing, attack/release, microphone opt-in and rendering remain unchanged.
Speaker capture uses `--coalesce` to serialize the latest FFT frame five times
per second, matching the existing UI cadence. FFT state still advances at every
256-sample hop; default and microphone output retain every hop. QML applies the
already coalesced frame directly, avoiding about 57.5 JSON parses per second
during playback. Hidden panel/dock spectra stop binding levels and animating,
while retaining media geometry and their mapped surfaces for instant opening.

The root clock schedules the next minute boundary unless its Qt format contains
unquoted seconds or milliseconds. Formats with seconds retain one-second updates;
settings changes refresh immediately. Dock focus checks run once after focus or
relevant state changes instead of repeating every 150 ms on an open page.

The shortcut guide queries Hyprland directly without repeated Python startup.
Unchanged snapshots do not rebuild the list. Its 1.5-second check remains scoped
to the open guide: runtime bind/unbind edits need not emit a reload event. Lua
symbol names are still recovered from a validated text snapshot, including edits
that change only a symbol omitted from JSON.

Validation commands:

```sh
python3 -m unittest discover -s tests -p test_media_activity.py -v
python3 config/quickshell/tests/test_spectrum.py
python3 -m unittest discover -s tests -p test_microphone.py -v
python3 -m unittest discover -s tests -p test_resource_scheduling.py -v
```

These are work-count reductions, not measured percentages of whole-desktop CPU,
RAM or battery consumption. No service or desktop feature is disabled.
