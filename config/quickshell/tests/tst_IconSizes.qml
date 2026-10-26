import QtQuick
import QtTest
import ".."
import "../SettingsModel.js" as Model

Item {
    width: 1366; height: 120
    Bar {
        id: bar
        width: parent.width
        statusData: ({workspaces: [], audio: {icon:"♪",text:"64%"}, network: {}, bluetooth: {}, battery: {present:true,text:"󰁹 86%"}})
        mediaData: ({playing:true,title:"Track",levels:[1,0.5]})
        trayModel: [{icon: Qt.resolvedUrl("../icons/preview-tray.svg")}]
    }
    TestCase {
        name: "IconSizes"
        when: windowShown
        function cleanup() { bar.settings = {}; }
        function trayImage() { return findChild(bar,"trayIcon").children.find(child => child.fillMode !== undefined); }
        function test_globalSizingIncludesGlassGlyphsTrayAndSpectrum() {
            bar.settings = {bar:{height:32,iconSize:24}};
            // Ink is normalized from a large font; the rendered size is the
            // contract, not the internal 128 px outline used for measurement.
            fuzzyCompare(bar.moduleItems.audio.iconGlyphRect.height,24,0.01);
            fuzzyCompare(bar.moduleItems.audio.textGlyphRect.height,24,0.01);
            fuzzyCompare(bar.moduleItems.wifi.glyphRect.height,24,0.01);
            compare(findChild(bar,"distroGlassLogo").iconSize,24);
            fuzzyCompare(bar.moduleItems.settings.glyphRect.height,24,0.01);
            compare(trayImage().width,24);
            fuzzyCompare(bar.moduleItems.battery.iconGlyphRect.height,24,0.01);
            fuzzyCompare(bar.moduleItems.battery.textGlyphRect.height,24,0.01);
            compare(bar.moduleItems.battery.shownText,"86%");
            compare(bar.moduleItems.media.item.spectrumWidth,87);
        }
        function test_individualSizeWinsAndResetFollowsGlobal() {
            bar.settings = {bar:{height:32,iconSize:32},items:[{id:"wifi",iconSize:12},{id:"launcher",iconSize:40},{id:"tray",iconSize:20}]};
            fuzzyCompare(bar.moduleItems.wifi.glyphRect.height,12,0.01);
            compare(findChild(bar,"distroGlassLogo").iconSize,40);
            compare(trayImage().width,20);
            fuzzyCompare(bar.moduleItems.audio.iconGlyphRect.height,32,0.01);
            bar.settings = {bar:{height:32,iconSize:32},items:[{id:"wifi",iconSize:0}]};
            fuzzyCompare(bar.moduleItems.wifi.glyphRect.height,32,0.01);
            bar.settings = {bar:{height:32,iconSize:0}};
            fuzzyCompare(bar.moduleItems.wifi.glyphRect.height,15.36,0.01);
            fuzzyCompare(findChild(bar,"distroGlassLogo").iconSize,15.36,0.01);
            fuzzyCompare(bar.moduleItems.audio.iconGlyphRect.height,15.36,0.01);
            fuzzyCompare(trayImage().width,15.36,0.01);
        }
        function test_largerIconsGrowHitAreasAndKeepMenuAnchors() {
            bar.settings = {bar:{height:32,iconSize:48}};
            for(let id of ["launcher","settings","audio","wifi","bluetooth","notifications","battery","power"]) {
                let item = bar.moduleItems[id];
                verify(item.height >= 48);
                verify(item.y >= 0);
                verify(item.y + item.height <= bar.height);
                compare(bar.menuRect(id).x, item.x);
                compare(bar.menuRect(id).width, item.width);
                compare(bar.menuRect(id).height,item.height);
            }
            verify(bar.height >= 52);
        }
        function test_fullPillFitsUnchangedItemsWithSmallHeadroom() {
            for (let edge of ["top", "bottom"]) {
                bar.settings = {bar:{position:edge,height:30,uniformItems:true,fullBackground:"off"},
                    items:[{id:"workspaces",iconSize:21,fontSize:8},{id:"audio",iconSize:14,fontSize:10},
                        {id:"wifi",iconSize:12},{id:"bluetooth",iconSize:15},{id:"power",iconSize:15}]};
                let ids = bar.orderedItems("left").concat(bar.orderedItems("center"), bar.orderedItems("right"));
                let heights = ids.map(id => bar.moduleItems[id].height);
                let panelHeight = bar.height;
                bar.settings = Object.assign({}, bar.settings, {bar:Object.assign({}, bar.settings.bar, {fullBackground:"on"})});
                let surface = findChild(bar,"fullPanelPill");
                verify(surface.visible);
                compare(bar.height, panelHeight);
                for (let i = 0; i < ids.length; ++i) compare(bar.moduleItems[ids[i]].height, heights[i]);
                let top = Math.min(...ids.map(id => bar.moduleItems[id].y));
                let bottom = Math.max(...ids.map(id => bar.moduleItems[id].y + bar.moduleItems[id].height));
                fuzzyCompare(surface.y, top - 2, 0.01);
                fuzzyCompare(surface.y + surface.height, bottom + 2, 0.01);
                verify(surface.height < panelHeight);
            }
        }
        function test_retiredMotionSettingsDoNotSurviveMerge() {
            let defaults={version:1,bar:{iconSize:0},items:[{id:"audio",iconSize:0}],hyprland:{}};
            let merged=Model.merge(defaults,{version:1,bar:{genieEffect:true,genieOpenDuration:300},items:[{id:"audio",genieEffect:"on",genieCloseDuration:400}]});
            compare(merged.bar.genieEffect,undefined);
            compare(merged.items[0].genieEffect,undefined);
            compare(merged.items[0].genieCloseDuration,undefined);
        }
    }
}
