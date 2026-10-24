import QtQuick
import QtTest
import ".."
import "../SettingsModel.js" as Settings
import "../AdaptiveColors.js" as Colors

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
    Rectangle {
        id: inkBackground
        visible: false
        width: 400; height: 40
        color: "black"
        Pill {
            id: inkSample
            anchors.fill: parent
            settings: ({uniformItems:true, uniformGlyphHeight:12, background:"off", outlineFree:true,
                textColor:"#ffffff", iconColor:"#ffffff"})
        }
    }
    SignalSpy { id: dragEdits; target: geometrySlider; signalName: "edited" }
    TestCase {
        name: "BarRegressions"
        when: windowShown
        function cleanup() { inkBackground.visible = false; geometrySlider.visible = false; bar.settings = {}; bar.statusIconsOnly = false; bar.width = scene.width; bar.mediaData = {playing: false}; bar.trayModel = []; bar.notificationData = {count: 0}; bar.statusData = {workspaces: [], audio: {}, network: {}, bluetooth: {}, battery: {}}; }
        function connectorConfig(position, items, options) {
            bar.width = position === "left" || position === "right" ? 40 : scene.width;
            return {bar:Object.assign({position:position, background:"on", spacing:20}, options || {}),
                items:Object.keys(bar.moduleItems).map(id => Object.assign({id:id, side:"left", enabled:!!items[id]}, items[id] || {}))};
        }
        function test_requestedDefaultPillProportions_data() {
            let rows = [];
            for (let edge of ["top","bottom","left","right"])
                for (let thickness of [30,40,64])
                    for (let uniform of [false,true])
                        for (let centered of [false,true])
                            rows.push({tag:[edge,thickness,uniform,centered].join("-"),edge:edge,
                                thickness:thickness,uniform:uniform,centered:centered});
            return rows;
        }
        function test_requestedDefaultPillProportions(data) {
            bar.statusData = {workspaces:[{id:1,name:"1"},{id:12,name:"12"}],
                audio:{icon:"󰕾",text:"48%"},network:{text:"󰤨"},bluetooth:{},battery:{}};
            bar.mediaData = {playing:true,title:"Song",levels:[1,0.8]};
            bar.trayModel = [{icon:Qt.resolvedUrl("../icons/preview-tray.svg")}];
            let modules = {launcher:{},settings:{},audio:{},wifi:{},workspaces:{},media:{},
                calendar:{side:"center"},tray:{side:"right"},power:{side:"right"}};
            for (let full of ["on","off"]) {
                bar.settings = connectorConfig(data.edge,modules,{height:data.thickness,iconSize:0,
                    fullBackground:full,uniformItems:data.uniform,centerItems:data.centered,hyprknots:false});
                if (bar.vertical) bar.width = bar.implicitWidth;
                wait(0);
                let margins = Settings.screenMargins(bar.settings.bar);
                compare(margins[bar.vertical ? "top" : "left"],10,"outer leading margin");
                compare(margins[bar.vertical ? "bottom" : "right"],10,"outer trailing margin");
                let fullPill = findChild(bar,"fullPanelPill");
                compare(fullPill.visible,full === "on");
                let crossSize = bar.vertical ? bar.width : bar.height;
                fuzzyCompare(crossSize,data.thickness,0.01,"panel thickness");
                for (let id of ["launcher","settings","audio","wifi","calendar","power"]) {
                    let item = bar.moduleItems[id], background = findChild(item,"pillBackground");
                    fuzzyCompare(background.height,data.thickness * 0.6,0.01,id + " own pill height");
                    if (data.uniform && !bar.iconsOnly && !item.labelIsIcon && !item.shownIcon.length)
                        fuzzyCompare(item.uniformTextHeight,data.thickness * 10 / 30,0.01,id + " text scale");
                    else fuzzyCompare(item.glyphRect.height,data.thickness * (data.uniform ? 12 / 30 : 0.48),0.01,id + " ink height");
                    let cross = bar.vertical ? item.x + item.width / 2 : item.y + item.height / 2;
                    fuzzyCompare(cross,crossSize / 2,0.01,id + " cross-axis center");
                }
                let audio = bar.moduleItems.audio;
                compare(audio.effectiveLeftPadding,5,"base left padding");
                compare(audio.effectiveRightPadding,5,"base right padding");
                let ends = ["left","center","right"].reduce((all, side) => all.concat(bar.orderedItems(side)), []);
                let first = bar.moduleItems[ends[0]], last = bar.moduleItems[ends[ends.length - 1]];
                let leading = bar.vertical ? first.y - fullPill.y : first.x - fullPill.x;
                let trailing = bar.vertical ? fullPill.y + fullPill.height - last.y - last.height
                    : fullPill.x + fullPill.width - last.x - last.width;
                fuzzyCompare(leading,full === "on" ? 5 : 0,0.01,"leading content inset");
                fuzzyCompare(trailing,full === "on" ? 5 : 0,0.01,"trailing content inset");
                for (let number of [1,12]) {
                    let workspace = findChild(bar,"workspace" + number);
                    fuzzyCompare(workspace.height,data.thickness * 0.6 * 0.72,0.01,"workspace is smaller than status controls");
                    let ink = workspace.textGlyphRect;
                    verify(ink.height <= workspace.height * 0.8 + 0.01,"number fits vertically");
                    verify(ink.width <= workspace.width * 0.8 + 0.01,"number fits horizontally");
                    fuzzyCompare(ink.x + ink.width / 2,workspace.width / 2,0.5,"number centered");
                    if (data.uniform && number === 1)
                        fuzzyCompare(ink.height,workspace.height * 0.65,0.01,"workspace number fits smaller circle");
                }
                fuzzyCompare(findChild(bar,"mediaSpectrum").height,data.thickness * (data.uniform ? 0.4 : 0.48),0.01,"media ink height");
                fuzzyCompare(bar.moduleItems.media.height,data.thickness * 0.6,0.01,"media pill height");
                if (data.uniform && !bar.iconsOnly)
                    fuzzyCompare(bar.moduleItems.media.item.uniformTextHeight,data.thickness * 10 / 30,0.01,"media matches clock text");
                fuzzyCompare(bar.moduleItems.tray.trayIconSize,data.thickness * (data.uniform ? 0.4 : 0.48),0.01,"tray artwork height");
                fuzzyCompare(findChild(bar.moduleItems.tray,"trayIcon").height,data.thickness * 0.6,0.01,"tray pill height");
            }
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
        function test_centeredIconsHideLabelsAndRestoreNormalText() {
            bar.statusData = {workspaces:[{id:1,name:"Dev",active:true},{id:12,name:"Chat"}],
                audio:{icon:"󰕾",text:"48%"},network:{text:"󰤨"},bluetooth:{text:"󰂯"},battery:{present:true,text:"󰁹 82%"}};
            bar.mediaData = {playing:true,title:"Artist — A song",levels:[0.2,0.8,0.4]};
            bar.notificationData = {count:42};
            bar.trayModel = [{icon:Qt.resolvedUrl("../icons/preview-tray.svg")}];
            for (let edge of ["top","bottom"]) {
                let modules = {};
                for (let id of Object.keys(bar.moduleItems)) modules[id] = {};
                modules.calendar = {side:"center"};
                modules.audio = {side:"right",paddingLeft:20,paddingRight:-5};
                bar.settings = connectorConfig(edge,modules,{centerItems:true,iconSize:16});
                wait(0);
                let saved = JSON.stringify(bar.settings.items);
                for (let id of ["launcher","settings","calendar","audio","wifi","bluetooth","notifications","battery","power"]) {
                    let item = bar.moduleItems[id];
                    compare(item.shownText,"",id + " text");
                    compare(item.width,bar.panelSlotSize,id + " icon slot");
                    if (id !== "launcher" && id !== "settings") verify(item.shownIcon.length > 0,id + " icon");
                }
                compare(bar.moduleItems.calendar.shownIcon,"󰃭");
                verify(findChild(bar,"distroGlassLogo").visible);
                verify(findChild(bar,"settingsGlassCog").visible);
                let first = findChild(bar,"workspace1"), second = findChild(bar,"workspace12");
                compare(first.shownText,"1"); compare(second.shownText,"12");
                compare(first.shownIcon,""); compare(second.shownIcon,"");
                verify(first.content.font.pixelSize < first.effectiveIconSize);
                verify(second.content.font.pixelSize < second.effectiveIconSize);
                compare(first.width,bar.workspacePillSize);
                compare(second.width,bar.workspacePillSize);
                compare(first.height,bar.workspacePillSize);
                compare(second.height,bar.workspacePillSize);
                verify(first.textGlyphRect.width <= first.width * 0.8 + 0.01);
                verify(second.textGlyphRect.width <= second.width * 0.8 + 0.01);
                compare(bar.moduleItems.media.item.shownText,"");
                compare(findChild(bar,"mediaSpectrum").barCount,5);
                verify(!findChild(bar,"notificationBadge").visible);
                bar.settings = Object.assign({},bar.settings,{bar:Object.assign({},bar.settings.bar,{centerItems:false})});
                wait(0);
                compare(bar.moduleItems.calendar.shownText,bar.clockText);
                compare(bar.moduleItems.audio.shownText,"48%");
                compare(bar.moduleItems.battery.shownText,"82%");
                compare(findChild(bar,"workspace1").shownText,"Dev");
                compare(bar.moduleItems.media.item.shownText,"Artist — A song");
                verify(findChild(bar,"notificationBadge").visible);
                compare(JSON.stringify(bar.settings.items),saved);
            }
        }
        function test_workspacePillsStayCircularAcrossLabelsAndEdges() {
            bar.statusData = {workspaces:[{id:1,name:"1",active:true},{id:12,name:"12"},{id:123,name:"Dev"}],audio:{},network:{},bluetooth:{},battery:{}};
            for (let edge of ["top","bottom","left","right"]) {
                for (let uniform of [false,true]) {
                    bar.settings = connectorConfig(edge,{workspaces:{radius:0,fontSize:9}},{uniformItems:uniform});
                    wait(0);
                    for (let id of [1,12,123]) {
                        let pill = findChild(bar,"workspace" + id);
                        let background = findChild(pill,"pillBackground");
                        fuzzyCompare(pill.width,pill.height,0.01);
                        fuzzyCompare(background.width,background.height,0.01);
                        fuzzyCompare(background.radius,background.width / 2,0.01);
                        fuzzyCompare(pill.textGlyphRect.x + pill.textGlyphRect.width / 2,pill.width / 2,0.01,"workspace label centered");
                        verify(pill.textGlyphRect.width <= pill.width * 0.8 + 0.01,"explicit font fits width");
                        verify(pill.textGlyphRect.height <= pill.height * 0.8 + 0.01,"explicit font fits height");
                        verify(pill.content.width >= pill.content.implicitWidth,"workspace label is not elided");
                    }
                }
            }
        }
        function test_centeredWorkspacePillsUseUniformIconSlots() {
            bar.statusData = {workspaces:[{id:1,name:"1",active:true},{id:12,name:"12"}],audio:{},network:{},bluetooth:{},battery:{}};
            for (let edge of ["top","bottom"]) {
                bar.settings = connectorConfig(edge,{workspaces:{},calendar:{side:"center"}},{centerItems:false,iconSize:15});
                wait(0);
                let dimensions = [1,12].map(id => {
                    let pill=findChild(bar,"workspace"+id);
                    return {width:pill.width,height:pill.height,font:pill.content.font.pixelSize};
                });
                bar.settings = Object.assign({},bar.settings,{bar:Object.assign({},bar.settings.bar,{centerItems:true})});
                wait(0);
                [1,12].forEach((id,i) => {
                    let pill=findChild(bar,"workspace"+id);
                    compare(pill.shownText,String(id));
                    fuzzyCompare(pill.width,bar.workspacePillSize,0.01);
                    fuzzyCompare(pill.height,bar.workspacePillSize,0.01);
                    compare(pill.content.font.pixelSize,dimensions[i].font);
                });
                bar.settings = Object.assign({},bar.settings,{bar:Object.assign({},bar.settings.bar,{centerItems:false})});
                wait(0);
                [1,12].forEach((id,i) => {
                    let pill=findChild(bar,"workspace"+id);
                    fuzzyCompare(pill.width,dimensions[i].width,0.01);
                    fuzzyCompare(pill.height,dimensions[i].height,0.01);
                    compare(pill.content.font.pixelSize,dimensions[i].font);
                });
            }
        }
        function test_centeredItemsShareSlotsPillsAndGlyphCenters() {
            bar.statusData = {workspaces:[{id:1,name:"1",active:true},{id:2,name:"2"}],
                audio:{icon:"󰕾",text:"48%"},network:{text:"󰤨"},bluetooth:{text:"󰂯"},
                battery:{present:true,text:"󰁹 82%"}};
            bar.mediaData = {playing:true,title:"Song",levels:[0.2,0.8,0.4]};
            bar.trayModel = [{icon:Qt.resolvedUrl("../icons/preview-tray.svg")},
                {icon:Qt.resolvedUrl("../icons/preview-tray.svg")}];
            bar.notificationData = {count:3};
            let modules = {launcher:{side:"left"},settings:{side:"left"},workspaces:{side:"left"},
                media:{side:"left"},calendar:{side:"center"},tray:{side:"right"},notifications:{side:"right"},
                audio:{side:"right"},wifi:{side:"right"},bluetooth:{side:"right"},battery:{side:"right"},power:{side:"right"}};
            for (let edge of ["top","bottom"]) for (let mode of ["off","on"]) {
                bar.settings = connectorConfig(edge,modules,{centerItems:true,uniformItems:true,iconSize:20,
                    height:30,background:mode,fullBackground:"on",spacing:7,hyprknots:false,compactSpacing:7});
                wait(0);
                let ids = ["left","center","right"].reduce((all,side) => all.concat(bar.orderedItems(side)),[]);
                let previous = null;
                for (let id of ids) {
                    let item = bar.moduleItems[id];
                    fuzzyCompare(item.height,id === "workspaces" ? bar.workspacePillSize : bar.panelSlotSize,0.01,id + " slot height");
                    if (id !== "workspaces" && id !== "tray")
                        fuzzyCompare(item.width,bar.panelSlotSize,0.01,id + " slot width");
                    if (item.glyphRect && item.glyphRect.width > 0) {
                        let tolerance = id === "settings" ? 1 : 0.01;
                        fuzzyCompare(item.x + item.glyphRect.x + item.glyphRect.width / 2,
                            item.x + item.width / 2,tolerance,id + " glyph center x");
                        fuzzyCompare(item.y + item.glyphRect.y + item.glyphRect.height / 2,
                            item.y + item.height / 2,tolerance,id + " glyph center y");
                    }
                    if (mode === "on" && id !== "tray" && id !== "workspaces") {
                        let background = findChild(item,"pillBackground");
                        fuzzyCompare(background.width,bar.panelSlotSize,0.01,id + " pill width");
                        fuzzyCompare(background.height,bar.panelSlotSize,0.01,id + " pill height");
                        fuzzyCompare(background.radius,bar.panelSlotSize / 2,0.01,id + " round pill");
                    }
                    if (previous) fuzzyCompare(item.x - previous.x - previous.width,7,0.01,id + " gap");
                    previous = item;
                }
                for (let workspace of [findChild(bar,"workspace1"),findChild(bar,"workspace2")]) {
                    fuzzyCompare(workspace.width,bar.workspacePillSize,0.01,"workspace pill width");
                    fuzzyCompare(workspace.height,bar.workspacePillSize,0.01,"workspace pill height");
                    fuzzyCompare(workspace.x + workspace.width / 2,
                        workspace.x + workspace.glyphRect.x + workspace.glyphRect.width / 2,1,"workspace glyph center");
                }
                let trayIcons = findChild(bar.moduleItems.tray,"trayIcon").parent.children.filter(child => child.objectName === "trayIcon");
                for (let trayIcon of trayIcons) {
                    fuzzyCompare(trayIcon.width,bar.panelSlotSize,0.01,"tray slot width");
                    fuzzyCompare(trayIcon.height,bar.panelSlotSize,0.01,"tray slot height");
                    if (mode === "on") {
                        let background = findChild(trayIcon,"pillBackground");
                        fuzzyCompare(background.width,bar.panelSlotSize,0.01,"tray pill width");
                        fuzzyCompare(background.height,bar.panelSlotSize,0.01,"tray pill height");
                        fuzzyCompare(background.radius,bar.panelSlotSize / 2,0.01,"tray round pill");
                    }
                }
                let full = findChild(bar,"fullPanelPill");
                verify(full.visible);
                fuzzyCompare(bar.panelSlotSize / full.height,0.6,0.01,"inner pills occupy 60% of full pill height");
                fuzzyCompare(full.x + full.width / 2,bar.width / 2,0.01,"full pill center");
                fuzzyCompare(bar.moduleItems[ids[0]].x - full.x,bar.fullPillInset,0.01,"full pill leading cap");
                fuzzyCompare(full.x + full.width - bar.moduleItems[ids[ids.length - 1]].x
                    - bar.moduleItems[ids[ids.length - 1]].width,bar.fullPillInset,0.01,"full pill trailing cap");
                fuzzyCompare(full.height,bar.panelSlotSize + 2 * bar.panelItemInset,0.01,"full pill vertical inset");
                fuzzyCompare(full.y,0,0.01,"full pill top");
                for (let id of ids) {
                    let item = bar.moduleItems[id];
                    let inset = bar.panelItemInset + (id === "workspaces" ? (bar.panelSlotSize - bar.workspacePillSize) / 2 : 0);
                    fuzzyCompare(item.y - full.y,inset,0.01,id + " top inset");
                    fuzzyCompare(full.y + full.height - item.y - item.height,
                        inset,0.01,id + " bottom inset");
                }
            }
        }
        function test_centeredGapReachesEveryGroupWorkspaceAndTray() {
            bar.statusData = {workspaces:[{id:1,name:"1",active:true},{id:2,name:"2"}],audio:{},network:{},bluetooth:{},battery:{}};
            bar.mediaData = {playing:true,title:"Song",levels:[0.2,0.8]};
            bar.trayModel = [{icon:Qt.resolvedUrl("../icons/preview-tray.svg")},{icon:Qt.resolvedUrl("../icons/preview-tray.svg")}];
            for (let edge of ["top","bottom","left","right"]) {
                for (let knots of [true,false]) for (let gap of [0,5,20]) {
                    bar.settings = connectorConfig(edge,{workspaces:{side:"left"},media:{side:"left"},calendar:{side:"center"},
                        audio:{side:"right",pillGroup:"status"},wifi:{side:"right",pillGroup:"status"},tray:{side:"right"}},
                        {centerItems:true,hyprknots:knots,spacing:knots ? gap : 27,compactSpacing:knots ? 1 : gap,groupSpacing:29});
                    if (bar.vertical) bar.width = bar.implicitWidth;
                    wait(0);
                    let ids = ["left","center","right"].reduce((ids,side) => ids.concat(bar.orderedItems(side)),[]);
                    for (let i = 1; i < ids.length; ++i) {
                        let a=bar.moduleItems[ids[i-1]], b=bar.moduleItems[ids[i]];
                        fuzzyCompare(bar.vertical ? b.y-a.y-a.height : b.x-a.x-a.width,gap,0.01,ids[i-1] + " to " + ids[i]);
                    }
                    let row = bar.moduleItems.workspaces;
                    compare(row.spacing,gap);
                    let first = findChild(bar,"workspace1"), second = findChild(bar,"workspace2");
                    fuzzyCompare(bar.vertical ? second.y-first.y-first.height : second.x-first.x-first.width,gap,0.01);
                    let tray = findChild(bar.moduleItems.tray,"trayIcon").parent;
                    compare(tray.spacing,gap);
                    let icons = tray.children.filter(child => child.objectName === "trayIcon");
                    if (!bar.vertical) {
                        fuzzyCompare(icons[1].x-icons[0].x-icons[0].width,gap,0.01);
                        compare(bar.moduleItems.tray.height,bar.panelSlotSize);
                    }
                }
            }
        }
        function test_spacingControlsFollowCurrentMode() {
            editor.settings = {adaptiveColors:true,clockFormat:"hh:mm",centerItems:true,hyprknots:false};
            verify(findChild(editor,"compactSpacingControl").enabled);
            verify(!findChild(editor,"spacingControl").enabled);
            verify(!findChild(editor,"groupSpacingControl").enabled);
            editor.settings = Object.assign({},editor.settings,{centerItems:false,hyprknots:true});
            verify(!findChild(editor,"compactSpacingControl").enabled);
            verify(findChild(editor,"spacingControl").enabled);
            verify(findChild(editor,"groupSpacingControl").enabled);
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
                    fuzzyCompare(start(bluetooth) - start(wifi) - size(wifi),bar.itemSpacing,0.01);
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
        function test_uniformSpacingMeasuresVisibleGlyphsInBothLayouts() {
            bar.statusData = {workspaces:[],audio:{},network:{text:"󰤨"},bluetooth:{text:"󰂯"},battery:{}};
            for (let centered of [false,true]) for (let knots of [false,true]) for (let gap of [0,5,20]) {
                bar.settings = connectorConfig("top",{
                    wifi:{side:"left",pillGroup:"status",iconSize:9,paddingLeft:30,paddingRight:25,spacingRight:12},
                    bluetooth:{side:"left",pillGroup:"status",iconSize:32,paddingLeft:20,paddingRight:20,spacingLeft:30},
                    power:{side:"left",iconSize:40}},
                    {uniformItems:true,centerItems:centered,iconSize:15,hyprknots:knots,
                        spacing:knots ? gap : 29,compactSpacing:knots ? 27 : gap,groupSpacing:25});
                wait(0);
                let ids=bar.orderedItems("left");
                for (let i=0; i<ids.length; ++i) {
                    let item=bar.moduleItems[ids[i]], ink=item.glyphRect;
                    compare(item.effectiveIconSize,Settings.item(bar.settings,ids[i]).iconSize,ids[i] + " individual icon size");
                    if (centered) {
                        fuzzyCompare(item.width,bar.panelSlotSize,0.01,ids[i] + " icon slot width");
                        fuzzyCompare(item.height,bar.panelSlotSize,0.01,ids[i] + " icon slot height");
                        fuzzyCompare(ink.x+ink.width/2,item.width/2,0.01,ids[i] + " centered glyph");
                        fuzzyCompare(ink.y+ink.height/2,item.height/2,0.01,ids[i] + " centered glyph");
                    } else {
                        fuzzyCompare(ink.x+ink.width/2,item.width/2,0.01,ids[i] + " centered glyph");
                        let background = findChild(item,"pillBackground");
                        compare(background.width,background.height,ids[i] + " circular pill");
                    }
                    if (i) {
                        let previous=bar.moduleItems[ids[i-1]];
                        fuzzyCompare(item.x-previous.x-previous.width,gap,0.01,"pill gap");
                    }
                }
                compare(bar.appearance("bluetooth").iconSize,32);
                bar.settings=Object.assign({},bar.settings,{bar:Object.assign({},bar.settings.bar,{uniformItems:false})});
                compare(bar.appearance("bluetooth").iconSize,32,"individual setting remains saved");
            }
        }
        function test_uniformSizeCoversCustomMarksMediaTrayAndCompactWorkspaces() {
            bar.statusData={workspaces:[{id:1,name:"1"},{id:12,name:"12"}],audio:{icon:"󰕾",text:"48%"},network:{},bluetooth:{},battery:{present:true,text:"󰁹 82%"}};
            bar.mediaData={playing:true,title:"Song",levels:[0.2,0.8]};
            bar.trayModel=[{icon:Qt.resolvedUrl("../icons/preview-tray.svg")},{icon:Qt.resolvedUrl("../icons/preview-tray.svg")}];
            for (let centered of [false,true]) {
                let modules={}; for(let id of Object.keys(bar.moduleItems)) modules[id]={};
                modules.workspaces={iconSize:9,fontSize:9};
                bar.settings=connectorConfig("top",modules,{uniformItems:true,centerItems:centered,iconSize:15,hyprknots:false,compactSpacing:5});
                wait(0);
                for (let id of ["launcher","settings","calendar","audio","wifi","bluetooth","notifications","battery","power"])
                    compare(bar.moduleItems[id].effectiveIconSize,15,id);
                compare(findChild(bar,"distroGlassLogo").iconSize,15);
                fuzzyCompare(bar.moduleItems.settings.glyphRect.height,15,0.01);
                compare(findChild(bar,"mediaSpectrum").width,15);
                compare(findChild(bar,"mediaSpectrum").height,15);
                compare(bar.moduleItems.tray.trayIconSize,15);
                compare(findChild(bar,"workspace1").content.font.pixelSize,128);
                if (!centered) {
                    let height = bar.moduleItems.audio.height;
                    for (let id of ["launcher","settings","calendar","tray","media","notifications","wifi","bluetooth","battery","power"])
                        compare(bar.moduleItems[id].height,height,id + " uniform height");
                }
                if (centered) {
                    compare(findChild(bar,"workspace12").height,bar.workspacePillSize);
                    compare(bar.moduleItems.tray.trayTargetSize,bar.panelSlotSize);
                } else {
                    let workspace = findChild(bar,"workspace12");
                    compare(workspace.height,workspace.width);
                    compare(workspace.height,bar.workspacePillSize);
                    verify(workspace.height < bar.moduleItems.media.height,"workspace circle is smaller than media pill");
                    verify(workspace.glyphRect.height < findChild(bar,"mediaSpectrum").height,"workspace number is smaller than spectrum");
                }
                compare(bar.moduleItems.workspaces.spacing,5);
                compare(findChild(bar.moduleItems.tray,"trayIcon").parent.spacing,5);
            }
        }
        function test_uniformIndividualSizesAndMatchingClockAudioFonts() {
            bar.statusData = {workspaces:[],audio:{icon:"󰕾",text:"100%"},network:{text:"󰤨"},bluetooth:{},battery:{}};
            for (let edge of ["top","bottom","left","right"]) {
                bar.settings = connectorConfig(edge,{calendar:{fontSize:10},audio:{fontSize:10},
                    wifi:{iconSize:24},power:{}},{height:30,uniformItems:true,iconSize:12});
                if (bar.vertical) bar.width = bar.implicitWidth;
                wait(0);
                let clock = bar.moduleItems.calendar, audio = bar.moduleItems.audio;
                if (!bar.vertical) {
                    fuzzyCompare(clock.textInkScale,audio.textInkScale,0.0001,"clock and percentage use the same font scale");
                    compare(clock.content.font.family,audio.content.font.family);
                    compare(clock.content.font.bold,audio.content.font.bold);
                    compare(clock.uniformTextHeight,10);
                }
                fuzzyCompare(bar.moduleItems.wifi.glyphRect.height,24,0.01,"individual size applies in uniform mode");
                fuzzyCompare(bar.moduleItems.power.glyphRect.height,12,0.01,"other items retain global size");
                verify(bar.verticalThickness >= 24 / 0.48,"panel grows for individual size");
                let updated = Settings.copy(bar.settings);
                Settings.item(updated,"wifi").iconSize = 0;
                Settings.item(updated,"calendar").fontSize = 18;
                bar.settings = updated;
                wait(0);
                fuzzyCompare(bar.moduleItems.wifi.glyphRect.height,12,0.01,"reset follows global size");
                if (!bar.vertical) {
                    compare(clock.uniformTextHeight,18,"text override applies independently");
                    compare(audio.uniformTextHeight,10,"other text remains unchanged");
                }
            }
        }
        function test_uniformNotificationBadgeFollowsVisibleBell() {
            bar.settings = connectorConfig("top",{notifications:{}},{uniformItems:true,iconSize:12});
            for (let count of [1,12,999]) {
                bar.notificationData = {count:count};
                let bell = bar.moduleItems.notifications, badge = findChild(bell,"notificationBadge");
                verify(badge.visible);
                fuzzyCompare(badge.x,bell.textGlyphRect.x + bell.textGlyphRect.width - 2,0.01);
                fuzzyCompare(badge.y,bell.textGlyphRect.y - 2,0.01);
                verify(badge.glyphRect.y >= 0 && badge.glyphRect.y + badge.glyphRect.height <= bell.height);
                fuzzyCompare(badge.glyphRect.height,bar.panelTextSize,1,"badge matches clock ink height");
            }
        }
        function test_uniformRenderedInkHasMatchingHeightAndCenter() {
            inkBackground.visible = true;
            for (let size of [12,16,24]) {
                inkSample.settings = {uniformItems:true,uniformGlyphHeight:size,background:"off",
                    outlineFree:true,textColor:"#ffffff",iconColor:"#ffffff"};
                for (let sample of [
                    {text:"October 24 Saturday",family:"DejaVu Sans"},
                    {text:"100%",family:"DejaVu Sans"},
                    {text:"80%",family:"DejaVu Sans"},
                    {text:"󰂯",family:"GoMono Nerd Font"},
                    {text:"󰤨",family:"GoMono Nerd Font"},
                    {text:"󰐥",family:"GoMono Nerd Font"},
                    {text:"",icon:"󰕾",family:"DejaVu Sans"},
                    {text:"",icon:"󰁹",family:"DejaVu Sans"}
                ]) {
                    inkSample.text = sample.text;
                    inkSample.icon = sample.icon || "";
                    inkSample.family = sample.family;
                    waitForRendering(inkSample);
                    let image = grabImage(inkBackground), top = image.height, bottom = -1;
                    for (let y = 0; y < image.height; ++y) {
                        for (let x = 0; x < image.width; ++x) {
                            if (image.red(x,y) > 32 && image.green(x,y) > 32 && image.blue(x,y) > 32) {
                                top = Math.min(top,y); bottom = Math.max(bottom,y); break;
                            }
                        }
                    }
                    let name = (sample.text || sample.icon) + " at " + size;
                    verify(bottom >= top,name + " renders");
                    fuzzyCompare(bottom - top + 1,size,1,name + " actual pixel height");
                    fuzzyCompare((top + bottom + 1) / 2,inkSample.height / 2,1,name + " actual pixel center");
                }
            }
        }
        function test_uniformVisibleEdgesMatchWorkspacePills() {
            bar.statusData = {workspaces:[{id:1,name:"1"},{id:12,name:"12"}],audio:{icon:"󰕾",text:"48%"},network:{text:"󰤨"},bluetooth:{text:"󰂯"},battery:{present:true,text:"󰁹 82%"}};
            bar.mediaData = {playing:true,title:"Artist — Song",levels:[1,0.8]};
            for (let centered of [false,true]) for (let edge of ["top","bottom","left","right"]) {
                let modules = {};
                for (let id of Object.keys(bar.moduleItems)) modules[id] = {background:"off"};
                modules.workspaces = {background:"on",iconSize:9,fontSize:9};
                bar.settings = connectorConfig(edge,modules,{uniformItems:true,centerItems:centered,iconSize:16});
                if (bar.vertical) bar.width = bar.implicitWidth;
                wait(0);
                for (let id of ["launcher","settings","calendar","audio","wifi","bluetooth","notifications","battery","power"]) {
                    let item = bar.moduleItems[id], ink = item.glyphRect;
                    if (!bar.iconsOnly && !item.labelIsIcon && !item.shownIcon.length)
                        fuzzyCompare(item.uniformTextHeight,16 * 10 / 12,0.01,id + " text scale " + edge);
                    else fuzzyCompare(ink.height,16,0.01,id + " visible height " + edge);
                    fuzzyCompare(ink.y + ink.height / 2,item.height / 2,0.01,id + " visible vertical center " + edge);
                    if (!bar.iconsOnly && item.shownText.length && !item.labelIsIcon) {
                        fuzzyCompare(item.uniformTextHeight,16 * 10 / 12,0.01,id + " label scale");
                        fuzzyCompare(item.textGlyphRect.y + item.textGlyphRect.height / 2,ink.y + ink.height / 2,0.01,id + " text and icon centers");
                    }
                }
                let workspace = findChild(bar,"workspace12"), background = findChild(workspace,"pillBackground");
                compare(background.height,bar.workspacePillSize);
                compare(background.width,bar.workspacePillSize);
                compare(workspace.content.font.pixelSize,128);
                verify(workspace.content.width >= workspace.content.implicitWidth,"two-digit workspace number fits its pill");
                if (!bar.vertical) {
                    let top = workspace.mapToItem(bar,background.x,background.y).y;
                    fuzzyCompare(top + background.height / 2,bar.moduleItems.audio.y + bar.moduleItems.audio.height / 2,0.01,"workspace pill and icon centers match");
                }
                let spectrum = findChild(bar,"mediaSpectrum");
                compare(spectrum.height,16);
            }
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
        function test_bareKnotsUseVisibleContentAndLeaveClearance() {
            let links = findChild(bar, "panelConnectors");
            bar.statusData = {workspaces:[],audio:{icon:"󰕾",text:"100%"},network:{text:"󰤨"},bluetooth:{},battery:{}};
            for (let edge of ["top","bottom","left","right"]) {
                bar.settings = connectorConfig(edge,{audio:{background:"off"},wifi:{background:"off"}},
                    {height:30,uniformItems:true,fullBackground:"on",spacing:8,hyprknotsKnotSize:60});
                if (bar.vertical) bar.width = bar.implicitWidth;
                wait(0);
                let audio = bar.moduleItems.audio, wifi = bar.moduleItems.wifi;
                let segment = links.segments[0];
                let audioEnd = bar.vertical ? audio.y + audio.iconGlyphRect.y + audio.iconGlyphRect.height
                    : audio.x + audio.textGlyphRect.x + audio.textGlyphRect.width;
                let wifiStart = bar.vertical ? wifi.y + wifi.iconGlyphRect.y : wifi.x + wifi.textGlyphRect.x;
                fuzzyCompare(segment.start,audioEnd + 2,0.01,"line clears trailing visible content");
                fuzzyCompare(segment.end,wifiStart - 2,0.01,"line clears leading visible content");
                let size = links.knotSizeFor(segment.end - segment.start);
                verify(size * 2.5 + 1.6 * links.knotScale + 1.2 + 2 <= segment.end - segment.start + 0.01,
                    "knot stroke has clearance at both ends");
            }
            for (let length of [3,6,8,10,20]) {
                let size = links.knotSizeFor(length);
                if (size > 0) verify(size * 2.5 + 1.6 * links.knotScale + 1.2 + 2 <= length + 0.01);
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
        function test_centeredFullPillDefaultEndPadding() {
            let pill = findChild(bar, "fullPanelPill");
            for (let edge of ["top", "bottom"]) for (let padding of [0, 2, 12]) {
                bar.settings = connectorConfig(edge, {audio:{},wifi:{side:"right"}},
                    {centerItems:true,fullBackground:"on",contentPaddingLeft:padding,contentPaddingRight:padding});
                wait(0);
                fuzzyCompare(bar.moduleItems.audio.x - pill.x, bar.fullPillInset + padding, 0.01);
                fuzzyCompare(pill.x + pill.width - bar.moduleItems.wifi.x - bar.moduleItems.wifi.width, bar.fullPillInset + padding, 0.01);
                fuzzyCompare(pill.x + pill.width / 2, bar.width / 2, 0.01);
            }
        }
        function test_centeredKnotsCoverBareGroupedWorkspaceAndTrayIcons() {
            let links = findChild(bar, "panelConnectors");
            bar.statusData = {workspaces:[{id:1,name:"1"},{id:2,name:"2"}],audio:{},network:{},bluetooth:{},battery:{}};
            bar.trayModel = [{icon:Qt.resolvedUrl("../icons/preview-tray.svg")},{icon:Qt.resolvedUrl("../icons/preview-tray.svg")}];
            for (let edge of ["top","bottom","left","right"]) {
                bar.settings = connectorConfig(edge, {audio:{pillGroup:"test"},wifi:{pillGroup:"test"},workspaces:{},tray:{}},
                    {centerItems:true,background:"off",spacing:100});
                if (bar.vertical) bar.width = bar.implicitWidth;
                wait(0);
                compare(links.segments.length,5);
                for (let segment of links.segments) compare(segment.knots.length,1);
                compare(links.arrangeKnots(links.segments,42),links.arrangeKnots(links.segments,42));
                verify(JSON.stringify(links.arrangeKnots(links.segments,42)) !== JSON.stringify(links.arrangeKnots(links.segments,123)));
            }
        }
        function test_iconPillBackgroundsAreCircularWithoutChangingLabels() {
            for (let centered of [false,true]) for (let uniform of [false,true]) {
                bar.settings = connectorConfig("top", {wifi:{radius:0},audio:{radius:0}},
                    {centerItems:centered,uniformItems:uniform});
                bar.statusData = {audio:{icon:"󰕾",text:"48%"},network:{text:"󰤨"},bluetooth:{},battery:{}};
                wait(0);
                let wifi = bar.moduleItems.wifi, circle = findChild(wifi,"pillBackground");
                compare(circle.width,circle.height);
                compare(circle.radius,circle.width / 2);
                compare(bar.moduleItems.audio.circular,centered);
                if (!centered) compare(bar.moduleItems.audio.shownText,"48%");
            }
        }
        function test_smallWorkspacesKeepFullPillVerticallyCentered() {
            bar.statusData = {workspaces:[{id:1,name:"1"},{id:2,name:"2"}],audio:{text:"48%"},
                network:{},bluetooth:{},battery:{}};
            for (let edge of ["top","bottom"]) {
                bar.settings = connectorConfig(edge, {workspaces:{fontSize:9,iconSize:9},
                    audio:{side:"right"},calendar:{side:"center"}}, {fullBackground:"on"});
                wait(0);
                let full = findChild(bar,"fullPanelPill");
                let center = full.y + full.height / 2;
                fuzzyCompare(center,bar.height / 2,0.01,"full pill vertical center");
                for (let id of ["workspaces","audio","calendar"]) {
                    let item = bar.moduleItems[id];
                    fuzzyCompare(item.y + item.height / 2,center,0.01,id + " vertical center");
                }
                let row = bar.moduleItems.workspaces;
                let workspace = findChild(bar,"workspace1");
                fuzzyCompare(row.y + workspace.y + workspace.height / 2,center,0.01,"workspace button center");
            }
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
                compare(bar.vertical ? pill.y + bar.insetTop : pill.x + bar.insetLeft, bar.vertical ? bar.moduleItems.settings.y : bar.moduleItems.settings.x);
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
        function test_hyprknotsRetainVividAdaptiveHues() {
            let links = findChild(bar,"panelConnectors");
            let previous = bar.wallpaperSource;
            for (let backdrop of ["#080c14","#567485","#ffffff"]) {
                let sample = Qt.color(backdrop), region = {average:sample,minimum:sample,maximum:sample};
                for (let neutral of [false,true]) {
                    bar.wallpaperSource = "wallpaper-a.jpg";
                    let first = links.contrastingInk(region,0,neutral);
                    verify(first.hslSaturation > 0.7,"chain and knots retain color");
                    verify(Colors.contrast(first,sample) >= 4.5,"visible on dark, medium and light surfaces");
                    let colors = [];
                    for (let i=0; i<12; ++i) colors.push(String(links.contrastingInk(region,i*42,neutral)));
                    verify(new Set(colors).size > 3,"spatial hue variety");
                    bar.wallpaperSource = "wallpaper-b.jpg";
                    let changed = [];
                    for (let i=0; i<12; ++i) changed.push(String(links.contrastingInk(region,i*42,neutral)));
                    verify(JSON.stringify(colors) !== JSON.stringify(changed),"palette changes with wallpaper");
                }
            }
            bar.wallpaperSource = previous;
        }
        function test_hyprknotsAdaptToPillColorAndTransparency() {
            let links = findChild(bar,"panelConnectors");
            for (let edge of ["top","bottom","left","right"]) {
                let modules = {launcher:{backgroundColor:"#ffffff"},
                    audio:{pillGroup:"pair",backgroundColor:"#000000"},wifi:{pillGroup:"pair"}};
                let options = {fullBackground:"on",fullPillTransparency:0,groupPillTransparency:0,spacing:20};
                bar.settings = connectorConfig(edge,modules,options);
                wait(0);
                let first = bar.moduleItems.launcher, audio = bar.moduleItems.audio, wifi = bar.moduleItems.wifi;
                let cross = bar.vertical ? bar.insetLeft+bar.contentWidth/2 : bar.insetTop+bar.contentHeight/2;
                let gap = bar.vertical ? (first.y+first.height+audio.y)/2 : (first.x+first.width+audio.x)/2;
                let region = links.regionAt(gap,cross,4);
                fuzzyCompare(region.average,Qt.color("#ffffff"),0.001);
                let ink = links.colorAt(gap,cross,4,true);
                verify(Colors.contrast(ink,region.average) >= 4.5);
                let groupGap = bar.vertical ? (audio.y+audio.height+wifi.y)/2 : (audio.x+audio.width+wifi.x)/2;
                region = links.regionAt(groupGap,cross,4);
                fuzzyCompare(region.average,Qt.color(bar.vertical ? "#ffffff" : "#000000"),0.001);
                let previousSegments = JSON.stringify(links.segments);
                options.fullPillTransparency = 100;
                options.groupPillTransparency = 100;
                bar.settings = connectorConfig(edge,modules,options);
                wait(0);
                verify(JSON.stringify(links.segments) !== previousSegments);
                let transparentInk = links.colorAt(gap,cross,4,true);
                verify(Colors.luminance(transparentInk) > Colors.luminance(ink));
                compare(links.surfaceContains(findChild(bar,"fullPanelPill"),bar.vertical ? cross : gap,
                    bar.vertical ? gap : cross),false);
            }
        }
        function test_pillTransparencyIsIndependentAndPreservesGlyphs() {
            for (let edge of ["top", "bottom", "left", "right"]) {
                bar.settings = connectorConfig(edge, {audio:{pillGroup:"pair",backgroundOpacity:0.4},
                    wifi:{pillGroup:"pair"},calendar:{}}, {fullBackground:"on",
                    individualPillTransparency:25,groupPillTransparency:60,fullPillTransparency:100});
                wait(0);
                let calendar = bar.moduleItems.calendar;
                compare(findChild(calendar,"pillBackground").opacity,0.75);
                compare(calendar.opacity,1);
                compare(findChild(calendar,"pillIcon").opacity,1);
                let group = bar.vertical ? bar.moduleItems.audio : findChild(bar,"sharedPill_pair");
                fuzzyCompare(findChild(group,"pillBackground").opacity,0.4,0.001);
                compare(group.settings.backgroundOpacity,0.4);
                compare(group.styledBackground(Qt.rgba(0.2,0.3,0.4,0.01)).a,1);
                compare(calendar.styledBackground(Qt.rgba(0.2,0.3,0.4,0.01)).a,1);
                let full = findChild(bar,"fullPanelPill");
                compare(findChild(full,"pillBackground").opacity,0);
                compare(bar.moduleItems.audio.opacity,1);
                compare(bar.moduleItems.audio.settings.pillTransparency,bar.vertical ? 60 : 25);
                bar.settings = connectorConfig(edge,{calendar:{}},{fullBackground:"on"});
                compare(findChild(calendar,"pillBackground").opacity,1);
                compare(findChild(full,"pillBackground").opacity,1);
                bar.settings = connectorConfig(edge,{calendar:{backgroundOpacity:0.01}},
                    {individualPillTransparency:0});
                wait(0);
                let background = findChild(calendar,"pillBackground");
                tryVerify(() => background.color.a === 1);
                compare(background.color.a,1);
                compare(background.opacity,1);
                compare(calendar.settings.backgroundOpacity,0.01);
                bar.settings = connectorConfig(edge,{calendar:{backgroundOpacity:0.01}},
                    {individualPillTransparency:-1});
                fuzzyCompare(calendar.styledBackground(calendar.tint).a,0.01,0.001);
            }
        }
        function test_pillTransparencyControlsEditAndResetIndependently() {
            editor.settings = {adaptiveColors:true,clockFormat:"hh:mm"};
            let keys = ["individualPillTransparency","groupPillTransparency","fullPillTransparency"];
            for (let key of keys) {
                let control = findChild(editor,key + "Control");
                verify(control !== null);
                control.commitDisplayValue(70);
                compare(editor.settings[key],70);
                for (let other of keys) if (other !== key) compare(editor.settings[other] ?? -1,-1);
                control.edited("");
                compare(editor.settings[key],-1);
            }
        }
        function test_workspaceDigitsShareWorkspaceOneSize() {
            bar.statusData = {workspaces:Array.from({length:9},(_,i) => ({id:i+1,name:String(i+1),active:i===0})),audio:{},network:{},bluetooth:{},battery:{}};
            for (let edge of ["top","bottom","left","right"]) {
                bar.settings = connectorConfig(edge,{workspaces:{}},{uniformItems:true});
                wait(0);
                let first = findChild(bar,"workspace1");
                for (let number = 2; number <= 9; ++number) {
                    let workspace = findChild(bar,"workspace"+number);
                    compare(workspace.width,first.width,"same circle width");
                    compare(workspace.height,first.height,"same circle height");
                    fuzzyCompare(workspace.textInkScale,first.textInkScale,0.0001,"same font scale as 1");
                    fuzzyCompare(workspace.glyphRect.x + workspace.glyphRect.width / 2,workspace.width / 2,0.01,"number centered");
                }
            }
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
            verify(bell.width >= bar.panelSlotSize);
            bar.notificationData = undefined;
            compare(bell.text, "󰂚");
            verify(bell.visible);
            bar.notificationData = {count: 12, tooltip: "12 unread notifications"};
            compare(bell.text, "󰂚");
            verify(bell.width > bar.panelSlotSize);
            let badge = findChild(bell, "notificationBadge");
            for (let count of [1, 12, 999]) {
                bar.notificationData = {count: count};
                let glyphRight = bell.textGlyphRect.x + bell.textGlyphRect.width;
                fuzzyCompare(badge.x,glyphRight - 2,0.01);
                verify(badge.y < bell.textGlyphRect.y);
                verify(badge.x + badge.width < bell.width);
            }
            grabImage(bell).save("/tmp/quickshell-bell-badge.png");
        }
    }
}
