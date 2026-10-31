"""Exercise the native FFT with deterministic audio, without desktop sockets."""
import array
import json
import math
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

HELPER = Path(__file__).resolve().parents[1] / "helpers" / "audio-spectrum"
RATE = 16000
HOP = 256


def signal(frequencies, amplitude=0.4, hops=32):
    pcm = array.array("h", (
        round(amplitude * 32767 * sum(math.sin(2 * math.pi * f * i / RATE)
                                     for f in frequencies) / max(1, len(frequencies)))
        for i in range(hops * HOP)
    ))
    if sys.byteorder != "little":
        pcm.byteswap()
    return pcm.tobytes()


def spectrum(pcm):
    result = subprocess.run([str(HELPER), "--stdin"], input=pcm,
                            capture_output=True, check=True)
    return [json.loads(line) for line in result.stdout.splitlines()]


class SpectrumTests(unittest.TestCase):
    def test_coalescing_preserves_fft_frames_and_silence_at_five_hz(self):
        pcm = signal([500], hops=63) + signal([], hops=62)
        full = spectrum(pcm)
        result = subprocess.run([str(HELPER), "--coalesce", "--stdin"], input=pcm,
                                capture_output=True, check=True)
        frames = [json.loads(line) for line in result.stdout.splitlines()]
        indices = [i for i in range(len(full)) if (i + 1) * HOP // 3200 > i * HOP // 3200]
        self.assertEqual(len(frames), 10)
        self.assertEqual(frames, [full[i] for i in indices])
        self.assertGreater(frames[0][5], 0.75)
        self.assertEqual(frames[-1], [0] * 12)

    def test_bass_midrange_and_treble_use_separate_bands(self):
        for frequency, band in [(46.875, 0), (125, 2), (500, 5), (2000, 8), (5000, 11)]:
            with self.subTest(frequency=frequency):
                levels = spectrum(signal([frequency]))[-1]
                self.assertEqual(max(range(12), key=levels.__getitem__), band)
                self.assertGreater(levels[band], 0.75)

    def test_every_audio_hop_emits_a_bounded_frame(self):
        frames = spectrum(signal([100, 500, 2000, 5000], hops=24))
        self.assertEqual(len(frames), 24)
        for frame in frames:
            self.assertEqual(len(frame), 12)
            self.assertTrue(all(0 <= value <= 1 for value in frame))

    def test_quiet_passages_fall_instead_of_staying_at_the_ceiling(self):
        frames = spectrum(signal([500]) + signal([500], amplitude=0.025))
        self.assertGreater(frames[31][5], 0.75)
        self.assertLess(frames[-1][5], 0.25)
        self.assertGreater(frames[-1][5], 0.05)

    def test_silence_releases_smoothly_then_reaches_zero(self):
        frames = spectrum(signal([500]) + signal([], hops=48))
        self.assertGreater(frames[32][5], 0)
        self.assertLess(frames[32][5], frames[31][5])
        self.assertTrue(all(frames[i+1][5] <= frames[i][5] for i in range(32, len(frames)-1)))
        self.assertEqual(frames[-1], [0] * 12)

    def test_silence_never_creates_fake_motion(self):
        self.assertTrue(all(frame == [0] * 12 for frame in spectrum(signal([]))))

    def test_attack_follows_a_new_note_within_two_hops(self):
        frames = spectrum(signal([], hops=8) + signal([2000], hops=8))
        self.assertGreater(frames[9][8], 0.6)

    def test_refuses_microphone_or_implicit_sources(self):
        for args in [[], ["@DEFAULT_SOURCE@"], ["alsa_input.microphone"]]:
            with self.subTest(args=args):
                result = subprocess.run([str(HELPER), *args], capture_output=True)
                self.assertEqual(result.returncode, 2)

    def test_native_capture_restarts_and_follows_output(self):
        with tempfile.TemporaryDirectory(prefix="quickshell-spectrum-test-") as directory:
            work = Path(directory)
            (work / "runtime").mkdir(mode=0o700)
            frames = work / "frames.jsonl"
            frames.write_text("\n".join(json.dumps(frame) for frame in
                                       spectrum(signal([2000], hops=8))) + "\n")
            environment = dict(os.environ, QT_QPA_PLATFORM="offscreen",
                               QT_QUICK_BACKEND="software",
                               XDG_RUNTIME_DIR=str(work / "runtime"),
                               XDG_STATE_HOME=str(work / "state"),
                               QUICKSHELL_SPECTRUM_TEST_FRAMES=str(frames))
            fixture = work / "Validate.qml"
            fixture.write_text(Path(__file__).with_name("CheckSpectrum.qml").read_text()
                               .replace('import ".."', 'import "' + HELPER.parent.parent.as_uri() + '"'))
            result = subprocess.run(["quickshell", "-p", str(fixture)],
                                    env=environment, text=True, capture_output=True,
                                    timeout=10)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn("PASS: native FFT-to-QML", result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
