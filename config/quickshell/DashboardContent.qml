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
    // Retain the sampled hue and saturation instead of burying it under gray.
    readonly property color cardColor: Style.Theme.highContrast ? "#000000"
        : Qt.hsva(wallpaperSample.hsvHue, wallpaperSample.hsvSaturation * 0.72,
                  0.12 + wallpaperSample.hsvValue * 0.10, 1)
    readonly property color textColor: Style.Theme.highContrast ? "#ffffff" : Colors.mix(wallpaperSample, Qt.color("#ffffff"), 0.94)
    readonly property color secondaryColor: Colors.mix(cardColor, textColor, 0.82)
    readonly property color accentColor: Style.Theme.highContrast ? "#ffffff"
        : Colors.mix(Colors.vibrantForeground(wallpaperSample, wallpaperSample), textColor, 0.58)
    readonly property color outlineColor: Colors.mix(cardColor, accentColor, Style.Theme.highContrast ? 1 : 0.38)
    signal dismissRequested()
    signal settingsRequested()
    signal lockRequested()
    signal menuRequested(string name)
    function uptimeText(seconds) {
        if (seconds === undefined || seconds === null) return "—";
        const minutes = Math.floor(seconds / 60);
        const days = Math.floor(minutes / 1440);
        return (days ? days + "d " : "") + Math.floor(minutes % 1440 / 60) + "h " + minutes % 60 + "m";
    }
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
                Label { objectName: "dashboardUptime"; text: "Uptime · " + page.uptimeText(page.resourceData.system?.uptimeSeconds); color: page.secondaryColor; Layout.fillWidth: true }
                Label { objectName: "dashboardOsAge"; text: "OS age · " + (page.resourceData.system?.osAgeDays !== null && page.resourceData.system?.osAgeDays !== undefined ? page.resourceData.system.osAgeDays + " days (estimated)" : "Unavailable"); color: page.secondaryColor; Layout.fillWidth: true }
                Label { text: page.services.statusData.network.tooltip; Layout.fillWidth: true; elide: Text.ElideRight; color: page.secondaryColor }
                Label { text: page.services.batteryInfo.present ? page.services.batteryInfo.percentage + "% · " + (page.services.batteryInfo.pluggedIn ? "Plugged in" : "On battery") : "Desktop power"; color: page.accentColor }
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
                adaptivePalette: true
                textColor: page.textColor
                secondaryColor: page.secondaryColor
                accentColor: page.accentColor
                surfaceColor: page.cardColor
                x: 12; y: 12
                width: Math.max(0, parent.width - 24) / scale
                height: implicitHeight
                scale: 0.9
                transformOrigin: Item.TopLeft
            }
        }
    }
    component Label: MenuLabel { color: page.textColor }
    component Action: MenuButton {
        accent: page.accentColor
        fillColor: Colors.alpha(page.accentColor, 0.06)
        hoverColor: Colors.alpha(page.accentColor, 0.14)
        pressedColor: Colors.alpha(page.accentColor, 0.20)
        outlineColor: page.outlineColor
        focusColor: page.accentColor; implicitHeight: 32; topPadding: 6; bottomPadding: 6 }
    component Card: Rectangle {
        radius: 16
        color: page.cardColor
        border.width: 1
        border.color: page.outlineColor
        implicitWidth: 250
    }
}
