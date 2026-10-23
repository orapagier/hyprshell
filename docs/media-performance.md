# Media background work

Media playback detection follows speaker peak changes rather than a repeating
67 ms timer. MPRIS playback remains active even during silent passages;
non-MPRIS streams retain the 900 ms silence grace period. The speaker peak
monitor remains enabled so new audio is detected without polling.

Only an actively playing title longer than 28 Unicode code points runs the
67 ms marquee timer. The two-second opening pause, 300 ms character steps,
separator and wrap are unchanged. Title character arrays are cached until the
metadata changes. Idle playback and short titles need no repeating media timer.

The native spectrum helper computes fixed band compensation once at startup.
FFT processing, output cadence, attack/release, microphone opt-in and rendering
remain unchanged.

Validation commands:

```sh
python3 -m unittest discover -s tests -p test_media_activity.py -v
python3 config/quickshell/tests/test_spectrum.py
python3 -m unittest discover -s tests -p test_microphone.py -v
```

These changes remove approximately 15 timer callbacks per second when idle or
showing a short title, plus 12 repeated fixed `pow` calculations per audio hop
(750 per second at 16 kHz / 256 samples). They are work-count reductions, not
measured percentages of whole-desktop CPU, RAM or battery consumption.
