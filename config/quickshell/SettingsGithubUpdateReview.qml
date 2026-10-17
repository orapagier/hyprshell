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
    readonly property var reviewRows: (review.selections || []).concat(review.conflicts || [])
    function choiceFor(row) {
        return conflictChoices[row.path] === undefined ? row.choice : conflictChoices[row.path];
    }
    function reviewedChoices() {
        let values = ({});
        for (let row of reviewRows) values[row.path] = choiceFor(row);
        return values;
    }
    function choosePreferences(value) {
        let next = Object.assign({}, conflictChoices);
        for (let row of review.selections || []) {
            if (row.preference) next[row.path] = value;
        }
        conflictChoices = next;
    }
    readonly property bool choicesComplete: {
        let rows = reviewRows;
        return rows.length > 0 && rows.every(row => choiceFor(row) === "local" || choiceFor(row) === "github");
    }
    readonly property bool choicesReviewed: reviewRows.every(row => row.choice && row.choice === choiceFor(row))
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
                    sections.push("Personal preferences stay yours unless you choose the developer’s version. Independent configurations can be selected below. Core shell files update together; conflicting core files still require a choice. Review any changed choices before syncing. Checking and updating do not commit your unsynced edits. Log out and back in after completion.");
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
                    enabled: !dialog.busy && !dialog.dependenciesStarted && dialog.review.canInstallDependencies === true && dialog.choicesReviewed
                    palette.windowText: Style.Theme.text
                    Accessible.name: text
                }
                SettingsButton {
                    objectName: "githubDependencyInstall"
                    text: dialog.installingDependencies ? "Installing…" : "Install dependencies"
                    enabled: !dialog.busy && !dialog.dependenciesStarted && dialog.review.canInstallDependencies === true && dialog.choicesReviewed && dependencyApproval.checked
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
            SettingsCard {
                Layout.fillWidth: true
                visible: (dialog.review.selections || []).length > 0
                title: "Personal preferences and configuration updates"
                subtitle: "Keep my preferences is the default. Choose individual categories below, or adopt all developer preferences. Generated files follow their source. Display choices depend on your hardware. Core shell files update together."
                RowLayout {
                    SettingsButton {
                        objectName: "githubKeepPreferences"
                        text: "Keep my preferences"
                        enabled: !dialog.busy
                        onClicked: dialog.choosePreferences("local")
                    }
                    SettingsButton {
                        objectName: "githubUsePreferences"
                        text: "Use developer preferences"
                        enabled: !dialog.busy
                        onClicked: dialog.choosePreferences("github")
                    }
                }
            }
            Repeater {
                model: dialog.reviewRows
                delegate: ColumnLayout {
                    id: conflict
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 8
                    Label { text: conflict.modelData.label || conflict.modelData.path; textFormat: Text.PlainText; wrapMode: Text.WrapAnywhere; color: Style.Theme.accentText; Layout.fillWidth: true }
                    Label { text: (conflict.modelData.preference ? "Personal preference. " : "") + "This choice keeps the entire file or category, including deletions. Files: " + (conflict.modelData.files || [conflict.modelData.path]).join(", "); color: Style.Theme.muted; Layout.fillWidth: true; wrapMode: Text.Wrap }
                    CheckBox {
                        id: comparison
                        text: "Show comparison"
                        palette.windowText: Style.Theme.text
                    }
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
                                    checked: dialog.choiceFor(conflict.modelData) === version.modelData
                                    enabled: !dialog.busy
                                    palette.windowText: Style.Theme.text
                                    Accessible.name: text + " for " + conflict.modelData.path
                                    onClicked: dialog.choose(conflict.modelData.path, checked ? version.modelData : "")
                                }
                                ScrollView {
                                    visible: comparison.checked
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 160
                                    clip: true
                                    TextArea {
                                        text: conflict.modelData[version.modelData] || ""
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
                        visible: comparison.checked
                        text: "Differences (− local, + developer)"
                        color: Style.Theme.text
                    }
                    ScrollView {
                        visible: comparison.checked
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
                visible: dialog.reviewRows.length > 0
                enabled: !dialog.busy && dialog.choicesComplete
                onClicked: {
                    acknowledgement.checked = false;
                    dialog.run(["--resolve", dialog.review.token, "--choices-json", JSON.stringify(dialog.reviewedChoices())]);
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
