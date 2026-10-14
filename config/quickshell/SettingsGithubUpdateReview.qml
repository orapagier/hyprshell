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
    property var conflictChoices: ({})
    property string message: ""
    property bool success: true
    property bool applying: false
    property bool requesting: false
    property bool dependenciesStarted: false
    property bool installingDependencies: false
    property string dependencyOutput: ""
    property bool checkAfterStatus: false
    readonly property bool busy: requesting || applying || installingDependencies
    signal requestAction(var args)
    property string action: ""
    anchors.centerIn: parent
    width: Math.min(780, hostWidth - 40)
    height: Math.min(700, hostHeight - 50)
    padding: 22
    modal: true
    closePolicy: requesting || applying ? Popup.NoAutoClose : Popup.CloseOnEscape | Popup.CloseOnPressOutside
    background: Rectangle { color: Style.Theme.surface; radius: 14; border.color: Style.Theme.controlBorder }
    function run(args) {
        if (requesting) return;
        action = args[0];
        if (action === "--preview" || action === "--resolve") {
            dependencyApproval.checked = false;
            dependenciesStarted = false;
            dependencyOutput = "";
        }
        if (action === "--preview") {
            review = ({});
            conflictChoices = ({});
            acknowledgement.checked = false;
            message = "Checking the developer’s GitHub repository for updates missing from this machine…";
        }
        success = true;
        requestAction(args);
    }
    function choose(path, value) {
        let next = Object.assign({}, conflictChoices);
        next[path] = value;
        conflictChoices = next;
    }
    readonly property bool choicesComplete: {
        let rows = review.conflicts || [];
        return rows.length > 0 && rows.every(row => conflictChoices[row.path] === "local" || conflictChoices[row.path] === "github");
    }
    readonly property bool choicesReviewed: (review.conflicts || []).every(row => row.choice && row.choice === conflictChoices[row.path])
    onOpened: { checkAfterStatus = true; run(["--status"]); }
    contentItem: ColumnLayout {
        spacing: 12
        Label { text: "Sync from GitHub"; font.pixelSize: 20; font.bold: true; color: Style.Theme.text }
        Label {
            Layout.fillWidth: true
            objectName: "githubUpdateSource"
            text: "You are updating from the developer’s GitHub repository: " + (dialog.review.repository ? dialog.review.repository + " · " + dialog.review.branch : "https://github.com/orapagier/hyprshell.git · main")
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
            id: reviewScroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: availableWidth
            ColumnLayout {
                width: reviewScroll.availableWidth
                spacing: 14
            TextArea {
                Layout.fillWidth: true
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
                    add("Missing installed dependencies", r.missingPackages);
                    add("Packages no longer required (not automatically removed)", r.packagesRemoved);
                    add("Changed files", r.changes);
                    if (r.notes) sections.push("Release notes\n" + r.notes);
                    sections.push("Local changes are preserved where they combine with the update. Choose the full file to keep for each conflict, then review your choices. Checking and updating do not commit your unsynced edits. Log out and back in after completion.");
                    return sections.join("\n\n");
                }
            }
            SettingsCard {
                Layout.fillWidth: true
                visible: (dialog.review.missingPackages || []).length > 0 || dialog.dependenciesStarted
                title: "Install missing dependencies"
                subtitle: (dialog.review.dependencyNote || "") + " Your confirmation allows installation of these packages and their required dependencies. Administrator authorization uses the desktop password prompt."
                Label {
                    Layout.fillWidth: true; wrapMode: Text.Wrap
                    text: (dialog.review.missingPackages || []).join(", ")
                    textFormat: Text.PlainText; color: Style.Theme.text
                }
                TextArea {
                    objectName: "githubDependencyCommand"
                    Layout.fillWidth: true; wrapMode: TextEdit.Wrap
                    text: dialog.review.dependencyCommand || ""
                    textFormat: TextEdit.PlainText
                    readOnly: true; selectByMouse: true
                    font.family: "monospace"; color: Style.Theme.text
                    background: Rectangle { color: Style.Theme.field; radius: 6 }
                }
                Label {
                    Layout.fillWidth: true; wrapMode: Text.Wrap
                    text: dialog.installingDependencies ? "Installation runs in the background and continues if you close this window. Compatibility is checked again after success." : dialog.dependenciesStarted ? "Review the result above and the output below. Choose Check again before retrying or syncing." : dialog.review.canInstallDependencies ? "Confirm below to install in the background. The desktop update is applied only after a new compatibility review." : "Resolve the other update review issues and review your conflict choices before installing here."
                    color: Style.Theme.muted
                }
                CheckBox {
                    id: dependencyApproval
                    objectName: "githubDependencyApproval"
                    text: "I allow this package installation" + (dialog.review.dependencyFullUpgrade ? " and full system upgrade." : ".")
                    enabled: !dialog.busy && !dialog.dependenciesStarted && dialog.review.canInstallDependencies === true
                    palette.windowText: Style.Theme.text
                    Accessible.name: text
                }
                SettingsButton {
                    objectName: "githubDependencyInstall"
                    text: dialog.installingDependencies ? "Installing…" : "Install dependencies"
                    enabled: !dialog.busy && !dialog.dependenciesStarted && dialog.review.canInstallDependencies === true && dependencyApproval.checked
                    onClicked: dialog.run(["--install-dependencies", dialog.review.token, "--acknowledge"])
                }
                BusyIndicator { running: dialog.installingDependencies; visible: running }
                ScrollView {
                    Layout.fillWidth: true; Layout.preferredHeight: 160
                    visible: dialog.dependencyOutput !== ""
                    clip: true
                    TextArea {
                        objectName: "githubDependencyOutput"
                        text: dialog.dependencyOutput; textFormat: TextEdit.PlainText
                        readOnly: true; selectByMouse: true; wrapMode: TextEdit.Wrap
                        color: Style.Theme.text; font.family: "monospace"
                        background: Rectangle { color: Style.Theme.field; radius: 6 }
                    }
                }
            }
            Repeater {
                model: dialog.review.conflicts || []
                delegate: ColumnLayout {
                    id: conflict
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 8
                    Label { text: conflict.modelData.path; textFormat: Text.PlainText; wrapMode: Text.WrapAnywhere; color: Style.Theme.accentText; Layout.fillWidth: true }
                    Label { text: "This choice keeps the entire file, including a deletion."; color: Style.Theme.muted; Layout.fillWidth: true; wrapMode: Text.Wrap }
                    RowLayout {
                        Layout.fillWidth: true
                        Repeater {
                            model: ["local", "github"]
                            delegate: ColumnLayout {
                                id: version
                                required property string modelData
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                CheckBox {
                                    objectName: version.modelData === "local" ? "githubConflictKeepLocal" : "githubConflictUseDeveloper"
                                    text: version.modelData === "local" ? "Keep your local version" : "Use developer’s version"
                                    checked: dialog.conflictChoices[conflict.modelData.path] === version.modelData
                                    enabled: !dialog.busy
                                    palette.windowText: Style.Theme.text
                                    Accessible.name: text + " for " + conflict.modelData.path
                                    onClicked: dialog.choose(conflict.modelData.path, checked ? version.modelData : "")
                                }
                                ScrollView {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 160
                                    clip: true
                                    TextArea {
                                        text: conflict.modelData[version.modelData]
                                        textFormat: TextEdit.PlainText
                                        readOnly: true
                                        selectByMouse: true
                                        wrapMode: TextEdit.Wrap
                                        color: Style.Theme.text
                                        background: Rectangle { color: Style.Theme.field; radius: 6 }
                                    }
                                }
                            }
                        }
                    }
                    Label {
                        text: "Differences (− local, + developer)"
                        color: Style.Theme.text
                    }
                    ScrollView {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 140
                        clip: true
                        TextArea {
                            objectName: "githubConflictDiff"
                            text: conflict.modelData.diff || "Compare the versions above."
                            textFormat: TextEdit.PlainText
                            readOnly: true
                            selectByMouse: true
                            wrapMode: TextEdit.Wrap
                            font.family: "monospace"
                            color: Style.Theme.text
                            background: Rectangle { color: Style.Theme.field; radius: 6 }
                        }
                    }
                }
            }
            SettingsButton {
                objectName: "githubConflictReview"
                text: "Review choices"
                visible: (dialog.review.conflicts || []).length > 0
                enabled: !dialog.busy && dialog.choicesComplete
                onClicked: {
                    acknowledgement.checked = false;
                    dialog.run(["--resolve", dialog.review.token, "--choices-json", JSON.stringify(dialog.conflictChoices)]);
                }
            }
            }
        }
        CheckBox {
            id: acknowledgement
            objectName: "githubUpdateAcknowledgement"
            Layout.fillWidth: true
            visible: dialog.review.ready === true && dialog.choicesReviewed
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
                enabled: !dialog.busy && !dialog.dependenciesStarted && dialog.review.ready === true && dialog.choicesReviewed && acknowledgement.checked
                onClicked: dialog.run(["--apply", dialog.review.token, "--acknowledge"])
            }
            SettingsButton { objectName: "githubUpdateClose"; text: "Close"; enabled: !dialog.requesting && !dialog.applying; onClicked: dialog.close() }
        }
    }
}
