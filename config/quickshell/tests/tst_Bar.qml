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
                compare(first.width,bar.panelSlotSize);
                compare(second.width,bar.panelSlotSize);
                compare(first.height,bar.moduleItems.audio.height);
                compare(second.height,bar.moduleItems.audio.height);
                verify(first.content.implicitWidth <= first.width);
                verify(second.content.implicitWidth <= second.width);
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
                        fuzzyCompare(pill.content.x + pill.content.width / 2,pill.width / 2,0.01,"workspace label centered");
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
                    fuzzyCompare(pill.width,bar.panelSlotSize,0.01);
                    fuzzyCompare(pill.height,bar.panelSlotSize,0.01);
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
                    fuzzyCompare(item.height,bar.panelSlotSize,0.01,id + " slot height");
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
                    fuzzyCompare(workspace.width,bar.panelSlotSize,0.01,"workspace slot width");
                    fuzzyCompare(workspace.height,bar.panelSlotSize,0.01,"workspace slot height");
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
                verify(bar.panelSlotSize / full.height <= 0.7, "inner pills occupy at most 70% of full pill height");
                fuzzyCompare(full.x + full.width / 2,bar.width / 2,0.01,"full pill center");
                fuzzyCompare(bar.moduleItems[ids[0]].x - full.x,bar.panelItemInset,0.01,"full pill leading cap");
                fuzzyCompare(full.x + full.width - bar.moduleItems[ids[ids.length - 1]].x
                    - bar.moduleItems[ids[ids.length - 1]].width,bar.panelItemInset,0.01,"full pill trailing cap");
                fuzzyCompare(full.height,bar.panelSlotSize + 2 * bar.panelItemInset,0.01,"full pill vertical inset");
                fuzzyCompare(full.y,0,0.01,"full pill top");
                for (let id of ids) {
                    let item = bar.moduleItems[id];
                    fuzzyCompare(item.y - full.y,bar.panelItemInset,0.01,id + " top inset");
                    fuzzyCompare(full.y + full.height - item.y - item.height,
                        bar.panelItemInset,0.01,id + " bottom inset");
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
                    compare(item.effectiveIconSize,15,ids[i] + " common icon size");
                    if (centered) {
                        fuzzyCompare(item.width,bar.panelSlotSize,0.01,ids[i] + " icon slot width");
                        fuzzyCompare(item.height,bar.panelSlotSize,0.01,ids[i] + " icon slot height");
                        fuzzyCompare(ink.x+ink.width/2,item.width/2,0.01,ids[i] + " centered glyph");
                        fuzzyCompare(ink.y+ink.height/2,item.height/2,0.01,ids[i] + " centered glyph");
                    } else {
                        fuzzyCompare(ink.x+ink.width/2,item.width/2,0.01,ids[i] + " centered glyph");
                        compare(item.width,item.height,ids[i] + " circular pill");
                    }
                    if (i) {
                        let previous=bar.moduleItems[ids[i-1]];
                        fuzzyCompare(item.x-previous.x-previous.width,gap,0.01,"pill gap");
                    }
                }
                compare(bar.appearance("bluetooth").iconSize,15);
                bar.settings=Object.assign({},bar.settings,{bar:Object.assign({},bar.settings.bar,{uniformItems:false})});
                compare(bar.appearance("bluetooth").iconSize,32,"individual setting remains saved");
            }
        }
        function test_uniformSizeCoversCustomMarksMediaTrayAndCompactWorkspaces() {
            bar.statusData={workspaces:[{id:1,name:"1"},{id:12,name:"12"}],audio:{icon:"󰕾",text:"48%"},network:{},bluetooth:{},battery:{present:true,text:"󰁹 82%"}};
            bar.mediaData={playing:true,title:"Song",levels:[0.2,0.8]};
            bar.trayModel=[{icon:Qt.resolvedUrl("../icons/preview-tray.svg")},{icon:Qt.resolvedUrl("../icons/preview-tray.svg")}];
            for (let centered of [false,true]) {
                let modules={}; for(let id of Object.keys(bar.moduleItems)) modules[id]={iconSize:30};
                modules.workspaces={iconSize:9,fontSize:9};
                bar.settings=connectorConfig("top",modules,{uniformItems:true,centerItems:centered,iconSize:15,hyprknots:false,compactSpacing:5});
                wait(0);
                for (let id of ["launcher","settings","calendar","audio","wifi","bluetooth","notifications","battery","power"])
                    compare(bar.moduleItems[id].effectiveIconSize,15,id);
                compare(findChild(bar,"distroGlassLogo").iconSize,15);
                compare(findChild(bar,"settingsGlassCog").iconSize,15);
                compare(findChild(bar,"mediaSpectrum").width,15);
                compare(findChild(bar,"mediaSpectrum").height,15);
                compare(bar.moduleItems.tray.trayIconSize,15);
                compare(findChild(bar,"workspace1").content.font.pixelSize,9);
                if (!centered) {
                    let height = bar.moduleItems.audio.height;
                    for (let id of ["wifi","bluetooth","battery","power"])
                        compare(bar.moduleItems[id].height,height,id + " uniform height");
                }
                if (centered) {
                    compare(findChild(bar,"workspace12").height,bar.panelSlotSize);
                    compare(bar.moduleItems.tray.trayTargetSize,bar.panelSlotSize);
                } else {
                    let workspace = findChild(bar,"workspace12");
                    compare(workspace.height,workspace.width);
                    verify(workspace.height < bar.panelSlotSize);
                }
                compare(bar.moduleItems.workspaces.spacing,5);
                compare(findChild(bar.moduleItems.tray,"trayIcon").parent.spacing,5);
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
                fuzzyCompare(bar.moduleItems.audio.x - pill.x, Math.max(bar.panelItemInset,padding), 0.01);
                fuzzyCompare(pill.x + pill.width - bar.moduleItems.wifi.x - bar.moduleItems.wifi.width, Math.max(bar.panelItemInset,padding), 0.01);
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
