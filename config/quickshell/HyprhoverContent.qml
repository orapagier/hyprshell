pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "AdaptiveColors.js" as Colors

Column {
    id: content
    readonly property bool roundedMenuButtons: true
    required property var owner
    property string group: "left"
    readonly property var menuColors: Colors.menuColorsFor(content)
    property alias controls: modelBar
    readonly property var tabs: modelBar.orderedItems(group)
    property string selected: ""
    readonly property var labels: ({launcher:"Apps", settings:"Settings", workspaces:"Workspaces", media:"Media", calendar:"Calendar", tray:"Tray", notifications:"Notifications", audio:"Audio", wifi:"Wi-Fi", bluetooth:"Bluetooth", battery:"Battery", power:"Power"})
    readonly property var symbols: ({launcher:"󰀻", settings:"󰒓", workspaces:"󰍹", media:"󰎆", calendar:"󰃭", tray:"󰀻", notifications:"󰂚", audio:"󰕾", wifi:"󰤨", bluetooth:"󰂯", battery:"󰁹", power:"󰐥"})
    signal dismissRequested()
    signal settingsRequested()
    spacing: 12
    function select(id) { if (tabs.includes(id)) selected = id; }
    function reconcile() { if (!tabs.includes(selected)) selected = tabs[0] || ""; }
    onTabsChanged: reconcile()
    Component.onCompleted: reconcile()
    // Reuse the panel's saved ordering, group membership and dynamic availability.
    Bar {
        id: modelBar
        visible: false
        width: content.width
        onlySide: content.group
        settings: content.owner.settings
        statusData: content.owner.statusData
        mediaData: content.owner.mediaData
        notificationData: content.owner.notificationData
        trayModel: content.owner.trayModel
        outputName: content.owner.screen.name
    }
    Row {
        width: parent.width
        Text { text: "HYPRHOVER"; color: content.menuColors.secondary; font.pixelSize: 10; font.letterSpacing: 2; width: parent.width - 40 }
        Text { text: "esc"; color: content.menuColors.secondary; font.pixelSize: 11 }
    }
    Row {
        id: tabStrip
        objectName: "hyprhoverTabs"
        width: parent.width
        spacing: Math.min(6, width / Math.max(1, content.tabs.length * 6))
        readonly property real diameter: Math.max(0, Math.min(32,
            (width - spacing * Math.max(0, content.tabs.length - 1)) / Math.max(1, content.tabs.length)))
        Repeater {
            model: content.tabs
            delegate: Button {
                id: tab
                required property string modelData
                objectName: "hyprhoverTab-" + modelData
                readonly property bool selected: content.selected === modelData
                hoverEnabled: true
                width: tabStrip.diameter
                height: width
                padding: 0
                Accessible.name: content.labels[modelData] || modelData
                onHoveredChanged: if (hovered) content.select(modelData)
                onClicked: content.select(modelData)
                onActiveFocusChanged: if (activeFocus) content.select(modelData)
                background: Rectangle {
                    radius: width / 2
                    color: Qt.rgba(content.menuColors.accent.r, content.menuColors.accent.g, content.menuColors.accent.b, tab.selected ? 0.24 : tab.hovered ? 0.12 : 0.045)
                    border.width: 1
                    border.color: Qt.rgba(content.menuColors.accent.r, content.menuColors.accent.g, content.menuColors.accent.b, tab.selected ? 0.4 : 0.10)
                    Behavior on color { ColorAnimation { duration: 120 } }
                }
                contentItem: Text {
                    text: content.symbols[tab.modelData] || ""
                    color: tab.selected ? content.menuColors.accent : content.menuColors.text
                    font.family: "GoMono Nerd Font"
                    font.pixelSize: Math.max(1, tab.width * 0.46)
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }
    }
    Rectangle { width: parent.width; height: 1; color: content.menuColors.accent; opacity: 0.15 }
    Text {
        text: content.labels[content.selected] || "No visible items"
        color: content.menuColors.text
        font.pixelSize: 17
        font.weight: Font.DemiBold
    }
    Loader {
        id: page
        objectName: "hyprhoverTabPage"
        width: parent.width
        sourceComponent: ({launcher: appsPage, settings: settingsPage, workspaces: workspacesPage, media: mediaPage,
            calendar: calendarPage, tray: trayPage, notifications: notificationsPage, audio: audioPage,
            wifi: wifiPage, bluetooth: bluetoothPage, battery: batteryPage, power: powerPage})[content.selected] || null
    }
    Component { id: calendarPage; CalendarMenu {} }
    Component { id: audioPage; AudioMenu { services: content.owner.services } }
    Component { id: wifiPage; WifiMenu { services: content.owner.services } }
    Component { id: bluetoothPage; BluetoothMenu { services: content.owner.services } }
    Component { id: batteryPage; BatteryMenu { services: content.owner.services } }
    Component { id: notificationsPage; InboxMenu { inbox: content.owner.inbox } }
    Component { id: powerPage; PowerMenu {} }
    Component { id: settingsPage; SettingsMenu { onOpenRequested: content.settingsRequested() } }
    Component {
        id: appsPage
        LauncherMenu {
            implicitHeight: 300
            height: implicitHeight
            applicationService: content.owner.applicationService
            wallpaperSource: content.owner.wallpaperSource
            active: content.owner.opened
            onLaunched: content.dismissRequested()
        }
    }
    Component {
        id: mediaPage
        ColumnLayout {
            MediaPreview { Layout.fillWidth: true; mediaData: content.owner.mediaData; active: content.owner.opened }
            RowLayout {
                Layout.fillWidth: true
                MenuButton { Layout.fillWidth: true; text: "Previous"; enabled: !!content.owner.services.player?.canGoPrevious; onClicked: content.owner.services.player.previous() }
                MenuButton { Layout.fillWidth: true; text: content.owner.services.player?.isPlaying ? "Pause" : "Play"; enabled: !!content.owner.services.player?.canTogglePlaying; onClicked: content.owner.services.player.togglePlaying() }
                MenuButton { Layout.fillWidth: true; text: "Next"; enabled: !!content.owner.services.player?.canGoNext; onClicked: content.owner.services.player.next() }
            }
        }
    }
    Component {
        id: workspacesPage
        ColumnLayout {
            id: workspaces
            property var preview: (content.owner.statusData.workspaces || []).find(w => w.active) || (content.owner.statusData.workspaces || [])[0] || null
            Row {
                id: workspaceTabs
                objectName: "hyprhoverWorkspaceTabs"
                Layout.fillWidth: true
                readonly property int count: (content.owner.statusData.workspaces || []).length
                spacing: Math.min(6, width / Math.max(1, count * 6))
                readonly property real diameter: Math.max(0, Math.min(32,
                    (width - spacing * Math.max(0, count - 1)) / Math.max(1, count)))
                Repeater {
                    model: content.owner.statusData.workspaces || []
                    Button {
                        id: workspaceTab
                        required property var modelData
                        objectName: "hyprhoverWorkspace-" + modelData.id
                        readonly property bool previewed: workspaces.preview?.id === modelData.id
                        width: workspaceTabs.diameter
                        height: width
                        padding: 0
                        Accessible.name: "Workspace " + (modelData.name || modelData.id)
                        hoverEnabled: true
                        onHoveredChanged: if (hovered) workspaces.preview = modelData
                        onActiveFocusChanged: if (activeFocus) workspaces.preview = modelData
                        onClicked: { content.owner.services.workspace(modelData.id); content.dismissRequested(); }
                        background: Rectangle {
                            radius: width / 2
                            color: Qt.rgba(content.menuColors.accent.r, content.menuColors.accent.g, content.menuColors.accent.b,
                                workspaceTab.previewed ? 0.24 : workspaceTab.modelData.active ? 0.14 : 0.045)
                            border.width: 1
                            border.color: Qt.rgba(content.menuColors.accent.r, content.menuColors.accent.g, content.menuColors.accent.b,
                                workspaceTab.previewed || workspaceTab.modelData.active ? 0.4 : 0.10)
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }
                        contentItem: Text {
                            text: String(workspaceTab.modelData.id)
                            color: workspaceTab.previewed || workspaceTab.modelData.active ? content.menuColors.accent : content.menuColors.text
                            font.family: "Noto Sans"
                            font.pixelSize: Math.max(1, Math.min(12, workspaceTab.width * 0.4))
                            font.weight: workspaceTab.modelData.active ? Font.DemiBold : Font.Normal
                            verticalAlignment: Text.AlignVCenter
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }
                }
            }
            WorkspacePreview {
                Layout.fillWidth: true
                workspaceId: workspaces.preview?.id || 0
                output: content.owner.screen
                wallpaperSource: content.owner.wallpaperSource
                active: content.owner.opened
            }
        }
    }
    Component {
        id: trayPage
        ColumnLayout {
            spacing: 8
            Repeater {
                model: content.owner.trayModel
                MenuButton {
                    id: trayButton
                    required property var modelData
                    Layout.fillWidth: true
                    text: modelData.title || modelData.id || "Application"
                    onClicked: {
                        if (modelData.onlyMenu && modelData.hasMenu) showMenu();
                        else modelData.activate();
                    }
                    function showMenu() {
                        let point = mapToItem(content.owner.contentItem, 0, height);
                        modelData.display(content.owner, point.x, point.y);
                    }
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.RightButton | Qt.MiddleButton
                        onClicked: mouse => {
                            if (mouse.button === Qt.MiddleButton) trayButton.modelData.secondaryActivate();
                            else if (trayButton.modelData.hasMenu) trayButton.showMenu();
                        }
                        onWheel: wheel => trayButton.modelData.scroll(wheel.angleDelta.y || wheel.angleDelta.x, !wheel.angleDelta.y)
                    }
                }
            }
        }
    }
}
