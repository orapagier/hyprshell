import QtQuick
import QtTest
import "../SettingsModel.js" as Model

TestCase {
    name: "PanelConfiguration"
    function settings() {
        return {version: 1, bar: {position: 'top', visible: true, workspaceScope: 'all', workspaceList: [], workspaceOverrides: {}}, items: [],
            panels: {hyprpane: {enabled: true, monitors: []},
                hyprdock: {enabled: false, monitors: [], position: 'bottom', visible: true, workspaceScope: 'all', workspaceList: [], workspaceOverrides: {}},
                hyprbar: {enabled: false, monitors: [], position: 'right', visible: true, workspaceScope: 'all', workspaceList: [], workspaceOverrides: {}}},
            pins: {mode: 'shared', shared: ['kitty.desktop'], hyprdock: ['app.desktop'], hyprbar: []}};
    }
    function test_legacyMergeKeepsEdgeVisibilityAndAppearance() {
        let defaults = settings();
        let saved = {version: 1, bar: {position: 'left', height: 72, workspaceOverrides: {'3': false}}, items: []};
        let merged = Model.merge(defaults, saved);
        compare(merged.bar.position, 'left');
        compare(merged.bar.height, 72);
        compare(Model.panelVisible(merged, 'hyprpane', 'eDP-1', 3), false);
        compare(Model.panelVisible(merged, 'hyprpane', 'eDP-1', 1), true);
        compare(merged.panels, defaults.panels);
        compare(defaults.bar.position, 'top');
        merged.bar.workspaceScope = 'selected';
        compare(Model.panelVisible(merged, 'hyprpane', 'eDP-1', null), true);
    }
    function test_everyPairAndEdge() {
        let names = ['hyprpane', 'hyprdock', 'hyprbar'];
        for (let pair of [[0, 1], [0, 2], [1, 2]]) {
            for (let a of ['top', 'bottom', 'left', 'right']) {
                for (let b of ['top', 'bottom', 'left', 'right']) {
                    let config = settings();
                    for (let index = 0; index < names.length; ++index) config.panels[names[index]].enabled = pair.indexOf(index) >= 0;
                    for (let entry of [[pair[0], a], [pair[1], b]]) {
                        let target = entry[0] === 0 ? config.bar : config.panels[names[entry[0]]];
                        target.position = entry[1];
                    }
                    compare(!!Model.panelLayoutError(config), a === b);
                }
            }
        }
    }
    function test_monitorGatesWorkspaceOverridesAndThreeComponents() {
        let config = settings();
        config.panels.hyprpane.monitors = ['eDP-1'];
        compare(Model.panelVisible(config, 'hyprpane', 'HDMI-A-1', 1), false);
        config.panels.hyprdock.enabled = true;
        config.panels.hyprbar.enabled = true;
        verify(Model.panelLayoutError(config).indexOf('at most two') >= 0);
        config.panels.hyprbar.visible = false;
        config.panels.hyprbar.workspaceOverrides = {'99': true};
        verify(Model.panelLayoutError(config).indexOf('workspace 99') >= 0);
        config.panels.hyprbar.monitors = ['HDMI-A-1'];
        compare(Model.panelLayoutError(config), '');
        config.panels.hyprpane.enabled = false;
        compare(Model.panelVisible(config, 'hyprpane', 'eDP-1', 1), false);
    }
    function test_conflictingMergeThrowsWithoutMutatingPreviousSettings() {
        let defaults = settings(), saved = Model.copy(defaults);
        saved.panels.hyprdock.enabled = true;
        saved.panels.hyprdock.position = 'top';
        let rejected = false;
        try { Model.merge(defaults, saved); } catch (error) { rejected = String(error).indexOf('Choose another edge') >= 0; }
        verify(rejected);
        compare(defaults.panels.hyprdock.enabled, false);
    }
    function test_reservedPreferencesAndPinListsSurviveUnrelatedEdits() {
        let defaults = settings(), saved = Model.copy(defaults);
        saved.panels.hyprdock.spacing = 17;
        saved.pins.mode = 'separate';
        let merged = Model.merge(defaults, saved);
        compare(merged.panels.hyprdock.spacing, 17);
        compare(Model.effectivePins(merged, 'hyprdock'), ['app.desktop']);
        merged.pins.mode = 'shared';
        compare(Model.effectivePins(merged, 'hyprbar'), ['kitty.desktop']);
        compare(merged.pins.hyprdock, ['app.desktop']);
    }
}
