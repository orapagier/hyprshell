"""Frame capture is opt-in, bounded, and connected to real Qt windows."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


@unittest.skipUnless(shutil.which('quickshell'), 'Native Quickshell required')
class FrameTimingTests(unittest.TestCase):
    def test_frame_signals_and_automatic_stop(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'shell').symlink_to(ROOT / 'config/quickshell', target_is_directory=True)
            (root / 'runtime').mkdir(mode=0o700)
            entry = root / 'Check.qml'
            entry.write_text('''import QtQuick
import Quickshell
import "shell"
ShellRoot {
    id: root
    function check(value, message) { if (!value) { console.error(message); Qt.exit(1); throw new Error(message); } }
    FloatingWindow {
        id: window; visible: true; implicitWidth: 100; implicitHeight: 100
        Rectangle {
            width: 60; height: 60; color: 'red'
            NumberAnimation on rotation { from: 0; to: 360; duration: 500; loops: Animation.Infinite }
        }
    }
    FrameTiming { id: frames; windows: [{name:'test',window:window}] }
    Timer {
        interval: 100; running: true
        onTriggered: {
            root.check(!frames.recording && frames.observers.count === 0, 'Idle capture must have no observers');
            frames.record('test', 1);
            root.check(Object.keys(frames.samples).length === 0, 'Idle signals must do no work');
            frames.start(1);
            frames.record('synthetic', 100);
            frames.record('synthetic', 116);
            frames.record('synthetic', 134);
            frames.record('synthetic', 450);
            let report = frames.finish().synthetic;
            root.check(report.intervals === 2 && report.median_ms === 16 && report.p95_ms === 18
                && report.gaps_over_250ms === 1, 'Cadence summary or idle gap accounting is wrong');
            frames.start(1);
            root.check(!frames.start(1), 'Concurrent captures must not replace each other');
            finish.start();
        }
    }
    Timer {
        id: finish; interval: 1300
        onTriggered: {
            root.check(!frames.recording && frames.observers.count === 0, 'Capture must stop automatically');
            let report = frames.finish().test;
            root.check(report && report.intervals > 3, 'Real frame-swapped events were not captured');
            console.log('FRAME_TIMING_OK'); Qt.quit();
        }
    }
    Timer { interval: 5000; running: true; onTriggered: Qt.exit(2) }
}
''')
            env = dict(os.environ, XDG_RUNTIME_DIR=str(root / 'runtime'), XDG_STATE_HOME=str(root / 'state'),
                       QT_QPA_PLATFORM='offscreen', QT_QPA_PLATFORMTHEME='', QT_QUICK_BACKEND='software')
            result = subprocess.run(['quickshell', '--log-rules', 'qml.debug=true', '-p', str(entry)],
                                    env=env, capture_output=True, text=True, timeout=7)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn('FRAME_TIMING_OK', output)
            for error in ('ReferenceError', 'TypeError', 'Unable to assign', 'Binding loop'):
                self.assertNotIn(error, output)
