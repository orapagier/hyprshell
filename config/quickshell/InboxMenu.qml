pragma ComponentBehavior: Bound
import QtQuick
import "AdaptiveColors.js" as Colors
import QtQuick.Controls
import QtQuick.Layouts

ColumnLayout {
    id: page
    readonly property var menuColors: Colors.menuColorsFor(page)
    required property var inbox
    property string expanded: ""
    readonly property var rows: inbox.rows.filter(r => (r.app + " " + r.summary + " " + r.body).toLowerCase().includes(search.text.toLowerCase()))
    spacing: 8
    Component.onCompleted: inbox.markRead()
    Connections {
        target: page.inbox
        function onUnreadChanged() { if (page.inbox.unread > 0) page.inbox.markRead(); }
    }
    TextField {
        id: search
        Layout.fillWidth: true
        Layout.leftMargin: notificationScroll.leftPadding
        Layout.rightMargin: notificationScroll.rightPadding
        placeholderText: "Search notifications"; color: page.menuColors.text; placeholderTextColor: page.menuColors.secondary
        font.family: "DejaVu Sans"; font.pixelSize: 13
        background: Rectangle { radius: 8; color: "#0bffffff"; border.color: "#1fffffff" }
    }
    MenuLabel { text: "No notifications"; visible: page.rows.length === 0; color: page.menuColors.secondary }
    ScrollView {
        id: notificationScroll
        objectName: "notificationScroll"
        Layout.fillWidth: true; Layout.preferredHeight: Math.min(360, items.implicitHeight)
        clip: true; visible: page.rows.length > 0
        // The popover already supplies the shared 18px side margins.
        leftPadding: 0
        rightPadding: 0
        contentWidth: availableWidth
        contentHeight: items.implicitHeight
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        ScrollBar.vertical.policy: ScrollBar.AsNeeded
        ScrollBar.vertical.interactive: true
        ColumnLayout {
            id: items
            width: notificationScroll.availableWidth; spacing: 6
            height: implicitHeight
            Repeater {
                model: page.rows
                delegate: NotificationCard {
                    id: card
                    required property var modelData
                    objectName: "notification-" + String(modelData.id)
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.minimumHeight: implicitHeight
                    notification: modelData
                    expanded: page.expanded === String(modelData.id)
                    onToggleRequested: {
                        let id = String(modelData.id);
                        page.expanded = page.expanded === id ? "" : id;
                    }
                    onDismissRequested: page.inbox.dismiss(modelData.id)
                    onActionRequested: actionId => page.inbox.invoke(modelData.id, actionId)
                }
            }
        }
    }
    MenuButton {
        text: "Clear all"
        Layout.fillWidth: true
        Layout.leftMargin: notificationScroll.leftPadding
        Layout.rightMargin: notificationScroll.rightPadding
        enabled: page.inbox.rows.length > 0
        accent: "#f38ba8"
        onClicked: page.inbox.clear()
    }
}
