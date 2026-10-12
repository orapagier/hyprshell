pragma ComponentBehavior: Bound
import QtQuick
import "SettingsModel.js" as Settings

Item {
    id: bar
    property var settings: ({})
    readonly property string position: settings.bar?.position || "top"
    readonly property bool vertical: position === "left" || position === "right"
    // Derive side-bar width from preferences, rather than wrapped content:
    // wrapped labels depend on their width and must not resize their container.
    readonly property real verticalThickness: Math.max(68, (settings.bar?.height || 32) + 4,
        ...Object.keys(moduleItems).filter(id => itemShown(id)).map(id => {
            let style = Settings.appearance(settings, id);
            return Math.max(64, settings.bar?.height || 32, (style.iconSize || 16) + 24) + 4;
        }))
    function itemX(id) { return vertical ? (width - moduleItems[id].width) / 2 : itemPosition(id); }
    function itemY(id) { return vertical ? itemPosition(id) : (height - moduleItems[id].height) / 2; }
    readonly property var moduleItems: ({
            launcher: distroLogo,
            settings: settingsCog,
            workspaces: workspaceRow,
            media: mediaSlot,
            calendar: clock,
            tray: trayPill,
            notifications: bell,
            audio: audio,
            wifi: wifi,
            bluetooth: bluetooth,
            battery: battery,
            power: power
        })
    readonly property var defaultSides: ({
            launcher: "left",
            settings: "left",
            workspaces: "left",
            media: "left",
            calendar: "center"
        })
    function itemEnabled(id) {
        return Settings.item(settings, id).enabled !== false;
    }
    function side(id) {
        return Settings.item(settings, id).side || defaultSides[id] || "right";
    }
    function pillName(id) { return Settings.item(settings, id).pillGroup || ""; }
    function itemShown(id) {
        // Item.visible also becomes false when an ancestor is hidden. Keep
        // module geometry stable when switching Settings pages or workspaces.
        if (!itemEnabled(id)) return false;
        if (id === "media") return mediaSlot.active;
        if (id === "tray") return trayIcons.count > 0;
        if (id === "battery") return !!statusData.battery.present;
        return true;
    }
    function orderedItems(sideName) {
        let keys = Object.keys(moduleItems);
        let sorted = keys.filter(k => side(k) === sideName && itemShown(k));
        sorted.sort((a, b) => ((Settings.item(settings, a).order ?? keys.indexOf(a)) - (Settings.item(settings, b).order ?? keys.indexOf(b))) || keys.indexOf(a) - keys.indexOf(b));
        let result = [], seen = new Set();
        for (let id of sorted) {
            if (!pillName(id)) result.push(id);
            else if (!seen.has(pillName(id))) {
                seen.add(pillName(id));
                result.push(...sorted.filter(k => pillName(k) === pillName(id)));
            }
        }
        return result;
    }
    readonly property var sharedPills: {
        let result = [];
        for (let sideName of ["left", "center", "right"]) {
            let seen = new Set();
            for (let id of orderedItems(sideName)) {
                let name = pillName(id);
                if (name && !seen.has(name)) {
                    seen.add(name);
                    result.push({name:name, side:sideName, ids:orderedItems(sideName).filter(k => pillName(k) === name)});
                }
            }
        }
        return result;
    }
    function sharedRect(ids) {
        let first = moduleItems[ids[0]], last = moduleItems[ids[ids.length - 1]];
        if (vertical) {
            let w = Math.max(...ids.map(id => moduleItems[id].width));
            return Qt.rect((width-w)/2, first.y, w, last.y + last.height - first.y);
        }
        let h = Math.max(...ids.map(id => moduleItems[id].height));
        return Qt.rect(first.x, (height-h)/2, last.x + last.width - first.x, h);
    }
    function appearance(id) {
        let style = Settings.appearance(settings, id, wallpaperSource.toString());
        let group = sharedPills.find(group => group.ids.includes(id));
        if (group) style.sharedBackgroundShown = Settings.sharedBackground(settings, group.ids[0]) !== "off";
        return style;
    }
    function sharedStyle(id) {
        let style = bar.appearance(id);
        style.background = Settings.sharedBackground(settings, id);
        style.hideText = true;
        style.hideIcon = true;
        return style;
    }
    function itemPosition(id) {
        let group = orderedItems(side(id));
        let spacing = settings.bar ? (settings.bar.spacing ?? 3) : 3;
        let left = k => Settings.item(settings, k).spacingLeft || 0;
        let right = k => Settings.item(settings, k).spacingRight || 0;
        let leading = group.length ? Math.max(0, left(group[0])) : 0;
        let trailing = group.length ? Math.max(0, right(group[group.length - 1])) : 0;
        let gap = i => Math.max(0, (pillName(group[i]) && pillName(group[i]) === pillName(group[i + 1]) ? (settings.bar?.groupSpacing ?? 3) : spacing) + right(group[i]) + left(group[i + 1]));
        let total = leading + trailing + group.reduce((n, k, i) => n + (vertical ? moduleItems[k].height : moduleItems[k].width) + (i < group.length - 1 ? gap(i) : 0), 0);
        let length = vertical ? height : width;
        let cursor = (side(id) === "right" ? length - total : side(id) === "center" ? (length - total) / 2 : 0) + leading;
        for (let i = 0; i < group.length; i++) {
            let k = group[i];
            if (k === id)
                return cursor;
            cursor += (vertical ? moduleItems[k].height : moduleItems[k].width) + (i < group.length - 1 ? gap(i) : 0);
        }
        return cursor;
    }
    property var statusData: ({
            workspaces: [],
            audio: {},
            network: {},
            bluetooth: {},
            battery: {}
        })
    property var mediaData: ({
            playing: false,
            levels: [],
            title: "",
            tooltip: ""
        })
    property var notificationData: ({
            count: 0,
            tooltip: "Notifications",
            class: "empty"
        })
    property string outputName: ""
    property url wallpaperSource: ""
    property real screenWidth: width + 20
    property real screenHeight: 768
    property real screenOffsetX: 10
    property real screenOffsetY: 5
    readonly property alias wallpaperColors: wallpaperSampler
    WallpaperColors {
        id: wallpaperSampler
        source: bar.wallpaperSource
        screenWidth: bar.screenWidth
        screenHeight: bar.screenHeight
        offsetX: bar.screenOffsetX
        offsetY: bar.screenOffsetY
        bandHeight: bar.height
        bandWidth: bar.vertical ? bar.width : bar.screenWidth
        regionOffsetX: bar.vertical ? bar.screenOffsetX : 0
    }
    property var trayModel: []
    property string clockText: ""
    property string activeMenu: ""
    signal menuHovered(string name)
    signal menuLeft(string name)
    readonly property var menuTargets: ({
            launcher: distroLogo,
            settings: settingsCog,
            calendar: clock,
            notifications: bell,
            audio: audio,
            wifi: wifi,
            bluetooth: bluetooth,
            battery: battery,
            power: power
        })
    function menuRect(name) {
        let item = menuTargets[name];
        if (!item)
            return Qt.rect(12, 2, 24, 20);
        // Read layout positions directly so the connector follows screen and
        // status-width changes, including movement of the containing row.
        // Anchor on the visible content, which asymmetric inside-pill padding
        // shifts away from the item's geometric centre.
        let contentShift = vertical ? 0 : (item.effectiveLeftPadding - item.effectiveRightPadding) / 2;
        return Qt.rect(item.x + contentShift, item.y, item.width, item.height);
    }
    function menuAccent(name) {
        let item = menuTargets[name];
        if (!item)
            return "#b4befe";
        // Follow the visible glyph, including custom and adaptive colors.
        if (name === "launcher" || name === "settings")
            return item.settings.iconColor || item.settings.textColor || item.effectiveForeground;
        return item.shownIcon.length ? item.iconColor : item.textColor;
    }
    signal action(string name, var argument)
    signal trayAction(var item, var source, int button)
    signal trayScroll(var item, var event)
    function rgba(hex, alpha) {
        return Qt.rgba(parseInt(hex.slice(1, 3), 16) / 255, parseInt(hex.slice(3, 5), 16) / 255, parseInt(hex.slice(5, 7), 16) / 255, alpha);
    }
    implicitWidth: vertical ? verticalThickness : 0
    implicitHeight: vertical ? screenHeight - 2 * (settings.bar?.marginSide ?? 10)
        : Math.max(settings.bar?.height || 32,
            ...Object.keys(moduleItems).filter(id => itemShown(id)).map(id => moduleItems[id].height + 4))
    height: implicitHeight
    Repeater {
        model: bar.sharedPills
        delegate: Pill {
            required property var modelData
            objectName: "sharedPill_" + modelData.name
            readonly property var bounds: bar.sharedRect(modelData.ids)
            readonly property string leader: modelData.ids[0]
            x: bounds.x; y: bounds.y; width: bounds.width; height: bounds.height
            z: -1
            interactive: false
            settings: bar.sharedStyle(leader)
            foreground: bar.moduleItems[leader].foreground ?? "#cdd6f4"
            tint: bar.moduleItems[leader].tint ?? Qt.rgba(30/255, 30/255, 46/255, 0.28)
            outline: bar.moduleItems[leader].outline ?? Qt.rgba(1, 1, 1, 0.16)
            colorSampler: Settings.adaptive(bar.settings, leader) ? bar.wallpaperColors : null
            colorRoot: bar
            opacity: Settings.item(bar.settings, leader).opacity ?? 1
        }
    }
    BarMenuButton {
        id: distroLogo
        bar: bar
        menu: "launcher"
        x: bar.itemX("launcher")
        y: bar.itemY("launcher")
        vertical: bar.vertical
        maximumWidth: bar.vertical ? Math.max(64, bar.settings.bar?.height || 32, (settings.iconSize || 16) + 24) : 10000
        settings: bar.appearance("launcher")
        opacity: Settings.item(bar.settings, "launcher").opacity ?? 1
        visible: bar.itemEnabled("launcher")
        text: ""
        foreground: "#51a2da"
        family: "GoMono Nerd Font"
        pixelSize: 20
        bold: false
        minimumTextWidth: settings.iconSize || settings.fontSize || 22
        implicitHeight: Math.max(28, (settings.iconSize || settings.fontSize || 22) + 6, content.implicitHeight + 8)
        leftPadding: 2
        rightPadding: 2
        backgroundVisible: false
        content.opacity: distroLogo.settings.text || distroLogo.settings.icon ? 1 : 0
        GlassLogo {
            objectName: "distroGlassLogo"
            iconSize: distroLogo.settings.iconSize || distroLogo.settings.fontSize || 22
            visible: !distroLogo.settings.text && !distroLogo.settings.icon && !distroLogo.settings.hideText && !distroLogo.settings.hideIcon
            x: distroLogo.content.x
            width: distroLogo.content.width
            height: distroLogo.height
            accent: distroLogo.settings.iconColor || distroLogo.settings.textColor || distroLogo.effectiveForeground
            highlighted: distroLogo.hovered || distroLogo.selected
            contrastEdge: distroLogo.glyphHalo
            edgeColor: distroLogo.iconEdge
            vivid: distroLogo.bare
        }
    }
    BarMenuButton {
        id: settingsCog
        bar: bar; menu: "settings"
        x: bar.itemX("settings"); y: bar.itemY("settings")
        vertical: bar.vertical
        maximumWidth: bar.vertical ? Math.max(64, bar.settings.bar?.height || 32, (settings.iconSize || 16) + 24) : 10000
        settings: bar.appearance("settings")
        opacity: settings.opacity ?? 1
        visible: bar.itemEnabled("settings")
        text: "󰒓"
        family: "GoMono Nerd Font"; pixelSize: 16
        backgroundVisible: false
        minimumTextWidth: Math.max(16, settings.iconSize || settings.fontSize || 22)
        implicitHeight: Math.max(28, (settings.iconSize || settings.fontSize || 22) + 6, content.implicitHeight + 8)
        content.opacity: settingsCog.settings.text || settingsCog.settings.icon ? 1 : 0
        GlassCog {
            objectName: "settingsGlassCog"
            iconSize: settingsCog.settings.iconSize || settingsCog.settings.fontSize || 22
            visible: !settingsCog.settings.text && !settingsCog.settings.icon && !settingsCog.settings.hideText && !settingsCog.settings.hideIcon
            x: settingsCog.content.x; width: settingsCog.content.width; height: settingsCog.height
            accent: settingsCog.settings.iconColor || settingsCog.settings.textColor || settingsCog.effectiveForeground
            highlighted: settingsCog.hovered || settingsCog.selected
            contrastEdge: settingsCog.glyphHalo
            edgeColor: settingsCog.iconEdge
            vivid: settingsCog.bare
        }
        foreground: "#b4befe"
        tint: bar.rgba("#b4befe", 0.18); outline: bar.rgba("#b4befe", 0.26)
        leftPadding: 2; rightPadding: 2
    }
    Grid {
        id: workspaceRow
        x: bar.itemX("workspaces")
        y: bar.itemY("workspaces") + (bar.vertical ? 0 : Math.max(0, (height - implicitHeight) / 2))
        opacity: Settings.item(bar.settings, "workspaces").opacity ?? 1
        visible: bar.itemEnabled("workspaces")
        objectName: "workspacesSlot"
        columns: bar.vertical ? 1 : Math.max(1, workspaceRepeater.count)
        horizontalItemAlignment: Grid.AlignHCenter
        verticalItemAlignment: Grid.AlignVCenter
        height: Math.max(28, implicitHeight)
        spacing: 2
        leftPadding: Math.max(0, 1 + (Settings.item(bar.settings, "workspaces").paddingLeft || 0))
        rightPadding: Math.max(0, 3 + (Settings.item(bar.settings, "workspaces").paddingRight || 0))
        Repeater {
            id: workspaceRepeater
            model: (bar.statusData.workspaces || []).filter(w => !bar.outputName || w.monitor === bar.outputName)
            delegate: Pill {
                objectName: "workspace" + modelData.id
                settings: {
                    let appearance = Object.assign({}, bar.appearance("workspaces"), {paddingLeft:0, paddingRight:0});
                    if (active && appearance.vibrantColor) {
                        let base = Qt.color(appearance.vibrantColor);
                        // Use the opposite hue while preserving the existing pill styling.
                        appearance.vibrantColor = Qt.hsla((base.hslHue + 0.5) % 1, base.hslSaturation, base.hslLightness, 1).toString();
                    }
                    return appearance;
                }
                colorSampler: Settings.adaptive(bar.settings, "workspaces") ? bar.wallpaperColors : null
                colorRoot: bar
                required property var modelData
                property bool active: modelData.active || false
                vertical: bar.vertical
                maximumWidth: bar.vertical ? Math.max(1, bar.verticalThickness - 4 - workspaceRow.leftPadding - workspaceRow.rightPadding) : 10000
                height: Math.max(20, shownText.length ? content.implicitHeight + 6 : 0, shownIcon.length ? effectiveIconSize + 6 : 0)
                text: modelData.name || String(modelData.id)
                leftPadding: 7
                rightPadding: 7
                foreground: active ? "#cba6f7" : "#a0a0a0"
                colorStyle: active ? "emphasized" : "muted"
                selected: active
                raised: false
                onClicked: bar.action("workspace", modelData.id)
                onWheel: event => bar.action("workspace-scroll", event.angleDelta.y > 0 ? -1 : 1)
            }
        }
    }
    Loader {
        id: mediaSlot
        objectName: "mediaSlot"
        x: bar.itemX("media")
        y: bar.itemY("media")
        opacity: Settings.item(bar.settings, "media").opacity ?? 1
        active: bar.itemEnabled("media") && !!bar.mediaData && bar.mediaData.playing === true
        visible: active
        sourceComponent: MediaPill {
            vertical: bar.vertical
            settings: bar.appearance("media")
            colorSampler: Settings.adaptive(bar.settings, "media") ? bar.wallpaperColors : null
            colorRoot: bar
            text: bar.mediaData.title || ""
            levels: bar.mediaData.levels || []
            maximumWidth: bar.vertical ? Math.max(64, bar.settings.bar?.height || 32) : Math.max(80, Math.min(300, bar.width * 0.24))
            interactive: false
        }
    }
    BarMenuButton {
        id: clock
        bar: bar
        menu: "calendar"
        x: bar.itemX("calendar")
        y: bar.itemY("calendar")
        vertical: bar.vertical
        maximumWidth: bar.vertical ? Math.max(64, bar.settings.bar?.height || 32, (settings.iconSize || 16) + 24) : 10000
        settings: bar.appearance("calendar")
        opacity: Settings.item(bar.settings, "calendar").opacity ?? 1
        visible: bar.itemEnabled("calendar")
        leftPadding: bar.vertical ? 6 : 11
        rightPadding: bar.vertical ? 6 : 11
        text: bar.clockText
        foreground: "#b4befe"
        tint: bar.rgba("#b4befe", 0.20)
        outline: bar.rgba("#b4befe", 0.28)
    }
    Pill {
        id: trayPill
        x: bar.itemX("tray")
        y: bar.itemY("tray")
        vertical: bar.vertical
        maximumWidth: bar.vertical ? Math.max(64, bar.settings.bar?.height || 32, (settings.iconSize || 16) + 24) : 10000
        settings: bar.appearance("tray")
        opacity: Settings.item(bar.settings, "tray").opacity ?? 1
        colorSampler: Settings.adaptive(bar.settings, "tray") ? bar.wallpaperColors : null
        colorRoot: bar
        foreground: "#cba6f7"
        interactive: false
        visible: bar.itemEnabled("tray") && trayIcons.count > 0
        width: trayRow.width + effectiveLeftPadding + effectiveRightPadding
        implicitHeight: Math.max(28, trayRow.height + 8)
        readonly property int trayIconSize: settings.iconSize || 16
        Flow {
            id: trayRow
            flow: bar.vertical ? Flow.LeftToRight : Flow.TopToBottom
            width: bar.vertical ? trayPill.trayIconSize : implicitWidth
            height: bar.vertical ? implicitHeight : trayPill.trayIconSize
            x: trayPill.effectiveLeftPadding
            anchors.verticalCenter: parent.verticalCenter
            visible: !trayPill.settings.hideIcon
            spacing: 0
            Repeater {
                id: trayIcons
                model: bar.trayModel
                delegate: Item {
                    id: trayIcon
                    required property var modelData
                    objectName: "trayIcon"
                    width: trayPill.settings.hideIcon ? 0 : trayPill.trayIconSize
                    height: trayPill.trayIconSize
                    Image {
                        anchors.fill: parent
                        source: trayIcon.modelData.icon
                        sourceSize.width: trayPill.trayIconSize
                        sourceSize.height: trayPill.trayIconSize
                        fillMode: Image.PreserveAspectFit
                    }
                    MouseArea {
                        id: trayPointer
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                        onClicked: mouse => bar.trayAction(trayIcon.modelData, trayIcon, mouse.button)
                        onWheel: event => bar.trayScroll(trayIcon.modelData, event)
                    }
                }
            }
        }
    }
    BarMenuButton {
        id: bell
        bar: bar
        menu: "notifications"
        x: bar.itemX("notifications")
        y: bar.itemY("notifications")
        vertical: bar.vertical
        maximumWidth: bar.vertical ? Math.max(64, bar.settings.bar?.height || 32, (settings.iconSize || 16) + 24) : 10000
        settings: bar.appearance("notifications")
        opacity: Settings.item(bar.settings, "notifications").opacity ?? 1
        visible: bar.itemEnabled("notifications")
        objectName: "notificationBell"
        text: "󰂚"
        family: "GoMono Nerd Font"
        pixelSize: 15
        minimumTextWidth: 12
        leftPadding: 7
        rightPadding: badge.visible ? Math.max(11, badge.implicitWidth + 1) : 11
        foreground: bar.notificationData && bar.notificationData.count > 0 ? "#f9e2af" : "#a6adc8"
        tint: bar.rgba("#a6adc8", 0.18)
        outline: bar.rgba("#a6adc8", 0.26)
        Text {
            id: badge
            objectName: "notificationBadge"
            // Attach to the glyph's upper-right corner, independently of
            // the pill width or number of digits in the count.
            x: bell.content.x + (bell.content.width + bell.content.implicitWidth) / 2 - 2
            y: bell.content.y - 2
            visible: !!bar.notificationData && bar.notificationData.count > 0
            text: bar.notificationData ? String(bar.notificationData.count || "") : ""
            color: bell.effectiveForeground
            style: bell.glyphHalo ? Text.Outline : bell.bare ? Text.Raised : Text.Normal
            styleColor: bell.glyphHalo ? bell.textEdge : bell.glyphShadow
            renderType: Text.QtRendering
            font.family: "DejaVu Sans"
            font.pixelSize: Math.max(8, Math.round(8 * bell.effectiveGlyphSize / 15))
            font.bold: true
        }
    }
    BarMenuButton {
        id: audio
        x: bar.itemX("audio")
        y: bar.itemY("audio")
        vertical: bar.vertical
        maximumWidth: bar.vertical ? Math.max(64, bar.settings.bar?.height || 32, (settings.iconSize || 16) + 24) : 10000
        settings: bar.appearance("audio")
        opacity: Settings.item(bar.settings, "audio").opacity ?? 1
        visible: bar.itemEnabled("audio")
        bar: bar
        menu: "audio"
        icon: bar.statusData.audio.icon || "󰕾"
        text: bar.statusData.audio.text || "--"
        foreground: "#89b4fa"
        tint: bar.rgba("#89b4fa", 0.20)
        outline: bar.rgba("#89b4fa", 0.28)
    }
    BarMenuButton {
        id: wifi
        x: bar.itemX("wifi")
        y: bar.itemY("wifi")
        vertical: bar.vertical
        maximumWidth: bar.vertical ? Math.max(64, bar.settings.bar?.height || 32, (settings.iconSize || 16) + 24) : 10000
        settings: bar.appearance("wifi")
        opacity: Settings.item(bar.settings, "wifi").opacity ?? 1
        visible: bar.itemEnabled("wifi")
        bar: bar
        menu: "wifi"
        text: bar.statusData.network.text || "󰤮"
        foreground: bar.statusData.network.connected ? "#94e2d5" : "#585b70"
        tint: bar.rgba("#94e2d5", 0.18)
        outline: bar.rgba("#94e2d5", 0.26)
        family: "GoMono Nerd Font"
        pixelSize: 15
        implicitWidth: implicitHeight
        leftPadding: 4
        rightPadding: 4
        // Center the visible glyph rather than the font's advance box.
        content.horizontalAlignment: Text.AlignLeft
        content.elide: Text.ElideNone
        content.x: (wifi.width - wifiGlyphMetrics.tightBoundingRect.width) / 2
                   - wifiGlyphMetrics.tightBoundingRect.x
        TextMetrics {
            id: wifiGlyphMetrics
            font: wifi.content.font
            text: wifi.content.text
        }
    }
    BarMenuButton {
        id: bluetooth
        x: bar.itemX("bluetooth")
        y: bar.itemY("bluetooth")
        vertical: bar.vertical
        maximumWidth: bar.vertical ? Math.max(64, bar.settings.bar?.height || 32, (settings.iconSize || 16) + 24) : 10000
        settings: bar.appearance("bluetooth")
        opacity: Settings.item(bar.settings, "bluetooth").opacity ?? 1
        visible: bar.itemEnabled("bluetooth")
        bar: bar
        menu: "bluetooth"
        text: bar.statusData.bluetooth.text || "󰂲"
        foreground: bar.statusData.bluetooth.connected ? "#89b4fa" : bar.statusData.bluetooth.powered ? "#b4befe" : "#585b70"
        tint: bar.rgba("#b4befe", 0.20)
        outline: bar.rgba("#b4befe", 0.28)
        family: "GoMono Nerd Font"
        pixelSize: 15
        implicitWidth: implicitHeight
        leftPadding: 4
        rightPadding: 4
    }
    BarMenuButton {
        id: battery
        x: bar.itemX("battery")
        y: bar.itemY("battery")
        vertical: bar.vertical
        maximumWidth: bar.vertical ? Math.max(64, bar.settings.bar?.height || 32, (settings.iconSize || 16) + 24) : 10000
        settings: bar.appearance("battery")
        opacity: Settings.item(bar.settings, "battery").opacity ?? 1
        bar: bar
        menu: "battery"
        visible: bar.itemEnabled("battery") && !!bar.statusData.battery.present
        readonly property string batteryLabel: bar.statusData.battery.text || ""
        icon: batteryLabel.indexOf(" ") >= 0 ? batteryLabel.slice(0, batteryLabel.indexOf(" ")) : ""
        text: batteryLabel.indexOf(" ") >= 0 ? batteryLabel.slice(batteryLabel.indexOf(" ") + 1) : batteryLabel
        foreground: bar.statusData.battery.charging ? "#fab387" : bar.statusData.battery.warning ? "#f38ba8" : "#a6e3a1"
        tint: bar.rgba(foreground.toString(), bar.statusData.battery.charging ? 0.20 : bar.statusData.battery.warning ? 0.22 : 0.18)
        outline: bar.rgba(foreground.toString(), bar.statusData.battery.charging ? 0.28 : bar.statusData.battery.warning ? 0.32 : 0.26)
    }
    BarMenuButton {
        id: power
        x: bar.itemX("power")
        y: bar.itemY("power")
        vertical: bar.vertical
        maximumWidth: bar.vertical ? Math.max(64, bar.settings.bar?.height || 32, (settings.iconSize || 16) + 24) : 10000
        settings: bar.appearance("power")
        opacity: Settings.item(bar.settings, "power").opacity ?? 1
        visible: bar.itemEnabled("power")
        bar: bar
        menu: "power"
        text: "󰐥"
        foreground: "#f38ba8"
        tint: bar.rgba("#f38ba8", 0.18)
        outline: bar.rgba("#f38ba8", 0.26)
        hoverTint: bar.rgba("#f38ba8", 0.30)
        family: "GoMono Nerd Font"
        pixelSize: 15
        leftPadding: 9
        rightPadding: 9
    }
}
