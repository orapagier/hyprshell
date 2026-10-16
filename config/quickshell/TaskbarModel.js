.pragma library

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
