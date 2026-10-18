"""Counter correctness and native dashboard rendering without changing the desktop."""
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
QML = ROOT / 'config/quickshell'
spec = importlib.util.spec_from_file_location('monitor', QML / 'helpers/system-monitor.py')
monitor = importlib.util.module_from_spec(spec)
spec.loader.exec_module(monitor)


class CollectorTests(unittest.TestCase):
    def test_cpu_excludes_guest_and_handles_resets(self):
        self.assertEqual(monitor.cpu_ticks('cpu 10 0 10 70 10 0 0 0 10 0'), (100, 80))
        self.assertEqual(monitor.cpu_percent((100, 80), (200, 130)), 50)
        self.assertIsNone(monitor.cpu_percent((100, 80), (100, 80)))

    def test_counter_reset_never_produces_negative_rate(self):
        self.assertEqual(monitor.rate((100, 200), (50, 500), 3), [0, 100])

    def test_available_memory_and_swap(self):
        data = monitor.memory('MemTotal: 100 kB\nMemAvailable: 40 kB\nCached: 20 kB\nSwapTotal: 10 kB\nSwapFree: 8 kB')
        self.assertEqual(data['memory_used'], 60 * 1024)
        self.assertEqual(data['swap_used'], 2 * 1024)

    def test_actual_machine_sample(self):
        collector = monitor.Collector()
        data = collector.sample()
        self.assertGreater(data['memory_total'], 0)
        self.assertGreater(data['uptime'], 0)
        self.assertGreaterEqual(data['memory_used'], 0)
        self.assertGreaterEqual(data['rx_rate'], 0)
        if 'install_epoch' in data:
            self.assertGreater(data['install_epoch'], 0)

    @unittest.skipUnless(shutil.which('quickshell'), 'Quickshell required')
    def test_native_view_and_controller(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            runtime = root / 'runtime'
            runtime.mkdir(mode=0o700)
            payload = root / 'quickshell'
            payload.mkdir()
            for source in QML.iterdir():
                if source.name != 'SystemMonitor.qml':
                    (payload / source.name).symlink_to(source, target_is_directory=source.is_dir())
            # Offscreen Qt has no layer-shell backend. Keep production bindings
            # and process lifecycle; replace only compositor-specific geometry.
            controller = (QML / 'SystemMonitor.qml').read_text().replace('PanelWindow {', 'FloatingWindow {')
            controller = '\n'.join(line for line in controller.splitlines()
                                   if not any(token in line for token in ('anchors { right:', 'margins {',
                                       'exclusionMode:', 'exclusiveZone:', 'WlrLayershell.', 'mask: Region')))
            controller = controller.replace('window.margins.right', '24').replace('window.margins.top', '64')
            (payload / 'SystemMonitor.qml').write_text(controller)
            (root / 'Check.qml').write_text('''import QtQuick
import QtQuick.Window
import Quickshell
import "''' + payload.as_uri() + '''"
ShellRoot {
    id: test
    Window {
        id: window
        visible: true; width: 800; height: 700
        SystemMonitorView {
            id: view
            width: 350; height: 620
            wallpaperSource: "''' + (QML / 'tests/fixtures/wallpaper-regions.svg').as_uri() + '''"
            screenWidth: 800; screenHeight: 400
            readings: ({os:'Example Linux', model:'Laptop', install_epoch:1700000000, cpu_model:'Processor'})
        }
    }
    SystemMonitor { id: controller; shown:false; services: ({batteryInfo:{}, statusData:{network:{}, bluetooth:{}}}) }
    Timer {
        property bool resized: false
        interval: 500; running: true
        onTriggered: {
            try {
                if (view.children[1].implicitHeight > view.height) throw new Error('Dashboard overflow');
                if (!resized) { resized = true; view.height = 480; restart(); return; }
                if (view.children[1].implicitHeight > view.height) throw new Error('Small screen overflow');
                window.contentItem.grabToImage(result => {
                    result.saveToFile('/tmp/hyprshell-system-monitor-preview.png');
                    console.log('SYSTEM_MONITOR_OK'); Qt.quit();
                });
            } catch (error) { console.error(error); Qt.exit(1); }
        }
    }
    Timer { interval:5000; running:true; onTriggered:Qt.exit(2) }
}''')
            env = dict(os.environ, XDG_RUNTIME_DIR=str(runtime), HYPRLAND_INSTANCE_SIGNATURE='',
                       QT_QPA_PLATFORMTHEME='', QT_QPA_PLATFORM='offscreen', QT_QUICK_BACKEND='software')
            result = subprocess.run(['quickshell', '--log-rules', 'qml.debug=true', '-p', str(root / 'Check.qml')], env=env,
                                    capture_output=True, text=True, timeout=10)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn('SYSTEM_MONITOR_OK', output)
            for error in ('ReferenceError', 'TypeError', 'Binding loop', 'Unable to assign'):
                self.assertNotIn(error, output)


if __name__ == '__main__':
    unittest.main()
