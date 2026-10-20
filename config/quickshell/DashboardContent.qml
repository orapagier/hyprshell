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
        columns: page.width >= 620 ? 2 : 1
        columnSpacing: 14; rowSpacing: 14
        WeatherCard {
            Layout.fillWidth: true; Layout.fillHeight: true
            Layout.preferredWidth: cards.columns === 2 ? page.width * 0.55 : page.width
            active: page.active
            textColor: page.textColor; secondaryColor: page.secondaryColor
            accentColor: page.accentColor; cardColor: page.cardColor
            outlineColor: page.outlineColor
        }
        Card {
            Layout.fillWidth: true; Layout.fillHeight: true
            Layout.preferredWidth: cards.columns === 2 ? page.width * 0.45 : page.width
            implicitHeight: systemDetails.implicitHeight + 48
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
                anchors.fill: parent; anchors.margins: 24; spacing: 0
                Label { objectName: "dashboardSystemInfo"; text: "THIS DEVICE"; color: page.secondaryColor; font.pixelSize: 10; font.letterSpacing: 1.8 }
                Label {
                    text: page.resourceData.system?.hostname || Quickshell.env("USER") || "System"
                    font.pixelSize: 24; font.weight: Font.DemiBold
                    Layout.topMargin: 12; Layout.fillWidth: true; elide: Text.ElideRight
                }
                Label { text: page.resourceData.system?.os || "Reading system information…"; color: page.secondaryColor; font.pixelSize: 12; Layout.topMargin: 4; Layout.fillWidth: true }
                Divider { Layout.topMargin: 20; Layout.bottomMargin: 18 }
                Label { text: "PROCESSOR"; color: page.secondaryColor; font.pixelSize: 10; font.letterSpacing: 1.2 }
                Label { text: page.resourceData.system?.cpuModel || "—"; font.pixelSize: 12; Layout.topMargin: 6; Layout.fillWidth: true }
                Label { text: "KERNEL"; color: page.secondaryColor; font.pixelSize: 10; font.letterSpacing: 1.2; Layout.topMargin: 14 }
                Label { text: page.resourceData.system?.kernel || "—"; font.pixelSize: 11; color: page.secondaryColor; Layout.topMargin: 5; Layout.fillWidth: true; wrapMode: Text.WrapAnywhere }
                Divider { Layout.topMargin: 18; Layout.bottomMargin: 12 }
                InfoRow {
                    title: "Memory"
                    valueName: "dashboardMemoryDetails"
                    value: page.resourceData.system?.memoryTotal ? (page.resourceData.system.memoryTotal / 1073741824).toFixed(1) + " GiB" : "—"
                }
                InfoRow { title: "Uptime"; valueName: "dashboardUptime"; value: page.uptimeText(page.resourceData.system?.uptimeSeconds); Layout.topMargin: 10 }
                InfoRow {
                    title: "OS age (est.)"; valueName: "dashboardOsAge"; Layout.topMargin: 10
                    value: page.resourceData.system?.osAgeDays !== null && page.resourceData.system?.osAgeDays !== undefined ? page.resourceData.system.osAgeDays + " days" : "Unavailable"
                }
                Item { Layout.fillHeight: true; Layout.minimumHeight: 20 }
                RowLayout {
                    Layout.fillWidth: true; spacing: 9
                    Rectangle { implicitWidth: 5; implicitHeight: 5; radius: 3; color: page.accentColor }
                    Label { text: page.services.statusData.network.tooltip; color: page.secondaryColor; font.pixelSize: 11; Layout.fillWidth: true }
                }
                Label {
                    text: page.services.batteryInfo.present ? page.services.batteryInfo.percentage + "% battery · " + (page.services.batteryInfo.pluggedIn ? "Plugged in" : "On battery") : "Desktop power"
                    font.pixelSize: 11; color: page.secondaryColor; Layout.topMargin: 7; Layout.fillWidth: true
                }
                RowLayout {
                    Layout.topMargin: 18; Layout.fillWidth: true; spacing: 8
                    Action { objectName: "dashboardSettings"; text: "Settings"; Layout.fillWidth: true; onClicked: page.settingsRequested() }
                    Action { objectName: "dashboardLock"; text: "Lock"; Layout.fillWidth: true; onClicked: page.lockRequested() }
                }
            }
        }
    }
    component Label: MenuLabel { color: page.textColor }
    component Divider: Rectangle {
        Layout.fillWidth: true; implicitHeight: 1
        color: Colors.alpha(page.textColor, Style.Theme.highContrast ? 0.6 : 0.09)
    }
    component InfoRow: RowLayout {
        id: info
        property string title
        property string value
        property string valueName: ""
        Layout.fillWidth: true; spacing: 10
        Label { text: info.title; font.pixelSize: 12; color: page.secondaryColor; Layout.fillWidth: true }
        Label { objectName: info.valueName; text: info.value; font.pixelSize: 13; font.weight: Font.Medium }
    }
    component Action: MenuButton {
        accent: page.textColor; font.pixelSize: 12
        fillColor: Colors.alpha(page.accentColor, 0.07)
        hoverColor: Colors.alpha(page.accentColor, 0.16)
        pressedColor: Colors.alpha(page.accentColor, 0.22)
        outlineColor: Style.Theme.highContrast ? page.textColor : "transparent"
        focusColor: page.accentColor
        implicitHeight: 36; topPadding: 9; bottomPadding: 9
        background: Rectangle {
            radius: 12
            color: parent.down ? parent.pressedColor : parent.hovered || parent.activeFocus ? parent.hoverColor : parent.fillColor
            border.width: 1; border.color: parent.activeFocus ? page.accentColor : parent.outlineColor
            Behavior on color { ColorAnimation { duration: Style.Theme.duration(page, 140) } }
        }
    }
    component Card: Rectangle {
        radius: 22
        color: page.cardColor
        border.width: 1
        border.color: Colors.alpha(page.textColor, Style.Theme.highContrast ? 1 : 0.08)
        implicitWidth: 280
    }
}
