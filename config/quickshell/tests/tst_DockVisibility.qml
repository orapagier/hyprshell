pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import ".."
import "../DockModel.js" as Model

Item {
    width:600; height:500
    DockVisibility { id: state }
    QtObject {
        id: fakeUtilities
        property bool busy:false
        property bool full:true
        property bool available:true
        property string error:''
        property string action:''
        function run(name) { action=name; }
    }
    DockTrashMenu { id: menu; width:300; utilities:fakeUtilities }
    TestCase {
        name:'DockVisibility'
        when:windowShown
        function init() {
            state.mode='always'; state.eligible=true; state.fullscreen=false;
            state.fullscreenPolicy='hide'; state.overlapped=false; state.hovered=false; state.interacting=false;
            fakeUtilities.action=''; menu.confirming=false;
        }
        function test_modes_data() { return ['always','auto-hide','dodge'].map(m=>({tag:m,mode:m})); }
        function test_modes(data) {
            state.mode=data.mode; state.overlapped=true;
            wait(550);
            compare(state.shown,data.mode==='always');
            compare(state.reserve,data.mode==='always');
            state.hovered=true; compare(state.shown,true);
            state.hovered=false; wait(200); compare(state.shown,true);
            state.interacting=true; wait(550); compare(state.shown,true);
            state.interacting=false; wait(550); compare(state.shown,data.mode==='always');
            state.overlapped=false; compare(state.shown,data.mode!=='auto-hide');
        }
        function test_fullscreenAndWorkspace() {
            state.fullscreen=true; compare(state.shown,false); compare(state.reserve,false);
            state.hovered=true; compare(state.shown,false);
            state.fullscreenPolicy='show'; compare(state.shown,true);
            state.eligible=false; compare(state.shown,false); compare(state.reserve,false);
        }
        function test_reentryCancelsHide() {
            state.mode='auto-hide'; state.hovered=true; state.hovered=false;
            wait(300); state.hovered=true; wait(300); compare(state.shown,true);
        }
        function test_alignmentAndOverlap() {
            compare(Model.aligned(500,200,'start'),0);
            compare(Model.aligned(500,200,'center'),150);
            compare(Model.aligned(500,200,'end'),300);
            let client={workspace:{id:2}, lastIpcObject:{at:[1020,20],size:[100,100]}};
            verify(Model.overlaps(Qt.rect(0,0,80,80),client,{x:1000,y:0},2));
            verify(!Model.overlaps(Qt.rect(0,0,80,80),client,{x:1000,y:0},1));
            client.lastIpcObject.pinned=true;
            verify(Model.overlaps(Qt.rect(0,0,80,80),client,{x:1000,y:0},1));
            verify(!Model.overlaps(Qt.rect(200,200,80,80),client,{x:1000,y:0},2));
        }
        function test_trashRequiresConfirmation() {
            let button=findChild(menu,'dockEmptyTrash');
            mouseClick(button); compare(fakeUtilities.action,''); verify(menu.confirming);
            menu.active=false; verify(!menu.confirming); compare(fakeUtilities.action,''); menu.active=true;
            mouseClick(button); mouseClick(button); compare(fakeUtilities.action,'empty-confirmed');
        }
    }
}
