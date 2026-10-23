.pragma library

// Wallpaper-seeded shuffles keep the preview and live bars in agreement.
var vibrantPalette = ['#ff6b9d', '#ff895c', '#ffd45c', '#b5ef63', '#5ee8a5', '#54e3da',
    '#5dccff', '#86a6ff', '#b88aff', '#ffffff', '#ff79d1', '#ff6575'];
var vibrantSessionSeed = Math.floor(Math.random() * 0x7fffffff) || 1;
function wallpaperPalette(source) {
    let seed = vibrantSessionSeed;
    let key = String(source || "");
    for (let i = 0; i < key.length; ++i)
        seed = Math.imul(seed ^ key.charCodeAt(i), 16777619);
    seed = seed || 1;
    let palette = vibrantPalette.slice();
    for (let n = palette.length - 1; n > 0; --n) {
        seed ^= seed << 13; seed ^= seed >>> 17; seed ^= seed << 5;
        let swap = (seed >>> 0) % (n + 1);
        [palette[n], palette[swap]] = [palette[swap], palette[n]];
    }
    return palette;
}
var vibrantIds = ['launcher', 'settings', 'workspaces', 'media', 'calendar', 'tray',
    'notifications', 'audio', 'wifi', 'bluetooth', 'battery', 'power'];

// Physical outer margins; unset sides retain the legacy edge/end controls.
function screenMargins(bar) {
    let edge = bar.position || 'top', vertical = edge === 'left' || edge === 'right';
    let result = {};
    for (let side of ['top', 'bottom', 'left', 'right']) {
        let key = 'screenMargin' + side[0].toUpperCase() + side.slice(1);
        let end = vertical ? side === 'top' || side === 'bottom' : side === 'left' || side === 'right';
        result[side] = bar[key] ?? (edge === side ? (bar.marginTop ?? 5) : end ? (bar.marginSide ?? 10) : 0);
    }
    return result;
}
function copy(value) { return JSON.parse(JSON.stringify(value)); }
function hoverPopdownsEnabled(bar, workspace) {
    let overrides = bar.hoverPopdownOverrides || {};
    let choice = overrides[String(workspace)];
    return typeof choice === 'boolean' ? choice : bar.hoverPopdowns !== false;
}
function barVisible(bar, workspace) {
    let overrides = bar.workspaceOverrides || {};
    if (typeof overrides[String(workspace)] === 'boolean') return overrides[String(workspace)];
    return bar.visible !== false && ((bar.workspaceScope || 'all') === 'all' ||
        (bar.workspaceList || []).indexOf(workspace) >= 0);
}
function withWorkspaceVisibility(bar, workspace, visible) {
    let next = copy(bar);
    next.workspaceOverrides = Object.assign({}, next.workspaceOverrides || {}, {[String(workspace)]: visible});
    return next;
}
function withAllBarVisibility(bar, visible) {
    return Object.assign(copy(bar), {visible: visible, workspaceScope: 'all', workspaceList: [], workspaceOverrides: {}});
}
function monitorVisible(settings, workspace) {
    let choice = (settings.workspaceOverrides || {})[String(workspace)];
    return typeof choice === 'boolean' ? choice : settings.enabled !== false;
}
function item(config, id) { return (config.items || []).find(i => i.id === id) || {}; }
function popdownTranslucency(config, id) {
    let value = item(config, id).popdownTranslucency;
    return value >= 0 ? value : ((config.bar && config.bar.popdownTranslucency) ?? 0.06);
}
function adaptive(config, id) {
    let mode = item(config, id).adaptiveColors;
    return mode === 'on' || (mode !== 'off' && (!config.bar || config.bar.randomVibrantColors || config.bar.adaptiveColors !== false));
}
function merge(defaults, saved) {
    if (!saved || saved.version !== 1) throw new Error('Unsupported settings version');
    let result = copy(defaults);
    result.bar = Object.assign(result.bar, saved.bar || {});
    for (let name of Object.keys(result.panels || {}))
        result.panels[name] = Object.assign(result.panels[name], (saved.panels || {})[name] || {});
    result.pins = {matches: copy((saved.pins || {}).matches || {})};
    result.systemMonitor = Object.assign(result.systemMonitor || {}, saved.systemMonitor || {});
    result.hyprland = saved.hyprland || {};
    result.clipboard = Object.assign(result.clipboard || {}, saved.clipboard || {});
    result.accessibility = Object.assign(result.accessibility || {}, saved.accessibility || {});
    result.notifications = Object.assign(result.notifications || {}, saved.notifications || {});
    result.power = Object.assign(result.power || {}, saved.power || {});
    result.locking = Object.assign(result.locking || {}, saved.locking || {});
    result.items = result.items.map(i => Object.assign(i, item(saved, i.id)));
    // Retire experimental motion preferences from older saved files.
    for (let section of [result.bar, ...result.items])
        for (let key of ['genieEffect', 'genieOpenDuration', 'genieCloseDuration']) delete section[key];
    return result;
}

