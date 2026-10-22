pragma ComponentBehavior: Bound
import QtQuick
import "AdaptiveColors.js" as Colors
import QtQuick.Layouts

ColumnLayout {
    id: card
    readonly property var menuColors: Colors.menuColorsFor(card)
    required property var notification
    property bool expanded: false
    signal toggleRequested()
    signal dismissRequested()
    signal actionRequested(string actionId)
    spacing: 6

    Item {
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        implicitHeight: header.implicitHeight
        Layout.minimumHeight: implicitHeight
        MenuButton {
            id: header
            objectName: "notificationHeader"
            anchors.fill: parent
            rightPadding: card.expanded ? 44 : 10
            implicitHeight: Math.max(54, contentItem.implicitHeight + topPadding + bottomPadding)
            onClicked: card.toggleRequested()
            contentItem: ColumnLayout {
                spacing: 4
                MenuLabel {
                    objectName: "notificationApp"
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: (card.notification.critical ? "Critical · " : "") + card.notification.app
                    font.pixelSize: 11
                    color: card.menuColors.secondary
                    wrapMode: Text.Wrap
                    // Only the collapsed preview has a line limit.
                    maximumLineCount: card.expanded ? 2147483647 : 1
                    elide: card.expanded ? Text.ElideNone : Text.ElideRight
                }
                MenuLabel {
                    objectName: "notificationSummary"
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: card.notification.summary
                    font.bold: true
                    wrapMode: Text.Wrap
                    maximumLineCount: card.expanded ? 2147483647 : 1
                    elide: card.expanded ? Text.ElideNone : Text.ElideRight
                }
            }
        }
        MenuButton {
            id: dismissButton
            objectName: "notificationDismiss"
            visible: card.expanded
            anchors { top: parent.top; right: parent.right; margins: 6 }
            width: 28; height: 28
            leftPadding: 0; rightPadding: 0; topPadding: 0; bottomPadding: 0
            text: "×"
            font.pixelSize: 20
            accent: "#f38ba8"
            Accessible.name: "Dismiss notification"
            contentItem: Text {
                text: dismissButton.text
                font: dismissButton.font
                color: dismissButton.accent
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            onClicked: card.dismissRequested()
        }
    }

    ColumnLayout {
        objectName: "notificationDetails"
        visible: card.expanded
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        Layout.leftMargin: 10
        Layout.rightMargin: 10
        spacing: 6
        MenuLabel {
            objectName: "notificationBody"
            text: card.notification.body
            visible: text.length > 0
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            Layout.minimumHeight: implicitHeight
            font.pixelSize: 12
            wrapMode: Text.Wrap
            elide: Text.ElideNone
            TapHandler { onTapped: card.toggleRequested() }
        }
        MenuLabel {
            text: Qt.formatDateTime(new Date(card.notification.received), "MMM d, h:mm AP")
            color: card.menuColors.secondary
            font.pixelSize: 10
            Layout.fillWidth: true
            TapHandler { onTapped: card.toggleRequested() }
        }
        Repeater {
            model: card.notification.active ? card.notification.actions : []
            delegate: MenuButton {
                required property var modelData
                Layout.fillWidth: true
                text: modelData.text
                onClicked: card.actionRequested(modelData.id)
            }
        }
    }
}
