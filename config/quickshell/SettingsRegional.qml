import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Quickshell.Io
import "style" as Style

ColumnLayout {
    id: page
    property var settings: ({version: 1, language: "", formats: "", timezone: ""})
    property var locales: []
    property var timezones: []
    property var preview: ({})
    property string revision: ""
    property string message: ""
    property bool success: true
    property bool loaded: false
    property bool confirmSystemZone: false
    readonly property bool busy: worker.running
    readonly property bool dirty: loaded && JSON.stringify(draft()) !== JSON.stringify(settings)
    spacing: 16
    Component.onCompleted: if (visible) request({operation: "status"})
    onVisibleChanged: { confirmSystemZone = false; if (visible && !busy && !dirty) request({operation: "status"}); }
    function draft() { return {version: 1, language: language.currentIndex > 0 ? locales[language.currentIndex - 1] : "", formats: formats.currentIndex > 0 ? locales[formats.currentIndex - 1] : "", timezone: zone.text.trim()}; }
    function request(payload) {
        if (busy) return;
        payload.expected = revision;
        worker.command = ["python3", decodeURIComponent(Qt.resolvedUrl("settings/regional.py").toString().replace(/^file:\/\//, "")), "--request-json", JSON.stringify(payload)]; worker.running = true;
    }
    Process {
        id: worker
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let result = JSON.parse(text); page.success = result.ok; page.message = result.message || "";
                    if (result.ok && result.settings) {
                        page.settings = result.settings; page.locales = result.locales; page.timezones = result.timezones; page.revision = result.revision; page.loaded = true;
                        language.currentIndex = page.locales.indexOf(page.settings.language) + 1;
                        formats.currentIndex = page.locales.indexOf(page.settings.formats) + 1;
                        zone.text = page.settings.timezone;
                    }
                    if (result.preview) page.preview = result.preview;
                    page.confirmSystemZone = false;
                } catch (e) { page.success = false; page.message = "Could not read regional preferences. Refresh and try again."; }
            }
        }
        onExited: (code, status) => { if (code !== 0 && page.success) { page.success = false; page.message = "Regional helper failed. Refresh and try again."; } }
    }
    Label { visible: !!page.message; text: page.message; color: page.success ? Style.Theme.success : Style.Theme.danger; Layout.fillWidth: true; wrapMode: Text.Wrap }
    SettingsButton { text: page.dirty ? "Discard edits & refresh" : "Refresh"; enabled: !page.busy; onClicked: page.request({operation: "status"}) }
    SettingsCard {
        title: "Application language and formats"
        subtitle: "Choose from locales generated on this machine. Application translations depend on each app. Hyprshell’s interface currently uses English."
        Layout.fillWidth: true
        Label { text: "Application language"; color: Style.Theme.text; font.pixelSize: Style.Theme.bodySize }
        SettingsComboBox { id: language; objectName: "regionalLanguage"; Layout.fillWidth: true; model: ["Use system language"].concat(page.locales); enabled: page.loaded && !page.busy }
        Label { text: "Date, time, and number formats"; color: Style.Theme.text; font.pixelSize: Style.Theme.bodySize }
        SettingsComboBox { id: formats; objectName: "regionalFormats"; Layout.fillWidth: true; model: ["Use system formats"].concat(page.locales); enabled: page.loaded && !page.busy }
        Label { text: "Your timezone (optional)"; color: Style.Theme.text; font.pixelSize: Style.Theme.bodySize }
        SettingsTextField { id: zone; objectName: "regionalTimezone"; Layout.fillWidth: true; placeholderText: "Use system timezone, or e.g. Asia/Manila"; color: Style.Theme.text; selectByMouse: true; enabled: page.loaded && !page.busy }
        Label { text: zone.text.trim() && !page.timezones.includes(zone.text.trim()) ? "Enter an installed timezone such as Asia/Manila or Europe/London." : "A personal timezone affects your apps at the next login. It does not change the hardware clock."; color: Style.Theme.muted; wrapMode: Text.Wrap; Layout.fillWidth: true }
        Flow {
            Layout.fillWidth: true; spacing: 8
            SettingsButton { objectName: "previewRegional"; text: "Preview formats"; enabled: page.loaded && !page.busy; onClicked: page.request({operation: "preview", settings: page.draft()}) }
            SettingsButton { objectName: "saveRegional"; text: "Save for next login"; highlighted: page.dirty; enabled: page.loaded && !page.busy && page.dirty; onClicked: page.request({operation: "save", settings: page.draft()}) }
        }
        Label { text: page.preview.error || [page.preview.date, page.preview.time, page.preview.zone, page.preview.number].filter(Boolean).join(" · "); color: Style.Theme.text; font.pixelSize: Style.Theme.bodySize; wrapMode: Text.Wrap; Layout.fillWidth: true }
        Label { text: "To add another language, generate its locale using your system’s locale settings, then Refresh. A manually configured LC_ALL takes precedence over these format choices."; color: Style.Theme.muted; font.pixelSize: Style.Theme.captionSize; wrapMode: Text.Wrap; Layout.fillWidth: true }
    }
    SettingsCard {
        title: "System timezone"
        subtitle: "Changes the timezone for all users and may request administrator authentication. Your personal timezone above remains independent."
        Layout.fillWidth: true
        SettingsButton { text: "Set system timezone…"; enabled: page.loaded && !page.busy && zone.text.trim() && page.timezones.includes(zone.text.trim()); onClicked: page.confirmSystemZone = true }
        Label { visible: page.confirmSystemZone; text: "Set the system timezone to “" + zone.text.trim() + "”?"; color: Style.Theme.warning; wrapMode: Text.Wrap; Layout.fillWidth: true }
        RowLayout {
            visible: page.confirmSystemZone
            SettingsButton { text: "Apply system timezone"; enabled: !page.busy; onClicked: page.request({operation: "system-timezone", timezone: zone.text.trim()}) }
            SettingsButton { text: "Cancel"; onClicked: page.confirmSystemZone = false }
        }
    }
}
