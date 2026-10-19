pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
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
    signal dismissRequested()
    signal settingsRequested()
    signal lockRequested()
    signal menuRequested(string name)
    function focusFirst() { page.forceActiveFocus(); }
    spacing: 12
    Keys.onEscapePressed: dismissRequested()
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
                Label { objectName: "dashboardMemoryDetails"; text: page.resourceData.system?.memoryTotal ? (page.resourceData.system.memoryTotal / 1073741824).toFixed(1) + " GiB RAM" : ""; color: page.secondaryColor; Layout.fillWidth: true }
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
                Label { text: "SHORTCUTS"; color: page.secondaryColor; font.pixelSize: 12; font.letterSpacing: 2 }
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
    component Label: MenuLabel { color: page.textColor }
    component Action: MenuButton { accent: page.textColor; implicitHeight: 32; topPadding: 6; bottomPadding: 6 }
    component Card: Rectangle {
        radius: 16
        color: page.cardColor
        border.width: 1
        border.color: page.outlineColor
        implicitWidth: 250
    }
}
