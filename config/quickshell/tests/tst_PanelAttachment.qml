import QtQuick
import QtTest
import ".."
import "../SettingsModel.js" as Settings

Item {
    width: 800; height: 300
    AttachedPanelSurface { id: surface; width: 500; height: 40; start: 40; end: 460 }
    Bar { id: attachedBar; x: 0; y: 150; width: 700; screenHeight: 150 }
    PanelReveal { id: reveal; x: 550; y: 50; width: 150; height: 40; autoHide: true; motionEnabled: false }
    TestCase {
        name: "PanelAttachment"
        when: windowShown
        function test_marginsPreservedExceptAttachedEdge() {
            for (let edge of ["top", "bottom", "left", "right"]) {
                let config = {position:edge, marginTop:15, marginSide:20,
                    screenMarginTop:11, screenMarginBottom:12, screenMarginLeft:13, screenMarginRight:14};
                let before = Settings.screenMargins(config);
                config.edgeAttached = true;
                let attached = Settings.screenMargins(config);
                for (let side of ["top", "bottom", "left", "right"])
                    compare(attached[side], side === edge ? 0 : before[side]);
                config.edgeAttached = false;
                compare(Settings.screenMargins(config), before);
            }
        }
        function test_attachmentFollowsCenteredAndSpreadItems() {
            for (let edge of ["top", "bottom", "left", "right"]) {
                for (let centered of [false, true]) {
                    attachedBar.width = edge === "left" || edge === "right" ? 40 : 700;
                    attachedBar.settings = {bar:{position:edge, centerItems:centered, edgeAttached:true},
                        items:Object.keys(attachedBar.moduleItems).map(id => ({id:id, enabled:id === "launcher" || id === "wifi", side:id === "wifi" ? "right" : "left"}))};
                    wait(0);
                    let backing = findChild(attachedBar, "attachedPanelSurface");
                    verify(backing.visible);
                    compare(backing.parent, attachedBar);
                    compare(backing.edge, edge);
                    verify(backing.last > backing.first);
                    if (!attachedBar.vertical && centered) verify(backing.last - backing.first < 350);
                    if (!attachedBar.vertical && !centered) verify(backing.last - backing.first > 350);
                }
            }
        }
        function test_fullPillTransformsIntoAttachedMaterial() {
            let items = Object.keys(attachedBar.moduleItems).map(id => ({id:id, enabled:id === "launcher" || id === "wifi", side:"left"}));
            for (let edge of ["top", "bottom", "left", "right"]) {
                for (let centered of [false, true]) {
                    attachedBar.width = edge === "left" || edge === "right" ? 40 : 700;
                    attachedBar.settings = {bar:{position:edge, centerItems:centered, edgeAttached:true,
                        fullBackground:"on", adaptiveColors:false, fullPillTransparency:35}, items:items};
                    wait(0);
                    let pill = findChild(attachedBar, "fullPanelPill");
                    let rounded = findChild(pill, "pillBackground");
                    let attached = findChild(attachedBar, "attachedPanelSurface");
                    verify(pill.visible); // material remains available to foreground adaptation
                    verify(!rounded.visible);
                    verify(attached.visible);
                    compare(attached.surfaceColor, pill.backgroundFill);
                    fuzzyCompare(attached.opacity, 0.65, 0.001);
                    attachedBar.settings = {bar:{position:edge, centerItems:centered, edgeAttached:false,
                        fullBackground:"on", adaptiveColors:false, fullPillTransparency:35}, items:items};
                    wait(0);
                    verify(rounded.visible);
                    verify(!attached.visible);
                    fuzzyCompare(rounded.opacity, 0.65, 0.001);
                }
            }
        }
        function test_fourEdgeGeometry() {
            for (let edge of ["top", "bottom", "left", "right"]) {
                surface.edge = edge;
                surface.width = surface.vertical ? 40 : 500;
                surface.height = surface.vertical ? 500 : 40;
                compare(surface.depth, 40); compare(surface.length, 500);
                compare(surface.first, 40); compare(surface.last, 460);
                verify(surface.radius > 0 && surface.radius <= surface.depth / 2);
                wait(1);
            }
        }
        function test_hoverAndMenuRetention() {
            mouseMove(reveal, -20, -20);
            reveal.autoHide = true;
            reveal.menuOpen = false;
            reveal.hoverHeld = false;
            compare(reveal.progress, 0);
            mouseMove(reveal, 20, 10);
            tryCompare(reveal, "progress", 1);
            mouseMove(reveal, -20, -20);
            compare(reveal.progress, 1); // pointer handoff grace period
            reveal.menuOpen = true;
            wait(450);
            compare(reveal.progress, 1);
            reveal.menuOpen = false;
            compare(reveal.progress, 0);
        }
        function test_hiddenInputStripAndDisabledMode() {
            mouseMove(reveal, -20, -20);
            reveal.hoverHeld = false;
            reveal.menuOpen = false;
            reveal.autoHide = true;
            for (let edge of ["top", "bottom", "left", "right"]) {
                reveal.edge = edge;
                let rect = reveal.inputRect;
                compare(reveal.vertical ? rect.width : rect.height, 2);
                compare(rect.x, edge === "right" ? reveal.width - 2 : 0);
                compare(rect.y, edge === "bottom" ? reveal.height - 2 : 0);
            }
            reveal.autoHide = false;
            compare(reveal.progress, 1);
            compare(reveal.inputRect, Qt.rect(0, 0, reveal.width, reveal.height));
        }
    }
}
