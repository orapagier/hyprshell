pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import "style" as Style

Popup {
    id: dialog
    objectName: "githubUpdateDialog"
    property real hostWidth: 1000
    property real hostHeight: 800
    property var review: ({})
    property string message: ""
    property bool success: true
    property bool applying: false
    property bool requesting: false
    readonly property bool busy: requesting || applying
    signal requestAction(var args)
    property string action: ""
    anchors.centerIn: parent
    width: Math.min(780, hostWidth - 40)
    height: Math.min(700, hostHeight - 50)
    padding: 22
    modal: true
    closePolicy: busy ? Popup.NoAutoClose : Popup.CloseOnEscape | Popup.CloseOnPressOutside
    background: Rectangle { color: Style.Theme.surface; radius: 14; border.color: Style.Theme.controlBorder }
    function run(args) {
        if (requesting) return;
        action = args[0];
        if (action === "--preview") {
            review = ({});
            acknowledgement.checked = false;
            message = "Fetching update details and checking this setup…";
        }
        success = true;
        requestAction(args);
    }
    onOpened: run(["--preview"])
    contentItem: ColumnLayout {
        spacing: 12
        Label { text: "Sync from GitHub"; font.pixelSize: 20; font.bold: true; color: Style.Theme.text }
        Label {
            Layout.fillWidth: true
            text: dialog.review.repository ? dialog.review.repository + " · " + dialog.review.branch : "Updates from this checkout’s GitHub tracking branch"
            textFormat: Text.PlainText
            wrapMode: Text.WrapAnywhere
            color: Style.Theme.accentText
        }
        Label {
            Layout.fillWidth: true; wrapMode: Text.Wrap
            text: dialog.message; textFormat: Text.PlainText
            color: dialog.success ? Style.Theme.muted : Style.Theme.danger
        }
        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: availableWidth
            TextArea {
                objectName: "githubUpdateReview"
                readOnly: true
                selectByMouse: true
                wrapMode: TextEdit.Wrap
                textFormat: TextEdit.PlainText
                color: Style.Theme.text
                font.pixelSize: Style.Theme.bodySize
                background: Rectangle { color: Style.Theme.field; radius: 8 }
                text: {
                    let r = dialog.review;
                    if (!r.target) return "Your settings and hardware checks will appear here before you can sync.";
                    let sections = ["Revision: " + r.base.slice(0, 12) + " → " + r.target.slice(0, 12)];
                    function add(title, rows) { if (rows && rows.length) sections.push(title + "\n" + rows.join("\n")); }
                    add("Updates", r.commits);
                    add("Compatibility checks", r.checks);
                    add("Must resolve before syncing", r.blockers);
                    add("Needs your review", r.warnings);
                    if (r.acceptance) sections.push("Validation record\n" + r.acceptance);
                    add("New package requirements", r.packagesAdded);
                    add("Packages no longer required (not automatically removed)", r.packagesRemoved);
                    add("Changed files", r.changes);
                    if (r.notes) sections.push("Release notes\n" + r.notes);
                    sections.push("Your current settings, shortcuts and display preferences will be retained. Conflicting desktop code edits block the update. Log out and back in after completion.");
                    return sections.join("\n\n");
                }
            }
        }
        CheckBox {
            id: acknowledgement
            objectName: "githubUpdateAcknowledgement"
            Layout.fillWidth: true
            visible: dialog.review.ready === true
            enabled: !dialog.busy
            text: "I reviewed the changes and hardware testing limitations."
            palette.windowText: Style.Theme.text
            Accessible.name: text
        }
        RowLayout {
            Layout.fillWidth: true
            SettingsButton {
                text: "Check again"
                enabled: !dialog.busy
                onClicked: dialog.run(["--preview"])
            }
            SettingsButton {
                text: "Update status"
                enabled: !dialog.busy
                onClicked: dialog.run(["--status"])
            }
            Item { Layout.fillWidth: true }
            SettingsButton {
                objectName: "githubUpdateConfirm"
                text: dialog.applying ? "Syncing…" : "Sync now"
                highlighted: true
                enabled: !dialog.busy && dialog.review.ready === true && acknowledgement.checked
                onClicked: dialog.run(["--apply", dialog.review.token, "--acknowledge"])
            }
            SettingsButton { text: "Close"; enabled: !dialog.busy; onClicked: dialog.close() }
        }
    }
}