// Resolve item appearance while preserving component defaults in inherit mode.
function appearance(config, id, wallpaperSource) {
    let result = Object.assign({}, item(config, id));
    if (!result.background || result.background === 'inherit')
        result.background = (config.bar && config.bar.background) || 'inherit';
    if (result.pillGroup) result.background = 'off';
    // Explicit item adaptation choices override the global random mode.
    if (config.bar && config.bar.randomVibrantColors &&
            (!result.adaptiveColors || result.adaptiveColors === 'inherit'))
        result.vibrantColor = wallpaperPalette(wallpaperSource)[Math.max(0, vibrantIds.indexOf(id))];
    result.iconSize = result.iconSize || (config.bar && config.bar.iconSize) || 0;
    return result;
}

function sharedBackground(config, id) {
    let mode = item(config, id).sharedBackground || 'inherit';
    if (mode === 'inherit') mode = config.bar?.sharedBackground || 'inherit';
    if (mode === 'inherit') mode = config.bar?.background || 'inherit';
    return mode === 'off' ? 'off' : 'on';
}

function setSharedBackground(config, id, mode) {
    let next = copy(config), current = item(next, id);
    for (let entry of next.items)
        if (entry.id === id || (current.pillGroup && entry.pillGroup === current.pillGroup)) entry.sharedBackground = mode;
    return next;
}

// Insert before a destination item, or append to the chosen side.
function reorder(config, id, side, beforeId) {
    let next = copy(config);
    let moving = item(next, id);
    if (!moving.id || ['left', 'center', 'right'].indexOf(side) < 0 || beforeId === id)
        return next;
    let previousSide = moving.side;
    let group = next.items.filter(i => i.id !== id && i.side === side).sort((a, b) => a.order - b.order);
    let index = group.findIndex(i => i.id === beforeId);
    group.splice(index < 0 ? group.length : index, 0, moving);
    if (previousSide !== side) moving.pillGroup = '';
    moving.side = side;
    group.forEach((i, n) => i.order = n);
    if (previousSide !== side)
        next.items.filter(i => i.side === previousSide).sort((a, b) => a.order - b.order).forEach((i, n) => i.order = n);
    return next;
}

function restoreItem(config, saved, id) {
    let original = item(config, id), previous = item(saved, id);
    if (!original.id || !previous.id) return copy(config);
    let next = copy(config);
    next.items[next.items.findIndex(i => i.id === id)] = copy(previous);
    if (original.side === previous.side && original.order === previous.order) return next;
    // Dragging renumbers a group. Restore the saved position relative to its
    // neighbours rather than treating its old numeric order as a new rank.
    let savedGroup = saved.items.filter(i => i.side === previous.side).sort((a,b) => a.order-b.order);
    let index = savedGroup.findIndex(i => i.id === id);
    let following = savedGroup.slice(index+1).find(i => item(next,i.id).side === previous.side);
    let beforeId = following ? following.id : "";
    if (!following) {
        let preceding = savedGroup.slice(0,index).reverse().find(i => item(next,i.id).side === previous.side);
        let group = next.items.filter(i => i.id !== id && i.side === previous.side).sort((a,b) => a.order-b.order);
        let after = preceding ? group.findIndex(i => i.id === preceding.id)+1 : group.length;
        beforeId = after < group.length ? group[after].id : "";
    }
    return reorder(next, id, previous.side, beforeId);
}

// A named pill follows its first member's alignment. Members retain their IDs.
function setPillGroup(config, id, name) {
    let next = copy(config), moving = item(next, id);
    let peer = next.items.find(i => i.id !== id && i.pillGroup === name && name);
    moving.pillGroup = name;
    if (peer) {
        moving.side = peer.side;
        moving.sharedBackground = peer.sharedBackground || 'inherit';
    }
    return next;
}
function setItemSide(config, id, side) {
    let next = copy(config), moving = item(next, id);
    for (let entry of next.items)
        if (entry.id === id || (moving.pillGroup && entry.pillGroup === moving.pillGroup)) entry.side = side;
    return next;
}

// Legacy bar/items remain the authoritative Hyprpane appearance and visibility.
function panelConfig(config, name) {
    let panel = (config.panels || {})[name] || {enabled: name === 'hyprpane', monitors: []};
    return name === 'hyprpane' ? Object.assign({}, config.bar, panel) : panel;
}
function panelVisible(config, name, monitor, workspace) {
    let panel = panelConfig(config, name);
    return panel.enabled !== false && (!(panel.monitors || []).length || panel.monitors.indexOf(monitor) >= 0) && (workspace === null ? panel.visible !== false : barVisible(panel, workspace));
}
