pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io

SettingsGithubUpdateReview {
    id: dialog
    requesting: request.running
    onRequestAction: args => {
        request.command = ["python3", decodeURIComponent(Qt.resolvedUrl("settings/github_update.py").toString().replace(/^file:\/\//, ""))].concat(args);
        request.running = true;
    }
    Process {
        id: request
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let result = JSON.parse(text);
                    dialog.success = result.ok === true;
                    dialog.message = result.message || "";
                    if (dialog.action === "--preview") dialog.review = result;
                    if (dialog.action === "--apply" || dialog.action === "--status") {
                        dialog.applying = result.running === true;
                        if (!dialog.applying) dialog.review = ({});
                    }
                } catch (error) {
                    dialog.success = false;
                    dialog.message = "Could not read update results. Check again to see the current status.";
                    dialog.applying = false;
                }
            }
        }
        stderr: StdioCollector {}
        onExited: (code, status) => {
            if (code !== 0 && dialog.success) {
                dialog.success = false;
                dialog.message = "The update check could not finish. Check your connection and GitHub access.";
                dialog.applying = false;
            }
        }
    }
    Timer {
        interval: 1500
        repeat: true
        running: dialog.opened && dialog.applying && !request.running
        onTriggered: dialog.run(["--status"])
    }
}
