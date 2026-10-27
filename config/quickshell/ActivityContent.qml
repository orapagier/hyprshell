pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Io
import "style" as Style
import "AdaptiveColors.js" as Colors
import "SettingsModel.js" as Settings

ColumnLayout {
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
    function focusFirst() { quiet.forceActiveFocus(); }
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
    spacing: 12
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
            quiet.checked = Qt.binding(() => page.store.config.notifications.doNotDisturb);
        }
    }
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
    Repeater {
        model: page.groups
        delegate: ColumnLayout {
            id: group
            required property var modelData
            readonly property bool expanded: page.expandedGroups.includes(modelData.key)
            Layout.fillWidth: true
            spacing: 6
            MenuButton {
                objectName: "activityGroup-" + group.modelData.key
                text: (group.expanded ? "▾ " : "▸ ") + group.modelData.name + " · " + group.modelData.rows.length
                accent: page.secondaryColor; font.pixelSize: 12
                Layout.fillWidth: true
                Accessible.name: (group.expanded ? "Collapse " : "Expand ") + group.modelData.name + " notifications"
                onClicked: {
                    page.expandedGroups = group.expanded
                        ? page.expandedGroups.filter(key => key !== group.modelData.key)
                        : page.expandedGroups.concat([group.modelData.key]);
                    if (!group.expanded && group.modelData.rows.some(row => String(row.id) === page.expanded)) page.expanded = "";
                }
            }
            Repeater {
                model: group.expanded ? group.modelData.rows : []
                delegate: NotificationCard {
                    required property var modelData
                    objectName: "activityNotification-" + String(modelData.id)
                    Layout.fillWidth: true; Layout.minimumWidth: 0
                    notification: modelData
                    expanded: page.expanded === String(modelData.id)
                    onToggleRequested: page.expanded = expanded ? "" : String(modelData.id)
                    onDismissRequested: page.inbox.dismiss(modelData.id)
                    onActionRequested: actionId => page.inbox.invoke(modelData.id, actionId)
                }
            }
        }
    }
}
