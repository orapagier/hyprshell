.pragma library
.import "SettingsModel.js" as Settings

function thickness(panel) { return Math.max(32, panel.thickness || 32); }
// Horizontal panels own corners. Menus also yield the full neighbouring edge,
// including its reveal strip, so either component remains reachable.
function occupiedEdges(config, component, monitor, workspace, paneThickness) {
    let result = {top: 0, bottom: 0, left: 0, right: 0};
    for (let name of ['hyprpane', 'hyprdock', 'hyprbar']) {
        if (name === component || !Settings.panelVisible(config, name, monitor, workspace)) continue;
        let panel = Settings.panelConfig(config, name), edge = panel.position;
        result[edge] = name === 'hyprpane'
            ? paneThickness + (panel.marginTop || 0) + (panel.paddingBottom || 0)
            : thickness(panel) + (panel.marginEdge || 0) + (panel.windowGap || 0);
    }
    return result;
}
function insets(config, component, monitor, workspace, paneThickness) {
    let edges = occupiedEdges(config, component, monitor, workspace, paneThickness);
    return {top: edges.top, bottom: edges.bottom};
}
function menuBounds(config, component, monitor, workspace, paneThickness, width, height) {
    let edges = occupiedEdges(config, component, monitor, workspace, paneThickness);
    return Qt.rect(edges.left, edges.top, Math.max(0, width-edges.left-edges.right),
        Math.max(0, height-edges.top-edges.bottom));
}
function intersection(first, second) {
    let x = Math.max(first.x, second.x), y = Math.max(first.y, second.y);
    return Qt.rect(x, y, Math.max(0, Math.min(first.x+first.width, second.x+second.width)-x),
        Math.max(0, Math.min(first.y+first.height, second.y+second.height)-y));
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

function pillStyle(config, panel, wallpaper) {
    let center = (config.items || []).filter(item => item.enabled !== false && item.side === 'center')
        .slice().sort((a,b) => (a.order ?? 0) - (b.order ?? 0));
    let id = center[0]?.id || 'calendar';
    let style = Settings.appearance(config, id, wallpaper);
    style.background = panel.background === 'inherit' || !panel.background
        ? Settings.sharedBackground(config, id) : panel.background;
    style.hideText = true; style.hideIcon = true;
    return {id:id, settings:style};
}
