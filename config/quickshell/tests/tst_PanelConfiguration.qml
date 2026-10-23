import QtQuick
import QtTest
import "../SettingsModel.js" as Model

TestCase {
    name: "PanelConfiguration"
    function settings() {
        return {version:1, bar:{position:'top',visible:true,workspaceScope:'all',workspaceList:[],workspaceOverrides:{}},
            items:[],panels:{hyprpane:{enabled:true,monitors:[]}},pins:{matches:{}}};
    }
    function test_legacyMergeKeepsEdgeVisibilityAndAppearance() {
        let defaults=settings();
        let saved={version:1,bar:{position:'left',height:72,workspaceOverrides:{'3':false}},items:[]};
        let merged=Model.merge(defaults,saved);
        compare(merged.bar.position,'left'); compare(merged.bar.height,72);
        verify(!Model.panelVisible(merged,'hyprpane','eDP-1',3));
        verify(Model.panelVisible(merged,'hyprpane','eDP-1',1));
        compare(defaults.bar.position,'top');
        merged.bar.workspaceScope='selected';
        verify(Model.panelVisible(merged,'hyprpane','eDP-1',null));
    }
    function test_monitorAndEnableGates() {
        let config=settings(); config.panels.hyprpane.monitors=['eDP-1'];
        verify(!Model.panelVisible(config,'hyprpane','HDMI-A-1',1));
        config.panels.hyprpane.enabled=false;
        verify(!Model.panelVisible(config,'hyprpane','eDP-1',1));
    }
}
