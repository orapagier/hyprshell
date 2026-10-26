pragma ComponentBehavior: Bound
import QtQuick
import "style" as Style
import QtQuick.Controls.Basic
import QtQuick.Layouts

ColumnLayout {
    id: page
    required property var settings
    property var applications: []
    property string appName: ""
    readonly property var knownApps: Array.from(new Set(applications.concat(Object.keys(settings.apps || {})))).sort()
    signal edited(string key, var value)
    function setApp(key, mode) {
        let apps = Object.assign({}, settings.apps);
        if (mode === "inherit") delete apps[key]; else apps[key] = mode;
        edited("apps", apps);
    }
    spacing: 20
    SettingsCard {
        Layout.fillWidth: true
        title: "Popups and quiet mode"
        subtitle: "Notifications stay in the bell inbox when popups are disabled or quiet mode is active."
        SettingsCheckBox {
            objectName: "notificationPopupsControl"
            text: "Show notification popups"
            checked: page.settings.popups
            onToggled: page.edited("popups", checked)
        }
        SettingsCheckBox {
            objectName: "notificationDndControl"
            text: "Do Not Disturb"
            checked: page.settings.doNotDisturb
            onToggled: page.edited("doNotDisturb", checked)
        }
        SettingsCheckBox {
            text: "Allow critical popups during Do Not Disturb"
            checked: page.settings.criticalBypass
            onToggled: page.edited("criticalBypass", checked)
        }
        SettingField {
            Layout.fillWidth: true
            label: "Popup duration (seconds)"
            value: String(page.settings.popupSeconds)
            description: "2–30 seconds. Critical popups stay until closed. Closing a popup keeps its inbox entry."
            onEdited: value => page.edited("popupSeconds", /^\d+$/.test(value) ? Number(value) : value)
        }
    }
    SettingsCard {
        Layout.fillWidth: true
        title: "Applications"
        subtitle: "App defaults follow your popup and quiet settings. Inbox only hides popups, and Off ignores new notifications, including critical alerts."
        SettingField {
            Layout.fillWidth: true
            label: "Add application ID or name"
            value: page.appName
            description: "Applications appear here after sending a notification. You can also enter their desktop ID or exact app name."
            onEdited: value => page.appName = value.trim()
        }
        SettingsButton {
            text: "Add with inbox only"
            enabled: page.appName.length > 0
            onClicked: { page.setApp(page.appName, "inbox"); page.appName = ""; }
        }
        Repeater {
            model: page.knownApps
            delegate: ColumnLayout {
                required property string modelData
                Layout.fillWidth: true
                Label { Layout.fillWidth: true; text: parent.modelData; wrapMode: Text.Wrap; color: Style.SettingsTheme.text; textFormat: Text.PlainText }
                SettingsComboBox {
                    Layout.fillWidth: true
                    model: ["Follow defaults", "Inbox only", "Off"]
                    currentIndex: ["inherit", "inbox", "off"].indexOf(page.settings.apps[modelData] || "inherit")
                    onActivated: index => page.setApp(modelData, ["inherit", "inbox", "off"][index])
                }
            }
        }
    }
}
