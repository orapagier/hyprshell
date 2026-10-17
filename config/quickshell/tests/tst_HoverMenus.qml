import QtQuick
import QtQuick.Controls
import QtTest
import ".."

Item {
    id: root
    width: 1366; height: 500
    MenuController { id: state; dismissPinnedOnLeave: openedByShortcut }
    Bar {
        id: bar
        z: 1
        width: parent.width
        clockText: "Oct 08   12:34 PM   Thu"
        statusData: ({workspaces: [], audio: {}, network: {}, bluetooth: {}, battery: {present: true, text: "󰂁 76%"}})
        activeMenu: state.section
        onMenuHovered: name => state.hover(name)
        onMenuLeft: name => state.leave(name)
        onAction: (name, argument) => {
            if (name === "settings") root.openSettings();
            else state.activate(name);
        }
    }
    MenuPopover {
        id: popover
        anchors.fill: parent
        triggerRect: bar.menuRect(state.displayedSection)
        alignment: bar.side(state.displayedSection)
        accent: bar.menuAccent(state.displayedSection)
        title: state.displayedSection
        symbol: "󰕾"
        opened: state.section.length > 0
        cardClickable: state.displayedSection === "settings"
        onCardClicked: root.openSettings()
        onHoverChanged: inside => state.retain(inside)
        page: state.displayedSection === "settings" ? settingsPage : actionPage
    }
    Component {
        id: settingsPage
        SettingsMenu { onOpenRequested: root.openSettings() }
    }
    Component {
        id: actionPage
            Item {
                implicitHeight: 140
                Button { objectName: "menuAction"; text: "Test action"; onClicked: root.actionCount++ }
            }
    }
    property int actionCount: 0
    property int settingsOpenCount: 0
    function openSettings() { state.close(); settingsOpenCount++; }
    TestCase {
        name: "HoverMenus"
        when: windowShown
        function init() { mouseMove(root, 5, 480); wait(20); state.close(); }
        function cleanup() { state.close(); state.hoverEnabled = true; bar.hoverPopdowns = true; bar.settings = {}; bar.mediaData = {}; root.width = 1366; }
        function hover(name) {
            let trigger = findChild(bar, name === "notifications" ? "notificationBell" : name + "Trigger");
            verify(trigger !== null);
            mouseMove(trigger, trigger.width / 2, trigger.height / 2);
            tryCompare(state, "section", name);
        }
        function expectedBodyX(side) {
            return side === "left" ? 12 : side === "right" ? root.width - popover.bodyWidth - 12 : (root.width - popover.bodyWidth) / 2;
        }
        function test_hoverOpensEveryMenu_data() {
            return ["launcher", "settings", "calendar", "notifications", "audio", "wifi", "bluetooth", "battery", "power"].map(name => ({tag: name, menu: name}));
        }
        function test_hoverOpensEveryMenu(data) {
            hover(data.menu);
            verify(!state.pinned);
            verify(popover.bodyX >= 12);
            compare(popover.bodyX, expectedBodyX(bar.side(data.menu)));
            let trigger = bar.menuRect(data.menu);
            compare(popover.neckY, trigger.y + trigger.height - 1);
            compare(popover.tipX, trigger.x + trigger.width / 2);
            if (data.menu === "launcher") {
                verify(findChild(popover, "menuFunnel").visible);
                compare(popover.bodyY, popover.neckY + 34);
            }
        }
        function test_pointerCanCrossBridgeAndUseMenu() {
            hover("audio");
            mouseMove(root, popover.shoulder, popover.bodyY - 8);
            wait(380);
            compare(state.section, "audio");
            let button = findChild(popover, "menuAction");
            verify(button !== null);
            mouseMove(button, button.width / 2, button.height / 2);
            wait(380);
            compare(state.section, "audio");
            let before = root.actionCount;
            mouseClick(button, button.width / 2, button.height / 2);
            compare(root.actionCount, before + 1);
            mouseMove(root, 5, 480);
            tryCompare(state, "section", "");
        }
        function test_settingsCogOpensWindow_data() {
            return [{tag: "direct", preview: false}, {tag: "preview", preview: true}];
        }
        function test_settingsCogOpensWindow(data) {
            if (data.preview) hover("settings");
            let cog = findChild(bar,"settingsTrigger");
            mouseMove(cog, cog.width / 2, cog.height / 2);
            let before = root.settingsOpenCount;
            mouseClick(cog,cog.width/2,cog.height/2);
            compare(root.settingsOpenCount, before + 1);
            compare(state.section,"");
            verify(!state.pinned);
            wait(180);
            compare(state.section,"");
        }
        function test_settingsPreviewCardOpensWindow_data() {
            return [
                {tag: "padding", x: 5, y: 5},
                {tag: "heading", x: 90, y: 30},
                {tag: "description", x: 100, y: 115}
            ];
        }
        function test_settingsPreviewCardOpensWindow(data) {
            hover("settings");
            wait(250);
            let before = root.settingsOpenCount;
            mouseClick(root, popover.bodyX + data.x, popover.bodyY + data.y);
            compare(root.settingsOpenCount, before + 1);
            compare(state.section, "");
        }
        function test_settingsPreviewButtonOpensWindowOnce() {
            hover("settings");
            wait(250);
            let button = findChild(popover, "openSettingsButton");
            verify(button !== null);
            let before = root.settingsOpenCount;
            mouseClick(button, button.width / 2, button.height / 2);
            compare(root.settingsOpenCount, before + 1);
            compare(state.section, "");
        }
        function test_launcherCanBeEnteredAndUsed() {
            hover("launcher");
            mouseMove(root, popover.shoulder, popover.bodyY - 8);
            wait(380);
            compare(state.section, "launcher");
            let button = findChild(popover, "menuAction");
            mouseMove(button, button.width / 2, button.height / 2);
            wait(380);
            compare(state.section, "launcher");
            let before = root.actionCount;
            mouseClick(button, button.width / 2, button.height / 2);
            compare(root.actionCount, before + 1);
            wait(250);
            grabImage(root).save("/tmp/quickshell-attached-launcher.png");
        }
        function test_clickOnlyWorkspacePreviewKeepsNavigation() {
            state.hoverEnabled = false; bar.hoverPopdowns = false;
            let before = bar.statusData;
            try {
                bar.statusData = Object.assign({}, before, {workspaces:[{id:2,name:"2"},{id:3,name:"3"}]});
                bar.previewWorkspaceId = 2;
                tryVerify(() => bar.previewWorkspaceItem !== null);
                let button = bar.previewWorkspaceItem;
                bar.previewWorkspaceId = 3;
                mouseMove(button, button.width / 2, button.height / 2);
                wait(180); compare(state.section, ""); compare(bar.previewWorkspaceId, 3);
                mouseClick(button, button.width / 2, button.height / 2, Qt.RightButton);
                compare(state.section, "workspacePreview"); compare(bar.previewWorkspaceId, 2);
                mouseClick(button, button.width / 2, button.height / 2, Qt.LeftButton);
                compare(state.section, "workspace");
            } finally { bar.statusData = before; }
        }
        function test_clickOnlyMediaOpensPopdown() {
            state.hoverEnabled = false; bar.hoverPopdowns = false;
            bar.mediaData = {playing:true, title:"Test song", levels:[]};
            let slot = findChild(bar, "mediaSlot");
            tryVerify(() => slot.item !== null);
            mouseMove(slot.item, slot.item.width / 2, slot.item.height / 2);
            wait(180); compare(state.section, "");
            mouseClick(slot.item, slot.item.width / 2, slot.item.height / 2);
            compare(state.section, "media"); verify(state.pinned);
        }
        function test_clickOnlyMenusDoNotOpenOrSwitchOnHover() {
            state.hoverEnabled = false; bar.hoverPopdowns = false;
            let audio = findChild(bar, "audioTrigger");
            mouseMove(audio, audio.width / 2, audio.height / 2);
            wait(180); compare(state.section, "");
            mouseClick(audio, audio.width / 2, audio.height / 2);
            compare(state.section, "audio"); verify(state.pinned);
            let wifi = findChild(bar, "wifiTrigger");
            mouseMove(wifi, wifi.width / 2, wifi.height / 2);
            wait(180); compare(state.section, "audio");
            mouseClick(wifi, wifi.width / 2, wifi.height / 2);
            compare(state.section, "wifi");
        }
        function test_disableCancelsPendingHoverButPreservesClickedMenu() {
            state.hover("audio"); state.hoverEnabled = false;
            wait(180); compare(state.section, "");
            state.activate("audio"); state.hoverEnabled = true; state.hoverEnabled = false;
            compare(state.section, "audio"); verify(state.pinned);
            state.close(); state.hoverEnabled = true;
            state.hover("wifi"); tryCompare(state, "section", "wifi");
            state.hoverEnabled = false; compare(state.section, "");
        }
        function test_hoverSwitchesToNeighbor() {
            hover("audio");
            hover("wifi");
            compare(popover.accent, bar.menuAccent("wifi"));
            mouseMove(root, popover.bodyX + 40, popover.bodyY + 80);
            wait(380);
            compare(state.section, "wifi");
        }
        function test_clickKeepsMenuOpenUntilDismissed() {
            hover("audio");
            let trigger = findChild(bar, "audioTrigger");
            mouseClick(trigger, trigger.width / 2, trigger.height / 2);
            verify(state.pinned);
            verify(!state.openedByShortcut);
            mouseMove(root, 5, 480);
            wait(380);
            compare(state.section, "audio");
            state.close();
            compare(state.section, "");
        }
        function test_shortcutMenuClosesOnPointerLeave() {
            state.activate("audio", true);
            verify(state.pinned);
            verify(state.openedByShortcut);
            compare(popover.bodyX, expectedBodyX(bar.side("audio")));
            compare(popover.tipX, bar.menuRect("audio").x + bar.menuRect("audio").width / 2);
            mouseMove(root, popover.bodyX + 150, popover.bodyY + 33);
            wait(380);
            compare(state.section, "audio");
            mouseMove(root, 5, 480);
            tryCompare(state, "section", "");
            verify(!state.openedByShortcut);
        }
        function test_shortcutPromotesHoveredMenuAndTogglesClosed() {
            hover("audio");
            state.activate("audio", true);
            verify(state.pinned);
            verify(state.openedByShortcut);
            state.activate("audio", true);
            compare(state.section, "");
            verify(!state.openedByShortcut);
        }
        function test_keyboardPowerMenuWaitsForKeyboardDismissal() {
            mouseMove(root, 5, 480);
            state.activate("power", true);
            state.retain(false);
            wait(380);
            compare(state.section, "power");
            verify(state.pinned);
            state.activate("power", true);
            compare(state.section, "");
            verify(!state.pinned);
        }
        function test_hoverSwitchClearsShortcutMode() {
            state.activate("audio", true);
            hover("wifi");
            verify(!state.pinned);
            verify(!state.openedByShortcut);
        }
        function test_connectorFollowsScreenResize() {
            hover("audio");
            root.width = 1000;
            waitForRendering(bar);
            let trigger = findChild(bar, "audioTrigger");
            let position = trigger.mapToItem(root, trigger.width / 2, 0);
            compare(popover.tipX, position.x);
            compare(popover.bodyX, expectedBodyX(bar.side("audio")));
        }
        function test_openMenuFollowsMovedIcon_data() {
            return ["launcher", "settings", "calendar", "notifications", "audio", "wifi", "bluetooth", "battery", "power"].map(name => ({tag: name, menu: name}));
        }
        function test_openMenuFollowsMovedIcon(data) {
            hover(data.menu);
            state.activate(data.menu); // Keep the menu open while editing settings.
            for (let side of ["center", "left", "right"]) {
                bar.settings = {items: [{id: data.menu, side: side, order: 0}, ...(data.menu === "calendar" ? [] : [{id: "calendar", enabled: false}])]};
                let rect = bar.menuRect(data.menu);
                let center = rect.x + rect.width / 2;
                compare(state.section, data.menu);
                compare(popover.tipX, center);
                compare(popover.bodyX, expectedBodyX(side));
                if (side === "center") fuzzyCompare(popover.bodyX + popover.bodyWidth / 2, root.width / 2, 0.01);
                verify(popover.containsPointer(Qt.point(popover.shoulder, popover.bodyY - 8)));
            }
        }
        function test_groupAlignment_data() {
            return ["left", "center", "right"].map(side => ({tag: side, side: side}));
        }
        function test_groupAlignment(data) {
            bar.settings = {items: [{id: "audio", side: data.side, order: 0}, {id: "wifi", side: data.side, order: 1}]};
            hover("audio");
            let audioTip = popover.tipX;
            let cardX = popover.bodyX;
            hover("wifi");
            verify(popover.tipX !== audioTip);
            compare(popover.bodyX, cardX);
            compare(cardX, expectedBodyX(data.side));
            wait(250);
            grabImage(root).save("/tmp/quickshell-popdown-" + data.side + ".png");
        }
        function test_hoverReentryDoesNotFlicker() {
            hover("audio");
            // Surface focus changes can deliver a brief leave/reentry pair.
            for (let i = 0; i < 4; i++) {
                state.leave("audio");
                wait(40);
                state.hover("audio");
                wait(350);
                compare(state.section, "audio");
            }
        }
        function test_exitAndMenuEntryEventOrder() {
            hover("audio");
            state.retain(true);
            state.leave("audio");
            wait(380);
            compare(state.section, "audio");
            state.retain(false);
            wait(40);
            state.retain(true);
            wait(380);
            compare(state.section, "audio");
            state.retain(false);
            tryCompare(state, "section", "");
        }
        function test_closeKeepsGeometryUntilInvisible_data() {
            return [{tag: "audio", menu: "audio"}, {tag: "calendar", menu: "calendar"}, {tag: "battery", menu: "battery"}, {tag: "launcher", menu: "launcher"}];
        }
        function test_closeKeepsGeometryUntilInvisible(data) {
            hover(data.menu);
            wait(250);
            let tip = popover.tipX;
            let x = popover.bodyX;
            let height = popover.bodyHeight;
            let button = findChild(popover, "menuAction");
            state.close();
            compare(popover.tipX, tip, "The closing funnel must stay attached to its icon");
            compare(popover.bodyX, x, "The closing calendar must stay centered");
            compare(popover.bodyHeight, height, "The card must retain its size while fading");
            compare(findChild(popover, "menuAction"), button);
            wait(50);
            compare(popover.tipX, tip);
            compare(findChild(popover, "menuAction"), button);
            tryVerify(() => findChild(popover, "menuAction") === null);
        }
        function test_renderConnectedPopover() {
            hover("audio");
            wait(250);
            let saved = false;
            root.grabToImage(result => { result.saveToFile("/tmp/quickshell-hover-menu.png"); saved = true; });
            tryVerify(() => saved);
        }
    }
}
