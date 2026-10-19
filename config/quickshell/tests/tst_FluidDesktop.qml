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
    function test_connected_spring_surface_data() {
        return ["top", "bottom", "left", "right"].map(edge => ({tag: edge, edge: edge}));
    }
    function test_connected_spring_surface(data) {
        let popover = createTemporaryObject(popoverComponent, test, {
            connected: true, edge: data.edge, alignToTrigger: true,
            triggerRect: Qt.rect(400, 300, 60, 28)
        });
        let half = (popover.vertical ? 28 : 60) / 2;
        compare(popover.attachmentHalfWidth, half);
        let footX = popover.tipX, footY = popover.neckY;
        popover.opened = true;
        let motion = popover.fluidMotion;
        tryVerify(() => motion.progress > 0 && motion.progress < 1);
        tryVerify(() => Math.abs(motion.stretchT - 1) > 0.001);
        compare(popover.tipX, footX); compare(popover.neckY, footY);
        // The new foot is tangent to the pill, with no filled area inside it.
        let join = popover.fluidOutline, capRight = footX + half - 14;
        fuzzyCompare(Math.hypot(join.footRight - capRight, join.footY - (footY - 14)), 14, 0.01);
        verify(!join.path.includes("NaN") && !join.path.includes("Infinity"));
        popover.opened = false;
        wait(50);
        let before = motion.progress;
        popover.opened = true;
        fuzzyCompare(motion.progress, before, 0.001, "Reversal preserves the current frame");
        tryCompare(motion, "progress", 1, 800);
        tryCompare(motion, "running", false, 4000);
        fuzzyCompare(motion.stretchT, 1, 0.002);
        fuzzyCompare(motion.stretchN, 1, 0.002);
        // Render the settled waist too: a valid SVG can still tessellate with a
        // missing connector in Qt's curve renderer at exactly tangent joins.
        let image = grabImage(popover);
        let sx = data.edge === "left" ? popover.neckY + 12
            : data.edge === "right" ? popover.width - popover.neckY - 12 : popover.tipX;
        let sy = data.edge === "top" ? popover.neckY + 12
            : data.edge === "bottom" ? popover.height - popover.neckY - 12 : popover.tipX;
        sx = Math.round(sx); sy = Math.round(sy);
        verify(image.red(sx,sy) !== image.red(1,1) || image.green(sx,sy) !== image.green(1,1)
            || image.blue(sx,sy) !== image.blue(1,1), "The settled waist remains painted");
        compare(image.pixel(430,314), image.pixel(1,1), "The pill interior has no second translucent fill");
        // A neighbouring menu excites the same springs even while opened stays true.
        popover.triggerRect = popover.vertical ? Qt.rect(400, 220, 60, 28) : Qt.rect(500, 300, 60, 28);
        tryVerify(() => motion.running);
        tryVerify(() => Math.abs(motion.shear) > 0.0001);
        let scroll = findChild(popover, "menuBodyScroll");
        let local = Qt.point(scroll.width / 2, scroll.height / 2);
        let actual = scroll.mapToItem(popover, local.x, local.y);
        let expected = popover.cardPoint(scroll.x + local.x, scroll.y + local.y);
        fuzzyCompare(actual.x, expected.x, 0.01);
        fuzzyCompare(actual.y, expected.y, 0.01);
        verify(popover.containsPointer(actual), "The moving card keeps its hover region");
        tryCompare(motion, "running", false, 4000);
        popover.opened = false;
        wait(40);
        Style.Theme.preferences = ({reducedMotion: true});
        compare(motion.progress, 0);
        popover.opened = true;
        compare(motion.progress, 1);
        compare(motion.running, false);
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
