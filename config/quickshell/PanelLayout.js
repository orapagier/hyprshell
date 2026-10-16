.pragma library
.import "SettingsModel.js" as Settings

// Presets change only component enablement and the edges of selected panels.
// Visibility scopes, disabled-panel positions and personal appearance survive.
function preset(config, index) {
    let layouts = [
        {hyprpane:'top',hyprdock:'bottom'},
        {hyprpane:'top',hyprbar:'bottom'},
        {hyprdock:'left',hyprbar:'bottom'},
        {hyprpane:'top'}, {hyprdock:'bottom'}, {hyprbar:'bottom'}
    ];
    if (!layouts[index]) return Settings.copy(config);
    let next = Settings.copy(config), layout = layouts[index];
    for (let name of ['hyprpane','hyprdock','hyprbar']) {
        next.panels[name].enabled = layout[name] !== undefined;
        if (layout[name]) (name === 'hyprpane' ? next.bar : next.panels[name]).position = layout[name];
    }
    return next;
}

function rows(config, monitor, workspace) {
    return ['hyprpane','hyprdock','hyprbar'].map(name => {
        let panel = Settings.panelConfig(config, name);
        return {name:name, edge:panel.position, enabled:panel.enabled !== false,
            shown:Settings.panelVisible(config,name,monitor,workspace),
            hideMode:panel.hideMode || 'always'};
    });
}
