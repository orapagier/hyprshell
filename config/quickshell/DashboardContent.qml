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
    readonly property var usage: resourceData.usage || ({})
    property bool active: false
    readonly property bool busy: weatherCard.busy || weatherCard.reloadAfterSave
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
    function gib(bytes) { return typeof bytes === "number" ? (bytes / 1073741824).toFixed(1) : "—"; }
    spacing: 12
    Keys.onEscapePressed: dismissRequested()
    GridLayout {
        id: cards
        Layout.fillWidth: true
        columns: page.width >= 620 ? 2 : 1
        columnSpacing: 14; rowSpacing: 14
        WeatherCard {
            id: weatherCard
            Layout.fillWidth: true; Layout.fillHeight: true
            Layout.preferredWidth: cards.columns === 2 ? page.width * 0.55 : page.width
            minimumHeaderHeight: cards.columns === 2 ? systemTitle.implicitHeight + systemSubtitle.implicitHeight + 4 : 0
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
                // Keep one full-wallpaper thumbnail. Moving/resizing the drawer
                // samples this cache rather than rereading Canvas pixels.
                offsetY: 0
                bandHeight: Math.max(1, page.screenHeight)
                sampleWidth: 96; sampleHeight: 64
            }
            ColumnLayout {
                id: systemDetails
                anchors.fill: parent; anchors.margins: 24; spacing: 0
                Label {
                    id: systemTitle
                    objectName: "dashboardSystemInfo"
                    text: page.resourceData.system?.hostname || Quickshell.env("USER") || "System"
                    font.pixelSize: 24; font.weight: Font.DemiBold
                    Layout.fillWidth: true; elide: Text.ElideRight
                }
                Label { id: systemSubtitle; text: page.resourceData.system?.os || "Reading system information…"; color: page.secondaryColor; font.pixelSize: 12; Layout.topMargin: 4; Layout.fillWidth: true }
                Item {
                    Layout.preferredHeight: cards.columns === 2 ? Math.max(0, weatherCard.headerImplicitHeight - systemTitle.implicitHeight - systemSubtitle.implicitHeight - 4) : 0
                }
                Rectangle {
                    objectName: "dashboardDeviceDetails"
                    Layout.fillWidth: true; Layout.topMargin: cards.columns === 2 ? 22 : 18
                    implicitHeight: deviceDetails.implicitHeight + 28
                    color: Colors.alpha(page.accentColor, Style.Theme.highContrast ? 0 : 0.04); radius: 16
                    border.width: Style.Theme.highContrast ? 1 : 0; border.color: page.textColor
                    ColumnLayout {
                        id: deviceDetails
                        anchors.fill: parent; anchors.margins: 14; spacing: 0
                        Label { text: "PROCESSOR"; color: page.secondaryColor; font.pixelSize: 10; font.letterSpacing: 1.2 }
                        Label { text: page.resourceData.system?.cpuModel || "—"; font.pixelSize: 12; Layout.topMargin: 6; Layout.fillWidth: true }
                        Label { text: "KERNEL"; color: page.secondaryColor; font.pixelSize: 10; font.letterSpacing: 1.2; Layout.topMargin: 14 }
                        Label { text: page.resourceData.system?.kernel || "—"; font.pixelSize: 11; color: page.secondaryColor; Layout.topMargin: 5; Layout.fillWidth: true; wrapMode: Text.WrapAnywhere }
                        Divider { Layout.topMargin: 12; Layout.bottomMargin: 12 }
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
                    }
                }
                Rectangle {
                    objectName: "dashboardResourceUsage"
                    Layout.fillWidth: true; Layout.fillHeight: true; Layout.topMargin: 14
                    implicitHeight: resourceDetails.implicitHeight + 28
                    color: Colors.alpha(page.accentColor, Style.Theme.highContrast ? 0 : 0.04); radius: 16
                    border.width: Style.Theme.highContrast ? 1 : 0; border.color: page.textColor
                    ColumnLayout {
                        id: resourceDetails
                        anchors.fill: parent; anchors.margins: 14; spacing: 10
                        Label { text: "RESOURCE USAGE"; color: page.secondaryColor; font.pixelSize: 10; font.letterSpacing: 1.2; Layout.fillWidth: true }
                        UsageRow {
                            objectName: "dashboardCpuUsage"; title: "CPU"
                            value: typeof page.usage.cpuPercent === "number" ? Math.round(page.usage.cpuPercent) + "%" : "—"
                            fraction: typeof page.usage.cpuPercent === "number" ? page.usage.cpuPercent / 100 : -1
                        }
                        UsageRow {
                            objectName: "dashboardRamUsage"; title: "RAM"
                            value: page.usage.memoryTotal > 0 ? page.gib(page.usage.memoryUsed) + " / " + page.gib(page.usage.memoryTotal) + " GiB" : "—"
                            fraction: page.usage.memoryTotal > 0 ? page.usage.memoryUsed / page.usage.memoryTotal : -1
                        }
                        UsageRow {
                            objectName: "dashboardStorageUsage"; title: "Storage (/)"
                            value: page.usage.storageTotal > 0 ? page.gib(page.usage.storageFree) + " GiB free" : "—"
                            fraction: page.usage.storageTotal > 0 ? 1 - page.usage.storageFree / page.usage.storageTotal : -1
                        }
                    }
                }
                Rectangle {
                    objectName: "dashboardConnectionStatus"
                    Layout.topMargin: 14; Layout.fillWidth: true
                    implicitHeight: connectionDetails.implicitHeight + 28
                    color: Colors.alpha(page.accentColor, Style.Theme.highContrast ? 0 : 0.04); radius: 16
                    border.width: Style.Theme.highContrast ? 1 : 0; border.color: page.textColor
                    ColumnLayout {
                        id: connectionDetails
                        anchors.fill: parent; anchors.margins: 14; spacing: 10
                        InfoRow {
                            title: "Bluetooth"; valueName: "dashboardBluetoothState"
                            value: page.services.adapter ? (page.services.adapter.enabled ? "On" : "Off") : "Unavailable"
                            Accessible.name: "Bluetooth: " + value
                        }
                        InfoRow {
                            title: "Audio"; valueName: "dashboardAudioLevel"
                            value: page.services.sink?.audio ? Math.round(page.services.sink.audio.volume * 100) + "%" + (page.services.sink.audio.muted ? " · Muted" : "") : "Unavailable"
                            Accessible.name: "Audio: " + value
                        }
                        InfoRow {
                            title: "Wi-Fi"; valueName: "dashboardWifiSignal"
                            value: page.services.connectedWifi ? Math.round(page.services.connectedWifi.signalStrength * 100) + "%" : page.services.wifiEnabled ? "Disconnected" : "Off"
                            Accessible.name: page.services.statusData.network.tooltip
                        }
                        InfoRow {
                            title: "Battery"; valueName: "dashboardBatteryLevel"
                            value: page.services.batteryInfo.present ? page.services.batteryInfo.percentage + "%" : "No battery"
                            Accessible.name: "Battery: " + value + (page.services.batteryInfo.present ? (page.services.batteryInfo.pluggedIn ? ", plugged in" : ", on battery") : "")
                        }
                    }
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
    component UsageRow: ColumnLayout {
        id: usageRow
        property string title
        property string value
        property real fraction: -1
        Layout.fillWidth: true; spacing: 6
        Accessible.name: title + ": " + value
        RowLayout {
            Layout.fillWidth: true; spacing: 8
            Label { text: usageRow.title; color: page.secondaryColor; font.pixelSize: 11; Layout.fillWidth: true }
            Label { text: usageRow.value; font.pixelSize: 11; font.weight: Font.Medium }
        }
        Rectangle {
            Layout.fillWidth: true; implicitHeight: 4; radius: 2
            color: Colors.alpha(page.textColor, Style.Theme.highContrast ? 0.35 : 0.10)
            Rectangle {
                width: parent.width * Math.max(0, Math.min(1, usageRow.fraction)); height: parent.height; radius: 2
                color: page.accentColor
            }
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
