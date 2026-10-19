import QtQuick
import QtTest
import ".."
import "../SettingsModel.js" as Model

Item {
    width: 1366; height: 80
    Bar { id: bar; width: parent.width; clockText: "12:34" }
    TestCase {
        name: "BarSettings"
        when: windowShown
        function cleanup() { bar.settings = {}; bar.mediaData = {playing: false}; }
        function test_disableRemovesLayoutSpaceAndMovesMenuAnchor() {
            let audio = findChild(bar, "audioTrigger"), wifi = findChild(bar, "wifiTrigger");
            let old = audio.x;
            bar.settings = {items: [{id: "wifi", enabled: false}]};
            compare(wifi.visible, false);
            verify(audio.x > old);
            compare(bar.menuRect("audio").x, audio.x);
        }
        function test_moveAndReorderAcrossAllThreeSides() {
            let audio = findChild(bar, "audioTrigger"), wifi = findChild(bar, "wifiTrigger");
            bar.settings = {items: [{id:"audio",side:"left",order:0}, {id:"wifi",side:"left",order:1}]};
            verify(audio.x < wifi.x);
            bar.settings = {items: [{id:"audio",side:"left",order:1}, {id:"wifi",side:"left",order:0}]};
            verify(wifi.x < audio.x);
            bar.settings = {items: [{id:"audio",side:"center",order:0}, {id:"calendar",enabled:false}]};
            fuzzyCompare(audio.x + audio.width / 2, bar.width / 2, 0.01);
            compare(bar.menuRect("audio").x, audio.x);
        }
        function test_asymmetricPaddingKeepsMenuAnchorOnPill() {
            let logo = bar.moduleItems.launcher;
            for (let padding of [{paddingLeft: 30}, {paddingRight: 30}, {paddingLeft: 18, paddingRight: 4}]) {
                bar.settings = {bar: {height: 32}, items: [Object.assign({id: "launcher"}, padding)]};
                compare(bar.menuRect("launcher").x, logo.x);
                compare(bar.menuRect("launcher").width, logo.width);
            }
        }
        function test_globalAdaptationAndPerItemOverride() {
            let audio = findChild(bar, "audioTrigger"), wifi = findChild(bar, "wifiTrigger");
            bar.settings = {bar: {adaptiveColors: false, height:32,spacing:3}, items:[{id:"wifi",adaptiveColors:"on"}]};
            compare(audio.colorSampler, null);
            verify(wifi.colorSampler !== null);
            bar.settings = {bar: {adaptiveColors: true,height:32,spacing:3}, items:[{id:"wifi",adaptiveColors:"off"}]};
            verify(audio.colorSampler !== null);
            compare(wifi.colorSampler, null);
        }
        function test_extraSpacingAddsToGeneralGapAndMovesAnchors() {
            let wifi = bar.moduleItems.wifi, bluetooth = bar.moduleItems.bluetooth;
            for (let side of ["left", "center", "right"]) {
                bar.settings = {bar:{height:32,spacing:5}, items:Object.keys(bar.moduleItems).map(id => ({
                    id:id, enabled:id === "wifi" || id === "bluetooth", side:side,
                    order:id === "wifi" ? 0 : 1, spacingLeft:id === "wifi" ? 7 : 3,
                    spacingRight:id === "wifi" ? 10 : 11
                }))};
                compare(bluetooth.x - wifi.x - wifi.width, 18);
                let total = 7 + wifi.width + 18 + bluetooth.width + 11;
                let start = side === "left" ? 0 : side === "center" ? (bar.width-total)/2 : bar.width-total;
                fuzzyCompare(wifi.x, start+7, 0.01);
                compare(bar.menuRect("wifi").x, wifi.x);
                compare(bar.menuRect("bluetooth").x, bluetooth.x);
            }
            bar.settings = {bar:{height:32,spacing:5}, items:[{id:"wifi",spacingLeft:100,spacingRight:100,enabled:false}]};
            let before = bluetooth.x;
            bar.settings = {bar:{height:32,spacing:5}, items:[{id:"wifi",enabled:false}]};
            compare(bluetooth.x, before);
        }
        function test_globalPillsAndIndividualOverrides() {
            let audio = bar.moduleItems.audio, wifi = bar.moduleItems.wifi;
            let logo = bar.moduleItems.launcher, cog = bar.moduleItems.settings;
            bar.settings = {bar:{height:32,background:"off"},items:[{id:"wifi",background:"on"}]};
            compare(audio.backgroundShown, false);
            compare(wifi.backgroundShown, true);
            compare(logo.backgroundShown, false);
            bar.settings = {bar:{height:32,background:"on"},items:[{id:"wifi",background:"off"}]};
            compare(audio.backgroundShown, true);
            compare(wifi.backgroundShown, false);
            compare(logo.backgroundShown, true);
            compare(cog.backgroundShown, true);
            bar.settings = {bar:{height:32,background:"inherit"}};
            compare(audio.backgroundShown, true);
            compare(logo.backgroundShown, false);
            compare(cog.backgroundShown, false);
            bar.mediaData = {playing:true,title:"Track"};
            bar.settings = {bar:{height:32,background:"off"}};
            compare(bar.moduleItems.media.item.backgroundShown, false);
            bar.settings = {bar:{height:32,background:"on"}};
            compare(bar.moduleItems.media.item.backgroundShown, true);
        }
        function test_manualColorsTextAndIconWinOverAdaptation() {
            let audio = findChild(bar, "audioTrigger");
            bar.settings = {items:[{id:"audio",text:"Sound",icon:"♪",textColor:"#ff0000",iconColor:"#00ff00",backgroundColor:"#0000ff",backgroundOpacity:0.4,opacity:0.6,fontSize:18}]};
            compare(audio.shownText, "Sound"); compare(audio.shownIcon, "♪");
            compare(audio.content.text, "Sound"); compare(audio.content.font.pixelSize,18);
            compare(audio.textColor, Qt.color("#ff0000")); compare(audio.iconColor, Qt.color("#00ff00"));
            let fill = audio.styledBackground(Qt.rgba(1,1,1,0.2));
            compare(fill.b, 1); fuzzyCompare(fill.a,0.4,0.001);
            compare(audio.opacity,0.6);
        }
        function test_hiddenMediaDoesNotKeepSpectrumAlive() {
            bar.mediaData = {playing:true,title:"Track",levels:[]};
            let slot = findChild(bar,"mediaSlot");
            verify(slot.item !== null);
            bar.settings = {items:[{id:"media",enabled:false}]};
            compare(slot.item,null);
        }
        function test_cogAppearsBesideLogoWithLegacyOrdering() {
            bar.settings = {items:[{id:"launcher",order:0},{id:"settings",order:1},{id:"workspaces",order:1}]};
            let cog = findChild(bar,"settingsTrigger"), logo = findChild(bar,"launcherTrigger");
            verify(cog.visible);
            verify(cog.x >= logo.x + logo.width);
            verify(cog.x < findChild(bar,"workspacesSlot").x);
            compare(bar.menuRect("settings").x,cog.x);
        }
        function test_glassIconsHaveNoBackgroundAndKeepHoverFeedback() {
            let cog = findChild(bar,"settingsTrigger"), logo = findChild(bar,"launcherTrigger");
            compare(cog.backgroundVisible,false);
            compare(logo.backgroundVisible,false);
            let glass = findChild(bar,"settingsGlassCog");
            verify(glass.visible);
            mouseMove(cog,cog.width/2,cog.height/2);
            verify(glass.highlighted);
            bar.activeMenu = "settings";
            mouseMove(bar,bar.width/2,bar.height-1);
            verify(glass.highlighted);
            bar.activeMenu = "";
        }
    }
}
