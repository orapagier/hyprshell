pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Io

SettingsGithubUpdateReview {
    id: dialog
    property bool recheckPending: false
    requesting: request.running
    onRequestAction: args => {
        if (args[0] === "--preview") dialog.recheckPending = false;
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
                    if (dialog.action === "--preview" || dialog.action === "--resolve") dialog.review = result;
                    if (result.operation === "dependencies") {
                        dialog.applying = false;
                        dialog.dependenciesStarted = true;
                        dialog.installingDependencies = result.running === true;
                        dialog.dependencyOutput = result.output || "";
                        if (!dialog.review.missingPackages) dialog.review = {missingPackages: result.packages || [], dependencyFullUpgrade: result.dependencyFullUpgrade};
                        if (!dialog.installingDependencies && result.ok) dialog.recheckPending = true;
                    } else if (dialog.action === "--apply" || dialog.action === "--status") {
                        dialog.applying = result.running === true;
                        if (!dialog.applying) dialog.review = ({});
                        if (dialog.action === "--status" && dialog.checkAfterStatus && !dialog.applying) dialog.recheckPending = true;
                    }
                    if (dialog.action === "--status") dialog.checkAfterStatus = false;
                } catch (error) {
                    dialog.success = false;
                    dialog.message = "Could not read update results. Check again to see the current status.";
                    dialog.applying = false;
                    dialog.installingDependencies = false;
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
        running: dialog.opened && (dialog.applying || dialog.installingDependencies) && !request.running
        onTriggered: dialog.run(["--status"])
    }
    Timer {
        interval: 100
        running: dialog.opened && dialog.recheckPending && !request.running
        onTriggered: { dialog.recheckPending = false; dialog.run(["--preview"]); }
    }
}
