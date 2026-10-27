pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import "style" as Style
import "AdaptiveColors.js" as Colors
import "SettingsModel.js" as Settings

ListView {
    id: page
    objectName: "activityContent"
    required property var inbox
    required property var store
    property bool active: false
    readonly property bool busy: writer.running
    property url wallpaperSource: ""
    property real screenWidth: 1366
    property real screenHeight: 768
    property rect wallpaperRegion: Qt.rect(0, 0, screenWidth, screenHeight)
    readonly property color wallpaperSample: wallpaperSampler.sampleRect(wallpaperRegion)
    readonly property color cardColor: Style.Theme.highContrast ? "#000000"
        : Qt.hsva(wallpaperSample.hsvHue, wallpaperSample.hsvSaturation * 0.72, 0.12 + wallpaperSample.hsvValue * 0.10, 1)
    readonly property color textColor: Style.Theme.highContrast ? "#ffffff" : Colors.mix(wallpaperSample, Qt.color("#ffffff"), 0.94)
    readonly property color secondaryColor: Colors.mix(cardColor, textColor, 0.82)
    readonly property color accentColor: Style.Theme.highContrast ? "#ffffff"
        : Colors.mix(Colors.vibrantForeground(wallpaperSample, wallpaperSample), textColor, 0.58)
    readonly property var groups: {
        let grouped = new Map();
        for (let row of inbox.rows) {
            let key = row.appKey || row.app || "Notifications";
            if (!grouped.has(key)) grouped.set(key, {key: key, name: row.app || key, rows: []});
            grouped.get(key).rows.push(row);
        }
        return Array.from(grouped.values());
    }
    property string expanded: ""
    property var expandedGroups: []
    property string error: ""
    signal dismissRequested()
    function focusFirst() { headerItem.quietControl.forceActiveFocus(); }
    function markRead() { if (active && inbox.unread > 0) inbox.markRead(); }
    onActiveChanged: {
        if (active) {
            expandedGroups = [];
            expanded = "";
        }
        Qt.callLater(markRead);
    }
    Connections { target: page.inbox; function onUnreadChanged() { Qt.callLater(page.markRead); } }
    Keys.onEscapePressed: dismissRequested()
    property real maximumViewportHeight: Math.max(1, Math.min(700, screenHeight - 32) - 36)
    implicitHeight: Math.min(maximumViewportHeight, contentHeight)
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    cacheBuffer: 160
    spacing: 6
    model: {
        let items = [];
        for (let group of groups) {
            items.push({group: group, row: null});
            if (expandedGroups.includes(group.key))
                for (let row of group.rows) items.push({group: null, row: row});
        }
        return items;
    }
    ScrollBar.vertical: ScrollBar {}
    function focusRow(index) {
        if (!count) return;
        currentIndex = Math.max(0, Math.min(count - 1, index));
        positionViewAtIndex(currentIndex, ListView.Contain);
        Qt.callLater(() => {
            let control = currentItem?.item;
            if (control?.focusFirst) control.focusFirst();
            else control?.forceActiveFocus();
        });
    }
    Keys.onDownPressed: focusRow(currentIndex + 1)
    Keys.onUpPressed: focusRow(currentIndex - 1)
    Connections {
        target: page.Window.window
        function onActiveFocusItemChanged() {
            let focused = page.Window.window.activeFocusItem;
            let ancestor = focused;
            while (ancestor && ancestor !== page.contentItem) ancestor = ancestor.parent;
            if (!ancestor) return;
            let point = focused.mapToItem(page.contentItem, 0, 0);
            if (point.y < page.contentY) page.contentY = point.y;
            else if (point.y + focused.height > page.contentY + page.height)
                page.contentY = point.y + focused.height - page.height;
        }
    }
    WallpaperColors {
        id: wallpaperSampler
        objectName: "activityWallpaperSampler"
        source: page.wallpaperSource
        screenWidth: page.screenWidth; screenHeight: page.screenHeight
        // Reuse a small full-wallpaper cache as the drawer animates/resizes.
        // Regional colors still follow wallpaperRegion without Canvas readbacks.
        offsetY: 0
        bandHeight: Math.max(1, page.screenHeight)
        sampleWidth: 96; sampleHeight: 64
    }
    Process {
        id: writer
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let result = JSON.parse(text);
                    if (!result.ok) page.error = result.message || "Could not save Do Not Disturb.";
                } catch (e) { page.error = "Could not save Do Not Disturb."; }
            }
        }
        stderr: StdioCollector {}
        onExited: (code, status) => {
            if (code !== 0 && !page.error) page.error = "Could not save Do Not Disturb.";
            page.store.reload();
            page.headerItem.quietControl.checked = Qt.binding(() => page.store.config.notifications.doNotDisturb);
        }
    }
    header: ColumnLayout {
        width: page.width
        spacing: 12
        property alias quietControl: quiet
        RowLayout {
            Layout.fillWidth: true
            MenuLabel { text: "Notifications"; color: page.textColor; font.pixelSize: 18; font.bold: true; Layout.fillWidth: true }
            MenuButton {
                objectName: "activityClear"
                text: "Clear all"; accent: page.accentColor
                enabled: page.inbox.rows.length > 0
                onClicked: page.inbox.clear()
            }
        }
        Switch {
            id: quiet
            objectName: "activityDnd"
            text: "Do Not Disturb"
            indicator: Rectangle {
                implicitWidth: 36; implicitHeight: 20
                x: quiet.leftPadding; y: (quiet.height - height) / 2
                radius: 10
                color: quiet.checked ? page.accentColor : page.cardColor
                border.color: quiet.activeFocus ? page.textColor : page.secondaryColor
                Rectangle {
                    x: quiet.checked ? parent.width - width - 3 : 3
                    y: 3; width: 14; height: 14; radius: 7
                    color: quiet.checked ? page.cardColor : page.secondaryColor
                }
            }
            contentItem: MenuLabel {
                text: quiet.text; color: page.textColor
                leftPadding: 46
                verticalAlignment: Text.AlignVCenter
            }
            Layout.fillWidth: true
            checked: page.store.config.notifications.doNotDisturb
            enabled: page.store.loaded && !writer.running
            onToggled: {
                let before = Settings.copy(page.store.config);
                let after = Settings.copy(before);
                after.notifications.doNotDisturb = checked;
                page.error = "";
                writer.command = ["python3", decodeURIComponent(Qt.resolvedUrl("settings/backend.py").toString().replace(/^file:\/\//, "")), "--save-json", JSON.stringify(after), "--expected-json", JSON.stringify(before)];
                writer.running = true;
            }
        }
        MenuLabel { text: page.error; visible: text.length > 0; color: "#f38ba8"; Layout.fillWidth: true; wrapMode: Text.Wrap }
        Rectangle {
            Layout.fillWidth: true
            visible: !!media.player
            implicitHeight: media.implicitHeight + 28
            radius: 16; color: page.cardColor
            border.color: Colors.mix(page.cardColor, page.accentColor, 0.38)
            MediaControls {
                id: media
                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 14 }
                textColor: page.textColor; secondaryColor: page.secondaryColor; accentColor: page.accentColor
            }
        }
        MenuLabel {
            objectName: "activityEmpty"
            text: "You’re all caught up"
            visible: page.inbox.rows.length === 0
            color: page.secondaryColor; Layout.fillWidth: true
            topPadding: 20; bottomPadding: 20
            horizontalAlignment: Text.AlignHCenter
        }
    }
    delegate: Loader {
        id: entry
        required property var modelData
        width: page.width
        sourceComponent: modelData.group ? groupHeader : notificationCard
        Component {
            id: groupHeader
            MenuButton {
                readonly property var group: entry.modelData.group
                readonly property bool expanded: page.expandedGroups.includes(group.key)
                objectName: "activityGroup-" + group.key
                text: (expanded ? "▾ " : "▸ ") + group.name + " · " + group.rows.length
                accent: page.secondaryColor; font.pixelSize: 12
                Accessible.name: (expanded ? "Collapse " : "Expand ") + group.name + " notifications"
                onClicked: {
                    let key = group.key;
                    let closing = expanded;
                    if (closing && group.rows.some(row => String(row.id) === page.expanded)) page.expanded = "";
                    page.expandedGroups = closing
                        ? page.expandedGroups.filter(value => value !== key)
                        : page.expandedGroups.concat([key]);
                }
            }
        }
        Component {
            id: notificationCard
            NotificationCard {
                notification: entry.modelData.row
                objectName: "activityNotification-" + String(notification.id)
                expanded: page.expanded === String(notification.id)
                onToggleRequested: page.expanded = expanded ? "" : String(notification.id)
                onDismissRequested: page.inbox.dismiss(notification.id)
                onActionRequested: actionId => page.inbox.invoke(notification.id, actionId)
            }
        }
    }
}
