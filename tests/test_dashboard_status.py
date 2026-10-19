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
                if source.name == 'MenuPopover.qml':
                    (payload / source.name).write_text(source.read_text())
                elif source.name != 'Dashboard.qml':
                    (payload / source.name).symlink_to(source, target_is_directory=source.is_dir())
            # The offscreen platform has no layer-shell backend. Keep the actual
            # dashboard logic/content and substitute only its native window base.
            source = (ROOT / 'config/quickshell/Dashboard.qml').read_text().replace('PanelWindow {', 'FloatingWindow {')
            source = '\n'.join(line for line in source.splitlines() if not any(
                token in line for token in ('anchors { top:', 'anchors { left:', 'exclusionMode:', 'exclusiveZone:', 'WlrLayershell.')))
            (payload / 'Dashboard.qml').write_text(source)
            for name, fill in {'bright': '#ffffff', 'dark': '#000000', 'colorful': '#e70064'}.items():
                (root / (name + '.svg')).write_text(
                    '<svg xmlns="http://www.w3.org/2000/svg" width="1100" height="850">'
                    '<path fill="' + fill + '" d="M0 0h1100v850H0z"/></svg>')
            (root / 'busy.svg').write_text(
                '<svg xmlns="http://www.w3.org/2000/svg" width="1100" height="850">'
                '<defs><pattern id="p" width="20" height="20" patternUnits="userSpaceOnUse">'
                '<path fill="white" d="M0 0h20v20H0z"/><path fill="black" d="M0 0h10v10H0zM10 10h10v10H10z"/>'
                '</pattern></defs><path fill="url(#p)" d="M0 0h1100v850H0z"/></svg>')
            entry = root / 'Check.qml'
            entry.write_text('''import QtQuick
import QtTest
import Quickshell
import "shell"
import "shell/AdaptiveColors.js" as Colors
import "shell/style" as Style
ShellRoot {
    id: test
    property int step: 0
    property real stoppedCounter: 0
    property int motionFrames: 0
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
        id: tick
        interval: 600; running: true; repeat: true
        onTriggered: {
            try {
                let popover = test.find(dashboard.contentItem, 'dashboardPopover');
                let controller = test.find(dashboard.contentItem, 'dashboardMenuState');
                if (test.step === 0) {
                    popover.edgeProgressChanged.connect(() => {
                        if (popover.edgeProgress > 0 && popover.edgeProgress < 1) test.motionFrames++;
                    });
                    controller.hover('dashboard');
                } else if (test.step === 1) {
                    test.check(dashboard.opened, "Hover delay opens dashboard");
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
                    test.check(popover.edge === 'left' && popover.connected, "Left-edge dashboard");
                    test.check(popover.edgeAttached && popover.bodyX === 0, "Dashboard sits flush with screen edge");
                    test.check(popover.footRadius > 0 && popover.footRadius <= 28, "Feet fit screen boundaries");
                    test.check(test.find(popover, 'edgeAttachedSurface').visible, "Attached surface replaces funnel");
                    test.check(!test.find(popover, 'menuFunnel').visible, "Dashboard hides narrow connector");
                    test.check(popover.containsPointer(Qt.point(5, popover.bodyY - popover.footRadius / 2)), "Curved foot retains hover");
                    test.check(Math.abs(popover.edgeProgress - 1) < 0.001, "Opening motion settles");
                    test.check(Math.abs(popover.bodyY - (dashboard.height - popover.bodyHeight) / 2) < 1, "Dashboard vertically centered");
                    test.check(dashboard.inputRect.x === 4 && dashboard.inputRect.width === dashboard.width - 4, "Input observes outside-card movement but preserves trigger");
                    test.check(dashboard.inputRect.height === dashboard.height, "Full-height input while open");
                    input.mouseMove(dashboard.contentItem, 10, dashboard.height / 2);
                    test.check(dashboard.pointerInside, "Pointer enters bridge from trigger");
                    controller.leave('dashboard');
                    input.mouseMove(dashboard.contentItem, popover.bodyX + 100, popover.bodyY + 100);
                    test.check(dashboard.pointerInside, "Pointer enters dashboard over its content");
                    test.check(dashboard.resourceData.cpuTotal > 0, "Local resource sampler runs");
                    input.mouseMove(dashboard.contentItem, dashboard.width - 1, 1);
                    test.check(!dashboard.pointerInside, "Pointer leaves dashboard");
                } else if (test.step === 2) {
                    test.check(!dashboard.opened, "Pointer exit closes dashboard");
                    test.check(dashboard.inputRect.height === 0, "Closed dashboard releases desktop input immediately");
                    controller.hover('dashboard');
                } else if (test.step === 3) {
                    test.check(dashboard.opened, "Repeated hover reopens dashboard");
                    input.mouseMove(dashboard.contentItem, 10, dashboard.height / 2);
                    controller.leave('dashboard');
                    input.mouseMove(dashboard.contentItem, dashboard.width - 1, 1);
                    input.mouseMove(dashboard.contentItem, popover.bodyX + 100, popover.bodyY + 100);
                } else if (test.step === 4) {
                    test.check(dashboard.opened, "Reentry cancels close delay");
                    let content = test.find(dashboard.contentItem, 'dashboardContent');
                    tick.stop();
                    let sampler = test.find(content, 'dashboardWallpaperSampler');
                    let previous = null;
                    for (let name of ['bright', 'dark', 'colorful', 'busy']) {
                        content.wallpaperSource = Qt.resolvedUrl(name + '.svg');
                        input.tryCompare(sampler, 'ready', true, 1500);
                        test.check(sampler.ready, "Wallpaper pixels sampled: " + name);
                        test.check(content.cardColor.a === 1, "Opaque reading surface: " + name);
                        if (previous !== null) test.check(content.cardColor.toString() !== previous, "Card tint follows changed wallpaper");
                        previous = content.cardColor.toString();
                        for (let foreground of [content.textColor, content.secondaryColor, content.accentColor])
                            test.check(Colors.contrast(foreground, content.cardColor) >= 7, "Text/card contrast at least 7:1: " + name);
                        test.check(Colors.contrast(Qt.color('#a6adc8'), content.cardColor) >= 4.5, "Embedded calendar captions readable: " + name);
                        for (let state of ['#0bffffff', '#38cba6f7', '#55cba6f7']) {
                            let fill = Qt.color(state);
                            let background = Colors.mix(content.cardColor, fill, fill.a);
                            test.check(Colors.contrast(content.textColor, background) >= 4.5, "Button text readable in each state: " + name);
                            test.check(Colors.contrast(content.accentColor, background) >= 4.5, "Accent button readable in each state: " + name);
                        }
                    }
                    tick.start();
                    input.mouseMove(dashboard.contentItem, dashboard.width - 1, 1);
                } else if (test.step === 5) {
                    test.check(!dashboard.opened, "Repeated exit closes dashboard");
                    test.stoppedCounter = dashboard.resourceData.cpuTotal;
                } else if (test.step === 10) {
                    test.check(dashboard.visible && !popover.rendering, "Window stays mapped but dashboard finishes exit animation");
                    test.check(popover.edgeProgress === 0, "Closing motion fully retracts to edge");
                    test.check(dashboard.resourceData.cpuTotal === test.stoppedCounter, "Hidden dashboard stops sampling");
                    dashboard.toggle(null);
                    test.check(dashboard.opened, "Shortcut opens dashboard");
                    input.mouseMove(dashboard.contentItem, popover.bodyX + 100, popover.bodyY + 100);
                    input.mouseMove(dashboard.contentItem, dashboard.width - 1, 1);
                } else if (test.step === 11) {
                    tick.stop();
                    test.check(!dashboard.opened, "Shortcut-opened dashboard also closes on leave: " + JSON.stringify({hovered:controller.hoveredMenu, inside:controller.pointerInMenu, pinned:controller.pinned, pointer:dashboard.pointerInside}));
                    dashboard.reveal(null);
                    test.check(dashboard.opened, "Reveal opens dashboard");
                    let content = test.find(dashboard.contentItem, 'dashboardContent');
                    content.dismissRequested();
                    test.check(!dashboard.opened, "Escape dismissal still works");
                    input.wait(450);
                    dashboard.reveal(null);
                    controller.retain(true);
                    input.wait(80);
                    test.check(test.motionFrames > 0, "Drawer animates through intermediate sizes");
                    controller.close();
                    input.wait(60);
                    let partial = popover.edgeProgress;
                    dashboard.reveal(null);
                    controller.retain(true);
                    test.check(Math.abs(popover.edgeProgress - partial) < 0.01, "Reopening continues without a jump");
                    input.wait(600);
                    test.check(popover.edgeProgress === 1, "Reversed animation settles open");
                    Style.Theme.preferences = ({reducedMotion: true});
                    input.wait(20);
                    controller.close();
                    test.check(popover.edgeProgress === 0, "Reduced motion closes instantly");
                    dashboard.reveal(null);
                    test.check(popover.edgeProgress === 1, "Reduced motion opens instantly");
                    controller.close();
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
            result = subprocess.run(['quickshell', '--log-rules', 'qml=true', '-p', str(entry)], env=env, capture_output=True, text=True, timeout=20)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn('DASHBOARD_NATIVE_OK', output)
            self.assertNotIn('ReferenceError', output)
            self.assertNotIn('Unable to assign', output)


if __name__ == '__main__':
    unittest.main()
