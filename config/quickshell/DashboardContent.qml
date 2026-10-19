pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris
import "style" as Style
import "AdaptiveColors.js" as Colors

ColumnLayout {
    id: page
    objectName: "dashboardContent"
    required property var services
    property var resourceData: ({})
    property bool active: false
    property url wallpaperSource: ""
    property real screenWidth: 1366
    property real screenHeight: 768
    property rect wallpaperRegion: Qt.rect(0, 0, screenWidth, screenHeight)
    readonly property color wallpaperSample: wallpaperSampler.sampleRect(wallpaperRegion)
    // Keep the wallpaper's hue, with an opaque dark backing under every label.
    // Even a pure-white sample stays dark enough for the calendar's fixed text.
    readonly property color cardColor: Style.Theme.highContrast ? "#000000" : Colors.mix(wallpaperSample, Qt.color("#11151f"), 0.88)
    readonly property color textColor: "#f5f7ff"
    readonly property color secondaryColor: "#d4d9e8"
    readonly property color accentColor: Colors.mix(wallpaperSample, Qt.color("#e4e9ff"), 0.88)
    readonly property color outlineColor: Colors.mix(cardColor, textColor, Style.Theme.highContrast ? 1 : 0.22)
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
            WallpaperColors {
                id: wallpaperSampler
                objectName: "dashboardWallpaperSampler"
                source: page.wallpaperSource
                screenWidth: page.screenWidth; screenHeight: page.screenHeight
                offsetY: page.wallpaperRegion.y
                bandHeight: Math.max(1, page.wallpaperRegion.height)
            }
            ColumnLayout {
                anchors.fill: parent; anchors.margins: 22
                Label { text: "GOOD " + (page.now.getHours() < 12 ? "MORNING" : page.now.getHours() < 18 ? "AFTERNOON" : "EVENING"); color: page.secondaryColor; font.pixelSize: 12; font.letterSpacing: 2 }
                Item { Layout.fillHeight: true }
                Label { text: Qt.formatTime(page.now, "hh:mm"); font.pixelSize: 58; font.weight: Font.Light; color: page.accentColor }
                Label { text: Qt.formatDate(page.now, "dddd, d MMMM"); font.pixelSize: 15; Layout.fillWidth: true }
                Item { Layout.fillHeight: true }
                Label { text: Quickshell.env("USER") || "Welcome home"; font.pixelSize: 20; font.weight: Font.DemiBold }
                RowLayout {
                    Layout.fillWidth: true
                    Action { text: "Settings"; Layout.fillWidth: true; onClicked: page.settingsRequested() }
                    Action { text: "Lock"; Layout.fillWidth: true; onClicked: page.lockRequested() }
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
                Label { text: "YOUR DESKTOP"; color: page.secondaryColor; font.pixelSize: 12; font.letterSpacing: 2 }
                Label { text: page.services.statusData.network.tooltip; Layout.fillWidth: true; font.pixelSize: 15 }
                Label { text: page.services.batteryInfo.present ? page.services.batteryInfo.percentage + "% · " + (page.services.batteryInfo.pluggedIn ? "Plugged in" : "On battery") : "Desktop power"; color: "#a6e3a1" }
                Meter { Layout.fillWidth: true; title: "CPU"; value: page.resourceData.cpuPercent ?? 0; available: page.resourceData.cpuPercent !== null && page.resourceData.cpuPercent !== undefined }
                Meter { Layout.fillWidth: true; title: "Memory"; value: page.memoryPercent; available: !!page.resourceData.memoryTotal }
                Label { objectName: "dashboardMemoryDetails"; text: page.resourceData.memoryTotal ? (page.resourceData.memoryUsed / 1048576).toFixed(1) + " / " + (page.resourceData.memoryTotal / 1048576).toFixed(1) + " GiB RAM" : page.resourceData.error || "Reading resource counters…"; color: page.secondaryColor; Layout.fillWidth: true }
                Label { objectName: "dashboardUptime"; text: page.resourceData.uptime !== undefined ? "Uptime · " + Math.floor(page.resourceData.uptime / 3600) + "h " + Math.floor(page.resourceData.uptime / 60 % 60) + "m" : ""; color: page.secondaryColor }
                Item { Layout.fillHeight: true }
                RowLayout {
                    Layout.fillWidth: true
                    Action { text: "Wi-Fi"; Layout.fillWidth: true; onClicked: page.menuRequested("wifi") }
                    Action { text: "Audio"; Layout.fillWidth: true; onClicked: page.menuRequested("audio") }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Action { text: "Notifications"; Layout.fillWidth: true; onClicked: page.menuRequested("notifications") }
                    Action { text: "Power"; Layout.fillWidth: true; onClicked: page.menuRequested("power") }
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
                Label { anchors.centerIn: parent; text: "♫"; font.pixelSize: 42; color: page.accentColor; visible: art.status !== Image.Ready }
            }
            ColumnLayout {
                Layout.fillWidth: true; spacing: 10
                Label { text: page.player ? page.player.identity.toUpperCase() : "NOW PLAYING"; font.pixelSize: 12; color: page.secondaryColor; font.letterSpacing: 2 }
                Label { text: page.player ? page.player.trackTitle || "Unknown track" : "Nothing playing"; font.pixelSize: 22; font.weight: Font.DemiBold; Layout.fillWidth: true; maximumLineCount: 2; elide: Text.ElideRight }
                Label { text: page.player ? page.player.trackArtist : "Play something in your favorite app"; color: page.secondaryColor; Layout.fillWidth: true }
                RowLayout {
                    Action { text: "Previous"; enabled: !!page.player && page.player.canGoPrevious; onClicked: page.player.previous() }
                    Action { text: page.player && page.player.isPlaying ? "Pause" : "Play"; enabled: !!page.player && page.player.canTogglePlaying; accent: page.accentColor; onClicked: page.player.togglePlaying() }
                    Action { text: "Next"; enabled: !!page.player && page.player.canGoNext; onClicked: page.player.next() }
                }
            }
        }
    }
    component Label: MenuLabel { color: page.textColor }
    component Action: MenuButton { accent: page.textColor }
    component Card: Rectangle {
        radius: 16
        color: page.cardColor
        border.width: 1
        border.color: page.outlineColor
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
            Label { text: meter.title; Layout.fillWidth: true }
            Label { text: meter.available ? Math.round(meter.value) + "%" : "—"; color: page.accentColor }
        }
        Rectangle {
            Layout.fillWidth: true; implicitHeight: 8
            radius: 4; color: "#1fffffff"
            Rectangle {
                height: parent.height; radius: 4; color: page.accentColor
                width: parent.width * Math.max(0, Math.min(100, meter.value || 0)) / 100
                Behavior on width { NumberAnimation { duration: Style.Theme.duration(meter, 350); easing.type: Easing.BezierSpline; easing.bezierCurve: Style.Theme.spatialCurve } }
            }
        }
    }
}
