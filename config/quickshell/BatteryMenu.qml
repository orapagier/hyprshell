pragma ComponentBehavior: Bound
import QtQuick
import "AdaptiveColors.js" as Colors
import QtQuick.Layouts

ColumnLayout {
    id: page
    readonly property var menuColors: Colors.menuColorsFor(page)
    required property var services
    readonly property var info: services.batteryInfo || ({present: false})
    readonly property int percentage: Number.isFinite(info.percentage) ? Math.max(0, Math.min(100, Math.round(info.percentage))) : 0
    readonly property color accent: info.charging ? "#fab387" : percentage <= 30 ? "#f38ba8" : "#a6e3a1"
    readonly property var care: {
        if (!Number.isFinite(info.percentage) || typeof info.pluggedIn !== "boolean")
            return {title: "Everyday battery care", message: "Aim for a moderate charge level and keep your laptop cool.", color: "#a6e3a1"};
        if (!info.pluggedIn && percentage <= 20)
            return {title: "Plug in soon", message: "Connect the charger to avoid draining the battery too low.", color: "#f38ba8"};
        if (info.pluggedIn && percentage >= 80)
            return {title: "Consider unplugging", message: "If you don't need extra runtime, unplug or use an 80% charge limit. With a charge limit enabled, staying plugged in is fine.", color: "#fab387"};
        if (info.pluggedIn && info.charging)
            return {title: "Charging toward 80%", message: "You can leave it connected for now. Around 80% is a useful stopping point for everyday use.", color: "#a6e3a1"};
        if (info.pluggedIn)
            return {title: "Charger connected", message: "If you usually work plugged in, an 80% charge limit can help. No need to repeatedly cycle the battery.", color: "#a6e3a1"};
        return {title: percentage >= 80 ? "No charging needed" : "Good charge level", message: "Use your laptop normally and consider recharging around 20%. Keeping it cool also helps.", color: "#a6e3a1"};
    }
    readonly property color careColor: care.color
    spacing: 12

    function duration(seconds) {
        if (!Number.isFinite(seconds) || seconds <= 0) return "Estimating…";
        let minutes = Math.ceil(seconds / 60);
        let hours = Math.floor(minutes / 60);
        return hours ? hours + "h" + (minutes % 60 ? " " + minutes % 60 + "m" : "") : minutes + "m";
    }
    function measurement(value, unit) {
        return Number.isFinite(value) && value > 0 ? value.toFixed(1) + " " + unit : "Not reported";
    }
    function chargeCapacity(value) {
        return Number.isFinite(value) && value > 0
            ? Math.round(value).toLocaleString(Qt.locale("en_US"), "f", 0) + " mAh" : "Not reported";
    }

    MenuLabel { visible: !page.info.present; text: "Battery information is unavailable"; Layout.fillWidth: true; color: page.menuColors.secondary }
    Rectangle {
        visible: !!page.info.present
        Layout.fillWidth: true
        implicitHeight: 112
        radius: 12
        color: Qt.rgba(page.accent.r, page.accent.g, page.accent.b, 0.08)
        border.color: Qt.rgba(page.accent.r, page.accent.g, page.accent.b, 0.18)
        RowLayout {
            x: 14; y: 12; width: parent.width - 28
            spacing: 12
            Text { text: page.info.charging ? "󰂄" : "󰁹"; color: page.accent; font.family: "GoMono Nerd Font"; font.pixelSize: 38 }
            ColumnLayout {
                spacing: 2
                Layout.fillWidth: true
                MenuLabel { objectName: "batteryCharge"; text: page.percentage + "%"; color: page.accent; font.pixelSize: 28; font.bold: true }
                MenuLabel { objectName: "batteryStatus"; text: page.info.status || "Unknown"; color: page.menuColors.secondary; font.pixelSize: 12 }
            }
        }
        Rectangle {
            x: 14; y: parent.height - 22; width: parent.width - 28
            height: 6; radius: 3; color: "#1fffffff"
            Rectangle { width: parent.width * page.percentage / 100; height: parent.height; radius: 3; color: page.accent; Behavior on width { NumberAnimation { duration: 200 } } }
        }
    }
    MenuLabel {
        visible: !!(page.info.present && page.info.model)
        text: page.info.model || ""
        Layout.fillWidth: true; Layout.minimumWidth: 0
        color: page.menuColors.secondary; font.pixelSize: 11
    }
    Repeater {
        model: page.info.present ? [
            {key: "time", label: page.info.charging ? "Time to full" : "Time remaining", value: page.duration(page.info.seconds), show: !!(page.info.charging || page.info.discharging)},
            {key: "health", label: "Battery health", value: Number.isFinite(page.info.health) && page.info.health > 0 ? page.info.health.toFixed(1) + "%" : "Not reported", show: true},
            {key: "fullCharge", label: "Full-charge capacity", value: page.chargeCapacity(page.info.fullMah), show: true},
            {key: "designCharge", label: "Design capacity", value: page.chargeCapacity(page.info.designMah), show: true},
            {key: "power", label: page.info.charging ? "Charging power" : "Power draw", value: page.measurement(Math.abs(page.info.power), "W"), show: !!(page.info.charging || page.info.discharging)},
            {key: "energy", label: "Energy remaining", value: page.measurement(page.info.energy, "Wh"), show: true},
            {key: "capacity", label: "Full energy", value: page.measurement(page.info.energyCapacity, "Wh"), show: true}
        ] : []
        delegate: RowLayout {
            id: detail
            required property var modelData
            visible: modelData.show
            Layout.fillWidth: true
            spacing: 8
            MenuLabel { text: detail.modelData.label; color: page.menuColors.secondary; Layout.fillWidth: true; font.pixelSize: 12 }
            MenuLabel { objectName: "batteryDetail-" + detail.modelData.key; text: detail.modelData.value; font.pixelSize: 12; horizontalAlignment: Text.AlignRight }
        }
    }
    Rectangle {
        objectName: "batteryCareCard"
        visible: !!page.info.present
        Layout.fillWidth: true
        implicitHeight: careContents.implicitHeight + 24
        radius: 10
        color: Qt.rgba(page.careColor.r, page.careColor.g, page.careColor.b, 0.08)
        border.color: Qt.rgba(page.careColor.r, page.careColor.g, page.careColor.b, 0.22)
        ColumnLayout {
            id: careContents
            x: 12; y: 12; width: parent.width - 24
            spacing: 6
            MenuLabel {
                objectName: "batteryCareTitle"
                text: page.care.title; color: page.care.color
                font.bold: true; font.pixelSize: 12
                Layout.fillWidth: true; Layout.minimumWidth: 0
            }
            MenuLabel {
                objectName: "batteryCareMessage"
                text: page.care.message; font.pixelSize: 11
                Layout.fillWidth: true; Layout.minimumWidth: 0
            }
            MenuLabel {
                text: "20–80% is a flexible target. A full charge is fine when you need more runtime."
                color: page.menuColors.secondary; font.pixelSize: 10
                Layout.fillWidth: true; Layout.minimumWidth: 0
            }
        }
    }
}
