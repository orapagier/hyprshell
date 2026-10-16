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
