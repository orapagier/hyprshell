"""Native playback detection and title scheduling without desktop services."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('quickshell'), 'Native Qt runtime required')
class MediaActivityTests(unittest.TestCase):
    def test_spectrum_accepts_native_coalesced_frames_and_resets(self):
        # Quickshell.Io is linked into Quickshell, not the standalone Qt runner.
        with tempfile.TemporaryDirectory(prefix='hyprshell-spectrum-frames-') as directory:
            root = Path(directory)
            runtime = root / 'runtime'; runtime.mkdir(mode=0o700)
            (root / 'shell').symlink_to(ROOT / 'config/quickshell', target_is_directory=True)
            entry = root / 'Check.qml'
            entry.write_text('''import QtQuick
import QtTest
import Quickshell
import "shell"
ShellRoot {
    AudioSpectrum { id: spectrum }
    TestCase { id: input; when: false }
    function check(value) {
        if (!spectrum.levels.every(n => n === value)) throw new Error("Unexpected spectrum frame");
    }
    Timer { interval: 100; running: true; onTriggered: {
        try {
            spectrum.acceptFrame(Array(12).fill(1)); check(1);
            spectrum.acceptFrame(Array(12).fill(0)); check(0);
            spectrum.acceptFrame(Array(12).fill(0.4));
            spectrum.acceptFrame(Array(12).fill(0.9)); check(0.9);
            spectrum.acceptFrame(Array(12).fill(0.4)); check(0.4);
            spectrum.acceptFrame(Array(12).fill(0.2));
            spectrum.acceptFrame(Array(12).fill(0.8));
            spectrum.acceptFrame(Array(12).fill(NaN)); check(0.8);
            spectrum.acceptFrame(Array(12).fill(1));
            spectrum.restart();
            input.wait(250); check(0);
            console.info("SPECTRUM_FRAMES_OK"); Qt.quit();
        } catch (error) { console.error(error); Qt.exit(1); }
    }}
}
''')
            env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software',
                       QT_QPA_PLATFORMTHEME='', XDG_RUNTIME_DIR=str(runtime),
                       XDG_CONFIG_HOME=str(root / 'config'), XDG_STATE_HOME=str(root / 'state'))
            result = subprocess.run(['quickshell', '-p', str(entry)], env=env,
                                    capture_output=True, text=True, timeout=10)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn('SPECTRUM_FRAMES_OK', output)

    def test_desktop_services_loads_idle(self):
        with tempfile.TemporaryDirectory(prefix='hyprshell-media-services-') as directory:
            root = Path(directory)
            runtime = root / 'runtime'; runtime.mkdir(mode=0o700)
            (root / 'shell').symlink_to(ROOT / 'config/quickshell', target_is_directory=True)
            entry = root / 'Check.qml'
            entry.write_text('''import QtQuick
import Quickshell
import "shell"
ShellRoot {
    DesktopServices { id: services }
    Timer { interval: 300; running: true; onTriggered: {
        if (services.playing || services.marquee !== "" || services.mediaData.playing) {
            console.error("Unexpected playback while isolated"); Qt.exit(1); return;
        }
        console.log("MEDIA_SERVICES_OK"); Qt.quit();
    }}
}
''')
            env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software',
                       QT_QPA_PLATFORMTHEME='', XDG_RUNTIME_DIR=str(runtime),
                       XDG_CONFIG_HOME=str(root / 'config'), XDG_STATE_HOME=str(root / 'state'),
                       DBUS_SESSION_BUS_ADDRESS='unix:path=/nonexistent-hyprshell-test-bus',
                       DBUS_SYSTEM_BUS_ADDRESS='unix:path=/nonexistent-hyprshell-test-system-bus',
                       PULSE_SERVER='unix:/nonexistent-hyprshell-test-pulse')
            env.pop('WAYLAND_DISPLAY', None)
            env.pop('HYPRLAND_INSTANCE_SIGNATURE', None)
            result = subprocess.run(['quickshell', '--log-rules', 'qml=true', '-p', str(entry)],
                                    env=env, capture_output=True, text=True, timeout=10)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn('MEDIA_SERVICES_OK', output)
            for error in ('ReferenceError', 'TypeError', 'Binding loop', 'Unable to assign'):
                self.assertNotIn(error, output)

    def test_media_activity(self):
        runner = subprocess.run(['python3', str(ROOT / 'tools/check_runtime.py'), '--qmltestrunner'],
                                capture_output=True, text=True, check=True).stdout.strip()
        with tempfile.TemporaryDirectory(prefix='hyprshell-media-activity-') as directory:
            root = Path(directory)
            runtime = root / 'runtime'; runtime.mkdir(mode=0o700)
            env = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software',
                       QT_QPA_PLATFORMTHEME='', XDG_RUNTIME_DIR=str(runtime),
                       XDG_CONFIG_HOME=str(root / 'config'), XDG_STATE_HOME=str(root / 'state'))
            result = subprocess.run([runner, '-input',
                                     str(ROOT / 'config/quickshell/tests/tst_MediaActivity.qml')],
                                    env=env, capture_output=True, text=True, timeout=25)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn('8 passed', output)
            for error in ('ReferenceError', 'TypeError', 'Binding loop', 'Unable to assign'):
                self.assertNotIn(error, output)
