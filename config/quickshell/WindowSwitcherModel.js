.pragma library

// Keep the switcher's ordering and selection rules independent from its
// layer-surface UI, so opening/closing windows cannot leave a stale selection.
function workspaceId(row) {
    let value = row ? row.workspace : null;
    return typeof value === "object" && value ? Number(value.id) : Number(value);
}

function workspaceRows(rows, workspace) {
    return (rows || []).filter(row => workspaceId(row) === Number(workspace)).slice().sort((left, right) => {
        let active = Number(!!right.active) - Number(!!left.active);
        if (active) return active;
        let title = String(left.title || "").localeCompare(String(right.title || ""));
        return title || String(left.address || "").localeCompare(String(right.address || ""));
    });
}

function indexForAddress(rows, address) {
    return (rows || []).findIndex(row => row.address === address);
}

function preferredAddress(rows, current, focused) {
    if (indexForAddress(rows, current) >= 0) return current;
    if (indexForAddress(rows, focused) >= 0) return focused;
    let active = (rows || []).find(row => row.active);
    return active ? active.address : rows && rows.length ? rows[0].address : "";
}

function nextIndex(count, current, step) {
    count = Math.max(0, Number(count) || 0);
    if (!count) return -1;
    step = Math.trunc(Number(step) || 1);
    if (current < 0 || current >= count) return step < 0 ? count - 1 : 0;
    return ((current + step) % count + count) % count;
}
