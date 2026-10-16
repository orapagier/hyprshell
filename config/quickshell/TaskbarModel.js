.pragma library
.import "DockModel.js" as Surface

// Filter before grouping so active state and pickers describe only visible windows.
function entries(groups, panel, output, workspace) {
    let result = [];
    for (let group of groups) {
        let windows = group.windows.filter(w =>
            (panel.windowWorkspaceScope !== 'current' || w.workspace === workspace)
            && (panel.windowMonitorScope !== 'current' || w.output === output));
        if (!windows.length) {
            if (group.pinned) result.push(Object.assign({}, group, {windows:[],active:false,urgent:false}));
            continue;
        }
        if (panel.grouped !== false) {
            let active = windows.find(w => w.active);
            result.push(Object.assign({}, group, {windows:windows, active:!!active,
                urgent:windows.some(w => w.urgent), name:(active || windows[0]).title}));
        } else {
            for (let window of windows) result.push(Object.assign({}, group, {
                key:'task:' + window.address, windows:[window], name:window.title,
                active:window.active, urgent:window.urgent}));
        }
    }
    return result;
}

function rightItems(config, component = "hyprbar") {
    let selected = config.panels?.[component]?.rightItems;
    if (selected === undefined && component === "hyprdock") return [];
    if (Array.isArray(selected)) return selected;
    let left = ['launcher', 'settings', 'workspaces', 'media'];
    return (config.items || []).filter(item => item.enabled !== false
        && (item.side || (left.indexOf(item.id) >= 0 ? 'left' : item.id === 'calendar' ? 'center' : 'right')) === 'right')
        .slice().sort((a,b) => (a.order ?? 0) - (b.order ?? 0)).map(item => item.id);
}
function statusConfig(config, edge, component = "hyprbar") {
    let selected = rightItems(config, component);
    let spacing = component === 'hyprbar' ? config.panels?.hyprbar?.spacingRight : null;
    let shared = Surface.pillStyle(config, config.panels?.[component] || {}, '').settings.background !== 'off';
    return Object.assign({}, config, {
        bar:Object.assign({}, config.bar, {position:edge, verticalPresentation:'compact'},
            spacing == null ? {} : {spacing:spacing}),
        items:['launcher','settings','workspaces','media','calendar','tray','notifications','audio','wifi','bluetooth','battery','power']
            .map(id => (config.items || []).find(item => item.id === id) || {id:id})
            .map(item => Object.assign({}, item, {
            enabled:selected.indexOf(item.id) >= 0, side:'right', order:selected.indexOf(item.id),
            background:'off', sharedBackground:'off', pillGroup:'', sharedBackgroundShown:shared
        }))
    });
}
