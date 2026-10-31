pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "SettingsModel.js" as Model

PanelWindow {
    id: dock
    required property var store
    required property var services
    required property var inbox
    required property var applicationService
    required property var settingsController
    property var projector: null
    property bool notificationTarget: false
    property var trayModel: []
    property url wallpaperSource: ""
    property string clockText: ""
    property bool available: true
    property bool modeEnabled: true
    property bool keyboardSession: false
    property bool motionEnabled: true
    readonly property string edge: store.panelConfig.bar.position || "top"
    readonly property bool vertical: edge === "left" || edge === "right"
    readonly property alias section: dockState.section
    readonly property alias settingsHost: settingsInner
    readonly property bool expanded: revealed || section.length > 0
    property bool revealed: false
    property bool requested: false
    property var resourceData: ({})
    property bool dashboardLoaded: false
    property bool activityLoaded: false
    signal lockRequested()
    signal activated()
    readonly property var menuColors: glass.menuColors
    readonly property var itemPalette: Model.wallpaperPalette(wallpaperSource.toString()).map(color => {
        // Retain wallpaper-driven shuffling, replacing only the blue/violet slots.
        return ({"#5dccff":"#ffb86b", "#86a6ff":"#f6c177", "#b88aff":"#f6a6d7"})[color] || color;
    })
    function itemColor(name) {
        const aliases = {dashboard:"launcher", activity:"notifications", keybindings:"workspaces"};
        let index = Model.vibrantIds.indexOf(aliases[name] || name);
        return itemPalette[Math.max(0, index)];
    }
    readonly property color headerColor: stripBar.menuTargets[dockState.displayedSection]
        ? stripBar.menuAccent(dockState.displayedSection) : itemColor(dockState.displayedSection)
    readonly property real stripSize: 36
    readonly property real compactLength: 76
    readonly property real naturalLength: Math.max(1, stripBar.groupLength("left"))
    readonly property real contentWidth: section === "settings" ? 1120 : section === "dashboard" ? 780 : section === "activity" ? 440 : section === "launcher" || section === "keybindings" ? 560 : 400
    readonly property real contentHeight: (section === "settings" ? 820 : section === "dashboard" ? (dashboardLoader.item?.implicitHeight || 0) + 40
        : section === "activity" ? (activityLoader.item?.implicitHeight || 0) + 40
        : section === "displays" ? (projectorSlot.children[0]?.height || 0) + 40 : Math.max(0, page.item?.implicitHeight || 0) + 40)
        + (popupLoader.active ? Math.min(150, popupLoader.implicitHeight) + 10 : 0)
    // The strip stays centered on the output, independent of the content width.
    readonly property real stripLength: Math.min(vertical ? height : width, naturalLength + 200)
    readonly property real targetWidth: Math.min(width, vertical
        ? (section ? contentWidth + stripSize + 24 : expanded ? stripSize : 24)
        : expanded ? Math.max(stripLength, section ? contentWidth + 32 : 0) : compactLength)
    readonly property real targetHeight: Math.min(height, vertical
        ? expanded ? Math.max(stripLength, section ? contentHeight + 40 : 0) : compactLength
        : section ? contentHeight + stripSize + 28 : expanded ? stripSize : 22)
    property real animatedWidth: targetWidth
    property real animatedHeight: targetHeight
    readonly property rect targetRect: Qt.rect(
        edge === "left" ? 0 : edge === "right" ? width - targetWidth : (width - targetWidth) / 2,
        edge === "top" ? 0 : edge === "bottom" ? height - targetHeight : (height - targetHeight) / 2,
        targetWidth, targetHeight)
    readonly property real surfaceWidth: Math.max(1, Math.min(width, animatedWidth))
    readonly property real surfaceHeight: Math.max(1, Math.min(height, animatedHeight))
    readonly property rect surfaceRect: Qt.rect(
        edge === "left" ? 0 : edge === "right" ? width - surfaceWidth : (width - surfaceWidth) / 2,
        edge === "top" ? 0 : edge === "bottom" ? height - surfaceHeight : (height - surfaceHeight) / 2,
        surfaceWidth, surfaceHeight)
    // Spring undershoot must not remove the pointer from the input region.
    // Retain only the union of the visual surface and its current destination.
    readonly property rect inputRect: Qt.rect(
        Math.min(surfaceRect.x, targetRect.x), Math.min(surfaceRect.y, targetRect.y),
        Math.max(surfaceRect.x + surfaceRect.width, targetRect.x + targetRect.width) - Math.min(surfaceRect.x, targetRect.x),
        Math.max(surfaceRect.y + surfaceRect.height, targetRect.y + targetRect.height) - Math.min(surfaceRect.y, targetRect.y))
    Behavior on animatedWidth { enabled: dock.motionEnabled; SpringAnimation { spring: 3.2; damping: 0.3; mass: 1; epsilon: 0.3 } }
    Behavior on animatedHeight { enabled: dock.motionEnabled; SpringAnimation { spring: 3.2; damping: 0.3; mass: 1; epsilon: 0.3 } }
    visible: true
    color: "transparent"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: 0
    WlrLayershell.namespace: "hyprshell-dock"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: !available ? WlrKeyboardFocus.None : (dockState.pinned || keyboardSession) ? WlrKeyboardFocus.Exclusive : section ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    mask: Region { x: dock.inputRect.x; y: dock.inputRect.y; width: dock.available ? dock.inputRect.width : 0; height: dock.available ? dock.inputRect.height : 0 }
    onAvailableChanged: if (!available) collapse()
    function collapse() { dockState.close(); revealed = false; requested = false; keyboardSession = false; }
    function closeContent() { dockState.close(); revealed = true; if (keyboardSession) dockState.pinned = true; strip.forceActiveFocus(); }
    function open(name, keyboard) {
        requested = true;
        revealed = true;
        if (keyboard === true) keyboardSession = true;
        dockState.activate(name, keyboard === true);
    }
    function prepareSettings() {
        requested = true;
        revealed = true;
        if (dockState.section !== "settings") {
            keyboardSession = true;
            dockState.pinned = true;
            dockState.openedByShortcut = true;
            dockState.section = "settings";
        }
        return settingsInner;
    }
    function revealKeyboard() { activated(); keyboardSession = true; requested = true; revealed = true; dockState.pinned = true; strip.forceActiveFocus(); }
    MenuController {
        id: dockState
        objectName: "dockMenuState"
        hoverEnabled: true
        dismissPinnedOnLeave: false
        dismissInhibited: dock.section === "settings" && !!card.Overlay.overlay
            && Array.from(card.Overlay.overlay.children).some(child => child.visible)
        onSectionChanged: {
            if (section === "dashboard") dock.dashboardLoaded = true;
            if (section === "activity") dock.activityLoaded = true;
            if (section !== "settings" && dock.settingsController.dockHost === settingsInner) dock.settingsController.hideEmbedded();
            if (dock.projector) {
                if (section === "displays") { dock.projector.dockHost = projectorSlot; dock.projector.open(); }
                else if (dock.projector.dockHost === projectorSlot) dock.projector.dismiss();
            }
            if (section === "settings" && !dock.settingsController.window?.dockOpened) Qt.callLater(() => { if (dockState.section === "settings") dock.settingsController.open(); });
            if (section) { dock.revealed = true; dock.activated(); }
        }
    }
    Timer { id: collapseDelay; interval: 350; onTriggered: { if (!cardHover.hovered && !dockState.pinned && !dock.section) dock.collapse(); } }
    GlassSurface {
        id: glass
        objectName: "dockGlass"
        wallpaperSource: dock.wallpaperSource
        screenWidth: dock.width; screenHeight: dock.height
        region: dock.surfaceRect
        cacheFullWallpaper: true
        translucency: dock.store.panelConfig.bar.dockTransparency ?? 0
    }
    Item {
        id: interaction
        objectName: "dockInteractionRegion"
        visible: dock.available
        x: dock.inputRect.x; y: dock.inputRect.y
        width: dock.inputRect.width; height: dock.inputRect.height
        HoverHandler {
            id: cardHover
            blocking: false
            onHoveredChanged: {
                dockState.retain(hovered);
                if (hovered) { collapseDelay.stop(); dock.revealed = true; }
                else {
                    dockState.leave(dockState.hoveredMenu);
                    collapseDelay.restart();
                    // For keyboard-opened or shortcut-opened items, full collapse on mouse leave
                    if (dock.keyboardSession && dock.section && !headerPointer.running) {
                        // Give a short delay so user can briefly move mouse out without immediate close
                        Qt.callLater(() => {
                            if (!cardHover.hovered && dock.keyboardSession && dock.section) {
                                dock.collapse();
                            }
                        }, 400);
                    }
                }
            }
        }
    }
    FocusScope {
        id: card
        clip: true
        parent: interaction
        objectName: "hyprdockSurface"
        visible: dock.available
        width: dock.surfaceRect.width
        height: dock.surfaceRect.height
        x: dock.surfaceRect.x - interaction.x
        y: dock.surfaceRect.y - interaction.y
        readonly property var menuColors: dock.menuColors
        Keys.onEscapePressed: { if (dock.section) dock.closeContent(); else dock.collapse(); }
        AttachedPanelSurface {
            anchors.fill: parent
            edge: dock.edge
            start: 12
            end: (dock.vertical ? height : width) - 12
            surfaceColor: glass.bottomColor
            outlineColor: "transparent"
            raised: false
        }
        // The first four pixels only reveal items, never activate their menus.
        MouseArea {
            objectName: "dockBase"
            z: 20
            x: dock.edge === "right" ? parent.width - width : 0
            y: dock.edge === "bottom" ? parent.height - height : 0
            width: dock.vertical ? 4 : parent.width
            height: dock.vertical ? parent.height : 4
            hoverEnabled: true
            onEntered: { collapseDelay.stop(); dockState.retain(true); dockState.leave(dockState.hoveredMenu); dock.revealed = true; }
        }
        Text {
            anchors.centerIn: parent
            visible: !dock.expanded
            text: dock.clockText
            color: dock.menuColors.text
            font.family: "Noto Sans"; font.pixelSize: 12; font.bold: true; font.letterSpacing: 1
        }
        FocusScope {
            id: strip
            objectName: "dockItemStrip"
            visible: dock.expanded
            x: dock.vertical ? (dock.edge === "right" ? parent.width - width : 0) : (parent.width - width) / 2
            y: dock.vertical ? (parent.height - height) / 2 : (dock.edge === "bottom" ? parent.height - height : 0)
            width: dock.vertical ? dock.stripSize : dock.stripLength
            height: dock.vertical ? dock.stripLength : dock.stripSize
            Keys.onLeftPressed: event => { focusNext(false); event.accepted = true; }
            Keys.onRightPressed: event => { focusNext(true); event.accepted = true; }
            Keys.onUpPressed: event => { focusNext(false); event.accepted = true; }
            Keys.onDownPressed: event => { focusNext(true); event.accepted = true; }
            function focusNext(forward) {
                let current = Window.window?.activeFocusItem || strip;
                let next = current.nextItemInFocusChain(forward);
                if (next) next.forceActiveFocus();
            }
            Flickable {
                id: stripScroll
                x: dock.vertical ? 0 : 180
                y: dock.vertical ? 180 : 4
                width: dock.vertical ? parent.width : Math.max(1, parent.width - 200)
                height: dock.vertical ? Math.max(1, parent.height - 200) : parent.height - 8
                contentWidth: dock.vertical ? width : stripBar.width
                contentHeight: dock.vertical ? stripBar.height : height
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                Bar {
                    id: stripBar
                    objectName: "dockBar"
                    width: dock.vertical ? stripScroll.width : dock.naturalLength
                    height: dock.vertical ? dock.naturalLength : stripScroll.height
                    settings: {
                        let config = Model.copy(dock.store.panelConfig);
                        Object.assign(config.bar, {fullBackground: "off", edgeAttached: false, autoHide: false, centerItems: false,
                            background: "off", hyprknots: false, uniformItems: false, height: 36,
                            contentPaddingTop: 0, contentPaddingBottom: 0, contentPaddingLeft: 0, contentPaddingRight: 0,
                            verticalPresentation: "compact"});
                        const status = ["bluetooth", "audio", "wifi", "battery", "power"];
                        const sideOrder = {left: 0, center: 1, right: 2};
                        config.items.sort((a, b) => (sideOrder[a.side] - sideOrder[b.side]) || a.order - b.order);
                        config.items = config.items.filter(item => !status.includes(item.id))
                            .concat(status.map(id => config.items.find(item => item.id === id)).filter(Boolean))
                            .map((item, index) => Object.assign(item, {side: "left", order: index, pillGroup: "",
                                spacingLeft: 2, spacingRight: 2, paddingLeft: 5, paddingRight: 5,
                                iconSize: 16, fontSize: 12}, ["launcher", "settings"].includes(item.id) ? {enabled: false} : {}));
                        // The dock has its own dark backing: use bright ink directly,
                        // rather than adapting bare glyphs to the wallpaper behind it.
                        if (config.bar.randomVibrantColors) {
                            for (let item of config.items) {
                                if (item.adaptiveColors && item.adaptiveColors !== "inherit") continue;
                                if (!item.iconColor) item.iconColor = dock.itemColor(item.id);
                                if (!item.textColor) item.textColor = dock.itemColor(item.id);
                            }
                        }
                        return config;
                    }
                    statusIconsOnly: true
                    dockStyle: true
                    dockBatteryLevel: dock.services.batteryInfo.percentage / 100
                    dockSignalLevel: dock.services.connectedWifi ? dock.services.connectedWifi.signalStrength : dock.services.wired ? 1 : 0
                    compactItemPadding: true
                    hoverPopdowns: true
                    clockText: dock.clockText
                    statusData: dock.services.statusData
                    mediaData: dock.services.mediaData
                    notificationData: dock.inbox.statusData
                    trayModel: dock.trayModel
                    outputName: dock.screen?.name || ""
                    wallpaperSource: dock.wallpaperSource
                    screenWidth: dock.width; screenHeight: dock.height
                    screenOffsetX: dock.surfaceRect.x + strip.x + stripScroll.x - stripScroll.contentX
                    screenOffsetY: dock.surfaceRect.y + strip.y + stripScroll.y - stripScroll.contentY
                    activeMenu: dock.section
                    onItemFocusRequested: item => {
                        let point = item.mapToItem(stripBar, 0, 0);
                        if (dock.vertical) stripScroll.contentY = Math.max(0, Math.min(stripScroll.contentHeight - stripScroll.height, point.y - stripScroll.height / 2));
                        else stripScroll.contentX = Math.max(0, Math.min(stripScroll.contentWidth - stripScroll.width, point.x - stripScroll.width / 2));
                    }
                    onMenuHovered: name => dockState.hover(name)
                    onMenuLeft: name => dockState.leave(name)
                    onPreviewUnavailable: dockState.close()
                    onAction: (name, argument) => {
                        if (name === "workspace") { dockState.close(); dock.services.workspace(argument); }
                        else if (name === "workspace-scroll") dock.services.scrollWorkspace(argument);
                        else dock.open(name, false);
                    }
                    onTrayAction: (item, source, button) => {
                        if (button === Qt.MiddleButton) item.secondaryActivate();
                        else if (button === Qt.RightButton || item.onlyMenu) {
                            let p = source.mapToItem(dock.contentItem, 0, source.height);
                            if (item.hasMenu) item.display(dock, p.x, p.y);
                        } else item.activate();
                    }
                    onTrayScroll: (item, event) => item.scroll(event.angleDelta.y || event.angleDelta.x, !event.angleDelta.y)
                }
            }
            Item {
                x: dock.vertical ? 0 : 20
                y: dock.vertical ? 20 : 4
                width: dock.vertical ? dock.stripSize : 160
                height: dock.vertical ? 160 : dock.stripSize - 8
                Repeater {
                    model: [{name:"launcher", icon:"", label:"Applications"}, {name:"dashboard", icon:"󰕮", label:"Dashboard"}, {name:"settings", icon:"󰒓", label:"Settings"}, {name:"keybindings", icon:"󰌌", label:"Keyboard shortcuts"}, {name:"activity", icon:"󰂚", label:"Activity and notifications"}]
                    ToolButton {
                        required property var modelData
                        required property int index
                        x: dock.vertical ? 0 : index * 32
                        y: dock.vertical ? index * 32 : 0
                        width: dock.vertical ? dock.stripSize : 32; height: dock.vertical ? 32 : dock.stripSize - 8
                        objectName: modelData.name + "DockTrigger"
                        Accessible.name: modelData.label
                        activeFocusOnTab: true
                        hoverEnabled: true
                        onHoveredChanged: { if (hovered) dockState.hover(modelData.name); else dockState.leave(modelData.name); }
                        onClicked: dock.open(modelData.name, false)
                        background: Rectangle { radius: 8; color: parent.hovered || parent.activeFocus ? Qt.rgba(dock.menuColors.text.r, dock.menuColors.text.g, dock.menuColors.text.b, 0.12) : "transparent"; border.width: parent.activeFocus ? 1 : 0; border.color: dock.menuColors.accent }
                        contentItem: Item {
                            id: shortcutIcon
                            readonly property var button: parent
                            scale: button.hovered || button.activeFocus ? 1.08 : 1
                            Behavior on scale { enabled: dock.motionEnabled; NumberAnimation { duration: 120 } }
                            Text { anchors.fill: parent; text: shortcutIcon.button.modelData.icon; visible: shortcutIcon.button.modelData.name !== "settings"; color: dock.itemColor(shortcutIcon.button.modelData.name); font.family: "GoMono Nerd Font"; font.pixelSize: 16; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                            GlassCog {
                                anchors.centerIn: parent
                                visible: shortcutIcon.button.modelData.name === "settings"
                                width: 19; height: 22; iconSize: 19
                                accent: dock.itemColor("settings")
                                highlighted: shortcutIcon.button.hovered || dock.section === "settings"
                                vivid: true
                            }
                            Grid {
                                anchors.centerIn: parent
                                visible: shortcutIcon.button.modelData.name === "launcher"
                                columns: 3; spacing: 3
                                Repeater { model: 9; Rectangle { required property int index; width: 3; height: 3; radius: 1.5; color: dock.itemColor("launcher") } }
                            }
                        }
                    }
                }
            }
        }
        Item {
            id: body
            objectName: "hyprdockBody"
            x: dock.edge === "left" ? dock.stripSize + 8 : 20
            y: dock.edge === "top" ? dock.stripSize + 8 : 20
            width: Math.max(1, card.width - (dock.vertical ? dock.stripSize + 28 : 40))
            height: Math.max(1, card.height - (dock.vertical ? 40 : dock.stripSize + 28))
            visible: dock.section.length > 0
            clip: true
            ColumnLayout {
                anchors.fill: parent
                spacing: 10
                Loader {
                    id: popupLoader
                    visible: active
                    Layout.fillWidth: true
                    Layout.preferredHeight: item ? Math.min(150, item.implicitHeight) : 0
                    active: dock.notificationTarget && dock.inbox.popups.length > 0
                    sourceComponent: Component { ScrollView { implicitHeight: popupStack.implicitHeight; clip: true; contentWidth: availableWidth; NotificationPopupStack { id: popupStack; width: parent.width; inbox: dock.inbox } } }
                }
                RowLayout {
                    id: headingRow
                    objectName: "dockHeading"
                    Layout.fillWidth: true
                    Label { Layout.fillWidth: true; text: ({settings:"Hyprsettings",dashboard:"Dashboard",activity:"Activity",keybindings:"Keyboard shortcuts",launcher:"Applications",calendar:"Calendar",audio:"Audio",wifi:"Wi-Fi",bluetooth:"Bluetooth",battery:"Battery",power:"Power",media:"Now playing",notifications:"Notifications",displays:"Projector options",alerts:"Notifications",workspacePreview:"Workspace"})[dockState.displayedSection] || "Hyprdock"; color: dock.headerColor; font.pixelSize: 16 }
                    ToolButton {
                        Accessible.name: "Close dock content"
                        implicitWidth: 30; implicitHeight: 30
                        background: Rectangle { radius: 8; color: parent.hovered ? Qt.rgba(dock.menuColors.text.r, dock.menuColors.text.g, dock.menuColors.text.b, 0.12) : "transparent" }
                        contentItem: Text { text: "×"; font.pixelSize: 20; color: dock.menuColors.text; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                        onClicked: dock.closeContent()
                    }
                }
                Item {
                    Layout.fillWidth: true; Layout.fillHeight: true
                    Flickable {
                        id: settingsSlot
                        anchors.fill: parent
                        visible: dock.section === "settings"
                        clip: true
                        contentWidth: Math.max(width, 760)
                        contentHeight: height
                        boundsBehavior: Flickable.StopAtBounds
                        Item { id: settingsInner; property var output: dock.screen; width: settingsSlot.contentWidth; height: settingsSlot.height }
                        ScrollBar.horizontal: ScrollBar {}
                    }
                    Item { id: projectorSlot; anchors.fill: parent; visible: dock.section === "displays" }
                    ScrollView {
                        id: dashboardViewport
                        anchors.fill: parent
                        visible: dock.section === "dashboard"
                        clip: true
                        contentWidth: availableWidth
                        Loader {
                            id: dashboardLoader
                            width: dashboardViewport.availableWidth
                            active: dock.dashboardLoaded
                            sourceComponent: dashboardPage
                        }
                    }
                    Loader {
                        id: activityLoader
                        anchors.fill: parent
                        visible: dock.section === "activity"
                        active: dock.activityLoaded
                        sourceComponent: activityPage
                    }
                    ScrollView {
                        id: menuViewport
                        anchors.fill: parent
                        visible: !["settings", "displays", "dashboard", "activity"].includes(dock.section)
                        clip: true
                        contentWidth: availableWidth
                        Loader {
                            id: page
                            objectName: "dockMenuPage"
                            width: menuViewport.availableWidth
                            height: implicitHeight
                            active: dock.section.length > 0 && !["settings", "displays", "dashboard", "activity"].includes(dock.section)
                            sourceComponent: ({dashboard:dashboardPage,activity:activityPage,keybindings:keysPage,launcher:launcherPage,calendar:calendarPage,audio:audioPage,wifi:wifiPage,bluetooth:bluetoothPage,battery:batteryPage,power:powerPage,notifications:inboxPage,media:mediaPage,workspacePreview:workspacePage})[dockState.displayedSection] || null
                            onLoaded: if (dockState.openedByShortcut) Qt.callLater(() => { if (page.item) { if (page.item.focusFirst) page.item.focusFirst(); else if (!["launcher", "keybindings"].includes(dock.section)) page.item.forceActiveFocus(); } });
                        }
                    }
                }
            }
        }
    }
    // Focus tracking: when focus moves out of dock content on search-autofocus windows,
    // trigger auto-close behavior for non-pinned keyboard sessions.
    Timer {
        id: focusTracker
        interval: 150; running: dock.section.length > 0; repeat: true
        onTriggered: {
            if (!dock.section) return;
            // Only track for windows with autofocus search bars
            if (!["launcher", "keybindings", "settings"].includes(dock.section)) return;
            // Check if focus moved outside dock content
            let activeItem = Window.activeFocusItem;
            let focusInsideDock = false;
            if (activeItem) {
                try {
                    let mapped = activeItem.mapToItem(card, 0, 0);
                    focusInsideDock = mapped !== null && mapped.x >= -200 && mapped.y >= -200
                        && mapped.x <= card.width + 200 && mapped.y <= card.height + 200;
                } catch (e) {
                    focusInsideDock = false;
                }
            }
            // When focus leaves dock content and we're not pinned, trigger close behavior
            if (!focusInsideDock && !dockState.pinned && dock.keyboardSession) {
                collapseDelay.restart();
                dockState.retain(false);
            } else if (focusInsideDock) {
                collapseDelay.stop();
                dockState.retain(true);
            }
        }
    }
    Connections {
        target: Window
        function onActiveFocusItemChanged() {
            if (!dock.section || dockState.pinned) return;
            // For keyboard session windows, detect focus out quickly
            if (dock.keyboardSession && ["launcher", "keybindings", "settings"].includes(dock.section)) {
                Qt.callLater(() => {
                    let activeItem = Window.activeFocusItem;
                    let inside = false;
                    if (activeItem) {
                        try {
                            let p = activeItem.mapToItem(card, 0, 0);
                            inside = (p !== null && p.x >= -100 && p.y >= -100
                                && p.x <= card.width + 100 && p.y <= card.height + 100);
                        } catch (e) { inside = false; }
                    }
                    if (!inside && !dockState.pinned) {
                        dockState.retain(false);
                    }
                });
            }
        }
    }
    // Wait for the surface to settle, then target the actual heading in logical
    // output coordinates. A section change from pointer hover never warps it.
    Connections {
        target: dockState
        function onSectionChanged() {
            headerPointer.stop();
            if (dock.section && dockState.openedByShortcut) headerPointer.restart();
        }
    }
    Timer {
        id: headerPointer
        interval: 100; repeat: true
        onTriggered: {
            if (!dock.section || !dockState.openedByShortcut) { stop(); return; }
            if (Math.abs(dock.surfaceWidth - dock.targetWidth) > 0.5
                || Math.abs(dock.surfaceHeight - dock.targetHeight) > 0.5) return;
            stop();
            let monitor = Hyprland.monitorFor(dock.screen);
            if (!monitor) return;
            let point = headingRow.mapToItem(dock.contentItem, headingRow.width / 2, headingRow.height / 2);
            let x = Math.round(monitor.x + point.x), y = Math.round(monitor.y + point.y);
            Hyprland.dispatch("hl.dsp.cursor.move({ x = " + x + ", y = " + y + " })");
        }
    }
    function showNotifications() {
        if (!modeEnabled || !notificationTarget || !inbox) return;
        if (inbox.popups.length && !section) { requested = true; revealed = true; dockState.section = "alerts"; }
        else if (!inbox.popups.length && section === "alerts") { dockState.close(); collapseDelay.restart(); }
    }
    onModeEnabledChanged: showNotifications()
    onNotificationTargetChanged: {
        if (!notificationTarget && section === "alerts") collapse();
        else showNotifications();
    }
    Connections {
        target: dock.inbox
        function onPopupsChanged() { dock.showNotifications(); }
    }
    Connections {
        target: dock.projector
        function onDockOpenedChanged() { if (dock.projector?.dockHost === projectorSlot && !dock.projector.dockOpened && dockState.section === "displays") dock.closeContent(); }
    }
    Connections { target: dockState; function onSectionChanged() { if (!dockState.section && !cardHover.hovered) collapseDelay.restart(); } }
    Process {
        running: dock.available && dock.section === "dashboard"
        command: ["python3", decodeURIComponent(Qt.resolvedUrl("helpers/dashboard-status.py").toString().replace(/^file:\/\//, "")), "--watch"]
        stdout: SplitParser { onRead: line => { try { dock.resourceData = JSON.parse(line); } catch (e) {} } }
    }
    Component { id: dashboardPage; DashboardContent { services: dock.services; resourceData: dock.resourceData; active: dock.section === "dashboard"; wallpaperSource: dock.wallpaperSource; screenWidth: dock.width; screenHeight: dock.height; wallpaperRegion: glass.region; onDismissRequested: dock.closeContent(); onSettingsRequested: dock.open("settings", true); onLockRequested: dock.lockRequested(); onMenuRequested: name => dock.open(name, true) } }
    Component { id: activityPage; ActivityContent { inbox: dock.inbox; store: dock.store; active: dock.section === "activity"; wallpaperSource: dock.wallpaperSource; screenWidth: dock.width; screenHeight: dock.height; wallpaperRegion: glass.region; onDismissRequested: dock.closeContent() } }
    Component { id: keysPage; KeybindingsMenu { fitContent: true } }
    Component { id: launcherPage; LauncherMenu { fitContent: true; applicationService: dock.applicationService; wallpaperSource: dock.wallpaperSource; active: dock.section === "launcher"; onLaunched: dock.collapse() } }
    Component { id: calendarPage; CalendarMenu {} }
    Component { id: audioPage; AudioMenu { services: dock.services } }
    Component { id: wifiPage; WifiMenu { services: dock.services } }
    Component { id: bluetoothPage; BluetoothMenu { services: dock.services } }
    Component { id: batteryPage; BatteryMenu { services: dock.services } }
    Component { id: powerPage; PowerMenu {} }
    Component { id: inboxPage; InboxMenu { inbox: dock.inbox } }
    Component { id: mediaPage; MediaPreview { mediaData: dock.services.mediaData; active: dock.section === "media" } }
    Component { id: workspacePage; WorkspacePreview { workspaceId: stripBar.previewWorkspace?.id || 0; output: dock.screen; wallpaperSource: dock.wallpaperSource; active: dock.section === "workspacePreview" } }
}
