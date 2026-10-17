import QtQuick
import QtTest
import ".."

Item {
    width: 900; height: 800
    SettingsGithubUpdateReview { id: dialog }
    SettingsGithubButton { id: button; text: "Sync from GitHub" }
    SignalSpy { id: requests; target: dialog; signalName: "requestAction" }
    TestCase {
        name: "GithubUpdateReview"
        when: windowShown
        function find(object, name) {
            if (object.objectName === name) return object;
            let children = object.children || [];
            for (let child of children) { let result = find(child, name); if (result) return result; }
            return null;
        }
        function test_reviewAndAcknowledgementGateApply() {
            let confirm = find(dialog.contentItem, "githubUpdateConfirm");
            let acknowledgement = find(dialog.contentItem, "githubUpdateAcknowledgement");
            verify(confirm !== null); verify(acknowledgement !== null);
            dialog.review = ({});
            verify(!confirm.enabled);
            dialog.review = {ready: true, token: "reviewed", target: "12345678901234", base: "00000000000000",
                             checks: ["Fedora 44"], warnings: ["Physical tests pending"], commits: ["Fix audio"],
                             blockers: [], changes: ["M shell.qml"]};
            verify(!confirm.enabled);
            acknowledgement.checked = true;
            verify(confirm.enabled);
            let report = find(dialog.contentItem, "githubUpdateReview");
            verify(report.text.indexOf("Fix audio") !== -1);
            verify(report.text.indexOf("Physical tests pending") !== -1);
            dialog.review = {ready: false, blockers: ["Unsupported version"]};
            verify(!confirm.enabled);
            dialog.applying = true;
            verify(!confirm.enabled);
            dialog.applying = false;
            acknowledgement.checked = false;
        }
        function test_conflictChoicesRequireReviewBeforeApply() {
            let confirm = find(dialog.contentItem, "githubUpdateConfirm");
            let acknowledgement = find(dialog.contentItem, "githubUpdateAcknowledgement");
            dialog.conflictChoices = ({});
            dialog.review = {ready: false, token: "conflict", conflicts: [{path: "config/hyprshell/settings.json", local: "local value", github: "incoming value", choice: ""}]};
            verify(!dialog.choicesComplete);
            verify(!confirm.enabled);
            dialog.choose("config/hyprshell/settings.json", "local");
            verify(dialog.choicesComplete);
            verify(!dialog.choicesReviewed);
            dialog.review = {ready: true, token: "resolved", conflicts: [{path: "config/hyprshell/settings.json", local: "local value", github: "incoming value", choice: "local"}]};
            acknowledgement.checked = true;
            verify(confirm.enabled);
            dialog.choose("config/hyprshell/settings.json", "github");
            verify(!dialog.choicesReviewed);
            verify(!confirm.enabled);
            dialog.review = ({});
            acknowledgement.checked = false;
        }
        function test_preferencesDefaultToLocalAndBulkChoicesRequireNewReview() {
            let confirm = find(dialog.contentItem, "githubUpdateConfirm");
            let acknowledgement = find(dialog.contentItem, "githubUpdateAcknowledgement");
            dialog.conflictChoices = ({});
            let rows = [
                {path: "config/hyprshell/settings.json", label: "Desktop and panels", preference: true, choice: "local"},
                {path: "config/hyprshell/theme.json", label: "Theme", preference: true, choice: "local"},
                {path: "config/kitty/kitty.conf", preference: false, choice: "github"}
            ];
            dialog.review = {ready: true, token: "prefs", selections: rows};
            verify(dialog.choicesComplete);
            verify(dialog.choicesReviewed);
            acknowledgement.checked = true;
            verify(confirm.enabled);
            dialog.choosePreferences("github");
            verify(!dialog.choicesReviewed);
            verify(!confirm.enabled);
            compare(dialog.choiceFor(rows[2]), "github");
            let reviewButton = find(dialog.contentItem, "githubConflictReview");
            verify(reviewButton.enabled);
            requests.clear(); reviewButton.clicked();
            let args = requests.signalArguments[0][0];
            compare(args[0], "--resolve");
            let choices = JSON.parse(args[3]);
            compare(choices[rows[0].path], "github");
            compare(choices[rows[1].path], "github");
            compare(choices[rows[2].path], "github");
            dialog.choosePreferences("local");
            verify(dialog.choicesReviewed);
            dialog.review = ({});
            dialog.conflictChoices = ({});
            acknowledgement.checked = false;
        }
        function test_dependencyInstallationNeedsSeparateConsentAndRecheck() {
            dialog.dependenciesStarted = false;
            dialog.review = {ready: false, token: "dependencies", base: "000000000000", target: "111111111111",
                             missingPackages: ["new-library"], dependencyCommand: "/usr/bin/pkexec /usr/bin/pacman -Syu --needed --noconfirm new-library",
                             dependencyFullUpgrade: true, canInstallDependencies: true};
            let install = find(dialog.contentItem, "githubDependencyInstall");
            let approval = find(dialog.contentItem, "githubDependencyApproval");
            let command = find(dialog.contentItem, "githubDependencyCommand");
            verify(install !== null); verify(approval !== null);
            compare(command.text, "/usr/bin/pkexec /usr/bin/pacman -Syu --needed --noconfirm new-library");
            verify(approval.text.indexOf("full system upgrade") !== -1);
            verify(!install.enabled);
            approval.checked = true;
            verify(install.enabled);
            requests.clear(); install.clicked();
            compare(requests.count, 1);
            compare(requests.signalArguments[0][0][0], "--install-dependencies");
            compare(requests.signalArguments[0][0][1], "dependencies");
            compare(requests.signalArguments[0][0][2], "--acknowledge");
            dialog.dependenciesStarted = true;
            dialog.installingDependencies = true;
            verify(dialog.busy);
            verify(find(dialog.contentItem, "githubUpdateClose").enabled);
            dialog.dependencyOutput = "Downloading packages";
            compare(find(dialog.contentItem, "githubDependencyOutput").text, "Downloading packages");
            verify(!install.enabled);
            verify(!find(dialog.contentItem, "githubUpdateConfirm").enabled);
            dialog.installingDependencies = false;
            dialog.run(["--preview"]);
            verify(!approval.checked);
            verify(!dialog.dependenciesStarted);
            dialog.review = ({});
        }
        function test_githubButtonHasReadableLabelAndIcon() {
            compare(button.Accessible.name, "Sync from GitHub");
            compare(button.contentItem.children[0].text, "\uf09b");
            verify(button.implicitWidth > 100);
        }
        function test_developerSourceAndExclusiveCheckboxes() {
            dialog.conflictChoices = ({});
            dialog.review = {ready: false, repository: "https://github.com/orapagier/hyprshell.git", branch: "main",
                             conflicts: [{path: "config/hyprshell/settings.json", local: "local value", github: "incoming value", diff: "-local value\n+incoming value", choice: ""}]};
            let source = find(dialog.contentItem, "githubUpdateSource");
            verify(source.text.indexOf("developer’s GitHub repository") !== -1);
            verify(source.text.indexOf("orapagier/hyprshell") !== -1);
            tryVerify(() => find(dialog.contentItem, "githubConflictKeepLocal") !== null);
            let local = find(dialog.contentItem, "githubConflictKeepLocal");
            let developer = find(dialog.contentItem, "githubConflictUseDeveloper");
            let diff = find(dialog.contentItem, "githubConflictDiff");
            verify(diff.text.indexOf("-local value") !== -1);
            verify(!local.checked); verify(!developer.checked);
            local.toggle(); local.clicked();
            verify(local.checked); verify(!developer.checked);
            verify(dialog.choicesComplete);
            developer.toggle(); developer.clicked();
            verify(!local.checked); verify(developer.checked);
            developer.toggle(); developer.clicked();
            verify(!dialog.choicesComplete);
            verify(!local.checked); verify(!developer.checked);
            dialog.review = ({});
            dialog.conflictChoices = ({});
        }
    }
}
