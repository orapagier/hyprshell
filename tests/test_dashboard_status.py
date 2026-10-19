"""Resource counter correctness, including guest accounting and idle I/O time."""
import importlib.util
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location('dashboard_status', ROOT / 'config/quickshell/helpers/dashboard-status.py')
STATUS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(STATUS)


class ResourceStatusTests(unittest.TestCase):
    def test_memory_uses_available_and_cpu_does_not_double_count_guests(self):
        with tempfile.TemporaryDirectory() as directory:
            proc = Path(directory)
            (proc / 'stat').write_text('cpu  100 20 30 400 50 6 7 8 60 10\ncpu0 1 2 3\n')
            (proc / 'meminfo').write_text('MemTotal: 10000 kB\nMemFree: 1000 kB\nMemAvailable: 3500 kB\n')
            (proc / 'uptime').write_text('12345.50 8000.0\n')
            result = STATUS.read_status(proc)
            self.assertEqual(result['cpuTotal'], 621)
            self.assertEqual(result['cpuIdle'], 450)
            self.assertEqual(result['memoryUsed'], 6500)
            self.assertEqual(result['memoryTotal'], 10000)
            self.assertEqual(result['uptime'], 12345.5)

    def test_missing_available_uses_free_memory(self):
        with tempfile.TemporaryDirectory() as directory:
            proc = Path(directory)
            (proc / 'stat').write_text('cpu 1 2 3 4\n')
            (proc / 'meminfo').write_text('MemTotal: 1000 kB\nMemFree: 250 kB\n')
            (proc / 'uptime').write_text('10 5\n')
            self.assertEqual(STATUS.read_status(proc)['memoryUsed'], 750)


@unittest.skipUnless(shutil.which('quickshell'), 'Native Quickshell is needed')
class DashboardNativeTests(unittest.TestCase):
    def test_hover_single_page_and_sampling_stop(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            payload = root / 'shell'
            payload.mkdir()
            for source in (ROOT / 'config/quickshell').iterdir():
                if source.name != 'Dashboard.qml':
                    (payload / source.name).symlink_to(source, target_is_directory=source.is_dir())
            # The offscreen platform has no layer-shell backend. Keep the actual
            # dashboard logic/content and substitute only its native window base.
            source = (ROOT / 'config/quickshell/Dashboard.qml').read_text().replace('PanelWindow {', 'FloatingWindow {')
            source = '\n'.join(line for line in source.splitlines() if not any(
                token in line for token in ('anchors { top:', 'anchors { left:', 'exclusionMode:', 'exclusiveZone:', 'WlrLayershell.')))
            (payload / 'Dashboard.qml').write_text(source)
            entry = root / 'Check.qml'
            entry.write_text('''import QtQuick
import QtTest
import Quickshell
import "shell"
ShellRoot {
    id: test
    property int step: 0
    property real stoppedCounter: 0
    TestCase { id: input; name: "DashboardPointer"; when: false }
    Dashboard {
        id: dashboard
        implicitWidth: 1100; implicitHeight: 850
        services: ({statusData:{network:{tooltip:"Test network"}},batteryInfo:{present:false}})
    }
    function check(value, message) { if (!value) throw new Error(message); }
    function find(item, name) {
        if (item.objectName === name) return item;
        for (let child of item.children || []) { let found = find(child, name); if (found) return found; }
        return null;
    }
    Timer {
        interval: 400; running: true; repeat: true
        onTriggered: {
            try {
                if (test.step === 0) {
                    dashboard.toggle(null);
                    test.check(dashboard.opened, "Dashboard opens");
                } else if (test.step === 1) {
                    let content = test.find(dashboard.contentItem, 'dashboardContent');
                    test.check(content !== null, "Production dashboard content loads");
                    test.check(test.find(content, 'dashboardMedia') === null, "No media tab");
                    test.check(test.find(content, 'dashboardPerformance') === null, "No performance tab");
                    test.check(test.find(content, 'dashboardClose') === null, "No close button");
                    test.check(test.find(content, 'dashboardMemoryDetails').visible, "Memory details on main page");
                    test.check(test.find(content, 'dashboardUptime').visible, "Uptime on main page");
                    let details = test.find(content, 'dashboardUptime');
                    let detailsCard = details.parent.parent;
                    test.check(details.y + details.height <= details.parent.height, "Resource details fit their card");
                    test.check(detailsCard.height >= details.parent.implicitHeight + 44, "Resource card fits its controls");
                    let card = test.find(dashboard.contentItem, 'dashboardCard');
                    test.check(Math.abs(card.x) < 1, "Dashboard arrives from left");
                    test.check(Math.abs(card.y - (dashboard.height - card.height) / 2) < 1, "Dashboard vertically centered");
                    input.mouseMove(dashboard.contentItem, 100, dashboard.height / 2);
                    test.check(dashboard.pointerInside, "Pointer enters dashboard over its content");
                    test.check(dashboard.resourceData.cpuTotal > 0, "Local resource sampler runs");
                    input.mouseMove(dashboard.contentItem, dashboard.width - 1, 1);
                    test.check(!dashboard.pointerInside, "Pointer leaves dashboard");
                } else if (test.step === 2) {
                    test.check(!dashboard.opened, "Pointer exit closes dashboard");
                    test.stoppedCounter = dashboard.resourceData.cpuTotal;
                } else if (test.step === 8) {
                    test.check(!dashboard.visible, "Dashboard unmaps after exit animation");
                    test.check(dashboard.resourceData.cpuTotal === test.stoppedCounter, "Hidden dashboard stops sampling");
                    dashboard.reveal(null);
                    test.check(dashboard.opened, "Edge reveal reopens dashboard");
                    dashboard.toggle(null);
                    test.check(!dashboard.opened, "Shortcut still toggles dashboard");
                    console.log('DASHBOARD_NATIVE_OK'); Qt.quit();
                }
                test.step++;
            } catch (error) { console.error(error); Qt.exit(1); }
        }
    }
}
''')
            runtime = root / 'runtime'; runtime.mkdir(mode=0o700)
            env = dict(os.environ, XDG_RUNTIME_DIR=str(runtime), QT_QPA_PLATFORM='offscreen',
                       QT_QPA_PLATFORMTHEME='', QT_QUICK_BACKEND='software')
            result = subprocess.run(['quickshell', '--log-rules', 'qml=true', '-p', str(entry)], env=env, capture_output=True, text=True, timeout=12)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn('DASHBOARD_NATIVE_OK', output)
            self.assertNotIn('ReferenceError', output)
            self.assertNotIn('Unable to assign', output)


if __name__ == '__main__':
    unittest.main()
