pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import "SettingsModel.js" as Settings
import "AdaptiveColors.js" as Colors

Item {
    id: bar
    property var settings: ({})
    property string onlySide: ""
    property bool compactItemPadding: false
    property bool statusIconsOnly: false
    property bool hoverPopdowns: true
    readonly property string position: settings.bar?.position || "top"
    readonly property bool vertical: position === "left" || position === "right"
    readonly property bool centerItems: settings.bar?.centerItems === true
    readonly property bool iconsOnly: vertical || centerItems
    readonly property bool uniformItems: settings.bar?.uniformItems === true
    readonly property bool fullBackgroundEnabled: !statusIconsOnly && Settings.fullBackgroundEnabled(settings.bar || {})
    readonly property bool edgeAttached: fullBackgroundEnabled && settings.bar?.edgeAttached === true
    readonly property real fullPillInset: fullBackgroundEnabled ? 5 : 0
    readonly property real baseThickness: settings.bar?.height || 32
    readonly property real panelIconSize: settings.bar?.iconSize || baseThickness * (uniformItems ? 12 / 30 : 0.6 * 0.8)
    // Compact October appearance: 10 px text ink and 12 px icon ink at 30 px.
    readonly property real panelTextSize: panelIconSize * 10 / 12
    readonly property bool iconPills: vertical || centerItems
    readonly property real panelSlotSize: verticalThickness * 0.6
    readonly property real workspacePillSize: panelSlotSize * 0.72
    readonly property real panelItemInset: verticalThickness * 0.2
    readonly property bool compact: vertical && settings.bar?.verticalPresentation === "compact"
    // Resolve thickness from settings, independently of child geometry.
    readonly property real verticalThickness: Math.max(baseThickness, uniformItems ? panelIconSize / 0.48 : 0,
        ...Object.keys(moduleItems).filter(id => itemShown(id)).map(id => {
            let style = Settings.appearance(settings, id);
            return Math.max(style.iconSize || 0, style.fontSize || 0) / 0.48;
        }))
    readonly property bool knotsEnabled: !statusIconsOnly && settings.bar?.hyprknots !== false
    readonly property real knotSize: 4.8 * ((settings.bar?.hyprknotsKnotSize ?? 100) / 100)
    // Reserve the full motif, its stroke, and clearance from bare icon ink.
    readonly property real minimumKnotGap: Math.ceil(Math.max(3.6 * knotSize,
        2.5 * knotSize + 1.6 * ((settings.bar?.hyprknotsKnotSize ?? 100) / 100) + 2) + 4)
    readonly property real itemSpacing: settings.bar?.hyprknots === false ? (settings.bar?.compactSpacing ?? 3)
        : Math.max(settings.bar?.spacing ?? 3, knotsEnabled ? minimumKnotGap : 0)
    readonly property real attachmentInset: edgeAttached ? (vertical ? 16 : 11) : 0
    readonly property real insetTop: (settings.bar?.contentPaddingTop ?? 0) + (vertical ? attachmentInset + fullPillInset : 0)
    readonly property real insetBottom: (settings.bar?.contentPaddingBottom ?? 0) + (vertical ? attachmentInset + fullPillInset : 0)
    readonly property real insetLeft: (settings.bar?.contentPaddingLeft ?? 0) + (vertical ? 0 : attachmentInset + fullPillInset)
    readonly property real insetRight: (settings.bar?.contentPaddingRight ?? 0) + (vertical ? 0 : attachmentInset + fullPillInset)
    readonly property real contentWidth: Math.max(0, width - insetLeft - insetRight)
    readonly property real contentHeight: Math.max(0, height - insetTop - insetBottom)
    readonly property real sectionGap: uniformItems || centerItems || settings.bar?.hyprknots === false ? itemSpacing : Math.max(12, itemSpacing)
    readonly property real minimumVerticalLength: {
        let sizes = ["left", "center", "right"].map(side => groupLength(side)).filter(size => size > 0);
        return sizes.reduce((total, size) => total + size, 0) + Math.max(0, sizes.length - 1) * sectionGap;
    }
    readonly property real layoutLength: vertical ? Math.max(contentHeight, minimumVerticalLength) : contentWidth
    readonly property real scrollOffset: layoutViewport.contentY
    readonly property bool overflowing: vertical && minimumVerticalLength > contentHeight
    function itemRect(id) {
        let item = moduleItems[id];
        // Explicit offset dependency makes menu anchors follow a scrolling rail.
        let offset = scrollOffset;
        return Qt.rect(item.x, item.y - (vertical ? offset : 0), item.width, item.height);
    }
    function spacingOffset(id, key) { return uniformItems ? 0 : (Settings.item(settings, id)[key] || 0); }
    function gapBetween(first, second) {
        let base = !uniformItems && !centerItems && pillName(first) && pillName(first) === pillName(second) ? (settings.bar?.groupSpacing ?? 3) : itemSpacing;
        return Math.max(knotsEnabled ? minimumKnotGap : 0,
            base + spacingOffset(first, "spacingRight") + spacingOffset(second, "spacingLeft"));
    }
    function groupLength(sideName) {
        let ids = orderedItems(sideName);
        if (!ids.length) return 0;
        return Math.max(0, spacingOffset(ids[0], "spacingLeft"))
            + Math.max(0, spacingOffset(ids[ids.length - 1], "spacingRight"))
            + ids.reduce((total, id, i) => total + (vertical ? moduleItems[id].height : moduleItems[id].width) + (i ? gapBetween(ids[i - 1], id) : 0), 0);
    }
    function centeredGroupStart(sideName, length, center) {
        let sides = ["left", "center", "right"];
        let sizes = sides.map(side => groupLength(side));
        let total = sizes.reduce((sum, size) => sum + size, 0)
            + Math.max(0, sizes.filter(size => size > 0).length - 1) * sectionGap;
        // Honor available padding when the centered block approaches an edge.
        let cursor = Math.max(0, Math.min(Math.max(0, length - total), center - total / 2));
        for (let i = 0; i < sides.length; ++i) {
            if (sides[i] === sideName) return cursor;
            if (sizes[i]) cursor += sizes[i] + sectionGap;
        }
        return cursor;
    }
    function verticalGroupStart(sideName) {
        if (centerItems && !overflowing)
            return centeredGroupStart(sideName, layoutLength, screenHeight / 2 - screenOffsetY - insetTop);
        let sides = ["left", "center", "right"], sizes = sides.map(side => groupLength(side));
        if (compact || overflowing) {
            let cursor = Math.max(0, (layoutLength - minimumVerticalLength) / 2);
            for (let i = 0; i < sides.length; ++i) {
                if (sides[i] === sideName) return cursor;
                if (sizes[i]) cursor += sizes[i] + sectionGap;
            }
        }
        if (sideName === "left") return 0;
        if (sideName === "right") return layoutLength - sizes[2];
        let low = sizes[0] ? sizes[0] + sectionGap : 0;
        let high = layoutLength - sizes[1] - (sizes[2] ? sizes[2] + sectionGap : 0);
        return Math.max(low, Math.min(high, (layoutLength - sizes[1]) / 2));
    }
    signal itemFocusRequested(var item)
    function ensureItemVisible(item) {
        itemFocusRequested(item);
        if (!vertical) return;
        let position = item.mapToItem(layoutViewport.contentItem, 0, 0);
        let next = layoutViewport.contentY;
        if (position.y < next) next = position.y;
        else if (position.y + item.height > next + height) next = position.y + Math.min(item.height, height) - height;
        layoutViewport.contentY = Math.max(0, Math.min(layoutViewport.contentHeight - height, next));
    }
    function scrollVertical(event) {
        if (!overflowing) { event.accepted = false; return; }
        let delta = event.pixelDelta.y || event.angleDelta.y / 3;
        layoutViewport.contentY = Math.max(0, Math.min(layoutViewport.contentHeight - height, layoutViewport.contentY - delta));
        event.accepted = true;
    }
    function itemX(id) { return insetLeft + (vertical ? (contentWidth - moduleItems[id].width) / 2 : itemPosition(id)); }
    function itemY(id) { return insetTop + (vertical ? itemPosition(id) : (contentHeight - moduleItems[id].height) / 2); }
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
    function menuItemId(name) { return name === "workspacePreview" ? "workspaces" : name; }
    function itemEnabled(id) {
        return (!onlySide || side(id) === onlySide) && Settings.item(settings, id).enabled !== false;
    }
    function side(id) {
        id = menuItemId(id);
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
            return Qt.rect(insetLeft + (contentWidth-w)/2, first.y, w, last.y + last.height - first.y);
        }
        let h = Math.max(...ids.map(id => moduleItems[id].height));
        return Qt.rect(first.x, insetTop + (contentHeight-h)/2, last.x + last.width - first.x, h);
    }
    function backingPills(id) {
        let result = fullPill.participating ? [fullPill] : [];
        if (!vertical) for (let i = 0; i < sharedPillRepeater.count; ++i) {
            let surface = sharedPillRepeater.itemAt(i);
            if (surface && surface.modelData.ids.includes(id)) result.push(surface);
        }
        return result;
    }
    function appearance(id) {
        let style = Settings.appearance(settings, id, wallpaperSource.toString());
        style.lightForeground = true;
        style.outlineFree = true;
        style.uniformItems = uniformItems;
        style.panelItemPadding = 5;
        style.backgroundVerticalInset = fullBackgroundEnabled && !vertical && side(id) !== "left" ? 2 : 0;
        style.panelPillHeight = id === "workspaces" ? workspacePillSize : panelSlotSize;
        style.fitGlyphWidth = id === "workspaces";
        let itemSize = style.iconSize || panelIconSize;
        style.uniformGlyphHeight = uniformItems ? (id === "workspaces" ? Math.min(itemSize, workspacePillSize * 0.65) : itemSize) : id === "workspaces"
            ? (style.iconSize || style.fontSize ? 0 : workspacePillSize * 0.8)
            : style.iconSize || style.fontSize || panelSlotSize * 0.8;
        if (uniformItems) {
            style.uniformTextHeight = style.fontSize || (id === "workspaces" ? style.uniformGlyphHeight : itemSize * 10 / 12);
            // Share one font scale for dates, percentages and other text labels.
            if (id !== "workspaces") style.textSizeReference = "100%";
        }
        style.panelAdaptive = true;
        style.backingPills = backingPills(id);
        // Individual and shared surfaces retain wallpaper-tinted glass in either mode.
        style.glassSurface = true;
        style.pillTransparency = settings.bar?.individualPillTransparency ?? -1;
        style.circularIcons = true;
        if (uniformItems || id !== "workspaces") {
            if (!style.iconSize) style.iconSize = uniformItems ? itemSize : style.fontSize || panelSlotSize * 0.8;
        }
        if (compactItemPadding) style.compactPadding = true;
        let group = sharedPills.find(group => group.ids.includes(id));
        if (group) {
            if (vertical) {
                // Keep group membership/order, drawing its background as separate circles.
                style.background = Settings.sharedBackground(settings, group.ids[0]);
                style.sharedBackgroundShown = false;
                style.pillTransparency = settings.bar?.groupPillTransparency ?? -1;
            } else style.sharedBackgroundShown = Settings.sharedBackground(settings, group.ids[0]) !== "off";
        }
        return style;
    }
    function sharedStyle(id) {
        let style = bar.appearance(id);
        style.backingPills = fullPill.participating ? [fullPill] : [];
        style.background = Settings.sharedBackground(settings, id);
        style.pillTransparency = settings.bar?.groupPillTransparency ?? -1;
        style.hideText = true;
        style.hideIcon = true;
        return style;
    }
    function itemPosition(id) {
        if (vertical) {
            let ids = orderedItems(side(id));
            let cursor = verticalGroupStart(side(id)) + (ids.length ? Math.max(0, spacingOffset(ids[0], "spacingLeft")) : 0);
            for (let i = 0; i < ids.length; ++i) {
                if (ids[i] === id) return cursor;
                cursor += moduleItems[ids[i]].height + (i + 1 < ids.length ? gapBetween(ids[i], ids[i + 1]) : 0);
            }
            return cursor;
        }
        let group = orderedItems(side(id));
        let left = k => spacingOffset(k, "spacingLeft");
        let right = k => spacingOffset(k, "spacingRight");
        let leading = group.length ? Math.max(0, left(group[0])) : 0;
        let trailing = group.length ? Math.max(0, right(group[group.length - 1])) : 0;
        let gap = i => gapBetween(group[i], group[i + 1]);
        let total = leading + trailing + group.reduce((n, k, i) => n + (vertical ? moduleItems[k].height : moduleItems[k].width) + (i < group.length - 1 ? gap(i) : 0), 0);
        let length = vertical ? contentHeight : contentWidth;
        let cursor = (centerItems
            ? centeredGroupStart(side(id), length, screenWidth / 2 - screenOffsetX - insetLeft)
            : side(id) === "right" ? length - total : side(id) === "center" ? (length - total) / 2 : 0) + leading;
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
    property real mediaMaximumWidth: Math.max(80, Math.min(300, width * 0.24))
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
        // Sample the occupied strip, excluding empty padding. Keep the item
        // coordinate origin separate from the sampled wallpaper region.
        bandHeight: bar.vertical ? bar.height : bar.contentHeight
        bandWidth: bar.vertical ? bar.contentWidth : bar.screenWidth
        regionOffsetX: bar.vertical ? bar.screenOffsetX + bar.insetLeft : 0
        regionOffsetY: bar.screenOffsetY + (bar.vertical ? 0 : bar.insetTop)
    }
    // Use the whole wallpaper so every link shares one ink, independent of
    // panel position, pill colors, and the local texture under a segment.
    WallpaperColors {
        id: knotsWallpaper
        objectName: "hyprknotsWallpaper"
        source: bar.wallpaperSource
        screenWidth: bar.screenWidth
        screenHeight: bar.screenHeight
        bandWidth: bar.screenWidth
        bandHeight: bar.screenHeight
        regionOffsetX: 0
        regionOffsetY: 0
        sampleWidth: 32
        sampleHeight: 32
    }
    property var trayModel: []
    property string clockText: ""
    property string activeMenu: ""
    signal previewUnavailable()
    onPreviewWorkspaceChanged: if (!previewWorkspace && activeMenu === "workspacePreview") previewUnavailable()
    signal menuHovered(string name)
    signal menuLeft(string name)
    property int previewWorkspaceId: 0
    readonly property var previewWorkspace: (statusData.workspaces || []).find(w => w.id === previewWorkspaceId) || null
    readonly property Item previewWorkspaceItem: {
        for (let i = 0; i < workspaceRepeater.count; ++i) {
            let item = workspaceRepeater.itemAt(i);
            if (item && item.modelData.id === previewWorkspaceId) return item;
        }
        return null;
    }
    readonly property var menuTargets: ({
            workspacePreview: previewWorkspaceItem,
            media: mediaSlot.item,
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
        if (name === "workspacePreview") {
            // Track the row's placement and scroll offset when regrouping it.
            let bounds = itemRect("workspaces");
            return Qt.rect(bounds.x + item.x, bounds.y + item.y, item.width, item.height);
        }
        if (name === "media") return itemRect("media");
        // The connector foot spans the visible pill, including asymmetric padding.
        // itemRect also tracks scroll movement on a vertical rail.
        return itemRect(name);
    }
    function menuHasTrigger(name) {
        let id = menuItemId(name);
        let item = menuTargets[name];
        return itemShown(id) && !!item && moduleItems[id].opacity > 0 && item.opacity > 0
            && item.glyphRect.width > 0 && item.glyphRect.height > 0;
    }
    function menuPointed(name) {
        // Every item uses the same stem, including wide and shared pills.
        return !!menuTargets[name];
    }
    function menuAnchorRect(name) {
        // Pill stems meet the outside of the item;
        // only bare items move the attachment inward to the visible glyph.
        if (!menuPointed(name) || !menuTargets[name].bare || fullPill.participating) return menuRect(name);
        let bounds = menuRect(name), rect = menuTargets[name].glyphRect;
        return Qt.rect(bounds.x + rect.x, bounds.y + rect.y, rect.width, rect.height);
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
    implicitWidth: vertical ? verticalThickness + insetLeft + insetRight : 0
    implicitHeight: vertical ? Math.max(1, Math.min(Math.max(1, screenHeight - Settings.screenMargins(settings.bar || {}).top - Settings.screenMargins(settings.bar || {}).bottom), compact ? minimumVerticalLength + insetTop + insetBottom : Infinity))
        : (edgeAttached
            ? Math.max(verticalThickness - 6,
                ...Object.keys(moduleItems).filter(id => itemShown(id)).map(id => moduleItems[id].height + 4))
            : verticalThickness) + insetTop + insetBottom
    // Reserve the occupied strip; the compositor supplies the window margin.
    readonly property real windowFacingInset: {
        let ids = Object.keys(moduleItems).filter(id => itemShown(id));
        if (!ids.length) return 0;
        let rects = ids.map(id => {
            let item = moduleItems[id];
            return Qt.rect(item.x, item.y, item.width, item.height);
        });
        if (fullPill.participating) rects.push(fullPill.bounds);
        let clearance = position === "top" ? height - Math.max(...rects.map(r => r.y + r.height)) - insetBottom
            : position === "bottom" ? Math.min(...rects.map(r => r.y)) - insetTop
            : position === "left" ? width - Math.max(...rects.map(r => r.x + r.width)) - insetRight
            : Math.min(...rects.map(r => r.x)) - insetLeft;
        return Math.max(0, clearance);
    }
    height: implicitHeight
    Flickable {
        id: layoutViewport
        objectName: "panelViewport"
        anchors.fill: parent
        contentWidth: width
        contentHeight: bar.vertical ? bar.layoutLength + bar.insetTop + bar.insetBottom : height
        interactive: bar.vertical && bar.overflowing
        clip: bar.vertical
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        ScrollBar.vertical: ScrollBar {
            width: 3
            policy: bar.overflowing ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
            active: bar.overflowing
        }
    // Angular links share one wallpaper-matched ink.
    Canvas {
        id: connectors
        objectName: "panelConnectors"
        anchors.fill: parent
        z: 0
        visible: !bar.statusIconsOnly && bar.settings.bar?.hyprknots !== false
        readonly property real lineWidth: bar.settings.bar?.hyprknotsLineWidth ?? 1.8
        readonly property real knotScale: (bar.settings.bar?.hyprknotsKnotSize ?? 100) / 100
        onLineWidthChanged: requestPaint()
        onKnotScaleChanged: requestPaint()
        function knotSizeFor(length) { return bar.knotSize; }
        function itemEdge(id, trailing) {
            let container = bar.moduleItems[id], item = container;
            let offset = bar.vertical ? container.y : container.x;
            if (id === "workspaces") {
                item = workspaceRepeater.itemAt(trailing ? workspaceRepeater.count - 1 : 0);
                if (item) offset += bar.vertical ? item.y : item.x;
            } else if (id === "media") item = mediaSlot.item;
            if (!item) return offset;
            let extent = bar.vertical ? item.height : item.width;
            if (!item.bare || !item.glyphRect)
                return offset + (trailing ? extent : 0);
            // Use both halves of icon-and-text items; glyphRect alone is the icon.
            let rects = [item.glyphRect];
            if (item.shownText?.length) rects.push(item.textGlyphRect);
            if (item.shownIcon?.length) rects.push(item.iconGlyphRect);
            if (item === bell && badge.participating) rects.push(badge.glyphRect);
            rects = rects.filter(rect => rect && rect.width > 0 && rect.height > 0);
            if (!rects.length) return offset + (trailing ? extent : 0);
            let edge = trailing ? Math.max(...rects.map(rect => bar.vertical ? rect.y + rect.height : rect.x + rect.width))
                : Math.min(...rects.map(rect => bar.vertical ? rect.y : rect.x));
            // Leave the same clear space at either end of a bare connection.
            return offset + Math.max(0, Math.min(extent, edge)) + (trailing ? 2 : -2);
        }
        property int patternSeed: Math.floor(Math.random() * 0x7fffffff) || 1
        function reshuffleKnots() {
            let next = Math.floor(Math.random() * 0x7fffffff) || 1;
            patternSeed = next === patternSeed ? (next % 0x7ffffffe) + 1 : next;
        }
        Connections {
            target: bar
            function onWallpaperSourceChanged() { connectors.reshuffleKnots(); }
        }
        function arrangeKnots(spans, seed) {
            let result = spans.map(() => []), slots = [];
            for (let i = 0; i < spans.length; ++i) {
                let span = spans[i], count = span.knotCount ?? span.knots.length;
                for (let j = 0; j < count; ++j)
                    slots.push({segment:i, knot:j, position:span.start + (span.end - span.start) * (j + 0.5) / count});
            }
            // Workspace gaps and module gaps share one spatial sequence.
            slots.sort((a, b) => a.position - b.position);
            let state = seed >>> 0, previous = -1;
            let weights = [3, 3, 2, 3, 3, 2]; // Favor links and couplings over chevrons.
            for (let slot of slots) {
                let options = [0, 1, 2, 3, 4, 5].filter(v => v % 3 !== previous);
                let total = options.reduce((sum, v) => sum + weights[v], 0);
                state = (Math.imul(state, 1664525) + 1013904223) >>> 0;
                let pick = state / 4294967296 * total, variant = options[options.length - 1];
                for (let option of options) {
                    pick -= weights[option];
                    if (pick < 0) { variant = option; break; }
                }
                result[slot.segment][slot.knot] = variant;
                previous = variant % 3; // Single/paired versions also count as the same motif.
            }
            return result;
        }
        readonly property var knotVariants: arrangeKnots(segments, patternSeed)
        onKnotVariantsChanged: requestPaint()
        function monochromeInk(sample) {
            let white = Qt.color("#ffffff"), black = Qt.color("#000000");
            return Colors.contrast(white, sample) >= Colors.contrast(black, sample) ? white : black;
        }
        function wallpaperInk(pixels, sample) {
            // Chroma-weighted hue votes keep gray areas from washing out accents.
            // Pick one family for the entire wallpaper, never per-link colors.
            let families = Array.from({length:12}, () => ({weight:0, r:0, g:0, b:0}));
            for (let i = 0; i + 3 < pixels.length; i += 4) {
                let r = pixels[i] / 255, g = pixels[i + 1] / 255, b = pixels[i + 2] / 255;
                let high = Math.max(r, g, b), low = Math.min(r, g, b), chroma = high - low;
                if (chroma < 0.12 || pixels[i + 3] < 128) continue;
                let hue = high === r ? ((g - b) / chroma + 6) % 6
                    : high === g ? (b - r) / chroma + 2 : (r - g) / chroma + 4;
                let family = families[Math.round(hue * 2) % 12], weight = chroma * chroma;
                family.weight += weight;
                family.r += r * weight; family.g += g * weight; family.b += b * weight;
            }
            let dominant = families.reduce((best, family) => family.weight > best.weight ? family : best, families[0]);
            if (dominant.weight === 0) return monochromeInk(sample);
            let hue = Qt.rgba(dominant.r / dominant.weight, dominant.g / dominant.weight,
                dominant.b / dominant.weight, 1).hslHue;
            // Preserve the chosen hue while finding a readable light/dark shade.
            let light = Qt.hsla(hue, 0.85, 0.68, 1), dark = Qt.hsla(hue, 0.85, 0.30, 1);
            let useLight = monochromeInk(sample).r === 1;
            let ink = useLight ? light : dark;
            for (let step = 1; step <= 10 && Colors.contrast(ink, sample) < 4.5; ++step)
                ink = Qt.hsla(hue, 0.85, useLight ? Math.min(1, 0.68 + step * 0.035) : Math.max(0, 0.30 - step * 0.035), 1);
            return ink;
        }
        readonly property color ink: {
            let pixels = knotsWallpaper.pixels;
            let sample = knotsWallpaper.sampleRect(Qt.rect(0, 0, bar.screenWidth, bar.screenHeight), false);
            return wallpaperInk(pixels, sample);
        }
        function colorAt(along, cross, span, neutral) { return ink; }
        function segmentFor(start, end, cross, workspace, knotted) {
            let geometry = {start:start, end:end, cross:cross, workspace:workspace, knotted:knotted};
            let sampled = null;
            function colors() {
                if (sampled === null) sampled = connectors.sampleSegment(geometry);
                return sampled;
            }
            // Geometry stays reactive; expensive contrast is needed only when
            // the settled segment is painted (or explicitly inspected).
            return {start:start, end:end, cross:cross, workspace:workspace,
                knotCount:knotted ? (workspace || bar.centerItems ? 1 : Math.max(1, Math.floor((end - start) / 42))) : 0,
                get ink() { return colors().ink; },
                get stops() { return colors().stops; },
                get knots() { return colors().knots; }};
        }
        function sampleSegment(segment) {
            let {start, end, cross, workspace, knotted} = segment;
            let length = end - start;
            let stops = [ink, ink];
            let count = knotted ? (workspace || bar.centerItems ? 1 : Math.max(1, Math.floor(length / 42))) : 0, knots = [];
            for (let i = 0; i < count; ++i)
                knots.push(colorAt(start + length * (i + 0.5) / count, cross, 12));
            return {start:start, end:end, cross:cross, workspace:workspace,
                ink:colorAt((start + end) / 2, cross, 8, true), stops:stops, knots:knots};
        }
        readonly property var segments: {
            let paletteInputs = colorInputs;
            let ids = Object.keys(bar.moduleItems).filter(id => bar.itemShown(id));
            ids.sort((a, b) => bar.vertical
                ? bar.moduleItems[a].y - bar.moduleItems[b].y
                : bar.moduleItems[a].x - bar.moduleItems[b].x);
            let result = [];
            for (let i = 1; i < ids.length; ++i) {
                let first = ids[i - 1], second = ids[i];
                let start = itemEdge(first, true);
                let end = itemEdge(second, false);
                if (end - start < 2) continue;
                let cross = bar.vertical ? bar.insetLeft + bar.contentWidth / 2 : bar.insetTop + bar.contentHeight / 2;
                result.push(segmentFor(start, end, cross, false, true));
            }
            if (bar.itemShown("workspaces")) {
                // Follow the actual filtered delegates, including their polished
                // positions, so workspace creation/removal never leaves a knot.
                for (let i = 1; i < workspaceRepeater.count; ++i) {
                    let a = workspaceRepeater.itemAt(i - 1), b = workspaceRepeater.itemAt(i);
                    if (!a || !b) continue;
                    let start = bar.vertical ? workspaceRow.y + a.y + a.height : workspaceRow.x + a.x + a.width;
                    let end = bar.vertical ? workspaceRow.y + b.y : workspaceRow.x + b.x;
                    let cross = bar.vertical ? workspaceRow.x + a.x + a.width / 2 : workspaceRow.y + a.y + a.height / 2;
                    if (end - start >= 2) result.push(segmentFor(start, end, cross, true, true));
                }
            }
            if (bar.centerItems && bar.itemShown("tray")) {
                for (let i = 1; i < trayIcons.count; ++i) {
                    let a = trayIcons.itemAt(i - 1), b = trayIcons.itemAt(i);
                    if (!a || !b) continue;
                    let start = bar.vertical ? trayPill.y + trayRow.y + a.y + a.height : trayPill.x + trayRow.x + a.x + a.width;
                    let end = bar.vertical ? trayPill.y + trayRow.y + b.y : trayPill.x + trayRow.x + b.x;
                    let cross = bar.vertical ? trayPill.x + trayRow.x + a.x + a.width / 2 : trayPill.y + trayRow.y + a.y + a.height / 2;
                    if (end - start >= 2) result.push(segmentFor(start, end, cross, false, true));
                }
            }
            return result;
        }
        // Repaint all links together when the wallpaper's shared ink changes.
        readonly property var colorInputs: [ink]
        onAvailableChanged: if (available) requestPaint()
        onSegmentsChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onVisibleChanged: if (visible) requestPaint()
        onPaint: {
            let ctx = getContext("2d");
            ctx.reset();
            function point(along, cross) {
                return bar.vertical ? {x:cross, y:along} : {x:along, y:cross};
            }
            // Chamfered chain link, interlocking coupling, and twin chevrons.
            // Straight cuts retain a recognizable silhouette at panel scale.
            function knotPath(variant, size) {
                ctx.beginPath();
                function move(x, y) { ctx.moveTo(x * size, y * size); }
                function line(x, y) { ctx.lineTo(x * size, y * size); }
                let motif = variant % 3;
                if (motif === 0) {
                    move(-1.25, 0); line(-0.65, -0.72); line(0.65, -0.72);
                    line(1.25, 0); line(0.65, 0.72); line(-0.65, 0.72);
                    ctx.closePath();
                } else if (motif === 1) {
                    move(-1.25, 0); line(-0.7, -0.7); line(0.2, -0.7); line(0.75, 0);
                    move(-0.75, 0); line(-0.2, 0.7); line(0.7, 0.7); line(1.25, 0);
                    move(-0.3, 0.32); line(0.3, -0.32);
                } else {
                    move(-1.15, -0.7); line(-0.45, 0); line(-1.15, 0.7);
                    move(0.15, -0.7); line(0.85, 0); line(0.15, 0.7);
                }
            }
            function strokeMetal(ink, width) {
                ctx.strokeStyle = ink; ctx.lineWidth = width; ctx.stroke();
            }
            for (let segmentIndex = 0; segmentIndex < segments.length; ++segmentIndex) {
                let segment = segments[segmentIndex];
                let a = point(segment.start, segment.cross), b = point(segment.end, segment.cross);
                ctx.lineCap = "square"; ctx.lineJoin = "miter";
                ctx.beginPath(); ctx.moveTo(a.x, a.y); ctx.lineTo(b.x, b.y);
                let gradient = ctx.createLinearGradient(a.x, a.y, b.x, b.y);
                for (let i = 0; i < segment.stops.length; ++i)
                    gradient.addColorStop(i / (segment.stops.length - 1), segment.stops[i]);
                strokeMetal(gradient, connectors.lineWidth);
                let length = segment.end - segment.start;
                // One joint per icon gap, and one every ~42 px on the open rail.
                let count = segment.knots.length;
                for (let knotIndex = 0; knotIndex < count; ++knotIndex) {
                    let p = point(segment.start + length * (knotIndex + 0.5) / count, segment.cross);
                    let size = connectors.knotSizeFor(length);
                    let variant = knotVariants[segmentIndex][knotIndex];
                    let ink = segment.knots[knotIndex];
                    ctx.save(); ctx.translate(p.x, p.y);
                    if (bar.vertical) ctx.rotate(Math.PI / 2);
                    // Keep the existing joint path and adapt only its ink.
                    knotPath(variant, size);
                    strokeMetal(ink, 1.6 * connectors.knotScale);
                    if (variant >= 3) {
                        knotPath(variant, size * 0.72);
                        strokeMetal(ink, 0.9 * connectors.knotScale);
                    }
                    ctx.beginPath();
                    ctx.moveTo(-size * 0.25, size * 0.22); ctx.lineTo(size * 0.25, -size * 0.22);
                    strokeMetal(ink, 1.2 * connectors.knotScale);
                    ctx.restore();
                }
            }
        }
    }
    AttachedPanelSurface {
        objectName: "attachedPanelSurface"
        parent: bar
        // Keep the screen-edge join, but fit the inward edge to the full pill.
        y: bar.position === "bottom" ? bar.height - height : 0
        width: bar.width
        height: bar.vertical ? bar.height : fullPill.bounds.y + fullPill.bounds.height
        z: -3
        visible: bar.edgeAttached && fullPill.backgroundShown && fullPill.memberIds.length > 0
        surfaceColor: fullPill.backgroundFill
        raised: fullPill.raised
        outlineColor: fullPill.settings.outlineColor
            || (fullPill.adaptivePalette ? fullPill.adaptivePalette.outline : fullPill.outline)
        opacity: fullPill.backgroundAlpha
        edge: bar.position
        start: bar.vertical ? Math.max(12, fullPill.bounds.y + bar.insetTop - 4 - bar.scrollOffset) : fullPill.bounds.x + bar.insetLeft - 4
        end: bar.vertical ? Math.min(bar.height - 12, fullPill.bounds.y + fullPill.bounds.height - bar.insetBottom + 4 - bar.scrollOffset)
            : fullPill.bounds.x + fullPill.bounds.width - bar.insetRight + 4
    }
    Pill {
        id: fullPill
        objectName: "fullPanelPill"
        drawBackground: !bar.edgeAttached
        readonly property var memberIds: bar.orderedItems("left").concat(bar.orderedItems("center"), bar.orderedItems("right"))
        readonly property string leader: fullPill.memberIds[0] || "launcher"
        readonly property var bounds: {
            if (!fullPill.memberIds.length) return Qt.rect(0, 0, 0, 0);
            let items = fullPill.memberIds.map(id => bar.moduleItems[id]);
            let left = Math.min(...items.map(item => item.x));
            let top = Math.min(...items.map(item => item.y));
            let right = Math.max(...items.map(item => item.x + item.width));
            let bottom = Math.max(...items.map(item => item.y + item.height));
            if (bar.vertical)
                return Qt.rect(0, top - bar.insetTop, bar.width,
                    bottom - top + bar.insetTop + bar.insetBottom);
            // Fit the horizontal surface to the items without resizing their layout.
            let surfaceTop = Math.max(0, top - 2);
            let surfaceBottom = Math.min(bar.height, bottom + 2);
            return Qt.rect(left - bar.insetLeft, surfaceTop,
                right - left + bar.insetLeft + bar.insetRight, surfaceBottom - surfaceTop);
        }
        // Keep appearance dependencies independent of ancestor/window visibility.
        // A reveal reuses the prepared palette instead of rebuilding every pill.
        readonly property bool participating: !bar.statusIconsOnly && memberIds.length > 0 && backgroundShown
        visible: participating
        x: fullPill.bounds.x; y: fullPill.bounds.y; width: fullPill.bounds.width; height: fullPill.bounds.height
        z: -2
        interactive: false
        vertical: bar.vertical
        settings: {
            let style = Settings.appearance(bar.settings, fullPill.leader, bar.wallpaperSource.toString());
            style.lightForeground = true;
            style.outlineFree = true;
            style.panelAdaptive = true;
            style.glassSurface = true;
            style.pillTransparency = bar.settings.bar?.fullPillTransparency ?? -1;
            let mode = bar.settings.bar?.fullBackground || "off";
            style.background = mode === "inherit" ? (bar.settings.bar?.background === "off" ? "off" : "on") : mode;
            style.hideText = true;
            style.hideIcon = true;
            return style;
        }
        foreground: bar.moduleItems[fullPill.leader].foreground ?? "#cdd6f4"
        tint: bar.moduleItems[fullPill.leader].tint ?? Qt.rgba(30/255, 30/255, 46/255, 0.28)
        outline: bar.moduleItems[fullPill.leader].outline ?? Qt.rgba(1, 1, 1, 0.16)
        colorSampler: Settings.adaptive(bar.settings, fullPill.leader) ? bar.wallpaperColors : null
        colorRoot: bar
        opacity: Settings.item(bar.settings, fullPill.leader).opacity ?? 1
    }
    Repeater {
        id: sharedPillRepeater
        model: bar.sharedPills
        delegate: Pill {
            required property var modelData
            objectName: "sharedPill_" + modelData.name
            readonly property bool participating: !bar.vertical
            visible: participating
            readonly property var bounds: bar.sharedRect(modelData.ids)
            readonly property string leader: modelData.ids[0]
            x: bounds.x; y: bounds.y; width: bounds.width; height: bounds.height
            z: -1
            interactive: false
            vertical: bar.vertical
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
        vertical: bar.iconPills
        maximumWidth: bar.vertical ? bar.verticalThickness - 4 : 10000
        settings: bar.appearance("launcher")
        opacity: Settings.item(bar.settings, "launcher").opacity ?? 1
        visible: bar.itemEnabled("launcher")
        text: ""
        foreground: "#51a2da"
        family: "GoMono Nerd Font"
        pixelSize: 20
        bold: false
        minimumTextWidth: settings.iconSize || settings.fontSize || 22
        implicitHeight: bar.panelSlotSize
        leftPadding: 2
        rightPadding: 2
        backgroundVisible: false
        content.opacity: distroLogo.settings.text || distroLogo.settings.icon ? 1 : 0
        glyphRect: launcherGlyph.visible ? Qt.rect(launcherGlyph.x + (launcherGlyph.width - launcherGlyph.iconSize) / 2,
            (height - launcherGlyph.iconSize) / 2, launcherGlyph.iconSize, launcherGlyph.iconSize)
            : !settings.text && !settings.icon ? Qt.rect(0, 0, 0, 0) : shownIcon.length ? iconGlyphRect : textGlyphRect
        GlassLogo {
            id: launcherGlyph
            objectName: "distroGlassLogo"
            iconSize: distroLogo.settings.iconSize || distroLogo.settings.fontSize || 22
            visible: !distroLogo.settings.text && !distroLogo.settings.icon && (bar.iconsOnly || !distroLogo.settings.hideText) && !distroLogo.settings.hideIcon
            x: bar.iconsOnly || distroLogo.uniformGlyphHeight > 0 ? (distroLogo.width - iconSize) / 2 : distroLogo.content.x
            width: bar.iconsOnly || distroLogo.uniformGlyphHeight > 0 ? iconSize : distroLogo.content.width
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
        vertical: bar.iconPills
        maximumWidth: bar.vertical ? bar.verticalThickness - 4 : 10000
        settings: bar.appearance("settings")
        opacity: settings.opacity ?? 1
        visible: bar.itemEnabled("settings")
        text: "󰒓"
        family: "GoMono Nerd Font"; pixelSize: 16
        backgroundVisible: false
        minimumTextWidth: Math.max(16, settings.iconSize || settings.fontSize || 22)
        implicitHeight: bar.panelSlotSize
        content.opacity: settingsCog.settings.text || settingsCog.settings.icon ? 1 : 0
        glyphRect: {
            if (!settingsGlyph.visible)
                return !settings.text && !settings.icon ? Qt.rect(0, 0, 0, 0) : shownIcon.length ? iconGlyphRect : textGlyphRect;
            // The cog occupies 2..22 of its 24-unit view box; include its rim
            // and offset glass layer, then follow the hover scale around center.
            let half = settingsGlyph.iconSize * (10 / 24 + 0.009), scale = settingsGlyph.scale;
            return Qt.rect(settingsGlyph.x + settingsGlyph.width / 2 - half * scale,
                settingsGlyph.y + height / 2 - half * scale, (2 * half + 0.6) * scale, (2 * half + 1.2) * scale);
        }
        GlassCog {
            id: settingsGlyph
            objectName: "settingsGlassCog"
            iconSize: settingsCog.uniformGlyphHeight > 0 ? Math.max(1, settingsCog.uniformGlyphHeight - 1.2) / (20 / 24 + 0.018) : settingsCog.settings.iconSize || settingsCog.settings.fontSize || 22
            y: settingsCog.uniformGlyphHeight > 0 ? -0.6 : 0
            visible: !settingsCog.settings.text && !settingsCog.settings.icon && (bar.iconsOnly || !settingsCog.settings.hideText) && !settingsCog.settings.hideIcon
            x: bar.iconsOnly || settingsCog.uniformGlyphHeight > 0 ? (settingsCog.width - iconSize) / 2 : settingsCog.content.x
            width: bar.iconsOnly || settingsCog.uniformGlyphHeight > 0 ? iconSize : settingsCog.content.width
            height: settingsCog.height
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
        y: bar.itemY("workspaces")
        opacity: Settings.item(bar.settings, "workspaces").opacity ?? 1
        visible: bar.itemEnabled("workspaces")
        objectName: "workspacesSlot"
        columns: bar.vertical ? 1 : Math.max(1, workspaceRepeater.count)
        horizontalItemAlignment: Grid.AlignHCenter
        verticalItemAlignment: Grid.AlignVCenter
        height: implicitHeight
        spacing: bar.statusIconsOnly ? 2 : bar.uniformItems || bar.centerItems || bar.settings.bar?.hyprknots === false ? bar.itemSpacing : Math.max(18, bar.itemSpacing)
        // Match the power circle's visible inset at the full panel ends.
        readonly property real endPadding: {
            if (!bar.uniformItems || !bar.fullBackgroundEnabled || bar.vertical || !power.circular) return 0;
            let surfaceWidth = Math.min(power.width, Math.max(0,
                power.height - 2 * (power.settings.backgroundVerticalInset || 0)));
            let extraWidth = power.width - surfaceWidth;
            // Center anchors round their position to whole pixels.
            return extraWidth - Math.round(extraWidth / 2);
        }
        leftPadding: bar.uniformItems || bar.centerItems ? endPadding : Math.max(0, (bar.vertical ? 0 : 1) + (Settings.item(bar.settings, "workspaces").paddingLeft || 0))
        rightPadding: bar.uniformItems || bar.centerItems ? endPadding : Math.max(0, (bar.vertical ? 0 : 3) + (Settings.item(bar.settings, "workspaces").paddingRight || 0))
        Repeater {
            id: workspaceRepeater
            model: (bar.statusData.workspaces || []).filter(w => !bar.outputName || w.monitor === bar.outputName)
            delegate: Pill {
                id: workspaceButton
                objectName: "workspace" + modelData.id
                settings: {
                    let appearance = Object.assign({}, bar.appearance("workspaces"), {paddingLeft:0, paddingRight:0});
                    appearance.compactPadding = true;
                    if (bar.centerItems) {
                        appearance.text = String(modelData.id);
                        appearance.hideText = false;
                        appearance.hideIcon = true;
                    }
                    appearance.textSizeReference = /^\d+$/.test(appearance.text || modelData.name || String(modelData.id)) ? "1" : "";
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
                vertical: bar.iconsOnly
                circular: true
                implicitWidth: Math.max(naturalWidth, 20, shownText.length ? content.implicitHeight + 6 : 0, shownIcon.length ? effectiveIconSize + 6 : 0)
                maximumWidth: bar.vertical ? Math.max(1, bar.panelSlotSize - workspaceRow.leftPadding - workspaceRow.rightPadding) : 10000
                width: bar.workspacePillSize
                onActiveFocusChanged: if (activeFocus) bar.ensureItemVisible(workspaceButton)
                iconOnly: false
                Accessible.name: "Workspace " + (modelData.name || String(modelData.id))
                height: width
                text: modelData.name || String(modelData.id)
                leftPadding: 7
                rightPadding: 7
                foreground: active ? "#cba6f7" : "#a0a0a0"
                colorStyle: active ? "emphasized" : "muted"
                selected: active
                raised: false
                onEntered: if (bar.hoverPopdowns) { bar.previewWorkspaceId = modelData.id; bar.menuHovered("workspacePreview"); }
                onExited: bar.menuLeft("workspacePreview")
                onClicked: mouse => {
                    if (!bar.hoverPopdowns && (!mouse || mouse.button !== Qt.RightButton)) {
                        let changePreview = bar.activeMenu === "workspacePreview" && bar.previewWorkspaceId !== modelData.id;
                        bar.previewWorkspaceId = modelData.id;
                        if (!changePreview) bar.action("workspacePreview", null);
                    } else bar.action("workspace", modelData.id);
                }
                onWheel: event => { bar.action("workspace-scroll", event.angleDelta.y > 0 ? -1 : 1); event.accepted = true; }
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
        onActiveChanged: if (!active && bar.activeMenu === "media") bar.previewUnavailable()
        visible: active
        sourceComponent: MediaPill {
            vertical: bar.iconPills
            iconOnly: bar.iconsOnly || bar.statusIconsOnly
            settings: {
                let style = bar.appearance("media");
                style.uniformTextHeight = (style.uniformTextHeight ?? style.uniformGlyphHeight) * 0.96;
                return style;
            }
            colorSampler: Settings.adaptive(bar.settings, "media") ? bar.wallpaperColors : null
            colorRoot: bar
            text: bar.mediaData.title || ""
            levels: bar.mediaData.levels || []
            maximumWidth: bar.vertical ? bar.verticalThickness - 4 : bar.mediaMaximumWidth
            interactive: !bar.hoverPopdowns
            onClicked: bar.action("media", null)
            onEntered: bar.menuHovered("media")
            onExited: bar.menuLeft("media")
            width: bar.iconPills ? bar.panelSlotSize : implicitWidth
        }
    }
    BarMenuButton {
        id: clock
        bar: bar
        menu: "calendar"
        x: bar.itemX("calendar")
        y: bar.itemY("calendar")
        vertical: bar.iconPills
        maximumWidth: bar.vertical ? bar.verticalThickness - 4 : 10000
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
        circular: trayIcons.count === 1
        x: bar.itemX("tray")
        y: bar.itemY("tray")
        vertical: bar.iconPills
        maximumWidth: bar.vertical ? bar.verticalThickness - 4 : 10000
        settings: {
            let style = bar.appearance("tray");
            if (bar.iconsOnly) style.background = "off";
            return style;
        }
        opacity: Settings.item(bar.settings, "tray").opacity ?? 1
        colorSampler: Settings.adaptive(bar.settings, "tray") ? bar.wallpaperColors : null
        colorRoot: bar
        foreground: "#cba6f7"
        interactive: false
        visible: bar.itemEnabled("tray") && trayIcons.count > 0
        width: bar.vertical ? bar.panelSlotSize : trayRow.width
        implicitHeight: bar.vertical ? Math.max(bar.panelSlotSize, trayRow.height) : bar.panelSlotSize
        content.y: bar.vertical ? 4 : (height - content.height) / 2
        leftPadding: bar.vertical ? 4 : 11
        rightPadding: bar.vertical ? 4 : 11
        readonly property real trayIconSize: settings.iconSize || bar.panelSlotSize * 0.8
        readonly property real trayTargetSize: bar.panelSlotSize
        Grid {
            id: trayRow
            columns: bar.vertical ? Math.max(1, Math.floor((bar.verticalThickness - 4 + spacing) / (trayPill.trayTargetSize + spacing))) : Math.max(1, trayIcons.count)
            x: (trayPill.width - width) / 2
            y: (parent.height - height) / 2
            visible: !trayPill.settings.hideIcon
            spacing: bar.uniformItems || bar.centerItems ? bar.itemSpacing : bar.vertical ? 4 : 0
            Repeater {
                id: trayIcons
                model: bar.trayModel
                delegate: Pill {
                    id: trayIcon
                    vertical: bar.iconPills
                    interactive: false
                    settings: bar.iconsOnly ? bar.appearance("tray") : ({background:"off", panelPillHeight:bar.panelSlotSize})
                    colorSampler: trayPill.colorSampler
                    colorRoot: bar
                    foreground: trayPill.foreground
                    tint: trayPill.tint
                    outline: trayPill.outline
                    required property var modelData
                    objectName: "trayIcon"
                    activeFocusOnTab: bar.vertical && !trayPill.settings.hideIcon
                    onActiveFocusChanged: if (activeFocus) bar.ensureItemVisible(trayIcon)
                    Keys.onReturnPressed: bar.trayAction(modelData, trayIcon, Qt.LeftButton)
                    Keys.onMenuPressed: bar.trayAction(modelData, trayIcon, Qt.RightButton)
                    Rectangle { anchors.fill: parent; radius: bar.vertical ? width / 2 : 4; color: "transparent"; border.width: parent.activeFocus ? 1 : 0; border.color: "#b4befe" }
                    width: trayPill.settings.hideIcon ? 0 : trayPill.trayTargetSize
                    height: trayPill.trayTargetSize
                    Image {
                        anchors.centerIn: parent
                        width: trayPill.trayIconSize; height: width
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
        vertical: bar.iconPills
        maximumWidth: bar.vertical ? bar.verticalThickness - 4 : 10000
        settings: bar.appearance("notifications")
        opacity: Settings.item(bar.settings, "notifications").opacity ?? 1
        visible: bar.itemEnabled("notifications")
        objectName: "notificationBell"
        text: "󰂚"
        family: "GoMono Nerd Font"
        pixelSize: 15
        minimumTextWidth: 12
        leftPadding: 7
        rightPadding: bar.vertical ? 6 : badge.participating ? Math.max(11, badge.implicitWidth + 1) : 11
        effectiveRightPadding: bar.uniformItems ? Math.max(5, badge.participating ? 2 * (badge.implicitWidth - 2) : 0) : bar.compactItemPadding && !bar.vertical
            ? Math.max(0, (badge.participating ? 2 * (badge.implicitWidth + 1) : 0) + (settings.paddingRight || 0))
            : Math.max(0, 5 + (badge.participating ? 2 * (badge.implicitWidth - 2) : 0) + (settings.paddingRight || 0))
        implicitHeight: bar.panelSlotSize
        content.y: uniformGlyphHeight > 0 ? normalizedTextY : (height - content.height) / 2
        foreground: bar.notificationData && bar.notificationData.count > 0 ? "#f9e2af" : "#a6adc8"
        tint: bar.rgba("#a6adc8", 0.18)
        outline: bar.rgba("#a6adc8", 0.26)
        TextMetrics {
            id: badgeMetrics
            font.family: "DejaVu Sans"
            font.pixelSize: 128
            font.bold: true
            text: badge.text
        }
        TextMetrics {
            id: badgeInkMetrics
            font: badge.font
            text: badge.text
        }
        Text {
            id: badge
            readonly property rect glyphRect: Qt.rect(x + badgeInkMetrics.tightBoundingRect.x,
                y + baselineOffset + badgeInkMetrics.tightBoundingRect.y,
                badgeInkMetrics.tightBoundingRect.width, badgeInkMetrics.tightBoundingRect.height)
            objectName: "notificationBadge"
            // Attach to the glyph's upper-right corner, independently of
            // the pill width or number of digits in the count.
            x: bar.vertical ? (bell.width - width) / 2 : bell.uniformGlyphHeight > 0 ? bell.textGlyphRect.x + bell.textGlyphRect.width - 2 : bell.content.x + (bell.content.width + bell.content.implicitWidth) / 2 - 2
            y: bar.vertical ? bell.height - height - 4 : bell.uniformGlyphHeight > 0 ? bell.textGlyphRect.y - 2 : bell.content.y - 2
            readonly property bool participating: !bar.iconsOnly && !bar.statusIconsOnly && !!bar.notificationData && bar.notificationData.count > 0
            visible: participating
            text: {
                let count = bar.notificationData ? String(bar.notificationData.count || "") : "";
                return bar.vertical ? Array.from(count).join("\n") : count;
            }
            color: bell.effectiveForeground
            style: bell.settings.outlineFree ? Text.Normal : bell.glyphHalo ? Text.Outline : bell.bare ? Text.Raised : Text.Normal
            styleColor: bell.glyphHalo ? bell.textEdge : bell.glyphShadow
            renderType: Text.QtRendering
            font.family: "DejaVu Sans"
            font.pixelSize: bar.uniformItems ? Math.max(1, Math.round(128 * bar.panelTextSize / Math.max(1, badgeMetrics.tightBoundingRect.height)))
                : Math.max(8, Math.round(8 * bell.effectiveGlyphSize / 15))
            font.bold: true
        }
    }
    BarMenuButton {
        id: audio
        // Percentage labels remain available in centered horizontal layouts.
        iconOnly: bar.vertical || bar.statusIconsOnly
        x: bar.itemX("audio")
        y: bar.itemY("audio")
        vertical: bar.vertical || (bar.centerItems && settings.hideText === true)
        maximumWidth: bar.vertical ? bar.verticalThickness - 4 : 10000
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
        vertical: bar.iconPills
        maximumWidth: bar.vertical ? bar.verticalThickness - 4 : 10000
        settings: bar.appearance("wifi")
        opacity: Settings.item(bar.settings, "wifi").opacity ?? 1
        visible: bar.itemEnabled("wifi")
        bar: bar
        menu: "wifi"
        text: bar.statusData.network.text || "󰤮"
        foreground: bar.statusData.network.internetWarning ? "#f9e2af" : bar.statusData.network.connected ? "#94e2d5" : "#585b70"
        tint: bar.rgba("#94e2d5", 0.18)
        outline: bar.rgba("#94e2d5", 0.26)
        family: "GoMono Nerd Font"
        pixelSize: 15
        implicitWidth: bar.uniformItems || (bar.compactItemPadding && !bar.vertical) ? naturalWidth : vertical ? bar.verticalThickness - 4 : implicitHeight
        leftPadding: 4
        rightPadding: 4
        // Center the visible glyph rather than the font's advance box.
        content.horizontalAlignment: bar.vertical && !bar.uniformItems ? Text.AlignHCenter : Text.AlignLeft
        content.elide: Text.ElideNone
        content.x: uniformGlyphHeight > 0 ? (circular || bar.vertical ? (wifi.width - wifiGlyphMetrics.tightBoundingRect.width * textInkScale) / 2 : effectiveLeftPadding) - wifiGlyphMetrics.tightBoundingRect.x * textInkScale : bar.vertical ? effectiveLeftPadding : (wifi.width - wifiGlyphMetrics.tightBoundingRect.width) / 2
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
        vertical: bar.iconPills
        maximumWidth: bar.vertical ? bar.verticalThickness - 4 : 10000
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
        implicitWidth: bar.uniformItems || (bar.compactItemPadding && !bar.vertical) ? naturalWidth : vertical ? bar.verticalThickness - 4 : implicitHeight
        leftPadding: 4
        rightPadding: 4
    }
    BarMenuButton {
        id: battery
        // Percentage labels remain available in centered horizontal layouts.
        iconOnly: bar.vertical || bar.statusIconsOnly
        x: bar.itemX("battery")
        y: bar.itemY("battery")
        vertical: bar.vertical || (bar.centerItems && settings.hideText === true)
        maximumWidth: bar.vertical ? bar.verticalThickness - 4 : 10000
        settings: bar.appearance("battery")
        opacity: Settings.item(bar.settings, "battery").opacity ?? 1
        bar: bar
        menu: "battery"
        visible: bar.itemEnabled("battery") && !!bar.statusData.battery.present
        readonly property string batteryLabel: bar.statusData.battery.text || ""
        blink: bar.statusData.battery.low === true
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
        vertical: bar.iconPills
        maximumWidth: bar.vertical ? bar.verticalThickness - 4 : 10000
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
}
