import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Quickshell.Io
import "style" as Style

ColumnLayout {
    id: page
    property var tools: ({})
    property string message: ""
    property string details: ""
    property bool success: true
    property bool confirmEnable: false
    readonly property bool busy: worker.running
    spacing: 16
    Component.onCompleted: request("status")
    function request(operation) {
        if (busy) return;
        worker.command = ["python3", decodeURIComponent(Qt.resolvedUrl("settings/peripherals.py").toString().replace(/^file:\/\//, "")), "--request-json", JSON.stringify({operation: operation, confirmed: confirmEnable})]; worker.running = true;
    }
    Process {
        id: worker
        stdout: StdioCollector { onStreamFinished: {
            try { let result = JSON.parse(text); page.success = result.ok; page.message = result.message || ""; page.details = result.details || ""; if (result.tools) page.tools = result.tools; page.confirmEnable = false; }
            catch (e) { page.success = false; page.message = "Could not read printing and scanning controls. Refresh to retry."; }
        } }
    }
    SettingsCard {
        title: "Printers"
        subtitle: "Configure printers and manage queues in the system printer tool. No printing service is enabled automatically."
        Layout.fillWidth: true
        Flow {
            Layout.fillWidth: true; spacing: 8
            SettingsButton { text: "Open printer settings"; enabled: !!page.tools["system-config-printer"] && !page.busy; onClicked: page.request("printers") }
            SettingsButton { text: "Check queues"; enabled: !!page.tools.lpstat && !page.busy; onClicked: page.request("check-printers") }
            SettingsButton { text: "Enable printing on demand…"; enabled: !!page.tools.lpstat && !page.busy; onClicked: page.confirmEnable = true }
        }
        SettingsLabel { visible: page.confirmEnable; text: "Enable the CUPS socket at boot and now? Administrator authentication happens in the terminal. The server starts when a client requests printing."; color: Style.Theme.text; Layout.fillWidth: true; wrapMode: Text.Wrap }
        RowLayout {
            visible: page.confirmEnable
            SettingsButton { text: "Enable printing…"; enabled: !page.busy; onClicked: page.request("enable-printing") }
            SettingsButton { text: "Cancel"; onClicked: page.confirmEnable = false }
        }
    }
    SettingsCard {
        title: "Scanners"
        subtitle: "Document Scanner handles previews, scanning and PDF export. Discovery runs only when requested; some devices need extra drivers."
        Layout.fillWidth: true
        Flow {
            Layout.fillWidth: true; spacing: 8
            SettingsButton { text: "Open Document Scanner"; enabled: !!page.tools["simple-scan"] && !page.busy; onClicked: page.request("scanner") }
            SettingsButton { text: "Find scanners"; enabled: !!page.tools.scanimage && !page.busy; onClicked: page.request("check-scanners") }
        }
    }
    Flow {
        Layout.fillWidth: true; spacing: 8
        SettingsButton { visible: !page.tools["system-config-printer"] || !page.tools["simple-scan"]; text: "Install printing & scanning tools…"; enabled: !page.busy; onClicked: page.request("install") }
        SettingsButton { objectName: "refreshPeripherals"; text: "Refresh tool availability"; enabled: !page.busy; onClicked: page.request("status") }
    }
    SettingsLabel { visible: page.busy; text: "Working… Device discovery can take a few seconds."; color: Style.Theme.muted; Layout.fillWidth: true; wrapMode: Text.Wrap }
    SettingsLabel { text: page.message; visible: !!text; color: page.success ? Style.Theme.success : Style.Theme.danger; Layout.fillWidth: true; wrapMode: Text.Wrap }
    SettingsLabel { text: page.details; textFormat: Text.PlainText; visible: !!text; color: Style.Theme.text; Layout.fillWidth: true; wrapMode: Text.Wrap }
}
