.pragma library
.import "SettingsModel.js" as Settings

function thickness(panel) { return Math.max(44, panel.thickness || 56, (panel.iconSize || 32) + 16); }
function insets(config, component, monitor, workspace, paneThickness) {
    let result = {top: 0, bottom: 0};
    for (let name of ['hyprpane', 'hyprdock']) {
        if (name === component || !Settings.panelVisible(config, name, monitor, workspace)) continue;
        let panel = Settings.panelConfig(config, name), edge = panel.position;
        if (edge !== 'top' && edge !== 'bottom') continue;
        result[edge] = name === 'hyprpane'
            ? paneThickness + (panel.marginTop || 0) + (panel.paddingBottom || 0)
            : thickness(panel) + (panel.marginEdge || 0) + (panel.windowGap || 0);
    }
    return result;
}
function dropIndex(pins, id, targetId) {
    let from = pins.indexOf(id), to = pins.indexOf(targetId);
    return from >= 0 && to >= 0 && from !== to ? to : -1;
}

function aligned(available, length, alignment) {
    return alignment === 'start' ? 0 : alignment === 'end' ? Math.max(0, available-length) : Math.max(0, (available-length)/2);
}
function overlaps(rect, client, output, workspace) {
    let info = client.lastIpcObject || {};
    if (!client.workspace || (client.workspace.id !== workspace && !info.pinned)) return false;
    let at = info.at || [], size = info.size || [];
    let x = at[0] - (output.x || 0), y = at[1] - (output.y || 0);
    return size[0] > 0 && size[1] > 0 && x < rect.x+rect.width && x+size[0] > rect.x
        && y < rect.y+rect.height && y+size[1] > rect.y;
}
