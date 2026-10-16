.pragma library

function desktopId(entry) {
    let id = String(entry && entry.id || '');
    return id && !id.endsWith('.desktop') ? id + '.desktop' : id;
}
function key(value) { return String(value || '').toLowerCase().replace(/\.desktop$/, ''); }
function windowClass(window) {
    let info = window.lastIpcObject || {};
    return String(window.wayland && window.wayland.appId || info.class || info.initialClass || '');
}
function match(window, entries, overrides) {
    let cls = windowClass(window), info = window.lastIpcObject || {};
    let identities = [cls, info.class, info.initialClass].filter(Boolean);
    for (let identity of identities) {
        if (Object.prototype.hasOwnProperty.call(overrides || {}, identity))
            return overrides[identity]; // Keep an explicit missing-app match too.
    }
    let best = [], score = 0;
    for (let entry of entries) {
        let id = key(desktopId(entry)), shortId = id.split('.').pop();
        let rank = 0;
        for (let identity of identities) {
            let value = key(identity);
            if (value === id) rank = Math.max(rank, 4);
            if (entry.startupClass && value === key(entry.startupClass)) rank = Math.max(rank, 3);
            if (value === shortId) rank = Math.max(rank, 2);
        }
        if (rank > score) { score = rank; best = [desktopId(entry)]; }
        else if (rank && rank === score) best.push(desktopId(entry));
    }
    // Ambiguity stays unmatched; never group unrelated apps by a title substring.
    return best.length === 1 ? best[0] : '';
}
function windowData(window, entries, overrides) {
    let info = window.lastIpcObject || {};
    return {address: window.address, title: window.title || info.title || 'Untitled window',
        appId: match(window, entries, overrides), identity: windowClass(window),
        active: !!window.activated, urgent: !!window.urgent,
        workspace: window.workspace ? window.workspace.id : (info.workspace || {}).id,
        workspaceName: window.workspace ? window.workspace.name : (info.workspace || {}).name || '',
        output: window.monitor ? window.monitor.name : '', handle: window};
}
function groups(entries, windows, pins, overrides, rows) {
    let result = [], byKey = {};
    function ensure(id, unknownKey, identity) {
        let groupKey = id ? 'app:' + id : 'window:' + unknownKey;
        if (!Object.prototype.hasOwnProperty.call(byKey, groupKey)) {
            let entry = entries.find(e => desktopId(e) === id) || null;
            let group = {key: groupKey, id: id, name: entry ? entry.name : id || identity || 'Unknown application',
                icon: entry ? entry.icon : '', entry: entry, installed: !!entry,
                pinned: pins.indexOf(id) >= 0, active: false, urgent: false, windows: []};
            byKey[groupKey] = group;
            result.push(group);
        }
        return byKey[groupKey];
    }
    for (let id of pins) ensure(id, '', '');
    let windowRows = rows === undefined ? windows.map(w => windowData(w, entries, overrides)) : rows;
    for (let row of windowRows) {
        let group = ensure(row.appId, key(row.identity) || row.address, row.identity);
        group.windows.push(row);
        group.active = group.active || row.active;
        group.urgent = group.urgent || row.urgent;
    }
    return result;
}
function launchCommand(entry) {
    let id = desktopId(entry);
    return /^[A-Za-z0-9_][A-Za-z0-9_.-]*\.desktop$/.test(id)
        ? ['uwsm', 'app', '-t', 'service', '--', id] : [];
}
function windowCommand(action, address, workspace, lua) {
    if (!/^(?:0x)?[a-fA-F0-9]+$/.test(String(address || ''))) return '';
    // Quickshell exposes bare hex addresses; Hyprland selectors need 0x.
    let selector = 'address:' + (String(address).startsWith('0x') ? address : '0x' + address);
    if (action === 'focus') return lua ? 'hl.dsp.focus({ window = "' + selector + '" })' : 'focuswindow ' + selector;
    if (action === 'close') return lua ? 'hl.dsp.window.close({ window = "' + selector + '" })' : 'closewindow ' + selector;
    if (action === 'move' && Number.isInteger(workspace) && workspace >= 1 && workspace <= 99)
        return lua ? 'hl.dsp.window.move({ window = "' + selector + '", workspace = ' + workspace + ', follow = false })'
                   : 'movetoworkspacesilent ' + workspace + ',' + selector;
    return '';
}
