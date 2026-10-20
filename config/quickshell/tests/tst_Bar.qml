import QtQuick
import QtTest
import ".."

Item {
    id: scene
    width: 1366; height: 80
    Bar { id: bar; width: parent.width; clockText: "Oct 08   12:34 PM   Thu" }
    TestCase {
        name: "BarRegressions"
        when: windowShown
        function cleanup() { bar.settings = {}; bar.statusIconsOnly = false; bar.width = scene.width; bar.mediaData = {playing: false}; bar.notificationData = {count: 0}; bar.statusData = {workspaces: [], audio: {}, network: {}, bluetooth: {}, battery: {}}; }
        function test_hyprknotsSizing() {
            let links = findChild(bar, "panelConnectors");
            compare(links.lineWidth, 1.8);
            compare(links.knotScale, 1);
            compare(links.knotSizeFor(100), 4.8);
            for (let position of ["top", "bottom", "left", "right"]) {
                bar.settings = {bar:{position:position, hyprknotsLineWidth:6, hyprknotsKnotSize:200}};
                compare(links.lineWidth, 6);
                compare(links.knotScale, 2);
                compare(links.knotSizeFor(100), 9.6);
                verify(links.knotSizeFor(3) <= 3 / 3.6);
                bar.settings = {bar:{position:position, hyprknotsLineWidth:0.5, hyprknotsKnotSize:50}};
                compare(links.lineWidth, 0.5);
                compare(links.knotSizeFor(100), 2.4);
            }
        }
        function test_hyprknotsToggle() {
            let links = findChild(bar, "panelConnectors");
            verify(links.visible);
            bar.settings = {bar:{hyprknots:false}};
            verify(!links.visible);
            bar.settings = {bar:{hyprknots:true}};
            verify(links.visible);
            bar.statusIconsOnly = true;
            verify(!links.visible);
        }
        function test_fullPillBoundsAndStyle() {
            let pill = findChild(bar, "fullPanelPill");
            verify(!pill.visible);
            for (let position of ["top", "bottom", "left", "right"]) {
                bar.width = position === "left" || position === "right" ? 40 : scene.width;
                bar.settings = {bar:{position:position, fullBackground:"on", background:"off", hyprknots:false},
                    items:[{id:"launcher", backgroundColor:"#123456", backgroundOpacity:0.4, radius:7, opacity:0.6}]};
                verify(pill.visible);
                compare(pill.settings.backgroundColor, "#123456");
                compare(pill.settings.backgroundOpacity, 0.4);
                compare(pill.settings.radius, 7);
                compare(pill.opacity, 0.6);
                for (let id of pill.memberIds) {
                    let item = bar.moduleItems[id];
                    verify(pill.x <= item.x && pill.y <= item.y);
                    verify(pill.x + pill.width >= item.x + item.width - 0.01);
                    verify(pill.y + pill.height >= item.y + item.height - 0.01);
                }
                bar.settings = {bar:{position:position, fullBackground:"on"}, items:[{id:"launcher",enabled:false}]};
                verify(!pill.memberIds.includes("launcher"));
                compare(pill.leader, "settings");
                compare(bar.vertical ? pill.y : pill.x, bar.vertical ? bar.moduleItems.settings.y : bar.moduleItems.settings.x);
            }
            bar.settings = {bar:{fullBackground:"inherit", background:"off"}};
            verify(!pill.visible);
            bar.settings = {bar:{fullBackground:"inherit", background:"on"}};
            verify(pill.visible);
            bar.statusIconsOnly = true;
            verify(!pill.visible);
            bar.statusIconsOnly = false;
            bar.settings = {bar:{fullBackground:"on"}, items:Object.keys(bar.moduleItems).map(id => ({id:id,enabled:false}))};
            verify(!pill.visible);
        }
        function test_workspaceColorFollowsActiveWorkspace() {
            bar.statusData = {workspaces: [{id:1, name:"1", active:true}, {id:2, name:"2", active:false}], audio: {}, network: {}, bluetooth: {}, battery: {}};
            let first = findChild(bar, "workspace1"), second = findChild(bar, "workspace2");
            verify(first !== null && second !== null);
            verify(first.adaptivePalette.tint.a > second.adaptivePalette.tint.a);
            let gray = second.effectiveForeground;
            fuzzyCompare(gray.r, gray.g, 0.01); fuzzyCompare(gray.g, gray.b, 0.01);
            bar.statusData = {workspaces: [{id:1, name:"1", active:false}, {id:2, name:"2", active:true}], audio: {}, network: {}, bluetooth: {}, battery: {}};
            first = findChild(bar, "workspace1"); second = findChild(bar, "workspace2");
            verify(second.adaptivePalette.tint.a > first.adaptivePalette.tint.a);
            let saved = false;
            scene.grabToImage(result => { result.saveToFile("/tmp/quickshell-workspace-colors.png"); saved = true; }, Qt.size(scene.width * 2, scene.height * 2));
            tryVerify(() => saved);
        }
        function test_mediaIsDestroyedWhenIdle() {
            let slot = findChild(bar, "mediaSlot");
            verify(slot !== null);
            compare(slot.active, false);
            compare(slot.item, null);
            bar.mediaData = {playing: true, levels: [0.1,0.2,0.3,0.4,0.5,0.6,0.7,0.8,0.9,1,0.7,0.2], title: "Test track", tooltip: "Test"};
            tryCompare(slot, "active", true);
            verify(slot.item !== null);
            bar.mediaData = {playing: false, levels: [], title: "Stale title"};
            tryCompare(slot, "active", false);
            compare(slot.item, null);
            bar.mediaData = undefined;
            compare(slot.active, false);
            compare(slot.item, null);
        }
        function test_bellRemainsWithNoDataOrUnreadCount() {
            let bell = findChild(bar,"notificationBell");
            verify(bell !== null);
            compare(bell.text, "󰂚");
            verify(bell.visible);
            verify(bell.width >= 30);
            bar.notificationData = undefined;
            compare(bell.text, "󰂚");
            verify(bell.visible);
            bar.notificationData = {count: 12, tooltip: "12 unread notifications"};
            compare(bell.text, "󰂚");
            verify(bell.width > 30);
            let badge = findChild(bell, "notificationBadge");
            let glyphRight = bell.content.x + bell.content.width;
            let glyphX = bell.content.x;
            for (let count of [1, 12, 999]) {
                bar.notificationData = {count: count};
                compare(bell.content.x, glyphX);
                verify(badge.x >= glyphRight - 3 && badge.x <= glyphRight);
                verify(badge.y < bell.content.y);
                verify(badge.x + badge.width < bell.width);
            }
            grabImage(bell).save("/tmp/quickshell-bell-badge.png");
        }
    }
}
