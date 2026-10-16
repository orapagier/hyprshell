import QtQuick
import QtQuick.Controls.Basic
import QtTest
import ".."
import "../SettingsModel.js" as Model

Item {
    id: scene
    width: 720; height: 900
    Rectangle { anchors.fill: parent; color: "#172333" }
    Bar {
        id: pane
        x: position === "right" ? scene.width - width - 8 : 8
        y: 10
        width: vertical ? implicitWidth : scene.width - 16
        height: vertical && !compact ? scene.height - 20 : implicitHeight
        screenHeight: scene.height
        clockText: "Friday October 16 02:45 PM"
        mediaData: ({playing: true, title: "Music", levels: [0.3,0.8,0.6,0.4,1,0.4]})
        statusData: ({workspaces: [{id:1,name:"1",active:true},{id:2,name:"2"}], audio: {icon:"󰕾",text:"64%"}, network:{text:"󰤨",connected:true}, bluetooth:{text:"󰂯",powered:true}, battery:{present:true,text:"󰁹 100%"}})
        notificationData: ({count:999,tooltip:"999 notifications"})
        trayModel: [{icon: Qt.resolvedUrl("../icons/preview-tray.svg"),title:"Example app"}]
        activeMenu: "calendar"
        onAction: (name, argument) => scene.action = name
        onTrayAction: (item, source, button) => scene.action = "tray"
    }
    MenuPopover {
        id: popover
        anchors.fill: parent
        edge: pane.position
        triggerRect: { let rect = pane.menuRect("calendar"); return Qt.rect(rect.x + pane.x, rect.y + pane.y, rect.width, rect.height); }
        title: "Calendar"
        symbol: "󰃭"
        opened: true
        instant: true
        page: Component { CalendarMenu { today: new Date(2026,9,16) } }
    }
    Text {
        x: scene.width / 2 - width / 2; y: 12
        text: (pane.position === "left" ? "Left" : "Right") + " · upright characters · " + (pane.compact ? "Compact" : "Full edge")
        color: "#cdd6f4"; font.pixelSize: 12
    }
    property string action: ""
    TestCase {
        name: "VerticalPane"
        when: windowShown
        function config(edge, mode) {
            return {bar: {position: edge, verticalPresentation: mode || "edge", height:32, iconSize:16, spacing:3, adaptiveColors:false}, items:[]};
        }
        function init() {
            scene.width = 720; scene.height = 900;
            pane.settings = config('left');
            pane.clockText = "Friday October 16 02:45 PM";
            pane.mediaData = {playing:true,title:"Music",levels:[0.3,0.8,0.6,0.4,1,0.4]};
            pane.trayModel = [{icon:Qt.resolvedUrl("../icons/preview-tray.svg"),title:"Example app"}];
            pane.notificationData = {count:999};
            pane.activeMenu = 'calendar';
            popover.opened = true;
            scene.action = '';
            findChild(pane, 'panelViewport').contentY = 0;
            wait(20);
        }
        function assertLayout() {
            let ids = Object.keys(pane.moduleItems).filter(id => pane.itemShown(id));
            ids.sort((a,b) => pane.moduleItems[a].y - pane.moduleItems[b].y);
            for (let i = 0; i < ids.length; ++i) {
                let item = pane.moduleItems[ids[i]];
                verify(item.x >= 0, ids[i] + ' left');
                verify(item.x + item.width <= pane.width + 0.1, ids[i] + ' right');
                if (i) {
                    let previous = pane.moduleItems[ids[i-1]];
                    verify(item.y >= previous.y + previous.height - 0.1, ids[i] + ' overlaps ' + ids[i-1]);
                }
            }
        }
        function test_lettersStackWithoutGrowingWidth_data() { return ['left','right'].map(edge => ({tag:edge,edge:edge})); }
        function test_lettersStackWithoutGrowingWidth(data) {
            pane.settings = config(data.edge);
            let original = pane.width;
            pane.clockText = 'September Wednesday 12:59 PM';
            compare(pane.width,original);
            compare(pane.width,40);
            let clock = pane.moduleItems.calendar;
            compare(clock.displayText, Array.from(pane.clockText).join('\n'));
            compare(clock.content.wrapMode, Text.NoWrap);
            for (let id of ['calendar','audio','battery'])
                for (let line of pane.moduleItems[id].displayText.split('\n')) verify(Array.from(line).length <= 1);
            verify(clock.content.contentWidth <= clock.content.width + 1);
            assertLayout();
        }
        function test_compactAndFullEdgeRetainAlignmentAndOrder() {
            pane.clockText = '12:34';
            pane.mediaData = {playing:false};
            pane.settings = config('left','compact');
            compare(pane.height,pane.minimumVerticalLength);
            verify(pane.height < scene.height - 20);
            assertLayout();
            let next = config('right','edge');
            next.items = [{id:'calendar',side:'left',order:0},{id:'launcher',side:'center'},{id:'audio',side:'right',order:20}];
            pane.settings = next;
            assertLayout();
            compare(pane.orderedItems('left')[0],'calendar');
            compare(pane.side('launcher'),'center');
            compare(pane.side('audio'),'right');
        }
        function test_smallScaledDisplayAndTrayOverflowScrollWithoutOverlap() {
            scene.width = 480; scene.height = 400;
            pane.trayModel = Array.from({length:18},(_,i) => ({icon:Qt.resolvedUrl("../icons/preview-tray.svg"),title:'App '+i}));
            pane.clockText = 'Wednesday September 30 11:59 PM';
            for (let edge of ['left','right']) {
                pane.settings = config(edge);
                assertLayout();
                verify(pane.overflowing);
                let viewport = findChild(pane,'panelViewport');
                verify(viewport.contentHeight > viewport.height);
                pane.ensureItemVisible(pane.moduleItems.power);
                verify(pane.scrollOffset > 0);
                let rect = pane.menuRect('power');
                verify(rect.y >= 0 && rect.y + rect.height <= pane.height + 0.1);
                let trayIcon = findChild(pane,'trayIcon');
                verify(trayIcon.width >= 24 && trayIcon.height >= 24);
                pane.ensureItemVisible(trayIcon);
                let before = pane.menuRect('calendar').y;
                pane.ensureItemVisible(pane.moduleItems.calendar);
                verify(pane.menuRect('calendar').y !== before);
                verify(popover.bodyX >= 12 && popover.bodyRight <= scene.width - 12 + 0.1);
                verify(popover.bodyY >= 12 && popover.bodyBottom <= scene.height - 12 + 0.1);
                let scroll = findChild(popover,'menuBodyScroll');
                verify(scroll.clip);
            }
        }
        function test_largeFontsSharedGroupsAndPreviewScroll() {
            scene.height = 500;
            let next = config('right');
            next.items = [{id:'audio',text:'Wide WWW',fontSize:24,pillGroup:'status'}, {id:'battery',pillGroup:'status'}];
            pane.settings = next;
            let audio = pane.moduleItems.audio;
            verify(audio.content.contentWidth <= audio.content.width + 1);
            let shared = findChild(pane,'sharedPill_status');
            verify(shared !== null);
            compare(shared.vertical,true);
            assertLayout();
            let overlay = editorFactory.createObject(pane, {width:pane.width,height:pane.height,bar:pane});
            let viewport = findChild(pane,'panelViewport');
            pane.ensureItemVisible(audio);
            let rect = pane.itemRect('audio');
            compare(overlay.itemAt(rect.x+rect.width/2,rect.y+rect.height/2),'audio');
            overlay.destroy();
        }
        Component { id: editorFactory; PreviewLayoutEditor {} }
        function test_customLabelsAndVisibilitySurviveBothOrientations() {
            for (let edge of ['left','right']) {
                let next = config(edge);
                next.items = [{id:'audio',text:'Volume',hideIcon:true},{id:'battery',hideText:true},{id:'wifi',text:'Connected network'}];
                pane.settings = next;
                compare(pane.moduleItems.audio.displayText,'V\no\nl\nu\nm\ne');
                compare(pane.moduleItems.audio.shownIcon,'');
                compare(pane.moduleItems.battery.shownText,'');
                verify(pane.moduleItems.wifi.content.contentWidth <= pane.moduleItems.wifi.content.width + 1);
                compare(pane.moduleItems.wifi.tooltipText.indexOf('Connected network') >= 0,true);
                assertLayout();
            }
        }
        function test_topBottomKeepHorizontalTextAndCustomizations() {
            scene.width = 1366;
            pane.clockText = 'Oct 16 02:45 PM Fri';
            for (let edge of ['top','bottom']) {
                let next = config(edge);
                next.items = [{id:'audio',side:'left',order:0,text:'Volume',hideIcon:true},{id:'calendar',side:'center'}];
                pane.settings = next;
                compare(pane.vertical,false);
                compare(pane.moduleItems.calendar.displayText,pane.clockText);
                compare(pane.moduleItems.audio.displayText,'Volume');
                compare(pane.moduleItems.audio.shownIcon,'');
                for (let id of Object.keys(pane.moduleItems).filter(id => pane.itemShown(id))) {
                    let item = pane.moduleItems[id];
                    verify(item.y >= 0 && item.y + item.height <= pane.height + 0.1,id);
                }
            }
        }
        function test_trayCustomTextAndHiddenIconsKeepTheirControls() {
            let next = config('left');
            next.items = [{id:'tray',text:'Apps'}];
            pane.settings = next;
            let tray = pane.moduleItems.tray, icon = findChild(tray,'trayIcon');
            verify(icon.y + icon.parent.y >= tray.content.height + 4);
            icon.forceActiveFocus();
            keyClick(Qt.Key_Return);
            compare(scene.action,'tray');
            next.items[0].hideIcon = true;
            pane.settings = Model.copy(next);
            compare(icon.parent.visible,false);
            verify(tray.height < 100);
            compare(tray.displayText,'A\np\np\ns');
        }
        function test_unicodeIconsAndAccentedLettersStayIntact() {
            compare(pane.moduleItems.notifications.displayText, "󰂚");
            compare(pane.moduleItems.wifi.displayText, "󰤨");
            let next = config('left');
            next.items = [{id:'audio',text:'Café 🐱'}];
            pane.settings = next;
            compare(pane.moduleItems.audio.displayText, 'C\na\nf\né\n \n🐱');
            next.items[0].text = 'Cafe\u0301';
            pane.settings = Model.copy(next);
            compare(pane.moduleItems.audio.displayText, 'C\na\nf\ne\u0301');
        }
        function test_notificationDigitsStayInsideAndMediaHasFullTooltip() {
            let bell = pane.moduleItems.notifications, badge = findChild(bell,'notificationBadge');
            compare(badge.text,'9\n9\n9');
            verify(badge.x >= 0 && badge.x + badge.width <= bell.width);
            verify(badge.y >= bell.content.y + bell.content.height);
            verify(badge.y + badge.height <= bell.height);
            pane.mediaData = {playing:true,title:'A very long music title that remains available in its tooltip',levels:[]};
            let media = pane.moduleItems.media.item;
            verify(media.displayText.split('\n').length <= 12);
            compare(media.displayText.slice(-1),'…');
            verify(media.text.indexOf('tooltip') >= 0);
        }
        function test_menuAnchorInwardAndKeyboardAction_data() { return ['left','right'].map(edge => ({tag:edge,edge:edge})); }
        function test_menuAnchorInwardAndKeyboardAction(data) {
            pane.settings = config(data.edge);
            pane.ensureItemVisible(pane.moduleItems.calendar);
            if (data.edge === 'left') verify(popover.bodyX > pane.x + pane.width);
            else verify(popover.bodyRight < pane.x);
            verify(popover.containsPointer(Qt.point(popover.bodyX+20,popover.bodyY+20)));
            popover.opened = false;
            pane.moduleItems.audio.forceActiveFocus();
            keyClick(Qt.Key_Return);
            compare(scene.action,'audio');
            let rect = pane.menuRect('audio');
            verify(rect.y >= 0 && rect.y + rect.height <= pane.height + 0.1);
        }
        function test_reviewScreenshots_data() { return ['left','right'].map(edge => ({tag:edge,edge:edge})); }
        function test_reviewScreenshots(data) {
            scene.height = 1100;
            pane.settings = config(data.edge);
            pane.ensureItemVisible(pane.moduleItems.calendar);
            wait(250);
            let saved = false;
            scene.grabToImage(result => { saved = result.saveToFile('/tmp/hyprpane-phase2-'+data.edge+'.png'); });
            tryVerify(() => saved);
        }
    }
}
