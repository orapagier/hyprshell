pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris
import "style" as Style

ColumnLayout {
    id: page
    objectName: "dashboardContent"
    required property var services
    property var resourceData: ({})
    property bool active: false
    property date now: new Date()
    readonly property var player: Mpris.players.values.find(p => p.isPlaying) || Mpris.players.values[0] || null
    readonly property real memoryPercent: resourceData.memoryTotal ? resourceData.memoryUsed / resourceData.memoryTotal * 100 : 0
    signal dismissRequested()
    signal settingsRequested()
    signal lockRequested()
    signal menuRequested(string name)
    function focusFirst() { page.forceActiveFocus(); }
    spacing: 18
    Keys.onEscapePressed: dismissRequested()
    Timer { interval: 1000; repeat: true; running: page.active; onTriggered: page.now = new Date() }
    GridLayout {
        Layout.fillWidth: true
        columns: page.width >= 800 ? 3 : page.width >= 560 ? 2 : 1
        columnSpacing: 14; rowSpacing: 14
        Card {
            Layout.fillWidth: true; Layout.fillHeight: true
            implicitHeight: 240
            ColumnLayout {
                anchors.fill: parent; anchors.margins: 22
                MenuLabel { text: "GOOD " + (page.now.getHours() < 12 ? "MORNING" : page.now.getHours() < 18 ? "AFTERNOON" : "EVENING"); color: "#a6adc8"; font.pixelSize: 11; font.letterSpacing: 2 }
                Item { Layout.fillHeight: true }
                MenuLabel { text: Qt.formatTime(page.now, "hh:mm"); font.pixelSize: 58; font.weight: Font.Light; color: "#b4befe" }
                MenuLabel { text: Qt.formatDate(page.now, "dddd, d MMMM"); font.pixelSize: 15; Layout.fillWidth: true }
                Item { Layout.fillHeight: true }
                MenuLabel { text: Quickshell.env("USER") || "Welcome home"; font.pixelSize: 20; font.weight: Font.DemiBold }
                RowLayout {
                    Layout.fillWidth: true
                    MenuButton { text: "Settings"; Layout.fillWidth: true; onClicked: page.settingsRequested() }
                    MenuButton { text: "Lock"; Layout.fillWidth: true; onClicked: page.lockRequested() }
                }
            }
        }
        Card {
            Layout.fillWidth: true; Layout.fillHeight: true
            implicitHeight: calendar.implicitHeight + 36
            CalendarMenu { id: calendar; anchors.fill: parent; anchors.margins: 18 }
        }
        Card {
            Layout.fillWidth: true; Layout.fillHeight: true
            implicitHeight: desktopDetails.implicitHeight + 44
            ColumnLayout {
                id: desktopDetails
                anchors.fill: parent; anchors.margins: 22; spacing: 14
                MenuLabel { text: "YOUR DESKTOP"; color: "#a6adc8"; font.pixelSize: 11; font.letterSpacing: 2 }
                MenuLabel { text: page.services.statusData.network.tooltip; Layout.fillWidth: true; font.pixelSize: 15 }
                MenuLabel { text: page.services.batteryInfo.present ? page.services.batteryInfo.percentage + "% · " + (page.services.batteryInfo.pluggedIn ? "Plugged in" : "On battery") : "Desktop power"; color: "#a6e3a1" }
                Meter { Layout.fillWidth: true; title: "CPU"; value: page.resourceData.cpuPercent ?? 0; available: page.resourceData.cpuPercent !== null && page.resourceData.cpuPercent !== undefined }
                Meter { Layout.fillWidth: true; title: "Memory"; value: page.memoryPercent; available: !!page.resourceData.memoryTotal }
                MenuLabel { objectName: "dashboardMemoryDetails"; text: page.resourceData.memoryTotal ? (page.resourceData.memoryUsed / 1048576).toFixed(1) + " / " + (page.resourceData.memoryTotal / 1048576).toFixed(1) + " GiB RAM" : page.resourceData.error || "Reading resource counters…"; color: "#a6adc8"; Layout.fillWidth: true }
                MenuLabel { objectName: "dashboardUptime"; text: page.resourceData.uptime !== undefined ? "Uptime · " + Math.floor(page.resourceData.uptime / 3600) + "h " + Math.floor(page.resourceData.uptime / 60 % 60) + "m" : ""; color: "#a6adc8" }
                Item { Layout.fillHeight: true }
                RowLayout {
                    Layout.fillWidth: true
                    MenuButton { text: "Wi-Fi"; Layout.fillWidth: true; onClicked: page.menuRequested("wifi") }
                    MenuButton { text: "Audio"; Layout.fillWidth: true; onClicked: page.menuRequested("audio") }
                }
                RowLayout {
                    Layout.fillWidth: true
                    MenuButton { text: "Notifications"; Layout.fillWidth: true; onClicked: page.menuRequested("notifications") }
                    MenuButton { text: "Power"; Layout.fillWidth: true; onClicked: page.menuRequested("power") }
                }
            }
        }
    }
    Card {
        Layout.fillWidth: true
        implicitHeight: 156
        RowLayout {
            anchors.fill: parent; anchors.margins: 22; spacing: 22
            Rectangle {
                Layout.preferredWidth: Math.min(108, page.width * 0.2)
                Layout.fillHeight: true
                radius: 14; color: "#1fffffff"
                Image {
                    id: art
                    anchors.fill: parent; anchors.margins: 8
                    source: page.player ? page.player.trackArtUrl : ""
                    fillMode: Image.PreserveAspectFit; asynchronous: true
                }
                MenuLabel { anchors.centerIn: parent; text: "♫"; font.pixelSize: 42; color: "#b4befe"; visible: art.status !== Image.Ready }
            }
            ColumnLayout {
                Layout.fillWidth: true; spacing: 10
                MenuLabel { text: page.player ? page.player.identity.toUpperCase() : "NOW PLAYING"; font.pixelSize: 11; color: "#a6adc8"; font.letterSpacing: 2 }
                MenuLabel { text: page.player ? page.player.trackTitle || "Unknown track" : "Nothing playing"; font.pixelSize: 22; font.weight: Font.DemiBold; Layout.fillWidth: true; maximumLineCount: 2; elide: Text.ElideRight }
                MenuLabel { text: page.player ? page.player.trackArtist : "Play something in your favorite app"; color: "#a6adc8"; Layout.fillWidth: true }
                RowLayout {
                    MenuButton { text: "Previous"; enabled: !!page.player && page.player.canGoPrevious; onClicked: page.player.previous() }
                    MenuButton { text: page.player && page.player.isPlaying ? "Pause" : "Play"; enabled: !!page.player && page.player.canTogglePlaying; accent: "#b4befe"; onClicked: page.player.togglePlaying() }
                    MenuButton { text: "Next"; enabled: !!page.player && page.player.canGoNext; onClicked: page.player.next() }
                }
            }
        }
    }
    component Card: Rectangle {
        radius: 16
        color: "#0bffffff"
        border.width: 1
        border.color: "#1fffffff"
        implicitWidth: 250
    }
    component Meter: ColumnLayout {
        id: meter
        required property string title
        property real value: 0
        property bool available: true
        spacing: 8
        RowLayout {
            Layout.fillWidth: true
            MenuLabel { text: meter.title; Layout.fillWidth: true }
            MenuLabel { text: meter.available ? Math.round(meter.value) + "%" : "—"; color: "#b4befe" }
        }
        Rectangle {
            Layout.fillWidth: true; implicitHeight: 8
            radius: 4; color: "#1fffffff"
            Rectangle {
                height: parent.height; radius: 4; color: "#b4befe"
                width: parent.width * Math.max(0, Math.min(100, meter.value || 0)) / 100
                Behavior on width { NumberAnimation { duration: Style.Theme.duration(meter, 350); easing.type: Easing.BezierSpline; easing.bezierCurve: Style.Theme.spatialCurve } }
            }
        }
    }
}
