import QtQuick
import QtTest
import ".."
import "../style" as Style

TestCase {
    id: test
    name: "FluidDesktop"
    visible: true
    when: windowShown
    width: 900; height: 700
    Component { id: buttonComponent; MenuButton { x: 20; y: 20; width: 160; height: 44; text: "Action" } }
    Component { id: popoverComponent; MenuPopover { width: 900; height: 700; preferredBodyWidth: 300; connected: false } }
    function cleanup() { Style.Theme.preferences = ({}); mouseMove(test, 880, 680); }
    function test_hover_retargets_and_preserves_geometry() {
        let button = createTemporaryObject(buttonComponent, test);
        mouseMove(test, 880, 680); wait(240);
        compare(button.background.radius, 8);
        mouseMove(button, 80, 22);
        tryCompare(button, "hovered", true);
        wait(60);
        verify(button.background.radius > 8, "Hover shape interpolates");
        compare(button.width, 160); compare(button.height, 44);
        mouseMove(test, 880, 680);
        tryCompare(button, "hovered", false);
        tryCompare(button.background, "radius", 8, 600);
    }
    function test_reduced_motion_and_press() {
        Style.Theme.preferences = ({reducedMotion: true});
        let button = createTemporaryObject(buttonComponent, test);
        mouseMove(button, 80, 22);
        tryCompare(button.background, "radius", 14);
        mousePress(button, 80, 22);
        compare(button.scale, 0.98);
        mouseRelease(button, 80, 22);
        compare(button.scale, 1);
        compare(Style.Theme.duration(button, 350), 0);
    }
    function test_connected_wave_keeps_pill_foot_fixed_data() {
        return ["top", "bottom", "left", "right"].map(edge => ({tag: edge, edge: edge}));
    }
    function test_connected_wave_keeps_pill_foot_fixed(data) {
        let popover = createTemporaryObject(popoverComponent, test, {
            connected: true, edge: data.edge, triggerRect: Qt.rect(400, 300, 60, 28)
        });
        let halfWidth = (popover.vertical ? 28 : 60) / 2;
        compare(popover.attachmentHalfWidth, halfWidth);
        verify(popover.neckHalfWidth > 0 && popover.neckHalfWidth < halfWidth * 0.4);
        compare(popover.attachmentRadius, 14);
        compare(popover.attachmentY, popover.neckY - 14);
        let footX = popover.tipX, footY = popover.neckY;
        popover.opened = true;
        tryVerify(() => popover.fluidProgress > 0 && popover.fluidProgress < 1);
        wait(100);
        verify(Math.abs(popover.fluidWave) > 0.01);
        compare(popover.tipX, footX); compare(popover.neckY, footY);
        compare(popover.attachmentHalfWidth, halfWidth);
        // Reverse mid-wave without losing the stable foot or leaving motion running.
        popover.opened = false;
        wait(50);
        popover.opened = true;
        tryCompare(popover, "fluidProgress", 1, 800);
        fuzzyCompare(popover.fluidOffset, 0, 0.001);
        fuzzyCompare(popover.waistX, footX, 0.001);
        Style.Theme.preferences = ({reducedMotion: true});
        popover.opened = false;
        compare(popover.fluidProgress, 0);
        popover.opened = true;
        compare(popover.fluidProgress, 1);
    }
    function test_popover_keeps_exit_rendering() {
        let popover = createTemporaryObject(popoverComponent, test);
        popover.opened = true;
        wait(400);
        compare(popover.rendering, true);
        popover.opened = false;
        compare(popover.rendering, true);
        tryCompare(popover, "rendering", false, 600);
        Style.Theme.preferences = ({reducedMotion: true});
        popover.opened = true;
        tryCompare(popover, "rendering", true);
        popover.opened = false;
        tryCompare(popover, "rendering", false);
    }
}
