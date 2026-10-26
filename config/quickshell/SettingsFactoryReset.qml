import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Quickshell.Io
import "style" as Style

SettingsCard {
    id: page
    property bool ready: true
    property var preview: null
    property string message: ""
    property bool success: true
    property bool starting: false
    readonly property bool busy: worker.running || starting
    signal restored(var settings)
    title: "Reset & factory reset"
    subtitle: "Choose the scope. Cleaning files frees storage; resetting settings changes preferences; a full factory reset reinstalls the operating system."
    onVisibleChanged: if (!visible) { preview = null; confirmation.text = ""; }
    function request(operation) {
        if (busy || !ready) return;
        let payload = {operation: operation, token: preview ? preview.token : "", confirmation: confirmation.text};
        worker.command = ["python3", decodeURIComponent(Qt.resolvedUrl("settings/system_cleanup.py").toString().replace(/^file:\/\//, "")), "--request-json", JSON.stringify(payload)];
        starting = true; message = ""; worker.running = true;
    }
    Process {
        id: worker
        onExited: (code, status) => { page.starting = false; if (code !== 0 && !page.message) { page.success = false; page.message = "Reset could not finish. Preview again."; page.preview = null; } }
        stdout: StdioCollector { onStreamFinished: {
            try {
                let result = JSON.parse(text);
                page.success = result.ok; page.message = result.message || "";
                page.preview = result.ok ? result.preview || null : null;
                if (result.ok && result.restored) { confirmation.text = ""; page.restored(result.restored); }
            } catch (e) { page.success = false; page.preview = null; page.message = "Could not read reset results."; }
        } }
        stderr: StdioCollector {}
    }
    SettingsComboBox {
        id: scope
        objectName: "factoryResetScope"
        Layout.fillWidth: true
        model: ["Reset Hyprshell settings", "Full factory reset / clean OS installation"]
        enabled: !page.busy
        onActivated: { page.preview = null; confirmation.text = ""; }
    }
    SettingsLabel {
        Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText
        text: scope.currentIndex === 0 ? "Resets saved bar layout, item appearance, compositor overrides, mouse/keyboard preferences, notifications, locking, power, accessibility and clipboard capture preferences to Hyprshell defaults. Creates an undo checkpoint first. Documents, installed apps, browser data, separate theme/display/shortcut/app preferences and manual configuration files are preserved." : "A full factory reset means returning to a clean operating system installation. Linux has no universal factory image for this laptop. Boot from OS installation media and reinstall; formatting a partition erases its accounts, applications, settings, files, VM disks and containers. Keeping a home partition keeps old data and is not a full reset. This panel explains the process; it does not erase disks or reinstall the OS."
        color: scope.currentIndex === 0 ? Style.SettingsTheme.text : Style.SettingsTheme.warning
    }
    SettingsLabel {
        visible: scope.currentIndex === 1
        Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText; color: Style.SettingsTheme.text
        text: "Before reinstalling:\n1. Back up documents, credentials/recovery keys, Windows VM data and anything you need from containers to another drive. Verify that the backup opens.\n2. Use Updates & recovery to checkpoint your desktop configuration and save it outside the disk being erased.\n3. Create bootable installation media for your chosen OS and boot it.\n4. Review the exact disks and partitions selected by the installer before formatting.\n5. Reinstall Hyprshell and restore only the data and preferences you want.\n\nA local checkpoint on the erased disk will also be lost. Cache cleanup cannot produce the same result."
    }
    SettingsButton { objectName: "previewSettingsReset"; visible: scope.currentIndex === 0; text: "Preview settings reset…"; enabled: page.ready && !page.busy; onClicked: { confirmation.text = ""; page.request("reset-preview"); } }
    SettingsLabel { visible: page.preview !== null; Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText; color: Style.SettingsTheme.warning; text: page.preview ? "Preferences to reset: " + (page.preview.changes.join(", ") || "Already at defaults") + ".\nType RESET to confirm. Recover the previous preferences from Updates & recovery → Desktop settings recovery." : "" }
    SettingsTextField { id: confirmation; objectName: "settingsResetConfirmation"; visible: page.preview !== null; enabled: !page.busy; placeholderText: "Type RESET"; Accessible.name: "Confirm settings reset" }
    RowLayout {
        visible: page.preview !== null
        SettingsButton { objectName: "confirmSettingsReset"; text: "Reset Hyprshell settings"; highlighted: true; enabled: page.ready && !page.busy && confirmation.text === "RESET" && page.preview !== null && page.preview.changes.length > 0; onClicked: page.request("reset") }
        SettingsButton { text: "Cancel"; enabled: !page.busy; onClicked: { page.preview = null; confirmation.text = ""; } }
    }
    SettingsLabel { visible: !page.ready; Layout.fillWidth: true; wrapMode: Text.Wrap; color: Style.SettingsTheme.warning; text: "Save or discard other Settings edits before resetting preferences." }
    SettingsLabel { visible: !!page.message; Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText; text: page.message; color: page.success ? Style.SettingsTheme.success : Style.SettingsTheme.danger }
}
