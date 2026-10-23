.pragma library
.import "SettingsModel.js" as Settings

// Change the pane edge while preserving appearance and visibility scopes.
function preset(config, index) {
    let edges = ['top', 'bottom', 'left', 'right'];
    let next = Settings.copy(config);
    if (edges[index]) next.bar.position = edges[index];
    return next;
}
function rows(config, monitor, workspace) {
    let panel = Settings.panelConfig(config, 'hyprpane');
    return [{name:'hyprpane', edge:panel.position, enabled:panel.enabled !== false,
        shown:Settings.panelVisible(config, 'hyprpane', monitor, workspace), hideMode:'always'}];
}
