import QtQuick
import QtTest
import ".."

Item {
    width: 900; height: 800
    SettingsGithubUpdateReview { id: dialog }
    SettingsGithubButton { id: button; text: "Sync from GitHub" }
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
        function test_githubButtonHasReadableLabelAndIcon() {
            compare(button.Accessible.name, "Sync from GitHub");
            compare(button.contentItem.children[0].text, "\uf09b");
            verify(button.implicitWidth > 100);
        }
    }
}
