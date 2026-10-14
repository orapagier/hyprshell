pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Quickshell.Io
import "style" as Style

ColumnLayout {
    id: page
    property bool administrator: false
    property var groups: []
    property var selected: []
    property var preview: null
    property var excluded: []
    property var fileEntries: []
    property int fileOffset: 0
    property int days: administrator ? 7 : 0
    property int keep: 5
    property string folder: ""
    property string message: ""
    property string details: ""
    property bool success: true
    property bool loaded: false
    property bool starting: false
    readonly property bool busy: worker.running || starting
    readonly property bool actionable: preview !== null && (preview.totalFiles > excluded.length || preview.groups.some(row => row.policy === "command" && !row.blocked))
    spacing: 16
    Component.onCompleted: request("catalog")
    function size(value) { return value >= 1073741824 ? (value / 1073741824).toFixed(2) + " GiB" : (value / 1048576).toFixed(2) + " MiB"; }
    function toggle(ident, checked) {
        selected = checked ? selected.concat([ident]) : selected.filter(value => value !== ident);
        preview = null;
    }
    function request(operation, offset) {
        if (busy) return;
        let payload = {operation: operation, selected: selected, days: days, keep: keep, folder: folder,
                       token: preview ? preview.token : "", excluded: excluded, offset: offset || 0, confirmed: operation === "clean"};
        let path = decodeURIComponent(Qt.resolvedUrl("settings/system_cleanup.py").toString().replace(/^file:\/\//, ""));
        // Catalog is read-only and never requests authentication. A separate system
        // catalog request uses --system through Python below without privileged work.
        if (administrator && operation !== "catalog")
            worker.command = ["pkexec", "/usr/bin/python3", path, "--system", "--request-json", JSON.stringify(payload)];
        else {
            if (administrator) payload.operation = "system-catalog";
            worker.command = ["python3", path, "--request-json", JSON.stringify(payload)];
        }
        if (operation !== "clean" && operation !== "files") { preview = null; excluded = []; fileEntries = []; fileOffset = 0; }
        message = ""; details = ""; starting = true; worker.running = true;
    }
    Process {
        id: worker
        onExited: (code, status) => {
            page.starting = false;
            if (code !== 0 && !page.message) {
                page.success = false;
                page.message = page.administrator ? "Authentication cancelled or cleanup could not finish. Preview again to check the current files." : "Cleanup could not finish. Preview again to check the current files.";
                page.preview = null;
            }
        }
        stdout: StdioCollector { onStreamFinished: {
            if (!text.trim()) return;
            try {
                let result = JSON.parse(text);
                page.success = result.ok; page.message = result.message || "";
                if (result.groups) { page.groups = result.groups; page.loaded = true; }
                if (result.filePage) { page.fileEntries = result.filePage.entries; page.fileOffset = result.filePage.offset; }
                else {
                    page.preview = result.ok ? result.preview || null : null;
                    page.fileEntries = page.preview ? page.preview.entries : [];
                }
                page.details = (result.errors || []).join("\n") + (result.actions || []).map(row => "\n" + row.title + ": " + (row.ok ? "completed" : "failed") + "\n" + row.output).join("\n");
            } catch (e) { page.success = false; page.preview = null; page.message = "Could not read cleanup results. Preview again."; }
        } }
        stderr: StdioCollector {}
    }
    SettingsCard {
        Layout.fillWidth: true
        title: page.administrator ? "System files · administrator access" : "Clean now · your files"
        subtitle: page.administrator ? "Select system maintenance categories. Preview and cleanup each request administrator authentication. Tools use their stated retention policies." : "Turn on the categories you want, then Analyze & preview below. Recent files are included by default (age 0). Close browsers before previewing their caches. These choices do not change your automatic cleanup schedule."
        Repeater {
            model: page.groups
            delegate: ColumnLayout {
                id: target
                required property var modelData
                Layout.fillWidth: true
                spacing: 4
                SettingsSwitch {
                    objectName: (page.administrator ? "systemCleanup-" : "userCleanup-") + target.modelData.id
                    Layout.fillWidth: true
                    text: target.modelData.title
                    checked: page.selected.indexOf(target.modelData.id) >= 0
                    enabled: !page.busy
                    onClicked: page.toggle(target.modelData.id, checked)
                }
                SettingsLabel {
                    Layout.fillWidth: true
                    text: target.modelData.paths.join("\n") || "Choose an existing non-hidden folder in your home below."
                    color: Style.Theme.muted; wrapMode: Text.WrapAnywhere; textFormat: Text.PlainText
                }
                SettingsLabel {
                    Layout.fillWidth: true
                    text: (target.modelData.risk === "low" ? "Rebuildable · " : target.modelData.risk === "history" ? "Troubleshooting history · " : target.modelData.risk === "recovery" ? "Recovery history · " : "Personal recovery copies · ") + target.modelData.impact
                    color: target.modelData.risk === "low" ? Style.Theme.muted : Style.Theme.warning
                    wrapMode: Text.WordWrap; textFormat: Text.PlainText
                }
            }
        }
        SettingsTextField {
            objectName: "cleanupChosenFolder"
            visible: page.selected.indexOf("chosen-folder") >= 0
            Layout.fillWidth: true
            placeholderText: "Example: ~/Documents or ~/Downloads"
            enabled: !page.busy
            text: page.folder
            onTextEdited: { page.folder = text; page.preview = null; }
            Accessible.name: "Folder containing backup or temporary copies"
        }
        RowLayout {
            Layout.fillWidth: true
            SettingsLabel { text: "Minimum file age (days)"; Layout.fillWidth: true; wrapMode: Text.Wrap }
            SpinBox { objectName: page.administrator ? "systemCleanupAge" : "userCleanupAge"; from: 0; to: 365; value: page.days; enabled: !page.busy; onValueModified: { page.days = value; page.preview = null; } }
        }
        SettingsLabel { Layout.fillWidth: true; text: "0 includes recent files. Otherwise files must be untouched for this many days. System package, temporary and journal tools use their own policies."; color: Style.Theme.muted; wrapMode: Text.Wrap }
        RowLayout {
            Layout.fillWidth: true
            SettingsLabel { text: "Keep newest backup sets"; Layout.fillWidth: true; wrapMode: Text.Wrap }
            SpinBox { objectName: page.administrator ? "systemCleanupKeep" : "userCleanupKeep"; from: 1; to: 100; value: page.keep; enabled: !page.busy; onValueModified: { page.keep = value; page.preview = null; } }
        }
        RowLayout {
            SettingsButton { objectName: page.administrator ? "previewSystemCleanup" : "previewUserCleanup"; text: page.busy ? "Working…" : "Analyze & preview…"; enabled: page.loaded && page.selected.length > 0 && !page.busy; onClicked: page.request("preview") }
            SettingsButton { text: "Select none"; enabled: !page.busy && page.selected.length > 0; onClicked: { page.selected = []; page.preview = null; } }
        }
    }
    SettingsCard {
        Layout.fillWidth: true
        visible: page.preview !== null
        title: "Review before cleanup"
        subtitle: "Deletion is permanent. Only the reviewed categories are included. If eligible files change or five minutes pass, analyze again."
        Repeater {
            model: page.preview ? page.preview.groups : []
            delegate: SettingsLabel {
                required property var modelData
                Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText
                text: modelData.title + " · " + (modelData.blocked ? "Skipped" : page.size(modelData.bytes) + (modelData.estimate ? " observed; reclaimed space depends on the tool's policy" : " · " + modelData.count + " eligible files")) + "\n" + modelData.paths.join("\n") + "\n" + modelData.impact + (modelData.emptyReason ? "\n" + modelData.emptyReason : "") + (modelData.command ? "\nAction: " + modelData.command.join(" ") : "") + (modelData.warnings.length ? "\n" + modelData.warnings.join("\n") : "")
                color: modelData.blocked || modelData.warnings.length ? Style.Theme.warning : Style.Theme.text
            }
        }
        SettingsLabel { Layout.fillWidth: true; wrapMode: Text.Wrap; text: page.preview ? (page.preview.totalFiles - page.excluded.length) + " individual files selected, plus the listed maintenance actions. Space estimates may overlap and can differ from recovered disk space." : ""; color: Style.Theme.warning }
        ScrollView {
            Layout.fillWidth: true; Layout.preferredHeight: 200; clip: true
            visible: page.preview !== null && page.preview.totalFiles > 0
            ColumnLayout {
                width: parent.width
                Repeater {
                    model: page.fileEntries
                    delegate: SettingsCheckBox {
                        id: fileChoice
                        required property var modelData
                        Layout.fillWidth: true
                        text: modelData.size + " bytes · " + modelData.path
                        implicitHeight: Math.max(38, contentItem.implicitHeight + 12)
                        contentItem: Text {
                            text: fileChoice.text
                            color: Style.Theme.text
                            font.pixelSize: Style.Theme.captionSize
                            leftPadding: fileChoice.indicator.width + fileChoice.spacing
                            wrapMode: Text.WrapAnywhere
                            verticalAlignment: Text.AlignVCenter
                        }
                        checked: page.excluded.indexOf(modelData.path) < 0
                        enabled: !page.busy
                        onClicked: page.excluded = checked ? page.excluded.filter(path => path !== fileChoice.modelData.path) : page.excluded.concat([modelData.path])
                    }
                }
            }
        }
        RowLayout {
            visible: page.preview !== null && page.preview.totalFiles > 200
            SettingsButton { text: "Previous files"; enabled: !page.busy && page.fileOffset > 0; onClicked: page.request("files", page.fileOffset - 200) }
            SettingsLabel { text: page.preview ? (page.fileOffset + 1) + "–" + Math.min(page.fileOffset + 200, page.preview.totalFiles) + " of " + page.preview.totalFiles : ""; color: Style.Theme.muted }
            SettingsButton { text: "Next files"; enabled: !page.busy && page.preview !== null && page.fileOffset + 200 < page.preview.totalFiles; onClicked: page.request("files", page.fileOffset + 200) }
        }
        SettingsLabel { visible: page.preview !== null && page.preview.totalFiles > 200; Layout.fillWidth: true; wrapMode: Text.Wrap; text: "Files on other pages remain selected unless unchecked. The selected file count above includes all pages."; color: Style.Theme.warning }
        SettingsButton { visible: page.preview !== null && !!page.preview.listPath; text: "Open full file list"; onClicked: Qt.openUrlExternally("file://" + page.preview.listPath) }
        RowLayout {
            SettingsButton { objectName: page.administrator ? "confirmSystemCleanup" : "confirmUserCleanup"; text: "Confirm cleanup"; highlighted: true; enabled: page.actionable && !page.busy; onClicked: page.request("clean") }
            SettingsButton { text: "Cancel"; enabled: !page.busy; onClicked: page.preview = null }
        }
    }
    SettingsLabel { visible: !!page.message; Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText; text: page.message; color: page.success ? Style.Theme.success : Style.Theme.danger }
    SettingsLabel { visible: !!page.details; Layout.fillWidth: true; wrapMode: Text.WrapAnywhere; textFormat: Text.PlainText; text: page.details; color: Style.Theme.muted }
}
