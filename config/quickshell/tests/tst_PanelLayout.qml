import QtQuick
import QtTest
import ".."
import "../PanelLayout.js" as LayoutModel
import "../SettingsModel.js" as Settings

Item {
    width: 700; height: 900
    SettingsPanelLayout {
        id: editor
        width: 600
        config: ({})
    }
    SignalSpy { id: chosen; target: editor; signalName: 'layoutChosen' }
    TestCase {
        name: 'PanelLayout'; when: windowShown
        function fixture() {
            let data = {bar:{position:'right',visible:true,workspaceScope:'all',workspaceOverrides:{'2':false},marginTop:17},
                panels:{}, pins:{mode:'separate',shared:['kitty.desktop'],hyprbar:['missing.desktop']},
                items:[{id:'audio',enabled:false}], notifications:{popups:false}};
            for (let name of ['hyprpane','hyprdock','hyprbar'])
                data.panels[name] = {enabled:name==='hyprpane',monitors:[],position:'left',visible:true,
                    workspaceScope:'all',workspaceOverrides:{},rightItems:['audio'],thickness:45,hideMode:'auto-hide'};
            data.panels.hyprpane = {enabled:true,monitors:[]};
            return data;
        }
        function init() {
            editor.config=fixture(); editor.selectedPreset=-1; editor.monitor='eDP-1'; editor.workspace=1; chosen.clear();
        }
        function test_presets_data() { return [0,1,2,3,4,5].map(i=>({tag:String(i),index:i})); }
        function test_presets(data) {
            let before=fixture(), original=JSON.stringify(before), next=LayoutModel.preset(before,data.index);
            compare(JSON.stringify(before),original);
            compare(Settings.panelLayoutError(next),'');
            compare(next.pins,before.pins); compare(next.items,before.items); compare(next.notifications,before.notifications);
            for (let name of ['hyprpane','hyprdock','hyprbar']) {
                let expected=Settings.copy(before.panels[name]);
                expected.enabled=next.panels[name].enabled;
                if (name!=='hyprpane' && expected.enabled) expected.position=next.panels[name].position;
                compare(next.panels[name],expected);
            }
            let expectedBar=Settings.copy(before.bar); expectedBar.position=next.bar.position;
            compare(next.bar,expectedBar);
            compare(LayoutModel.preset(before,-1),before);
        }
        function test_previewAndApply() {
            let before=JSON.stringify(editor.config);
            editor.selectedPreset=0;
            compare(JSON.stringify(editor.config),before); compare(chosen.count,0);
            compare(editor.panels.filter(p=>p.shown).map(p=>p.edge),['top','bottom']);
            mouseClick(findChild(editor,'applyPanelLayoutPreset'));
            compare(chosen.count,1); compare(chosen.signalArguments[0][0],LayoutModel.preset(editor.config,0));
            compare(editor.selectedPreset,-1);
        }
        function test_scopesAndOverrides() {
            let next=fixture(); next.panels.hyprpane.monitors=['HDMI-A-1']; editor.config=next;
            verify(!editor.panels[0].shown);
            editor.monitor='HDMI-A-1'; verify(editor.panels[0].shown);
            editor.workspace=2; verify(!editor.panels[0].shown);
            editor.selectedPreset=0;
            compare(editor.candidate.panels.hyprpane.monitors,['HDMI-A-1']);
            compare(editor.candidate.bar.workspaceOverrides,{'2':false});
            verify(!editor.panels[0].shown); verify(editor.panels[1].shown);
            editor.workspace=1; verify(editor.panels[0].shown);
        }
        function test_currentDraftFourEdgesAndCorners() {
            for (let edge of ['top','bottom','left','right']) {
                let next=fixture(); next.bar.position=edge; editor.config=next;
                compare(editor.panels[0].edge,edge);
                let rail=findChild(editor,'panelPreview_hyprpane');
                verify(rail.visible); compare(rail.vertical,edge==='left'||edge==='right');
                verify(rail.width>0 && rail.height>0);
            }
            editor.selectedPreset=2;
            let side=findChild(editor,'panelPreview_hyprdock'), bottom=findChild(editor,'panelPreview_hyprbar');
            verify(side.y+side.height<bottom.y);
        }
    }
}
