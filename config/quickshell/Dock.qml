pragma ComponentBehavior: Bound
import QtQuick
import "style" as Style
import QtQuick.Controls.Basic
import "DockModel.js" as Model
import "SettingsModel.js" as Settings
import "TaskbarModel.js" as Tasks

FocusScope {
    id: dock
    property bool hoverPopdowns: true
    required property var service
    required property var config
    property string component: 'hyprdock'
    readonly property bool taskbar: component === 'hyprbar'
    property string outputName: ''
    property var workspace: null
    property string edge: panel.position
    readonly property bool vertical: edge === 'left' || edge === 'right'
    readonly property var panel: config.panels[component]
    readonly property var groups: Tasks.entries(service.groups(component), panel, outputName, workspace)
    readonly property var launcherStyle: Settings.appearance(config,'launcher',wallpaperSource.toString())
    readonly property var settingsStyle: Settings.appearance(config,'settings',wallpaperSource.toString())
    property bool trashFull: false
    property bool desktopHidden: false
    readonly property var utilities: [
        {key:'files',name:'Files',utility:true,icon:'system-file-manager',windows:[]},
        {key:'settings',name:'Settings',utility:true,icon:'preferences-system',windows:[]},
        {key:'trash',name:trashFull ? 'Trash (full)' : 'Trash (empty)',utility:true,icon:trashFull ? 'user-trash-full' : 'user-trash',windows:[]},
        {key:'desktop',name:desktopHidden ? 'Restore desktop windows' : 'Show Desktop',utility:true,icon:desktopHidden ? 'view-restore' : 'user-desktop',windows:[]}
    ].filter(e => panel['show' + e.key[0].toUpperCase() + e.key.slice(1)] === true)
    readonly property var entries: [{key:'launcher', name:'Applications', launcher:true, windows:[]}].concat(groups, utilities)
    readonly property real thickness: Model.thickness(panel)
    readonly property real cellSize: thickness - 4
    property url wallpaperSource: ''
    property real screenWidth: 1366
    property real screenHeight: 768
    property real screenOffsetX: 0
    property real screenOffsetY: 0
    function itemLength(entry) { return cellSize; }
    property real trailingLength: 0
    readonly property real startPadding: panel.paddingStart ?? 6
    readonly property real endPadding: panel.paddingEnd ?? 6
    readonly property real statusEndPadding: panel.paddingEnd ?? 4
    readonly property real applicationEndPadding: trailingLength > 0 ? 6 : endPadding
    readonly property real applicationLength: Math.max(1, length - trailingLength)
    readonly property real iconSize: Math.min(panel.iconSize, cellSize - 2)
    TextMetrics {
        id: launcherMetrics
        text: '󰀻'
        font.family: 'GoMono Nerd Font'
        font.pixelSize: Math.min(dock.panel.iconSize, dock.cellSize - 2)
    }
    readonly property real spacing: panel.spacing ?? 4
    property real maximumLength: 800
    readonly property real naturalLength: startPadding + applicationEndPadding + entries.reduce((total, entry) => total + itemLength(entry), 0) + Math.max(0, entries.length - 1) * spacing
    readonly property real length: taskbar ? maximumLength : Math.min(maximumLength, naturalLength + trailingLength)
    readonly property bool overflowing: naturalLength > applicationLength
    readonly property real navigationSize: overflowing ? 24 : 0
    property bool keyboardInteraction: false
    property string draggingId: ''
    property string focusedKey: 'launcher'
    onEntriesChanged: Qt.callLater(() => {
        if (dock && dock.activeFocus) dock.focusIndex(Math.max(0,dock.entries.findIndex(entry => entry.key === dock.focusedKey)));
    })
    property point dragPoint: Qt.point(0, 0)
    signal utilityRequested(string key, bool context, rect trigger)
    signal launcherRequested(rect trigger)
    signal groupRequested(string key, rect trigger)
    signal previewsRequested(string key, rect trigger)
    signal interactionStarted()
    signal itemHovered(string kind, string key, rect trigger)
    signal itemLeft(string kind, string key, rect trigger)
    signal dismissRequested()
    implicitWidth: vertical ? thickness : length
    implicitHeight: vertical ? length : thickness
    function itemRect(item) { let p = item.mapToItem(dock, 0, 0); return Qt.rect(p.x,p.y,item.width,item.height); }
    function showGroup(group, item) { interactionStarted(); if (group.utility) utilityRequested(group.key, true, itemRect(item)); else groupRequested(group.key, itemRect(item)); }
    function activate(group, item) {
        interactionStarted();
        if (group.utility) { dismissRequested(); utilityRequested(group.key, false, itemRect(item)); }
        else if (group.launcher) { interactionStarted(); launcherRequested(itemRect(item)); }
        else if (group.windows.length > 1) previewsRequested(group.key, itemRect(item));
        else { dismissRequested(); service.activate(group, true); }
    }
    function focusIndex(index) {
        list.currentIndex = Math.max(0, Math.min(entries.length - 1, index));
        list.positionViewAtIndex(list.currentIndex, ListView.Contain);
        let item = list.itemAtIndex(list.currentIndex);
        if (item) item.forceActiveFocus();
    }
    function launcherRect() {
        list.positionViewAtIndex(0, ListView.Beginning);
        let item = list.itemAtIndex(0);
        return item ? itemRect(item) : Qt.rect(list.x, list.y, cellSize, cellSize);
    }
    function scroll(step) {
        let max = Math.max(0, (vertical ? list.contentHeight - list.height : list.contentWidth - list.width));
        if (vertical) list.contentY = Math.max(0, Math.min(max, list.contentY + step));
        else list.contentX = Math.max(0, Math.min(max, list.contentX + step));
    }
    function reorder(id, targetId) {
        let index = Model.dropIndex(Settings.effectivePins(config, component), id, targetId);
        if (index < 0 || service.busy) return false;
        return service.edit({action:'reorder', component:component, id:id, index:index});
    }
    function finishDrag() {
        if (!draggingId) return;
        let point = list.mapFromItem(dock, dragPoint.x, dragPoint.y);
        let index = list.indexAt(point.x + list.contentX, point.y + list.contentY);
        if (index >= 0 && entries[index].pinned) reorder(draggingId, entries[index].id);
        draggingId = '';
    }
    PanelPill {
        id:surface
        objectName: 'dockBackground'
        anchors.fill:parent
        config:dock.config; panel:dock.panel
        wallpaperSource:dock.wallpaperSource
        screenWidth:dock.screenWidth; screenHeight:dock.screenHeight
        screenOffsetX:dock.screenOffsetX; screenOffsetY:dock.screenOffsetY
    }
    ToolButton {
        objectName: 'dockScrollBack'
        visible: dock.overflowing
        x: dock.vertical ? (dock.width-width)/2 : 2
        y: dock.vertical ? 2 : (dock.height-height)/2
        width: dock.vertical ? dock.width-8 : 22; height: dock.vertical ? 22 : dock.height-4
        text: dock.vertical ? '↑' : '‹'; palette.buttonText: '#cdd6f4'
        Accessible.name: 'Scroll dock backward'
        onClicked: dock.scroll(-dock.cellSize * 2)
    }
    ListView {
        id: list
        objectName: 'dockApplications'
        x: dock.vertical ? 2 : dock.startPadding + dock.navigationSize
        y: dock.vertical ? dock.startPadding + dock.navigationSize : 2
        width: dock.vertical ? dock.width-4 : Math.max(0, dock.applicationLength - dock.startPadding - dock.applicationEndPadding - 2*dock.navigationSize)
        height: dock.vertical ? Math.max(0, dock.applicationLength - dock.startPadding - dock.applicationEndPadding - 2*dock.navigationSize) : dock.height-4
        orientation: dock.vertical ? ListView.Vertical : ListView.Horizontal
        model: dock.entries
        spacing: dock.spacing; clip: true
        boundsBehavior: Flickable.StopAtBounds
        currentIndex: 0
        keyNavigationEnabled: false
        WheelHandler {
            target: null
            onWheel: event => { dock.scroll(-(event.angleDelta.y || event.angleDelta.x) / 120 * dock.cellSize); event.accepted = true; }
        }
        delegate: Control {
            id: button
            required property var modelData
            required property int index
            objectName: 'dockItem' + index
            width: dock.cellSize; height: dock.cellSize
            activeFocusOnTab: true
            Accessible.role: Accessible.Button
            Accessible.name: modelData.name + (modelData.windows.length ? ', ' + modelData.windows.length + ' windows' : '')
            onActiveFocusChanged: if (activeFocus) {
                dock.focusedKey = modelData.key;
                list.currentIndex = index;
                list.positionViewAtIndex(index, ListView.Contain);
            }
            background: Rectangle {
                radius: pointer.containsMouse ? width * 0.36 : width / 2
                Behavior on radius { NumberAnimation { duration: Style.Theme.duration(button, Style.Theme.spatialDuration); easing.type: Easing.BezierSpline; easing.bezierCurve: Style.Theme.spatialCurve } }
                Behavior on color { ColorAnimation { duration: Style.Theme.duration(button, Style.Theme.hoverDuration); easing.type: Easing.BezierSpline; easing.bezierCurve: Style.Theme.effectsCurve } }
                color: button.modelData.active ? '#28cba6f7' : pointer.containsMouse || (button.activeFocus && dock.keyboardInteraction) ? '#18cdd6f4' : 'transparent'
                border.color: button.activeFocus && dock.keyboardInteraction ? '#cba6f7' : button.modelData.urgent ? '#fab387' : 'transparent'
            }
            Image {
                id: icon
                objectName: 'dockIcon' + button.index
                visible:!button.modelData.launcher && !(button.modelData.utility && button.modelData.key === 'settings')
                x: (parent.width-width)/2
                anchors.verticalCenter: parent.verticalCenter
                width: dock.iconSize; height: width
                source: button.modelData.launcher ? '' : dock.service.iconSource(button.modelData.icon)
                sourceSize.width: width; sourceSize.height: height
                fillMode: Image.PreserveAspectFit
                opacity: !button.modelData.launcher && !button.modelData.utility && !button.modelData.installed && !button.modelData.windows.length ? 0.45 : 1
            }
            Text {
                objectName: 'dockGlyph' + button.index
                x: icon.x + (icon.width-width)/2
                anchors.verticalCenter: parent.verticalCenter
                visible: button.modelData.launcher ? !!dock.launcherStyle.icon : !(button.modelData.utility && button.modelData.key === 'settings') && icon.status !== Image.Ready
                text: button.modelData.launcher ? dock.launcherStyle.icon || '󰀻' : '󰘳'
                color: '#cdd6f4'; font: launcherMetrics.font
            }
            GlassLogo {
                objectName:'dockLauncherLogo'
                anchors.fill:parent
                visible:button.modelData.launcher === true && !dock.launcherStyle.icon
                iconSize:dock.iconSize
                highlighted:pointer.containsMouse || (button.activeFocus && dock.keyboardInteraction)
            }
            GlassCog {
                anchors.fill:parent
                visible:button.modelData.utility === true && button.modelData.key === 'settings'
                iconSize:dock.iconSize
                accent:dock.settingsStyle.iconColor || dock.settingsStyle.vibrantColor || '#b4befe'
                highlighted:pointer.containsMouse || button.activeFocus
            }
            Rectangle {
                objectName: 'dockRunningIndicator'
                visible: dock.panel.indicators !== false && (button.modelData?.windows?.length || 0) > 0
                color: button.modelData.active ? '#39ff88' : '#ffdf00'; radius: 2
                width: 4; height: 4
                x: icon.x + icon.width - width
                y: icon.y + icon.height - height
                border.width: 1; border.color: '#181825'
            }
            Keys.onPressed: event => {
                dock.keyboardInteraction = true;
                if (event.key === Qt.Key_Escape) { dock.draggingId = ''; dock.keyboardInteraction = false; dock.focus = false; dock.dismissRequested(); event.accepted = true; }
                else if (event.key === Qt.Key_Menu || (event.key === Qt.Key_F10 && (event.modifiers & Qt.ShiftModifier))) {
                    if (!modelData.launcher) dock.showGroup(modelData, button);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Space) {
                    dock.activate(modelData, button); event.accepted = true;
                } else if (event.key === Qt.Key_Home) { dock.focusIndex(0); event.accepted = true; }
                else if (event.key === Qt.Key_End) { dock.focusIndex(dock.entries.length-1); event.accepted = true; }
                else {
                    let step = event.key === (dock.vertical ? Qt.Key_Down : Qt.Key_Right) ? 1
                             : event.key === (dock.vertical ? Qt.Key_Up : Qt.Key_Left) ? -1 : 0;
                    if (step) {
                        if ((event.modifiers & Qt.ControlModifier) && modelData.pinned) {
                            let pins = Settings.effectivePins(dock.config, dock.component), target = pins.indexOf(modelData.id) + step;
                            if (target >= 0 && target < pins.length) dock.reorder(modelData.id, pins[target]);
                        } else dock.focusIndex(index + step);
                        event.accepted = true;
                    }
                }
            }
            MouseArea {
                id: pointer
                anchors.fill: parent; hoverEnabled: true
                readonly property string hoverKind: button.modelData.launcher ? 'launcher' : button.modelData.windows.length ? 'previews' : ''
                function leavePreview() {
                    if (hoverKind) dock.itemLeft(hoverKind, button.modelData.key, dock.itemRect(button));
                }
                onEntered: if (hoverKind && !dock.draggingId && dock.hoverPopdowns) {
                    dock.interactionStarted();
                    dock.itemHovered(hoverKind, button.modelData.key, dock.itemRect(button));
                }
                onExited: leavePreview()
                Component.onDestruction: leavePreview()
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                property point pressPoint
                property bool moved: false
                preventStealing: !!button.modelData.pinned
                onPressed: mouse => {
                    dock.keyboardInteraction = false; button.forceActiveFocus(); pressPoint = Qt.point(mouse.x, mouse.y); moved = false;
                }
                onPositionChanged: mouse => {
                    if (!(pressedButtons & Qt.LeftButton) || !button.modelData.pinned || dock.service.busy) return;
                    if (Math.abs(mouse.x-pressPoint.x) + Math.abs(mouse.y-pressPoint.y) > 10) {
                        dock.dismissRequested();
                        moved = true; dock.draggingId = button.modelData.id;
                        dock.dragPoint = mapToItem(dock, mouse.x, mouse.y);
                    }
                }
                onReleased: mouse => {
                    if (moved) { dock.finishDrag(); return; }
                    if (!containsMouse) return;
                    if (mouse.button === Qt.RightButton && !button.modelData.launcher) dock.showGroup(button.modelData, button);
                    else if (mouse.button === Qt.MiddleButton && button.modelData.installed) dock.service.launch(button.modelData.id);
                    else if (mouse.button === Qt.LeftButton) dock.activate(button.modelData, button);
                }
                onCanceled: dock.draggingId = ''
            }
        }
    }
    ToolButton {
        objectName: 'dockScrollForward'
        visible: dock.overflowing
        x: dock.vertical ? (dock.width-width)/2 : dock.applicationLength-width-2
        y: dock.vertical ? dock.applicationLength-height-2 : (dock.height-height)/2
        width: dock.vertical ? dock.width-8 : 22; height: dock.vertical ? 22 : dock.height-4
        text: dock.vertical ? '↓' : '›'; palette.buttonText: '#cdd6f4'
        Accessible.name: 'Scroll dock forward'
        onClicked: dock.scroll(dock.cellSize * 2)
    }
    Rectangle {
        visible: !!dock.draggingId; z: 10
        x: dock.dragPoint.x-16; y: dock.dragPoint.y-16
        width: 32; height: 32; radius: 8; color: '#cba6f7'; opacity: 0.8
        Text { anchors.centerIn: parent; text: '↔'; color: '#181825' }
    }
    Timer {
        interval: 100; repeat: true; running: !!dock.draggingId
        onTriggered: {
            let point = list.mapFromItem(dock, dock.dragPoint.x, dock.dragPoint.y);
            let value = dock.vertical ? point.y : point.x, length = dock.vertical ? list.height : list.width;
            if (value < 24) dock.scroll(-dock.cellSize/2);
            else if (value > length-24) dock.scroll(dock.cellSize/2);
        }
    }
}
