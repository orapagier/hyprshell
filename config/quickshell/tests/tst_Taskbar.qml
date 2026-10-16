pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QtTest
import ".."
import "../TaskbarModel.js" as Tasks
import "../SettingsModel.js" as Settings

Item {
    id: scene
    width:900; height:700
    property var groups: []
    property var config: ({panels:{hyprbar:{position:'bottom',thickness:40,verticalWidth:220,iconSize:32,spacing:4,buttonWidth:180,showTitles:true,grouped:true,windowWorkspaceScope:'all',windowMonitorScope:'current'}},pins:{mode:'shared',shared:[]}})
    property string action: ''
    QtObject {
        id: service
        property bool busy:false
        property string error:''
        function groups(component) { return scene.groups; }
        function iconSource(name) { return ''; }
        function activate(group,preserve) { scene.action='focus:'+group.windows[0]?.address; return true; }
        function launch(id) { scene.action='launch:'+id; return true; }
        function edit(action) { return true; }
        function windowAction(kind,address,workspace,preserve) { scene.action=kind+':'+address+':'+workspace; return true; }
    }
    Dock {
        id: bar
        x:20; y:20; width:implicitWidth; height:implicitHeight
        component:'hyprbar'; outputName:'eDP-1'; workspace:1
        config:scene.config; service:service; maximumLength:600
        onPreviewsRequested:(key,rect) => scene.action='picker:'+key
        onGroupRequested:(key,rect) => scene.action='context:'+key
        onLauncherRequested:rect => scene.action='launcher'
    }
    DockActions { id: actions; visible:false; width:300; service:service; component:'hyprbar'; group:bar.groups[0] || null }
    SettingsTaskbarEditor { visible:false; width:400; settings:bar.panel }
    TestCase {
        name:'Taskbar'; when:windowShown
        function group(windows,pinned) { return {key:'app:test.desktop',id:'test.desktop',name:'Test',icon:'',installed:true,pinned:!!pinned,active:true,windows:windows}; }
        function rows() { return [
            {address:'aa',title:'First long upright window title',workspace:1,workspaceName:'1',output:'eDP-1',active:true},
            {address:'bb',title:'Second',workspace:2,workspaceName:'2',output:'eDP-1',active:false},
            {address:'cc',title:'External',workspace:1,workspaceName:'1',output:'HDMI-A-1',active:false}]; }
        function update(values) { let next=Settings.copy(scene.config); Object.assign(next.panels.hyprbar,values); scene.config=next; }
        function init() {
            scene.action=''; scene.groups=[group(rows(),true)];
            update({position:'bottom',showTitles:true,grouped:true,windowWorkspaceScope:'all',windowMonitorScope:'current'});
            bar.maximumLength=600; wait(30);
        }
        function test_filterGroupLifecycle() {
            compare(bar.groups.length,1); compare(bar.groups[0].windows.length,2);
            update({windowWorkspaceScope:'current'}); compare(bar.groups[0].windows.length,1);
            update({windowMonitorScope:'all'}); compare(bar.groups[0].windows.length,2);
            update({grouped:false}); compare(bar.groups.length,2);
            compare(bar.groups[1].key,'task:cc');
            scene.groups=[group([rows()[1]],true)]; compare(bar.groups.length,1); compare(bar.groups[0].windows.length,0);
            verify(!bar.groups[0].active);
            scene.groups=[group([],false)]; compare(bar.groups.length,0);
            scene.groups=[group([Object.assign({},rows()[0],{title:'Renamed',active:false})],false)];
            compare(bar.groups[0].name,'Renamed'); verify(!bar.groups[0].active);
        }
        function test_edges_data() { return ['top','bottom','left','right'].map(edge=>({tag:edge,edge:edge})); }
        function test_edges(data) {
            update({position:data.edge}); wait(30);
            compare(bar.vertical,data.edge==='left'||data.edge==='right');
            let button=findChild(bar,'dockItem1');
            compare(findChild(bar,'taskTitle1'),null);
            mouseMove(button); wait(650); compare(button.ToolTip.visible,false);
            if(bar.vertical) { compare(bar.width,48); compare(button.height,40); }
            else { compare(button.width,40); compare(bar.width,600); }
            mouseClick(button); compare(scene.action,'picker:app:test.desktop');
            mouseClick(button,button.width/2,button.height/2,Qt.RightButton); compare(scene.action,'context:app:test.desktop');
            update({grouped:false}); wait(30);
            button=findChild(bar,'dockItem1'); mouseClick(button); compare(scene.action,'focus:aa');
            update({showTitles:false}); wait(30); compare(findChild(bar,'taskTitle1'),null);
            scene.groups=Array.from({length:18},(_,i)=>Object.assign({},group([Object.assign({},rows()[0],{address:'ab'+i})],false),{key:'app:'+i}));
            bar.maximumLength=220; wait(30); verify(bar.overflowing);
            bar.focusIndex(bar.entries.length-1); wait(20);
            let list=findChild(bar,'dockApplications'); verify(bar.vertical ? list.contentY>0 : list.contentX>0);
            keyClick(Qt.Key_Home); keyClick(Qt.Key_Return); compare(scene.action,'launcher');
        }
        function test_moveAction() {
            actions.visible=true; wait(20);
            let picker=findChild(actions,'dockWindowPicker');
            let row=picker.itemAtIndex(0); verify(row);
            let move=findChild(row,'taskMoveButton'); verify(move);
            mouseClick(move); compare(scene.action,'move:aa:1');
            actions.visible=false;
        }
    }
}
