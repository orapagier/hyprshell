import QtQuick
import "style" as Style
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Quickshell.Io

ColumnLayout {
    id: page
    property string message: ""
    property bool success: true
    readonly property bool busy: worker.running
    spacing: 20

    function install() {
        if (busy) return;
        message = "Installing Hyprskill…";
        success = true;
        worker.running = true;
    }
    Process {
        id: worker
        command: ["python3", decodeURIComponent(Qt.resolvedUrl("settings/hyprskill.py").toString().replace(/^file:\/\//, "")), "--install"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let result = JSON.parse(text);
                    page.success = result.ok === true;
                    page.message = result.message;
                } catch (e) {
                    page.success = false;
                    page.message = "Could not read Hyprskill installation results.";
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: if (text) { page.success = false; page.message = text; }
        }
        onExited: (code, status) => {
            if (code !== 0 && page.success) {
                page.success = false;
                page.message = "Hyprskill installation failed. Check that your Hyprshell checkout is available.";
            }
        }
    }
    SettingsCard {
        Layout.fillWidth: true
        title: "Teach your agents about this desktop"
        subtitle: "Hyprskill helps Codex, Claude Code, and OpenCode find your desktop configuration and understand your setup from any folder. Detailed references load only when needed."
        SettingsButton {
            objectName: "installHyprskillButton"
            text: page.busy ? "Installing…" : "Install Hyprskill"
            enabled: !page.busy
            onClicked: page.install()
        }
        Label {
            Layout.fillWidth: true
            text: "Restart your agents after installing. Keep the Hyprshell checkout available; skill updates follow changes in the repository. Existing custom skills are preserved."
            wrapMode: Text.WordWrap
            color: Style.SettingsTheme.muted
        }
        Label {
            objectName: "hyprskillResult"
            Layout.fillWidth: true
            visible: page.message !== ""
            text: page.message
            wrapMode: Text.WrapAnywhere
            color: page.success ? Style.SettingsTheme.muted : Style.SettingsTheme.danger
        }
    }
}
