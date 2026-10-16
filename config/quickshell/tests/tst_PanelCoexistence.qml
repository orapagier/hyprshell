import QtQuick
import QtTest
import ".."
import "../DockModel.js" as Geometry
import "../SettingsModel.js" as Settings

Item {
    width: 800; height: 600
    MenuPopover {
        id: menu
        anchors.fill: parent
        alignToTrigger: true
        page: Component { Item { implicitHeight: 900 } }
    }
    TestCase {
        name: 'PanelCoexistence'
        when: windowShown
        function config() {
            let result = {bar:{position:'top',visible:true,marginTop:5,paddingBottom:2},panels:{}};
            for (let name of ['hyprpane','hyprdock','hyprbar'])
                result.panels[name] = {enabled:false,position:'bottom',visible:true,monitors:[],
                    workspaceOverrides:{},thickness:32,marginEdge:7,windowGap:3,hideMode:'always'};
            delete result.panels.hyprpane.position;
            return result;
        }
        function test_pairs_data() {
            let rows=[];
            for (let pair of [['hyprpane','hyprdock'],['hyprpane','hyprbar'],['hyprdock','hyprbar']])
                for (let first of ['top','bottom','left','right'])
                    for (let second of ['top','bottom','left','right'])
                        if (first !== second) rows.push({tag:pair.join('+')+':'+first+'+'+second,pair:pair,edges:[first,second]});
            return rows;
        }
        function test_pairs(data) {
            let saved=config();
            for (let i=0;i<2;i++) {
                saved.panels[data.pair[i]].enabled=true;
                (data.pair[i]==='hyprpane' ? saved.bar : saved.panels[data.pair[i]]).position=data.edges[i];
            }
            compare(Settings.panelLayoutError(saved),'');
            for (let i=0;i<2;i++) {
                let owner=data.pair[i], edge=data.edges[i], other=data.edges[1-i];
                let expected= data.pair[1-i]==='hyprpane' ? 39 : 42;
                let bounds=Geometry.menuBounds(saved,owner,'eDP-1',1,32,800,600);
                compare(bounds.x,other==='left' ? expected : 0);
                compare(bounds.y,other==='top' ? expected : 0);
                compare(bounds.width,800-(['left','right'].indexOf(other)>=0 ? expected : 0));
                compare(bounds.height,600-(['top','bottom'].indexOf(other)>=0 ? expected : 0));
                compare(Geometry.insets(saved,owner,'eDP-1',1,32),
                    {top:other==='top' ? expected : 0,bottom:other==='bottom' ? expected : 0});
                // This is also the input mask intersection used by both menu surfaces.
                let inward=edge==='top' ? Qt.rect(0,40,800,560) : edge==='bottom' ? Qt.rect(0,0,800,560)
                    : edge==='left' ? Qt.rect(40,0,760,600) : Qt.rect(0,0,760,600);
                let input=Geometry.intersection(bounds,inward);
                verify(input.x>=bounds.x && input.y>=bounds.y);
                verify(input.x+input.width<=bounds.x+bounds.width);
                verify(input.y+input.height<=bounds.y+bounds.height);
                menu.panelBounds=bounds; menu.edge=edge;
                menu.triggerRect=edge==='top' ? Qt.rect(380,5,32,32) : edge==='bottom' ? Qt.rect(380,563,32,32)
                    : edge==='left' ? Qt.rect(5,280,32,32) : Qt.rect(763,280,32,32);
                menu.opened=true; wait(1);
                verify(menu.bodyX>=bounds.x+12);
                verify(menu.bodyRight<=bounds.x+bounds.width-12);
                verify(menu.bodyY>=bounds.y+12);
                verify(menu.bodyBottom<=bounds.y+bounds.height-12);
                menu.opened=false;
            }
        }
        function test_workspaceMonitorAndHidePolicies() {
            let saved=config(); saved.panels.hyprbar.enabled=true;
            saved.panels.hyprbar.position='left';
            saved.panels.hyprbar.monitors=['HDMI-A-1'];
            compare(Geometry.menuBounds(saved,'hyprdock','eDP-1',1,32,800,600),Qt.rect(0,0,800,600));
            for (let mode of ['always','auto-hide','dodge']) {
                saved.panels.hyprbar.hideMode=mode;
                compare(Geometry.menuBounds(saved,'hyprdock','HDMI-A-1',1,32,800,600),Qt.rect(42,0,758,600));
            }
            saved.panels.hyprbar.workspaceOverrides={'2':false};
            compare(Geometry.menuBounds(saved,'hyprdock','HDMI-A-1',2,32,800,600),Qt.rect(0,0,800,600));
            // An unplugged/recreated output has no retained geometry cache.
            saved.panels.hyprbar.enabled=false;
            compare(Geometry.menuBounds(saved,'hyprdock','HDMI-A-1',1,32,1024,768),Qt.rect(0,0,1024,768));
        }
        function test_emptyIntersection() {
            let result=Geometry.intersection(Qt.rect(0,0,20,20),Qt.rect(30,30,10,10));
            compare(result.width,0); compare(result.height,0);
        }
    }
}
