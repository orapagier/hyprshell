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
    spacing: 12
    Keys.onEscapePressed: dismissRequested()
    Timer { interval: 1000; repeat: true; running: page.active; onTriggered: page.now = new Date() }
    GridLayout {
        id: cards
        Layout.fillWidth: true
        columns: page.width >= 520 ? 2 : 1
        columnSpacing: 12; rowSpacing: 12
        Card {
            Layout.fillWidth: true; Layout.fillHeight: true
            implicitHeight: systemDetails.implicitHeight + 32
            WallpaperColors {
                id: wallpaperSampler
                objectName: "dashboardWallpaperSampler"
                source: page.wallpaperSource
                screenWidth: page.screenWidth; screenHeight: page.screenHeight
                offsetY: page.wallpaperRegion.y
                bandHeight: Math.max(1, page.wallpaperRegion.height)
            }
            ColumnLayout {
                id: systemDetails
                anchors.fill: parent; anchors.margins: 16; spacing: 6
                Label { objectName: "dashboardSystemInfo"; text: "SYSTEM INFO"; color: page.secondaryColor; font.pixelSize: 12; font.letterSpacing: 2 }
                Label { text: page.resourceData.system?.hostname || Quickshell.env("USER") || "System"; font.pixelSize: 18; font.weight: Font.DemiBold; Layout.fillWidth: true; elide: Text.ElideRight }
                Label { text: page.resourceData.system?.os || "Reading system information…"; Layout.fillWidth: true; elide: Text.ElideRight }
                Label { text: page.resourceData.system?.cpuModel || ""; color: page.secondaryColor; Layout.fillWidth: true; elide: Text.ElideRight }
                Label { text: "Kernel · " + (page.resourceData.system?.kernel || "—"); color: page.secondaryColor; Layout.fillWidth: true; elide: Text.ElideRight }
                Label { objectName: "dashboardUptime"; text: page.resourceData.uptime !== undefined ? "Uptime · " + Math.floor(page.resourceData.uptime / 3600) + "h " + Math.floor(page.resourceData.uptime / 60 % 60) + "m" : "Uptime · —"; color: page.secondaryColor }
                Meter { Layout.fillWidth: true; title: "CPU"; value: page.resourceData.cpuPercent ?? 0; available: page.resourceData.cpuPercent !== null && page.resourceData.cpuPercent !== undefined }
                Meter { Layout.fillWidth: true; title: "Memory"; value: page.memoryPercent; available: !!page.resourceData.memoryTotal }
                Label { objectName: "dashboardMemoryDetails"; text: page.resourceData.memoryTotal ? (page.resourceData.memoryUsed / 1048576).toFixed(1) + " / " + (page.resourceData.memoryTotal / 1048576).toFixed(1) + " GiB RAM" : page.resourceData.error || "Reading resource counters…"; color: page.secondaryColor; Layout.fillWidth: true }
                Label { text: page.services.statusData.network.tooltip; Layout.fillWidth: true; elide: Text.ElideRight; color: page.secondaryColor }
                Label { text: page.services.batteryInfo.present ? page.services.batteryInfo.percentage + "% · " + (page.services.batteryInfo.pluggedIn ? "Plugged in" : "On battery") : "Desktop power"; color: "#a6e3a1" }
                RowLayout {
                    Layout.fillWidth: true
                    Action { text: "Settings"; Layout.fillWidth: true; onClicked: page.settingsRequested() }
                    Action { text: "Lock"; Layout.fillWidth: true; onClicked: page.lockRequested() }
                }
            }
        }
        Card {
            Layout.fillWidth: true; Layout.fillHeight: true
            implicitHeight: calendar.implicitHeight * calendar.scale + 24
            CalendarMenu {
                id: calendar
                x: 12; y: 12
                width: Math.max(0, parent.width - 24) / scale
                height: implicitHeight
                scale: 0.9
                transformOrigin: Item.TopLeft
            }
        }
        Card {
            Layout.fillWidth: true; Layout.fillHeight: true
            Layout.columnSpan: cards.columns
            implicitHeight: desktopDetails.implicitHeight + 32
            ColumnLayout {
                id: desktopDetails
                anchors.fill: parent; anchors.margins: 16; spacing: 6
                RowLayout {
                    Layout.fillWidth: true
                    Label { text: "TOP 5 PROCESSES"; color: page.secondaryColor; font.pixelSize: 12; font.letterSpacing: 2; Layout.fillWidth: true }
                    Label { text: "CPU ↓ · every 5s"; color: page.secondaryColor; font.pixelSize: 11 }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Label { text: "Process"; Layout.fillWidth: true; color: page.secondaryColor }
                    Label { text: "CPU"; Layout.preferredWidth: 66; horizontalAlignment: Text.AlignRight; color: page.secondaryColor }
                    Label { text: "RAM"; Layout.preferredWidth: 82; horizontalAlignment: Text.AlignRight; color: page.secondaryColor }
                }
                Repeater {
                    model: page.resourceData.topProcesses || []
                    delegate: RowLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        Label { text: modelData.name + " · " + modelData.pid; Layout.fillWidth: true; elide: Text.ElideRight }
                        Label { text: modelData.cpuPercent === null ? "—" : modelData.cpuPercent.toFixed(1) + "%"; Layout.preferredWidth: 66; horizontalAlignment: Text.AlignRight; color: page.accentColor }
                        Label { text: (modelData.memoryKiB / 1024).toFixed(1) + " MiB"; Layout.preferredWidth: 82; horizontalAlignment: Text.AlignRight }
                    }
                }
                Label { visible: !page.resourceData.topProcesses?.length; text: page.resourceData.error || "Reading processes…"; color: page.secondaryColor }
                Label { text: page.resourceData.cpuPercent === null ? "Measuring CPU… · RAM shown until the next sample" : "CPU: 100% = one core · RAM: resident memory"; color: page.secondaryColor; font.pixelSize: 11; Layout.fillWidth: true; wrapMode: Text.WordWrap }
                GridLayout {
                    Layout.fillWidth: true
                    columns: page.width >= 520 ? 4 : 2
                    Action { text: "Wi-Fi"; Layout.fillWidth: true; onClicked: page.menuRequested("wifi") }
                    Action { text: "Audio"; Layout.fillWidth: true; onClicked: page.menuRequested("audio") }
                    Action { text: "Notifications"; Layout.fillWidth: true; onClicked: page.menuRequested("notifications") }
                    Action { text: "Power"; Layout.fillWidth: true; onClicked: page.menuRequested("power") }
                }
            }
        }
    }
    Card {
        Layout.fillWidth: true
        implicitHeight: mediaDetails.implicitHeight + 32
        RowLayout {
            anchors.fill: parent; anchors.margins: 16; spacing: 14
            Rectangle {
                Layout.preferredWidth: Math.min(80, page.width * 0.2)
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
                id: mediaDetails
                objectName: "dashboardMediaDetails"
                Layout.fillWidth: true; spacing: 6
                Label { text: page.player ? page.player.identity.toUpperCase() : "NOW PLAYING"; font.pixelSize: 12; color: page.secondaryColor; font.letterSpacing: 2 }
                Label { text: page.player ? page.player.trackTitle || "Unknown track" : "Nothing playing"; font.pixelSize: 18; font.weight: Font.DemiBold; Layout.fillWidth: true; maximumLineCount: 2; elide: Text.ElideRight }
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
    component Action: MenuButton { accent: page.textColor; implicitHeight: 32; topPadding: 6; bottomPadding: 6 }
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
