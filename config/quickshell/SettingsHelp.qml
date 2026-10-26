pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Quickshell.Io
import "style" as Style

ColumnLayout {
    id: page
    property bool guideComplete: false
    property var report: null
    property string reportPath: ""
    property string message: ""
    property string buildLabel: "Hyprshell Rolling"
    property bool success: true
    readonly property bool busy: worker.running
    signal navigate(int section)
    signal guideFinished()
    spacing: 16
    Component.onCompleted: if (visible) request("status")
    onVisibleChanged: if (visible && !busy) request("status")
    function request(operation) {
        if (busy) return;
        worker.command = ["python3", decodeURIComponent(Qt.resolvedUrl("settings/diagnostics.py").toString().replace(/^file:\/\//, "")), "--request-json", JSON.stringify({operation: operation})]; worker.running = true;
    }
    Process {
        id: worker
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let result = JSON.parse(text); page.success = result.ok; page.message = result.message || "";
                    if (result.build) page.buildLabel = result.build.label;
                    if (result.guideComplete !== undefined) { page.guideComplete = result.guideComplete; if (page.guideComplete) page.guideFinished(); }
                    if (result.report) page.report = result.report;
                    if (result.path) page.reportPath = result.path;
                } catch (e) { page.success = false; page.message = "Could not read desktop checks. Try again."; }
            }
        }
        onExited: (code, status) => { if (code !== 0 && page.success) { page.success = false; page.message = "Desktop checks could not finish. Try again."; } }
    }
    Label { visible: !!page.message; text: page.message; color: page.success ? Style.SettingsTheme.success : Style.SettingsTheme.danger; Layout.fillWidth: true; wrapMode: Text.Wrap }
    Label { objectName: "hyprshellBuild"; text: page.buildLabel; color: Style.SettingsTheme.muted; Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText }
    SettingsCard {
        title: page.guideComplete ? "Getting-started guide" : "Welcome to your daily desktop"
        subtitle: "Work through the essentials at your own pace. Changes use the same saved Settings you can sync to GitHub."
        Layout.fillWidth: true
        Repeater {
            model: [
                {title: "1. Get connected", detail: "Use the bar’s Wi-Fi and Bluetooth menus. Network settings handles saved connections, hidden networks and VPNs.", page: -15},
                {title: "2. Make the screen comfortable", detail: "Check display scale and refresh rate. Display changes roll back unless you confirm them.", page: -7},
                {title: "3. Choose your applications", detail: "Set apps for links and files. Startup choices take effect at your next login.", page: -13},
                {title: "4. Protect your session", detail: "Choose automatic locking and before-sleep locking. Test the lock screen while you can unlock it.", page: -3},
                {title: "5. Keep a recovery path", detail: "Create desktop checkpoints and a personal-file backup. GitHub sync saves configuration; it does not save your documents.", page: -14},
                {title: "6. Make it your own", detail: "Adjust text, contrast and motion. Super+K shows your shortcuts; Ctrl+F searches Settings.", page: -16}
            ]
            delegate: ColumnLayout {
                id: step
                required property var modelData
                Layout.fillWidth: true
                Label { text: step.modelData.title; color: Style.SettingsTheme.text; font.bold: true; font.pixelSize: Style.SettingsTheme.bodySize; Layout.fillWidth: true; wrapMode: Text.Wrap }
                Label { text: step.modelData.detail; color: Style.SettingsTheme.muted; font.pixelSize: Style.SettingsTheme.captionSize; Layout.fillWidth: true; wrapMode: Text.Wrap }
                SettingsButton { text: "Open settings"; onClicked: page.navigate(step.modelData.page) }
            }
        }
        SettingsButton { objectName: "finishWelcomeGuide"; text: page.guideComplete ? "Guide completed" : "Finish getting started"; enabled: !page.busy && !page.guideComplete; onClicked: page.request("guide-complete") }
    }
    SettingsCard {
        title: "Desktop health and diagnostics"
        subtitle: "Checks run only when requested. Reports include service states, tool availability and basic system versions. They exclude personal names, network addresses, notification/clipboard contents, raw logs and configuration files. Nothing is uploaded."
        Layout.fillWidth: true
        Flow {
            Layout.fillWidth: true; spacing: 8
            SettingsButton { objectName: "runDesktopChecks"; text: page.busy ? "Checking…" : "Run desktop checks"; enabled: !page.busy; onClicked: page.request("check") }
            SettingsButton { objectName: "exportDesktopReport"; text: "Save diagnostic report"; enabled: !page.busy; onClicked: page.request("export") }
        }
        Repeater {
            model: page.report ? page.report.checks : []
            delegate: ColumnLayout {
                id: checkRow
                required property var modelData
                Layout.fillWidth: true
                Label { text: checkRow.modelData.title + " · " + ({ok: "Ready", attention: "Needs attention", unavailable: "Unavailable", inactive: "Inactive"})[checkRow.modelData.state]; color: checkRow.modelData.state === "ok" ? Style.SettingsTheme.success : checkRow.modelData.state === "attention" ? Style.SettingsTheme.warning : Style.SettingsTheme.muted; font.pixelSize: Style.SettingsTheme.bodySize; Layout.fillWidth: true; wrapMode: Text.Wrap }
                Label { text: checkRow.modelData.hint; color: Style.SettingsTheme.muted; font.pixelSize: Style.SettingsTheme.captionSize; Layout.fillWidth: true; wrapMode: Text.Wrap }
                SettingsButton { visible: checkRow.modelData.state === "attention"; text: "Open related settings"; onClicked: page.navigate(checkRow.modelData.page) }
            }
        }
        Label { visible: !!page.reportPath; text: page.reportPath; color: Style.SettingsTheme.muted; font.pixelSize: Style.SettingsTheme.captionSize; Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText }
        SettingsButton { visible: !!page.reportPath; text: "Review saved report"; onClicked: Qt.openUrlExternally("file://" + page.reportPath) }
    }
}
