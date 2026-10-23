import QtQuick
import QtTest
import ".."
import "../SettingsModel.js" as Settings

Item {
    id: scene
    width: 1366; height: 80
    Bar { id: bar; width: parent.width; clockText: "Oct 08   12:34 PM   Thu" }
    SettingsBarEditor {
        id: editor
        visible: false
        width: 700
        settings: ({adaptiveColors:true, clockFormat:"hh:mm"})
        onEdited: (key, value) => settings = Object.assign({}, settings, {[key]:value})
    }
    SettingsSlider {
        id: geometrySlider
        visible: false
        width: 400
        label: "Padding drag"
        editInterval: 32
        settingValue: 0
        onEdited: value => settingValue = value
    }
    SignalSpy { id: dragEdits; target: geometrySlider; signalName: "edited" }
    TestCase {
        name: "BarRegressions"
        when: windowShown
        function cleanup() { geometrySlider.visible = false; bar.settings = {}; bar.statusIconsOnly = false; bar.width = scene.width; bar.mediaData = {playing: false}; bar.trayModel = []; bar.notificationData = {count: 0}; bar.statusData = {workspaces: [], audio: {}, network: {}, bluetooth: {}, battery: {}}; }
        function connectorConfig(position, items, options) {
            bar.width = position === "left" || position === "right" ? 40 : scene.width;
            return {bar:Object.assign({position:position, background:"on", spacing:20}, options || {}),
                items:Object.keys(bar.moduleItems).map(id => Object.assign({id:id, side:"left", enabled:!!items[id]}, items[id] || {}))};
        }
        function test_asymmetricPaddingConnectorsAndSymmetricCentering() {
            let links = findChild(bar, "panelConnectors");
            bar.statusData = {workspaces:[{id:1,name:"1"},{id:2,name:"2"}],audio:{},network:{},bluetooth:{},battery:{}};
            for (let edge of ["top","bottom","left","right"]) {
                bar.settings = connectorConfig(edge, {audio:{},wifi:{side:"right"},calendar:{side:"center"},workspaces:{}},
                    {contentPaddingTop:100,contentPaddingBottom:0,contentPaddingLeft:100,contentPaddingRight:100});
                if (bar.vertical) bar.width = bar.implicitWidth;
                wait(0);
                let audio = bar.moduleItems.audio;
                let cross = bar.vertical ? audio.x + audio.width / 2 : audio.y + audio.height / 2;
                verify(links.segments.length > 0);
                for (let segment of links.segments) fuzzyCompare(segment.cross, cross, 0.01);
                if (!bar.vertical) {
                    let clock = bar.moduleItems.calendar;
                    fuzzyCompare(clock.x + clock.width / 2, bar.width / 2, 0.01);
                    compare(bar.wallpaperColors.bandHeight, bar.contentHeight);
                    compare(bar.wallpaperColors.regionOffsetY, bar.screenOffsetY + 100);
                    compare(bar.wallpaperColors.offsetY, bar.screenOffsetY);
                } else {
                    compare(bar.wallpaperColors.bandWidth, bar.contentWidth);
                    compare(bar.wallpaperColors.regionOffsetX, bar.screenOffsetX + 100);
                }
            }
        }
        function test_paddingDragCoalescesAndFlushesFinalValue() {
            geometrySlider.visible = true;
            geometrySlider.settingValue = 0;
            dragEdits.clear();
            let track = findChild(geometrySlider,"effectSlider");
            mousePress(track, 20, track.height / 2);
            for (let x = 25; x < track.width - 20; x += 5) mouseMove(track,x,track.height/2,0);
            verify(dragEdits.count < 8, "Pointer motion should coalesce into bounded updates");
            let value = Math.round(track.value);
            mouseRelease(track,track.width - 20,track.height/2);
            compare(geometrySlider.pendingDisplayValue,undefined);
            compare(geometrySlider.settingValue,Math.round(track.value));
            verify(geometrySlider.settingValue >= value);
        }
        function test_centerAllGroupsTogetherAndPreserveMembership() {
            for (let edge of ["top","bottom","left","right"]) {
                for (let knots of [true,false]) {
                    bar.settings = connectorConfig(edge, {audio:{side:"left"},calendar:{side:"center"},
                        wifi:{side:"right",pillGroup:"status"},bluetooth:{side:"right",pillGroup:"status"}},
                        {centerItems:true,hyprknots:knots,spacing:18,groupSpacing:7,contentPaddingLeft:13,contentPaddingRight:17});
                    if (bar.vertical) bar.width = bar.implicitWidth;
                    wait(0);
                    let savedItems = JSON.stringify(bar.settings.items);
                    compare(bar.orderedItems("left"),["audio"]);
                    compare(bar.orderedItems("center"),["calendar"]);
                    compare(bar.orderedItems("right"),["wifi","bluetooth"]);
                    let audio = bar.moduleItems.audio, clock = bar.moduleItems.calendar;
                    let wifi = bar.moduleItems.wifi, bluetooth = bar.moduleItems.bluetooth;
                    let start = item => bar.vertical ? item.y : item.x;
                    let size = item => bar.vertical ? item.height : item.width;
                    fuzzyCompare((start(audio) + start(bluetooth) + size(bluetooth)) / 2
                        + (bar.vertical ? bar.screenOffsetY : bar.screenOffsetX),
                        (bar.vertical ? bar.screenHeight : bar.screenWidth) / 2,0.01);
                    fuzzyCompare(start(clock) - start(audio) - size(audio),bar.sectionGap,0.01);
                    fuzzyCompare(start(wifi) - start(clock) - size(clock),bar.sectionGap,0.01);
                    fuzzyCompare(start(bluetooth) - start(wifi) - size(wifi),7,0.01);
                    compare(bar.sharedPills.length,1);
                    compare(bar.menuRect("audio").x,audio.x);
                    bar.settings = Object.assign({},bar.settings,{bar:Object.assign({},bar.settings.bar,{centerItems:false})});
                    wait(0);
                    compare(JSON.stringify(bar.settings.items),savedItems);
                    fuzzyCompare(start(audio),bar.vertical ? bar.insetTop : bar.insetLeft,0.01);
                }
            }
        }
        function test_centeredLayoutSkipsEmptyGroups() {
            for (let side of ["left","center","right"]) {
                let modules = {audio:{side:side}};
                bar.settings = connectorConfig("top",modules,{centerItems:true});
                wait(0);
                let item = bar.moduleItems.audio;
                fuzzyCompare(item.x + item.width / 2 + bar.screenOffsetX,bar.screenWidth/2,0.01);
            }
            bar.settings = connectorConfig("top",{audio:{side:"left"},wifi:{side:"right"}},{centerItems:true});
            wait(0);
            fuzzyCompare(bar.moduleItems.wifi.x - bar.moduleItems.audio.x - bar.moduleItems.audio.width,bar.sectionGap,0.01);
        }
        function test_centerAllItemsSwitch() {
            editor.settings = {adaptiveColors:true,clockFormat:"hh:mm"};
            let control = findChild(editor,"centerItemsControl");
            verify(!control.checked);
            control.checked = true; control.toggled();
            compare(editor.settings.centerItems,true);
            control.checked = false; control.toggled();
            compare(editor.settings.centerItems,false);
        }
        function test_compactSpacingAndWorkspaceGaps() {
            bar.statusData = {workspaces:[{id:1,name:"1"},{id:2,name:"2"}], audio:{}, network:{}, bluetooth:{}, battery:{}};
            for (let edge of ["top", "bottom", "left", "right"]) {
                for (let enabled of [true, false, true]) {
                    bar.settings = connectorConfig(edge, {audio:{},wifi:{},workspaces:{}}, {spacing:20,compactSpacing:3,hyprknots:enabled});
                    wait(0);
                    let audio = bar.moduleItems.audio, wifi = bar.moduleItems.wifi;
                    compare(bar.vertical ? wifi.y - audio.y - audio.height : wifi.x - audio.x - audio.width, enabled ? 20 : 3);
                    compare(bar.moduleItems.workspaces.spacing, enabled ? 20 : 3);
                    compare(bar.settings.bar.spacing, 20);
                }
            }
        }
        function test_fourSideMarginsAndInnerPadding() {
            for (let edge of ["top", "bottom", "left", "right"]) {
                let config = {position:edge,marginTop:5,marginSide:10};
                let margins = Settings.screenMargins(config);
                compare(margins[edge], 5);
                let vertical = edge === "left" || edge === "right";
                compare(margins[vertical ? "top" : "left"], 10);
                Object.assign(config, {screenMarginTop:11,screenMarginBottom:12,screenMarginLeft:13,screenMarginRight:14});
                compare(Settings.screenMargins(config), {top:11,bottom:12,left:13,right:14});
                bar.settings = connectorConfig(edge, {audio:{},wifi:{side:"right"}}, {verticalPresentation:"compact",hyprknots:false});
                wait(0);
                let beforeWidth = bar.implicitWidth, beforeHeight = bar.implicitHeight;
                let beforeX = bar.moduleItems.audio.x, beforeY = bar.moduleItems.audio.y;
                bar.settings = Object.assign({}, bar.settings, {bar:Object.assign({},bar.settings.bar,
                    {contentPaddingTop:7,contentPaddingBottom:11,contentPaddingLeft:13,contentPaddingRight:17})});
                if (vertical) bar.width = bar.implicitWidth;
                wait(0);
                compare(bar.moduleItems.audio.x, beforeX + 13 + (vertical ? (bar.width - 40 - 30) / 2 : 0));
                compare(bar.moduleItems.audio.y, beforeY + 7);
                compare(bar.implicitHeight, beforeHeight + 18);
                if (vertical) compare(bar.implicitWidth, beforeWidth + 30);
                let last = bar.moduleItems.wifi;
                if (!vertical) compare(last.x + last.width, bar.width - 17);
                else compare(last.y + last.height, bar.height - 11);
                verify(bar.menuRect("audio").x === bar.moduleItems.audio.x);
            }
        }
        function test_spacingControlsAndIndependentReset() {
            editor.settings = {spacing:18, hyprknots:false,adaptiveColors:true,clockFormat:"hh:mm"};
            findChild(editor,"compactSpacingControl").commitDisplayValue(5);
            compare(editor.settings.compactSpacing,5);
            compare(editor.settings.spacing,18);
            for (let side of ["Top","Bottom","Left","Right"]) {
                let margin = findChild(editor,"screenMargin" + side + "Control");
                verify(margin.inherited);
                margin.commitDisplayValue(23);
                compare(editor.settings["screenMargin" + side],23);
                margin.edited("");
                compare(editor.settings["screenMargin" + side],null);
                verify(margin.inherited);
                let padding = findChild(editor,"contentPadding" + side + "Control");
                padding.commitDisplayValue(9);
                compare(editor.settings["contentPadding" + side],9);
                padding.edited("");
                compare(editor.settings["contentPadding" + side],0);
            }
        }
        function test_hyprknotsBareNeighbors() {
            let links = findChild(bar, "panelConnectors");
            for (let position of ["top", "bottom", "left", "right"]) {
                for (let modes of [["on","on","on",true], ["off","on","on",false],
                        ["on","off","on",false], ["off","off","on",false],
                        ["inherit","inherit","off",false], ["on","on","off",true]]) {
                    bar.settings = connectorConfig(position, {audio:{background:modes[0]}, wifi:{background:modes[1]}}, {background:modes[2]});
                    compare(links.segments.length, 1);
                    compare(links.segments[0].knots.length > 0, modes[3]);
                    verify(links.segments[0].end > links.segments[0].start);
                }
                bar.settings = connectorConfig(position, {audio:{pillGroup:"pair", sharedBackground:"off"}, wifi:{pillGroup:"pair"}});
                compare(links.segments.length, 1);
                compare(links.segments[0].knots.length, 0);
                bar.settings = connectorConfig(position, {audio:{pillGroup:"pair", sharedBackground:"on"}, wifi:{pillGroup:"pair"}});
                compare(links.segments.length, 0);
                // Both open rails around the center keep their knots with bare
                // endpoints; the gap inside the right section remains a line.
                bar.settings = connectorConfig(position, {audio:{side:"left", background:"off"},
                    calendar:{side:"center", background:"off"},
                    wifi:{side:"right", background:"off"}, bluetooth:{side:"right", background:"off"}});
                compare(links.segments.length, 3);
                verify(links.segments[0].knots.length > 0);
                verify(links.segments[1].knots.length > 0);
                compare(links.segments[2].knots.length, 0);
            }
        }
        function test_hyprknotsContainerPills() {
            let links = findChild(bar, "panelConnectors");
            bar.statusData = {workspaces:[{id:1,name:"1"},{id:2,name:"2"}], audio:{}, network:{}, bluetooth:{}, battery:{}};
            bar.mediaData = {playing:true, title:"Track", levels:[0.3,0.8]};
            bar.trayModel = [{icon:Qt.resolvedUrl("../icons/preview-tray.svg")}];
            for (let position of ["top", "bottom", "left", "right"]) {
                for (let id of ["workspaces", "media", "tray"]) {
                    for (let mode of ["off", "on", "off"]) {
                        let items = {audio:{background:"on"}};
                        items[id] = {background:mode};
                        bar.settings = connectorConfig(position, items);
                        // Allow Grid/Repeater positioning to settle before checking gaps.
                        wait(0);
                        compare(links.segments.length, id === "workspaces" ? 2 : 1);
                        for (let segment of links.segments)
                            compare(segment.knots.length > 0, mode === "on");
                    }
                }
            }
        }
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
