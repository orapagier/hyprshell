pragma ComponentBehavior: Bound
import QtQuick
import "style" as Style
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Quickshell.Io

ColumnLayout {
    id: root
    required property var settings
    property var batteryInfo: ({})
    property string runtimeError: ""
    property var status: ({})
    property string message: ""
    property bool success: true
    property int requestedBrightness: -1
    readonly property bool busy: worker.running || brightnessDelay.running
    readonly property string helper: decodeURIComponent(Qt.resolvedUrl("settings/power.py").toString().replace(/^file:\/\//, ""))
    signal edited(string key, var value)
    spacing: 16
    function request(args) {
        if (worker.running) return;
        worker.command = ["python3", helper].concat(args);
        worker.running = true;
    }
    function refresh() { if (visible && requestedBrightness < 0 && !busy) request(["--status"]); }
    onVisibleChanged: if (visible) refresh()
    Component.onCompleted: refresh()
    Timer {
        id: brightnessDelay
        interval: 250
        onTriggered: {
            if (worker.running) { restart(); return; }
            let value = root.requestedBrightness;
            root.requestedBrightness = -1;
            root.request(["--brightness", String(value)]);
        }
    }
    Process {
        id: worker
        onExited: (code, status) => {
            if (code !== 0 && root.success) { root.success = false; root.message = "Power control failed. Refresh to retry."; }
        }
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let result = JSON.parse(text);
                    if (!result.ok) { root.success = false; root.message = result.message; return; }
                    root.success = true; root.message = "";
                    root.status = Object.assign({}, root.status, result);
                } catch (e) { root.success = false; root.message = "Could not read power controls. Refresh to retry."; }
            }
        }
    }
    SettingsCard {
        Layout.fillWidth: true
        title: "Battery"
        subtitle: root.batteryInfo.present ? (root.batteryInfo.percentage + "% · " + root.batteryInfo.status + (root.batteryInfo.pluggedIn ? " · Plugged in" : " · On battery")) : "No laptop battery reported. Power controls remain available where supported."
        Label {
            Layout.fillWidth: true
            visible: !!root.batteryInfo.present && root.batteryInfo.seconds > 0
            text: Math.round((root.batteryInfo.seconds || 0) / 60) + " minutes " + (root.batteryInfo.charging ? "until full" : "remaining") + " (estimate)"
            color: Style.SettingsTheme.muted; wrapMode: Text.WordWrap
        }
    }
    SettingsCard {
        Layout.fillWidth: true
        title: "Screen brightness"
        subtitle: "Adjust the laptop backlight now. External monitors may have separate controls."
        SettingsSlider {
            objectName: "powerBrightnessControl"
            Layout.fillWidth: true
            enabled: !!root.status.brightness
            label: "Brightness"
            settingValue: root.requestedBrightness >= 0 ? root.requestedBrightness : root.status.brightness ? root.status.brightness.percent : undefined
            inheritedText: "Unavailable"
            from: 1; to: 100; suffix: "%"
            allowReset: false
            onEdited: value => { root.requestedBrightness = value; brightnessDelay.restart(); }
        }
        Label {
            Layout.fillWidth: true
            visible: !!root.status.brightnessError && !root.status.brightness
            text: root.status.brightnessError || ""
            color: Style.SettingsTheme.muted; wrapMode: Text.WordWrap; font.pixelSize: Style.SettingsTheme.captionSize
        }
    }
    SettingsCard {
        Layout.fillWidth: true
        title: root.settings.separateBatteryTimers ? "Inactivity timers · Plugged in" : "Inactivity timers"
        subtitle: "Timers run while Hyprshell is open and respect Hypridle activity inhibitors. Screen locking is configured separately. Set 0 to disable a timer."
        Repeater {
            model: [{key: "dimMinutes", label: "Dim screen after"}, {key: "offMinutes", label: "Turn screen off after"}, {key: "suspendMinutes", label: "Suspend after"}]
            delegate: SettingsSlider {
                required property var modelData
                objectName: modelData.key + "Control"
                Layout.fillWidth: true
                label: modelData.label
                settingValue: root.settings[modelData.key]
                to: 240; suffix: " min"
                resetDescription: "Disable this timer"
                onEdited: value => root.edited(modelData.key, value === "" ? 0 : value)
            }
        }
        SettingsSlider {
            objectName: "dimPercentControl"
            Layout.fillWidth: true
            label: "Dimmed brightness"
            enabled: root.settings.dimMinutes > 0
            settingValue: root.settings.dimPercent
            from: 1; to: 100; suffix: "%"
            resetDescription: "Restore 20% dimmed brightness"
            onEdited: value => root.edited("dimPercent", value === "" ? 20 : value)
        }
        Label {
            Layout.fillWidth: true
            text: "Enabled timers must increase in this order: dim, screen off, then suspend. Brightness returns on activity unless you adjusted it manually. Suspending does not enable screen locking."
            color: Style.SettingsTheme.muted; wrapMode: Text.WordWrap; font.pixelSize: Style.SettingsTheme.captionSize
        }
    }
    SettingsCard {
        Layout.fillWidth: true
        title: "Battery timer policy"
        subtitle: "Switch using the desktop's existing battery service. No additional polling or idle daemon is needed. Screen locking keeps its own timeout on both power sources."
        SettingsSwitch { objectName: "separateBatteryTimers"; text: "Use different timers on battery"; checked: root.settings.separateBatteryTimers === true; Layout.fillWidth: true; onToggled: root.edited("separateBatteryTimers", checked) }
        Repeater {
            model: root.settings.separateBatteryTimers ? [{key: "batteryDimMinutes", label: "Dim on battery after"}, {key: "batteryOffMinutes", label: "Turn screen off on battery after"}, {key: "batterySuspendMinutes", label: "Suspend on battery after"}] : []
            delegate: SettingsSlider {
                required property var modelData
                Layout.fillWidth: true; label: modelData.label; settingValue: root.settings[modelData.key]; to: 240; suffix: " min"
                onEdited: value => root.edited(modelData.key, value === "" ? 0 : value)
            }
        }
        SettingsSlider { visible: root.settings.separateBatteryTimers === true; Layout.fillWidth: true; label: "Dimmed brightness on battery"; settingValue: root.settings.batteryDimPercent || 20; from: 1; to: 100; suffix: "%"; onEdited: value => root.edited("batteryDimPercent", value === "" ? 20 : value) }
    }
    SettingsCard {
        Layout.fillWidth: true
        title: "Laptop lid"
        subtitle: "Use system behavior by default. Custom behavior applies while Hyprshell runs, including when an external screen is attached."
        SettingsComboBox {
            objectName: "lidActionControl"
            Layout.fillWidth: true
            property var actions: ["system", "suspend", "ignore"]
            model: ["Use system behavior", "Suspend when closed", "Keep running when closed"]
            currentIndex: actions.indexOf(root.settings.lidAction)
            enabled: root.status.lidSupported || root.settings.lidAction !== "system"
            onActivated: index => root.edited("lidAction", actions[index])
        }
        Label {
            Layout.fillWidth: true
            visible: !!root.status.lidError
            text: root.status.lidError || ""
            wrapMode: Text.WordWrap; color: Style.SettingsTheme.muted; font.pixelSize: Style.SettingsTheme.captionSize
        }
    }
    SettingsCard {
        Layout.fillWidth: true
        title: "Power profile"
        subtitle: "Save a preference for supported hardware. Use system setting leaves the current profile under system control."
        SettingsComboBox {
            id: profile
            objectName: "powerProfileControl"
            Layout.fillWidth: true
            property var profiles: ["system"].concat(root.status.profiles ? root.status.profiles.available : [])
            model: profiles.map(p => ({system: "Use system setting", "power-saver": "Power saver", balanced: "Balanced", performance: "Performance"})[p])
            currentIndex: profiles.indexOf(root.settings.profile)
            onActivated: index => root.edited("profile", profiles[index])
        }
        Label {
            Layout.fillWidth: true
            text: root.settings.profile !== "system" && profile.profiles.indexOf(root.settings.profile) < 0 ? "Saved preference: " + root.settings.profile + ". This profile is currently unavailable; choose Use system setting or another supported profile." : root.status.profiles ? "Active: " + root.status.profiles.active : root.status.profilesError || "Checking supported profiles…"
            wrapMode: Text.WordWrap; color: Style.SettingsTheme.muted; font.pixelSize: Style.SettingsTheme.captionSize
        }
    }
    SettingsButton { text: "Refresh power controls"; enabled: !root.busy; onClicked: root.request(["--status"]) }
    Label {
        Layout.fillWidth: true
        visible: text !== ""
        text: [root.success ? "" : root.message, root.runtimeError].filter(Boolean).join("\n")
        wrapMode: Text.WordWrap; color: Style.SettingsTheme.danger
    }
}
