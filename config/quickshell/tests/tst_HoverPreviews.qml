import QtQuick
import QtTest
import ".."
import "../PreviewModel.js" as PreviewModel

Item {
    id: scene
    width: 1366; height: 900
    MenuController { id: state }
    Bar {
        id: pane
        z: 1
        x: position === 'right' ? scene.width - width : 0
        y: position === 'bottom' ? scene.height - height : 0
        width: vertical ? implicitWidth : scene.width
        height: vertical ? scene.height : implicitHeight
        screenHeight: scene.height
        statusData: ({workspaces:[{id:1,name:'1'},{id:2,name:'2'}],audio:{},network:{},bluetooth:{},battery:{}})
        mediaData: ({playing:true,title:'Track',levels:[0.2,0.8,0.4]})
        activeMenu: state.section
        onMenuHovered: name => state.hover(name)
        onMenuLeft: name => state.leave(name)
        onPreviewUnavailable: state.close()
        onAction: (name, argument) => scene.workspaceClicked = argument
    }
    MenuPopover {
        id: popover
        anchors.fill: parent
        edge: pane.position
        alignment: pane.side(state.displayedSection)
        triggerRect: {
            let rect = pane.menuRect(state.displayedSection);
            return Qt.rect(rect.x + pane.x,rect.y + pane.y,rect.width,rect.height);
        }
        opened: state.section.length > 0
        instant: true
        title: state.displayedSection
        page: Component { Item { implicitHeight: 180 } }
        onHoverChanged: inside => state.retain(inside)
    }
    property int workspaceClicked: 0
    TestCase {
        name: 'HoverPreviews'
        when: windowShown
        function init() { state.close(); mouseMove(scene,700,850); }
        function test_workspaceAndMediaHoverOnEveryEdge_data() {
            return ['top','bottom','left','right'].map(edge => ({tag:edge,edge:edge}));
        }
        function test_workspaceAndMediaHoverOnEveryEdge(data) {
            pane.settings = {bar:{position:data.edge},items:[]};
            pane.mediaData = {playing:true,title:'Track'};
            wait(20);
            for (let id of [1,2]) {
                let button = findChild(pane,'workspace'+id);
                mouseMove(button,button.width/2,button.height/2);
                tryCompare(state,'section','workspacePreview');
                compare(pane.previewWorkspaceId,id);
                let point = button.mapToItem(pane,0,0), rect = pane.menuRect('workspacePreview');
                compare(rect.x,point.x); compare(rect.y,point.y);
                compare(rect.width,button.width); compare(rect.height,button.height);
                verify(popover.bodyX >= 0 && popover.bodyRight <= scene.width);
                verify(popover.bodyY >= 0 && popover.bodyBottom <= scene.height);
                if (data.edge === 'top') verify(popover.bodyY > pane.y + pane.height);
                if (data.edge === 'bottom') verify(popover.bodyBottom < pane.y);
                if (data.edge === 'left') verify(popover.bodyX > pane.x + pane.width);
                if (data.edge === 'right') verify(popover.bodyRight < pane.x);
            }
            let media = pane.moduleItems.media.item;
            mouseMove(media,media.width/2,media.height/2);
            tryCompare(state,'section','media');
            let rect = pane.menuRect('media');
            compare(rect.width,media.width);
            pane.mediaData = {playing:false};
            tryCompare(state,'section','');
        }
        function test_workspaceClickStillDispatchesWithoutHoverSwitch() {
            pane.settings = {bar:{position:'top'},items:[]};
            scene.workspaceClicked = 0;
            let second = findChild(pane,'workspace2');
            mouseClick(second,second.width/2,second.height/2);
            compare(scene.workspaceClicked,2);
        }
        function test_mediaMatchAvoidsUnrelatedOrAmbiguousWindows() {
            let first = {title:'Song — Browser',lastIpcObject:{class:'firefox',pid:100}};
            let second = {title:'Another tab',lastIpcObject:{class:'firefox',pid:100}};
            let terminal = {title:'Terminal',lastIpcObject:{class:'kitty',pid:200}};
            compare(PreviewModel.mediaWindow([first,terminal],{appId:'firefox.desktop'}),first);
            compare(PreviewModel.mediaWindow([first,second],{appId:'firefox',trackTitle:'Song'}),first);
            compare(PreviewModel.mediaWindow([first,second],{appId:'firefox'}),null);
            compare(PreviewModel.mediaWindow([terminal],{appId:'firefox'}),null);
            compare(PreviewModel.mediaWindow([first,terminal],{processId:200}),terminal);
            compare(PreviewModel.mediaWindow([first,terminal],{}),null);
        }
    }
}
