pragma ComponentBehavior: Bound
import QtQuick
import QtTest
import ".."
import "../TaskbarModel.js" as Tasks
import "../SettingsModel.js" as Settings

Item {
    id: scene
    width:900; height:700
    property string menu:''
    TaskbarStatus {
        id:status
        width:vertical ? 48 : 500; height:vertical ? 500 : 48
        config:({panels:{hyprbar:{rightItems:null}},bar:{height:32,position:'top'},items:[]})
        notificationData:({count:3})
        statusData:({workspaces:[],audio:{text:'70%'},network:{},bluetooth:{},battery:{present:true,text:'80%'}})
        onAction:(name,argument) => scene.menu=name
    }
    TestCase {
        name:'TaskbarStatus'; when:windowShown
        function init() {
            scene.menu=''; status.edge='bottom';
            status.config={panels:{hyprbar:{rightItems:null}},bar:{height:32,spacing:3},items:[
                {id:'launcher',side:'left',enabled:true,order:0},
                {id:'calendar',side:'center',enabled:true,order:1},
                {id:'audio',side:'right',enabled:true,order:2},
                {id:'notifications',side:'right',enabled:true,order:3},
                {id:'wifi',side:'right',enabled:false,order:4},
                {id:'power',side:'right',enabled:true,order:5}]};
            wait(20);
        }
        function test_inheritAndCustomizeWithoutChangingPane() {
            compare(Tasks.rightItems(status.config),['audio','notifications','power']);
            compare(status.orderedItems('right'),['audio','notifications','power']);
            verify(!status.itemEnabled('calendar'));
            let original=Settings.copy(status.config);
            let next=Settings.copy(status.config); next.panels.hyprbar.rightItems=['calendar','wifi']; status.config=next;
            compare(status.orderedItems('right'),['calendar','wifi']);
            verify(status.itemEnabled('wifi')); compare(status.config.items,original.items);
            compare(status.side('calendar'),'right');
            next=Settings.copy(status.config); next.panels.hyprbar.rightItems=[]; status.config=next;
            compare(status.contentLength,0);
        }
        function test_mediaFitsNaturalWidth() {
            let next=Settings.copy(status.config); next.panels.hyprbar.rightItems=['media','audio']; status.config=next;
            status.mediaData={playing:true,title:'A very long media title that must remain bounded',levels:[0.2,0.8,0.4]};
            status.width=Qt.binding(() => status.contentLength);
            wait(30); verify(status.contentLength>0 && status.contentLength<500);
            status.mediaData={playing:false,levels:[]};
            status.width=Qt.binding(() => status.vertical ? 48 : 500);
        }
        function test_fourEdges_data() { return ['top','bottom','left','right'].map(edge=>({tag:edge,edge:edge})); }
        function test_fourEdges(data) {
            status.edge=data.edge; wait(30);
            verify(status.contentLength>0);
            let ids=status.orderedItems('right');
            for(let i=1;i<ids.length;i++) {
                let a=status.itemRect(ids[i-1]), b=status.itemRect(ids[i]);
                verify(status.vertical ? b.y>=a.y+a.height : b.x>=a.x+a.width);
            }
            let audio=status.moduleItems.audio;
            mouseClick(audio); compare(scene.menu,'audio');
            let rect=status.menuRect('audio'); verify(rect.width>0 && rect.height>0);
        }
    }
}
