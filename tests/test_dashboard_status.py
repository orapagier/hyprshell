"""Native dashboard interaction and absence of live resource polling."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
@unittest.skipUnless(shutil.which('quickshell'), 'Native Quickshell is needed')
class DashboardNativeTests(unittest.TestCase):
    def test_hover_single_page_and_static_system_info(self):
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
                token in line for token in ('anchors { top:', 'anchors { left:', 'margins {', 'exclusionMode:', 'exclusiveZone:', 'WlrLayershell.')))
            (payload / 'Dashboard.qml').write_text(source)
            for name, fill in {'bright': '#ffffff', 'dark': '#000000', 'colorful': '#e70064', 'blue': '#0066ee', 'green': '#00aa44'}.items():
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
    property var stoppedSnapshot: null
    property int motionFrames: 0
    property bool reboundSeen: false
    property bool stretchSeen: false
    Timer {
        interval: 16; running: dashboard.opened; repeat: true
        onTriggered: {
            let popover = test.find(dashboard.contentItem, 'dashboardPopover');
            test.reboundSeen = test.reboundSeen || popover.edgeProgress > 1.02;
            test.stretchSeen = test.stretchSeen || Math.abs(popover.edgeProgress - popover.cornerProgress) > 0.03;
        }
    }
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
                    test.check(test.find(content, 'dashboardSystemInfo').visible, "Upper card shows system information");
                    test.check(dashboard.resourceData.system.os.length > 0, "System identity populated");
                    test.check(dashboard.resourceData.system.uptimeSeconds > 0, "Uptime snapshot populated");
                    test.check(test.find(content, 'dashboardUptime').visible && test.find(content, 'dashboardOsAge').visible, "Uptime and OS age are visible");
                    test.check(dashboard.resourceData.cpuTotal === undefined && dashboard.resourceData.processes === undefined, "No live resource counters or processes");
                    test.check(test.find(content, 'dashboardMemoryDetails').visible, "Static RAM capacity shown");
                    test.check(test.find(content, 'dashboardMediaDetails') === null, "Music card removed");
                    test.check(popover.edge === 'left' && popover.connected, "Left-edge dashboard");
                    test.check(popover.edgeAttached && popover.bodyX === 0, "Dashboard sits flush with screen edge");
                    test.check(popover.footRadius > 0 && popover.footRadius <= 28, "Feet fit screen boundaries");
                    test.check(test.find(popover, 'edgeAttachedSurface').visible, "Attached surface replaces funnel");
                    test.check(!test.find(popover, 'menuFunnel').visible, "Dashboard hides narrow connector");
                    test.check(popover.containsPointer(Qt.point(5, popover.bodyY - popover.footRadius / 2)), "Curved foot retains hover");
                    test.check(Math.abs(popover.edgeProgress - 1) < 0.001, "Opening motion settles");
                    test.check(test.reboundSeen, "Spring overshoots visibly before settling");
                    test.check(test.stretchSeen, "Independent axes squash and stretch");
                    test.check(popover.attachedCorner && popover.bodyBottom === dashboard.height, "Dashboard joins bottom-left screen corner");
                    test.check(popover.bodyRight + popover.footRadius <= dashboard.width, "Bottom-right foot fits screen");
                    test.check(popover.containsPointer(Qt.point(popover.bodyRight + popover.footRadius / 2, dashboard.height - 2)), "Bottom-right foot retains hover");
                    test.check(!popover.containsPointer(Qt.point(dashboard.width - 1, 1)), "Opposite screen corner stays outside dashboard");
                    test.check(dashboard.inputRect.x === 0 && dashboard.inputRect.width === dashboard.width, "Input covers dashboard up to screen edges");
                    test.check(dashboard.mask.regions[0].intersection === Intersection.Subtract, "Corner stays on its dedicated hover surface");
                    test.check(dashboard.mask.regions[0].width === 24 && dashboard.mask.regions[0].y + dashboard.mask.regions[0].height === dashboard.height,
                        "Only the physical corner is excluded from dashboard input");
                    test.check(popover.bodyWidth === 620 && popover.bodyHeight <= 700 && popover.bodyHeight > 0,
                        "Dashboard fits its compact content");
                    test.check(dashboard.inputRect.height === dashboard.height, "Full-height input while open");
                    input.mouseMove(dashboard.contentItem, 10, dashboard.height - 24);
                    test.check(dashboard.pointerInside, "Pointer enters bridge from trigger");
                    controller.leave('dashboard');
                    input.mouseMove(dashboard.contentItem, popover.bodyX + 100, popover.bodyY + 100);
                    test.check(dashboard.pointerInside, "Pointer enters dashboard over its content");
                    test.check(dashboard.resourceData.system.memoryTotal > 0, "Static system identity loaded");
                    input.mouseMove(dashboard.contentItem, dashboard.width - 1, 1);
                    test.check(!dashboard.pointerInside, "Pointer leaves dashboard");
                } else if (test.step === 2) {
                    test.check(!dashboard.opened, "Pointer exit closes dashboard");
                    test.check(dashboard.inputRect.height === 0, "Closed dashboard releases desktop input immediately");
                    controller.hover('dashboard');
                } else if (test.step === 3) {
                    test.check(dashboard.opened, "Repeated hover reopens dashboard");
                    input.mouseMove(dashboard.contentItem, 10, dashboard.height - 24);
                    controller.leave('dashboard');
                    input.mouseMove(dashboard.contentItem, dashboard.width - 1, 1);
                    input.mouseMove(dashboard.contentItem, popover.bodyX + 100, popover.bodyY + 100);
                } else if (test.step === 4) {
                    test.check(dashboard.opened, "Reentry cancels close delay");
                    let content = test.find(dashboard.contentItem, 'dashboardContent');
                    tick.stop();
                    let sampler = test.find(content, 'dashboardWallpaperSampler');
                    let previous = null;
                    let previousAccent = null;
                    for (let name of ['bright', 'dark', 'colorful', 'blue', 'green', 'busy']) {
                        content.wallpaperSource = Qt.resolvedUrl(name + '.svg');
                        input.tryCompare(sampler, 'ready', true, 1500);
                        test.check(sampler.ready, "Wallpaper pixels sampled: " + name);
                        test.check(content.cardColor.a === 1, "Opaque reading surface: " + name);
                        if (previous !== null) test.check(content.cardColor.toString() !== previous, "Card tint follows changed wallpaper");
                        previous = content.cardColor.toString();
                        if (previousAccent !== null) test.check(content.accentColor.toString() !== previousAccent, "Accent follows changed wallpaper");
                        previousAccent = content.accentColor.toString();
                        test.check(test.find(content, 'dashboardWeather').textColor.toString() === content.textColor.toString(), "Weather follows dashboard palette");
                        for (let foreground of [content.textColor, content.secondaryColor, content.accentColor])
                            test.check(Colors.contrast(foreground, content.cardColor) >= 7, "Text/card contrast at least 7:1: " + name);
                        test.check(Colors.contrast(Qt.color('#a6adc8'), content.cardColor) >= 4.5, "Secondary captions readable: " + name);
                        for (let opacity of [0.06, 0.14, 0.20, 0.22]) {
                            let fill = Colors.alpha(content.accentColor, opacity);
                            let background = Colors.mix(content.cardColor, fill, fill.a);
                            test.check(Colors.contrast(content.textColor, background) >= 4.5, "Button text readable in each state: " + name);
                            test.check(Colors.contrast(content.accentColor, background) >= 4.5, "Accent button readable in each state: " + name);
                        }
                    }
                    tick.start();
                    input.mouseMove(dashboard.contentItem, dashboard.width - 1, 1);
                } else if (test.step === 5) {
                    test.check(!dashboard.opened, "Repeated exit closes dashboard");
                    test.stoppedSnapshot = dashboard.resourceData;
                } else if (test.step === 10) {
                    test.check(dashboard.visible && !popover.rendering, "Window stays mapped but dashboard finishes exit animation");
                    test.check(popover.edgeProgress === 0, "Closing motion fully retracts to edge");
                    test.check(dashboard.resourceData === test.stoppedSnapshot, "Hidden dashboard keeps static identity");
                    dashboard.toggle(null);
                    test.check(dashboard.opened, "Shortcut opens dashboard");
                    input.mouseMove(dashboard.contentItem, popover.bodyX + 100, popover.bodyY + 100);
                    input.mouseMove(dashboard.contentItem, dashboard.width - 1, 1);
                } else if (test.step === 11) {
                    tick.stop();
                    input.tryCompare(dashboard, 'opened', false, 1500);
                    test.check(!dashboard.opened, "Shortcut-opened dashboard also closes on leave: " + JSON.stringify({hovered:controller.hoveredMenu, inside:controller.pointerInMenu, pinned:controller.pinned, pointer:dashboard.pointerInside}));
                    dashboard.reveal(null);
                    test.check(dashboard.opened, "Reveal opens dashboard");
                    input.mouseMove(dashboard.contentItem, popover.bodyX + 100, popover.bodyY + 100);
                    input.wait(5400);
                    test.check(dashboard.resourceData !== test.stoppedSnapshot, "Reopening refreshes the snapshot");
                    let openedSnapshot = dashboard.resourceData;
                    input.wait(1200);
                    test.check(dashboard.resourceData === openedSnapshot, "No polling while open");
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
                    input.tryCompare(popover, "edgeProgress", 1, 1500);
                    test.check(popover.edgeProgress === 1, "Reversed animation settles open");
                    input.tryCompare(popover, "cornerProgress", 1, 1500);
                    Style.Theme.preferences = ({reducedMotion: true});
                    input.wait(20);
                    controller.close();
                    test.check(popover.edgeProgress === 0 && popover.cornerProgress === 0, "Reduced motion closes instantly");
                    dashboard.reveal(null);
                    test.check(popover.edgeProgress === 1 && popover.cornerProgress === 1, "Reduced motion opens instantly");
                    controller.close();
                    Style.Theme.preferences = ({});
                    input.mouseMove(dashboard.contentItem, dashboard.width - 1, 1);
                    dashboard.enterCorner(null);
                    test.check(dashboard.opened, "Corner entry opens immediately without a dwell");
                    controller.leave('dashboard');
                    input.wait(450);
                    test.check(dashboard.opened, "Dashboard survives slow handoff beyond old close timeout");
                    test.check(popover.triggerRect.x === 0 && popover.triggerRect.width === 24 && popover.triggerRect.height === 24
                        && popover.triggerRect.y + popover.triggerRect.height === dashboard.height,
                        "Square reveal target includes extreme left and bottom pixels");
                    input.mouseMove(dashboard.contentItem, popover.bodyX + 100, popover.bodyY + 100);
                    test.check(dashboard.pointerInside, "Cursor can enter after unfolding");
                    input.wait(1000);
                    test.check(dashboard.opened, "Entry grace expiry does not close an occupied dashboard");
                    input.mouseMove(dashboard.contentItem, dashboard.width - 1, 1);
                    input.tryCompare(dashboard, 'opened', false, 1000);
                    test.check(!dashboard.opened, "Normal leave dismissal resumes after entry");
                    dashboard.reveal(null);
                    input.tryCompare(dashboard, 'opened', false, 1800);
                    test.check(!dashboard.opened, "Abandoned reveal eventually closes");
                    dashboard.reveal(null);
                    content.dismissRequested();
                    test.check(!dashboard.opened, "Explicit dismiss bypasses opening grace");
                    let corner = input.findChild(dashboard, 'dashboardCornerReveal');
                    test.check(corner !== null, "Production corner reveal surface is available");
                    // QtTest needs a leave on the same synthetic window before reentry.
                    input.mouseMove(corner.contentItem, -1, -1);
                    controller.close();
                    input.mouseMove(corner.contentItem, 0, corner.height - 1);
                    test.check(dashboard.opened, "Extreme bottom-left pixel opens without cursor adjustment");
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
            env = dict(os.environ, XDG_CONFIG_HOME=str(root / 'config'), XDG_STATE_HOME=str(root / 'state'), XDG_RUNTIME_DIR=str(runtime), QT_QPA_PLATFORM='offscreen',
                       QT_QPA_PLATFORMTHEME='', QT_QUICK_BACKEND='software')
            result = subprocess.run(['quickshell', '--log-rules', 'qml=true', '-p', str(entry)], env=env, capture_output=True, text=True, timeout=30)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            self.assertIn('DASHBOARD_NATIVE_OK', output)
            self.assertNotIn('ReferenceError', output)
            self.assertNotIn('Unable to assign', output)


if __name__ == '__main__':
    unittest.main()
