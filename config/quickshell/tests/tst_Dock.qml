pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import ".."
import "../DockModel.js" as Geometry
import "../SettingsModel.js" as Settings

Item {
    id: scene
    width: 800; height: 700
    readonly property var appService: service
    property var config: ({})
    property var groups: []
    property var action: ({})
    property string request: ''
    QtObject {
        id: service
        property bool busy: false
        property string error: ''
        function groups(component) { return scene.groups; }
        function iconSource(name) { return ''; }
        function activate(group) { scene.request = group.id; return true; }
        function launch(id) { scene.request = 'launch:' + id; return true; }
        function windowAction(kind,address) { scene.request = kind + ':' + address; return true; }
        function edit(action) { scene.action = action; return true; }
    }
    Rectangle { anchors.fill:parent; color:'#172333' }
    Dock {
        id: dock
        x: vertical ? 20 : 30; y: vertical ? 20 : 80
        width:implicitWidth; height:implicitHeight
        service:scene.appService; config:scene.config
        maximumLength:700
        onLauncherRequested:scene.request = 'launcher'
        onGroupRequested:(key,trigger) => scene.request = 'picker:' + key
        onPreviewsRequested:(key,trigger) => scene.request = 'previews:' + key
    }
    DockActions { id: actions; x:400; width:264; service:scene.appService; group:scene.groups[0] || null }
    DockPreviews { id: previews; x:20; y:440; width:500; height:implicitHeight; visible:false; service:scene.appService; group:scene.groups[0] || null }
    SettingsDockEditor {
        id: editor
        visible:false; width:400
        settings:scene.config.panels ? scene.config.panels.hyprdock : ({})
        onEdited:(key,value) => scene.action = {key:key,value:value}
    }
    MenuPopover {
        id: popup
        anchors.fill:parent
        opened:false; alignToTrigger:true
        title:'App windows'; symbol:'󰘳'
        triggerRect:Qt.rect(120,600,48,48)
        page:Component { DockActions { service:scene.appService; group:scene.groups[0] || null } }
    }
    TestCase {
        name:'Dock'
        when:windowShown
        function init() {
            scene.config={bar:{position:'top',height:32,marginTop:5,paddingBottom:0,visible:true},
                panels:{hyprpane:{enabled:true,monitors:[]},hyprdock:{enabled:true,position:'bottom',thickness:56,iconSize:32,spacing:4,marginEdge:5,marginEnds:10,windowGap:0,background:'inherit'}},
                pins:{mode:'shared',shared:['app0.desktop','app1.desktop'],hyprdock:[],hyprbar:[]}};
            scene.groups=makeGroups(4);
            scene.action={}; scene.request=''; popup.opened=false; editor.visible=false; previews.visible=false;
            dock.maximumLength=700; dock.draggingId='';
            wait(20);
        }
        function makeGroups(count) {
            return Array.from({length:count},(_,i) => ({key:'app:app'+i+'.desktop',id:'app'+i+'.desktop',name:'Application '+i,icon:'',
                installed:i!==1,pinned:i<2,active:i===0,windows:i===1 ? [] : [{address:'ab'+i,title:'Window '+i,workspaceName:'1',output:'eDP-1',active:i===0}]}));
        }
        function edge(value) { let next=Settings.copy(scene.config); next.panels.hyprdock.position=value; scene.config=next; }
        function test_orientationOverflowAndFocus_data() { return ['top','bottom','left','right'].map(e=>({tag:e,edge:e})); }
        function test_orientationOverflowAndFocus(data) {
            edge(data.edge); scene.groups=makeGroups(16); dock.maximumLength=220; wait(30);
            compare(dock.vertical,data.edge==='left'||data.edge==='right');
            verify(dock.overflowing);
            let list=findChild(dock,'dockApplications');
            verify(dock.vertical ? dock.height<=220 : dock.width<=220);
            verify(findChild(dock,'dockItem0').width>=36);
            dock.focusIndex(16); wait(30);
            verify(dock.vertical ? list.contentY>0 : list.contentX>0);
            keyClick(Qt.Key_Home); wait(20);
            compare(list.currentIndex,0);
            keyClick(Qt.Key_Return); compare(scene.request,'launcher');
            keyClick(dock.vertical ? Qt.Key_Down : Qt.Key_Right); wait(20);
            compare(list.currentIndex,1);
            keyClick(Qt.Key_Return); compare(scene.request,'app0.desktop');
            keyClick(Qt.Key_Menu); compare(scene.request,'picker:app:app0.desktop');
            keyClick(dock.vertical ? Qt.Key_Down : Qt.Key_Right,Qt.ControlModifier);
            compare(scene.action,{action:'reorder',component:'hyprdock',id:'app0.desktop',index:1});
        }
        function test_pointerLaunchPickerAndDrag_data() { return ['top','bottom','left','right'].map(e=>({tag:e,edge:e})); }
        function test_pointerLaunchPickerAndDrag(data) {
            edge(data.edge); wait(20);
            let first=findChild(dock,'dockItem1'), second=findChild(dock,'dockItem2');
            mouseClick(first,first.width/2,first.height/2,Qt.LeftButton); compare(scene.request,'app0.desktop');
            mouseClick(first,first.width/2,first.height/2,Qt.RightButton); compare(scene.request,'picker:app:app0.desktop');
            mouseClick(first,first.width/2,first.height/2,Qt.MiddleButton); compare(scene.request,'launch:app0.desktop');
            let target=second.mapToItem(first,second.width/2,second.height/2);
            mousePress(first,first.width/2,first.height/2,Qt.LeftButton);
            mouseMove(first,target.x,target.y,30);
            mouseRelease(first,target.x,target.y,Qt.LeftButton);
            compare(scene.action,{action:'reorder',component:'hyprdock',id:'app0.desktop',index:1});
            compare(dock.draggingId,'');
            let next=scene.groups.slice(); next[0]=Object.assign({},next[0],{windows:next[0].windows.concat([{address:'ba',title:'Second',workspaceName:'2',output:'HDMI-A-1'}])}); scene.groups=next; wait(30);
            first=findChild(dock,'dockItem1'); mouseClick(first,20,20,Qt.LeftButton);
            compare(scene.request,'previews:app:app0.desktop');
            next=scene.groups.slice(); next[0]=Object.assign({},next[0],{windows:[Object.assign({},next[0].windows[0],{active:false}),Object.assign({},next[0].windows[1],{active:true})]}); scene.groups=next; wait(30);
            first=findChild(dock,'dockItem1'); mouseClick(first,20,20,Qt.LeftButton);
            compare(scene.request,'previews:app:app0.desktop');
            previews.visible=true; wait(30);
            compare(previews.orientation,ListView.Horizontal);
            let preview=findChild(previews,'dockPreview-ba');
            verify(preview); mouseClick(preview,preview.width/2,40);
            compare(scene.request,'focus:ba');
            let close=findChild(previews,'dockPreviewClose-ba');
            verify(close); mouseClick(close,14,14);
            compare(scene.request,'close:ba');
            mouseClick(first,20,20,Qt.RightButton);
            compare(scene.request,'picker:app:app0.desktop');
        }
        function test_settingsAndTargetSizing() {
            editor.visible=true; editor.z=100; wait(30);
            let enabled=findChild(editor,'dockEnabledControl');
            compare(enabled.checked,true); mouseClick(enabled,enabled.width-20,enabled.height/2); compare(scene.action,{key:'enabled',value:false});
            let control=findChild(editor,'dockEdgeControl');
            control.currentIndex=3; control.activated(3); compare(scene.action,{key:'position',value:'right'});
            let config=Settings.copy(scene.config);
            config.panels.hyprdock.thickness=28; config.panels.hyprdock.iconSize=96; scene.config=config;
            dock.maximumLength=220; wait(20);
            compare(dock.thickness,112); verify(findChild(dock,'dockItem0').width>=104);
        }
        function test_cornerInsetsAndSavedVisibility() {
            let config=Settings.copy(scene.config);
            config.bar.position='left';
            compare(Geometry.insets(config,'hyprpane','eDP-1',1,32),{top:0,bottom:61});
            config.panels.hyprdock.workspaceOverrides={'1':false};
            compare(Geometry.insets(config,'hyprpane','eDP-1',1,32),{top:0,bottom:0});
            config.panels.hyprdock.monitors=['HDMI-A-1'];
            compare(Geometry.insets(config,'hyprpane','eDP-1',2,32),{top:0,bottom:0});
            config.bar.position='top';
            compare(Geometry.insets(config,'hyprdock','eDP-1',2,38),{top:43,bottom:0});
            compare(Geometry.thickness({thickness:28,iconSize:96}),112);
        }
        function test_contextActionsAndMissingPin() {
            let buttons=actions.children.filter(c=>c.text!==undefined);
            let pin=buttons.find(b=>b.text==='Unpin from Hyprdock');
            verify(pin); pin.clicked(); compare(scene.action.action,'unpin');
            let next=scene.groups.slice(); next[0]=Object.assign({},next[0],{installed:false,windows:[]}); scene.groups=next; wait(20);
            compare(buttons.find(b=>b.text==='New instance').enabled,false);
            verify(pin.enabled); pin.clicked(); compare(scene.action.id,'app0.desktop');
        }
        function test_popoverAnchorsAndScreenshots_data() { return ['top','bottom','left','right'].map(e=>({tag:e,edge:e})); }
        function test_popoverAnchorsAndScreenshots(data) {
            edge(data.edge); popup.edge=data.edge;
            popup.triggerRect=data.edge==='top' ? Qt.rect(120,20,48,48) : data.edge==='bottom' ? Qt.rect(120,630,48,48) : data.edge==='left' ? Qt.rect(20,300,48,48) : Qt.rect(730,300,48,48);
            popup.opened=true; wait(40);
            verify(popup.bodyX>=0 && popup.bodyRight<=scene.width);
            verify(popup.bodyY>=0 && popup.bodyBottom<=scene.height);
            if(data.edge==='top') verify(popup.bodyY>popup.triggerRect.y+48);
            if(data.edge==='bottom') verify(popup.bodyBottom<popup.triggerRect.y);
            if(data.edge==='left') verify(popup.bodyX>popup.triggerRect.x+48);
            if(data.edge==='right') verify(popup.bodyRight<popup.triggerRect.x);
            grabImage(scene).save('/tmp/hyprdock-'+data.edge+'.png');
        }
        function test_horizontalPreviewPopover() {
            popup.preferredBodyWidth=720; popup.showHeader=false; popup.opened=true; wait(30);
            compare(popup.bodyWidth,720);
            verify(popup.bodyX>=0 && popup.bodyRight<=scene.width);
            popup.preferredBodyWidth=300; popup.showHeader=true;
        }
    }
}
