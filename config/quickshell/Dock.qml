pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import "DockModel.js" as Model
import "SettingsModel.js" as Settings

FocusScope {
    id: dock
    required property var service
    required property var config
    property string edge: config.panels.hyprdock.position
    readonly property bool vertical: edge === 'left' || edge === 'right'
    readonly property var panel: config.panels.hyprdock
    readonly property var groups: service.groups('hyprdock')
    readonly property var entries: [{key:'launcher', name:'Applications', launcher:true, windows:[]}].concat(groups)
    readonly property real thickness: Model.thickness(panel)
    readonly property real cellSize: thickness - 8
    readonly property real iconSize: Math.min(panel.iconSize, cellSize - 8)
    readonly property real spacing: panel.spacing ?? 4
    property real maximumLength: 800
    readonly property real naturalLength: 12 + entries.length * cellSize + Math.max(0, entries.length - 1) * spacing
    readonly property real length: Math.min(maximumLength, naturalLength)
    readonly property bool overflowing: naturalLength > length
    readonly property real navigationSize: overflowing ? 24 : 0
    property string draggingId: ''
    property string focusedKey: 'launcher'
    onEntriesChanged: Qt.callLater(() => {
        if (dock.activeFocus) dock.focusIndex(Math.max(0,dock.entries.findIndex(entry => entry.key === dock.focusedKey)));
    })
    property point dragPoint: Qt.point(0, 0)
    signal launcherRequested(rect trigger)
    signal groupRequested(string key, rect trigger)
    signal previewsRequested(string key, rect trigger)
    signal interactionStarted()
    implicitWidth: vertical ? thickness : length
    implicitHeight: vertical ? length : thickness
    function itemRect(item) { let p = item.mapToItem(dock, 0, 0); return Qt.rect(p.x,p.y,item.width,item.height); }
    function showGroup(group, item) { interactionStarted(); groupRequested(group.key, itemRect(item)); }
    function activate(group, item) {
        interactionStarted();
        if (group.launcher) { interactionStarted(); launcherRequested(itemRect(item)); }
        else if (group.windows.length > 1) previewsRequested(group.key, itemRect(item));
        else service.activate(group);
    }
    function focusIndex(index) {
        list.currentIndex = Math.max(0, Math.min(entries.length - 1, index));
        list.positionViewAtIndex(list.currentIndex, ListView.Contain);
        let item = list.itemAtIndex(list.currentIndex);
        if (item) item.forceActiveFocus();
    }
    function scroll(step) {
        let max = Math.max(0, (vertical ? list.contentHeight - list.height : list.contentWidth - list.width));
        if (vertical) list.contentY = Math.max(0, Math.min(max, list.contentY + step));
        else list.contentX = Math.max(0, Math.min(max, list.contentX + step));
    }
    function reorder(id, targetId) {
        let index = Model.dropIndex(Settings.effectivePins(config, 'hyprdock'), id, targetId);
        if (index < 0 || service.busy) return false;
        return service.edit({action:'reorder', component:'hyprdock', id:id, index:index});
    }
    function finishDrag() {
        if (!draggingId) return;
        let point = list.mapFromItem(dock, dragPoint.x, dragPoint.y);
        let index = list.indexAt(point.x + list.contentX, point.y + list.contentY);
        if (index >= 0 && entries[index].pinned) reorder(draggingId, entries[index].id);
        draggingId = '';
    }
    Rectangle {
        anchors.fill: parent; radius: 16
        visible: dock.panel.background === 'on' || (dock.panel.background !== 'off' && dock.config.bar?.background !== 'off')
        color: '#e61e1e2e'; border.color: '#38cdd6f4'
    }
    ToolButton {
        objectName: 'dockScrollBack'
        visible: dock.overflowing
        x: dock.vertical ? (dock.width-width)/2 : 2
        y: dock.vertical ? 2 : (dock.height-height)/2
        width: dock.vertical ? dock.width-8 : 22; height: dock.vertical ? 22 : dock.height-8
        text: dock.vertical ? '↑' : '‹'; palette.buttonText: '#cdd6f4'
        Accessible.name: 'Scroll dock backward'
        onClicked: dock.scroll(-dock.cellSize * 2)
    }
    ListView {
        id: list
        objectName: 'dockApplications'
        x: dock.vertical ? 4 : 6 + dock.navigationSize
        y: dock.vertical ? 6 + dock.navigationSize : 4
        width: dock.vertical ? dock.width-8 : Math.max(0, dock.width - 12 - 2*dock.navigationSize)
        height: dock.vertical ? Math.max(0, dock.height - 12 - 2*dock.navigationSize) : dock.height-8
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
                radius: 12
                color: button.modelData.active ? '#48cba6f7' : pointer.containsMouse || button.activeFocus ? '#22cdd6f4' : 'transparent'
                border.color: button.activeFocus ? '#cba6f7' : button.modelData.urgent ? '#fab387' : 'transparent'
            }
            Image {
                id: icon
                anchors.centerIn: parent
                width: dock.iconSize; height: width
                source: button.modelData.launcher ? '' : dock.service.iconSource(button.modelData.icon)
                sourceSize.width: width; sourceSize.height: height
                fillMode: Image.PreserveAspectFit
                opacity: !button.modelData.launcher && !button.modelData.installed && !button.modelData.windows.length ? 0.45 : 1
            }
            Text {
                anchors.centerIn: parent
                visible: button.modelData.launcher || icon.status !== Image.Ready
                text: button.modelData.launcher ? '󰀻' : '󰘳'
                color: '#cdd6f4'; font.family: 'GoMono Nerd Font'; font.pixelSize: dock.iconSize
            }
            Rectangle {
                objectName: 'dockRunningIndicator'
                visible: button.modelData.windows.length > 0
                color: button.modelData.active ? '#cba6f7' : '#a6adc8'; radius: 2
                width: dock.vertical ? 3 : Math.min(18, 4 + button.modelData.windows.length*4)
                height: dock.vertical ? Math.min(18, 4 + button.modelData.windows.length*4) : 3
                x: dock.edge === 'right' ? parent.width-width-1 : dock.vertical ? 1 : (parent.width-width)/2
                y: dock.edge === 'bottom' ? parent.height-height-1 : dock.vertical ? (parent.height-height)/2 : 1
            }
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) { dock.draggingId = ''; event.accepted = true; }
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
                            let pins = Settings.effectivePins(dock.config, 'hyprdock'), target = pins.indexOf(modelData.id) + step;
                            if (target >= 0 && target < pins.length) dock.reorder(modelData.id, pins[target]);
                        } else dock.focusIndex(index + step);
                        event.accepted = true;
                    }
                }
            }
            MouseArea {
                id: pointer
                anchors.fill: parent; hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                property point pressPoint
                property bool moved: false
                preventStealing: !!button.modelData.pinned
                onPressed: mouse => {
                    button.forceActiveFocus(); pressPoint = Qt.point(mouse.x, mouse.y); moved = false;
                }
                onPositionChanged: mouse => {
                    if (!(pressedButtons & Qt.LeftButton) || !button.modelData.pinned || dock.service.busy) return;
                    if (Math.abs(mouse.x-pressPoint.x) + Math.abs(mouse.y-pressPoint.y) > 10) {
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
        x: dock.vertical ? (dock.width-width)/2 : dock.width-width-2
        y: dock.vertical ? dock.height-height-2 : (dock.height-height)/2
        width: dock.vertical ? dock.width-8 : 22; height: dock.vertical ? 22 : dock.height-8
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
