import QtQuick
import "style" as Style
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Quickshell.Io

ColumnLayout {
    id: page
    property var apps: []
    property var associations: []
    property var startup: []
    property string revision: ""
    property string extra: ""
    property string requestedExtra: ""
    property bool loaded: false
    property bool success: true
    property string message: ""
    readonly property bool busy: worker.running
    spacing: 16
    onVisibleChanged: if (visible && !busy) request({operation: "status"})
    Component.onCompleted: if (visible) request({operation: "status"})

    function appName(ident) {
        let app = apps.find(a => a.id === ident);
        return app ? app.name : ident;
    }
    function request(payload) {
        if (busy) return;
        payload.expected = revision;
        if (payload.extra === undefined) payload.extra = extra;
        requestedExtra = payload.extra;
        worker.command = ["python3", decodeURIComponent(Qt.resolvedUrl("settings/applications.py").toString().replace(/^file:\/\//, "")), "--request-json", JSON.stringify(payload)];
        worker.running = true;
    }
    Process {
        id: worker
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let result = JSON.parse(text);
                    page.success = result.ok;
                    page.message = result.message || "";
                    if (result.ok) {
                        page.extra = page.requestedExtra;
                        page.apps = result.apps;
                        page.associations = result.associations;
                        page.startup = result.startup;
                        page.revision = result.revision;
                        page.loaded = true;
                    }
                    // Reset delegates after a rejected or failed change as well.
                    let rows = page.startup; page.startup = []; page.startup = rows;
                    let defaults = page.associations; page.associations = []; page.associations = defaults;
                } catch (e) { page.success = false; page.message = "Could not read application preferences. Try refreshing."; }
            }
        }
        stderr: StdioCollector { onStreamFinished: if (text) { page.success = false; page.message = "Could not update application preferences. Try refreshing."; } }
    }
    Label { visible: !!page.message; text: page.message; color: page.success ? Style.SettingsTheme.success : Style.SettingsTheme.danger; Layout.fillWidth: true; wrapMode: Text.Wrap }
    SettingsButton { text: "Refresh"; enabled: !page.busy; onClicked: page.request({operation: "status"}) }
    SettingsCard {
        title: "Default applications"
        subtitle: "Choose which installed app opens links and common file types. Each choice saves immediately."
        Layout.fillWidth: true
        Repeater {
            model: page.associations
            delegate: ColumnLayout {
                id: association
                required property var modelData
                Layout.fillWidth: true
                Label { text: association.modelData.label; color: Style.SettingsTheme.text }
                SettingsComboBox {
                    objectName: "defaultApplication-" + association.modelData.types[0]
                    Layout.fillWidth: true
                    enabled: page.loaded && !page.busy && association.modelData.candidates.length > 0
                    model: [association.modelData.mixed ? "Different apps for these file types" : association.modelData.current ? page.appName(association.modelData.current) + " (current)" : "Choose an application"].concat(association.modelData.candidates.map(id => page.appName(id)))
                    currentIndex: 0
                    onActivated: index => { if (index > 0) page.request({operation: "default", types: association.modelData.types, application: association.modelData.candidates[index - 1]}); }
                }
                Label { visible: association.modelData.candidates.length === 0; text: "No installed application advertises support for this file type."; color: Style.SettingsTheme.muted; wrapMode: Text.Wrap; Layout.fillWidth: true }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            SettingsTextField { id: mime; objectName: "customMimeType"; Layout.fillWidth: true; placeholderText: "Other file type, e.g. application/zip"; color: Style.SettingsTheme.text; selectByMouse: true; onAccepted: inspect.clicked() }
            SettingsButton { id: inspect; text: "Find apps"; enabled: !page.busy && mime.text.trim().length > 0; onClicked: page.request({operation: "status", extra: mime.text.trim()}) }
        }
    }
    SettingsCard {
        title: "Start at login"
        subtitle: "Changes take effect at your next login. Turning an entry off leaves its currently running app open."
        Layout.fillWidth: true
        Repeater {
            model: page.startup
            delegate: ColumnLayout {
                id: startupEntry
                required property var modelData
                Layout.fillWidth: true
                SettingsSwitch {
                    objectName: "startupApplication-" + startupEntry.modelData.id
                    Layout.fillWidth: true
                    text: startupEntry.modelData.name
                    checked: startupEntry.modelData.enabled
                    enabled: page.loaded && !page.busy
                    onToggled: page.request({operation: "startup", entry: startupEntry.modelData.id, enabled: checked})
                }
                Label { visible: !!startupEntry.modelData.reason; text: startupEntry.modelData.reason; color: Style.SettingsTheme.muted; Layout.fillWidth: true; wrapMode: Text.Wrap }
            }
        }
        Label { visible: page.loaded && page.startup.length === 0; text: "No application startup entries found."; color: Style.SettingsTheme.muted }
        RowLayout {
            Layout.fillWidth: true
            SettingsComboBox { id: addApp; objectName: "startupAppPicker"; Layout.fillWidth: true; enabled: page.loaded && !page.busy; model: page.apps.map(app => app.name) }
            SettingsButton { text: "Add app"; enabled: page.loaded && !page.busy && addApp.currentIndex >= 0; onClicked: page.request({operation: "add", application: page.apps[addApp.currentIndex].id, enabled: true}) }
        }
        Label { text: "Desktop essentials such as the bar, wallpaper, authorization, and power services are managed separately."; color: Style.SettingsTheme.muted; Layout.fillWidth: true; wrapMode: Text.Wrap }
    }
}
