pragma ComponentBehavior: Bound
import QtQuick
import "style" as Style
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Quickshell.Io

ColumnLayout {
    id: page
    property var monitors: []
    property var entries: []
    property var saved: ({version: 1, entries: []})
    property string message: ""
    property bool success: true
    property bool loaded: false
    property var initialEntries: []
    readonly property bool dirty: loaded && JSON.stringify(entries) !== JSON.stringify(initialEntries)
    property bool pending: false
    property bool decisionSent: false
    property int seconds: 0
    property bool refreshAfterExit: false
    property bool previewRunning: false
    readonly property bool busy: worker.running
    spacing: 16
    onVisibleChanged: {
        if (visible && !busy && !dirty) request("status");
        if (!visible && pending) decide("revert");
    }
    Component.onCompleted: if (visible) request("status")
    function edit(index, key, value) {
        let next = entries.map(e => Object.assign({}, e));
        next[index][key] = value;
        entries = next;
    }
    function dimensions(entry, monitor) {
        let resolution = entry.mode === "preferred" ? [monitor.width, monitor.height] : entry.mode.split("@")[0].split("x").map(Number);
        if (entry.transform % 2) resolution.reverse();
        let scale = entry.scale === "auto" ? monitor.scale : entry.scale;
        return resolution.map(v => Math.round(v / scale));
    }
    function duplicate(source) {
        entries = entries.map(e => Object.assign({}, e, {mirror: e.output === source ? "" : source}));
    }
    function extend() {
        entries = entries.map(e => Object.assign({}, e, {mirror: "", position: "auto"}));
    }
    function place(index, anchorName, direction) {
        let anchorIndex = entries.findIndex(e => e.output === anchorName);
        if (anchorIndex < 0) return;
        let anchor = entries[anchorIndex];
        let monitor = monitors[anchorIndex];
        let origin = anchor.position === "auto" ? [monitor.x, monitor.y] : anchor.position.split("x").map(Number);
        // Fix the anchor too, so an automatic rule cannot move it after placement.
        edit(anchorIndex, "position", origin[0] + "x" + origin[1]);
        edit(anchorIndex, "mirror", "");
        edit(index, "mirror", "");
        let ownSize = dimensions(entries[index], monitors[index]);
        let anchorSize = dimensions(anchor, monitor);
        if (direction === "left") origin[0] -= ownSize[0];
        if (direction === "right") origin[0] += anchorSize[0];
        if (direction === "above") origin[1] -= ownSize[1];
        if (direction === "below") origin[1] += anchorSize[1];
        edit(index, "position", origin[0] + "x" + origin[1]);
    }
    function request(operation) {
        if (busy) return;
        message = "";
        previewRunning = operation === "preview";
        decisionSent = false;
        let payload = {operation: operation};
        if (operation === "preview") { payload.entries = entries; payload.expected = saved; }
        worker.command = ["python3", decodeURIComponent(Qt.resolvedUrl("settings/displays.py").toString().replace(/^file:\/\//, "")), "--request-json", JSON.stringify(payload)];
        worker.running = true;
    }
    function decide(action) {
        if (pending && !decisionSent) { decisionSent = true; worker.write(action + "\n"); }
    }
    function receive(result) {
        if (result.message !== undefined || !result.ok || !message) success = result.ok;
        if (result.message !== undefined) message = result.message;
        if (result.monitors) { monitors = result.monitors; entries = result.entries; initialEntries = result.entries.map(e => Object.assign({}, e)); saved = result.saved; loaded = true; }
        if (result.pending === true) { pending = true; seconds = result.seconds; countdown.restart(); }
        if (result.pending === false) { pending = false; countdown.stop(); refreshAfterExit = previewRunning; previewRunning = false; }
    }
    Process {
        id: worker
        stdinEnabled: true
        stdout: StdioCollector {
            waitForEnd: false
            property int consumed: 0
            onTextChanged: {
                let lines = text.split("\n");
                while (consumed < lines.length - 1) {
                    let line = lines[consumed++];
                    try { page.receive(JSON.parse(line)); }
                    catch (e) { page.success = false; page.message = "Could not read display settings. Try refreshing."; }
                }
            }
        }
        stderr: StdioCollector { onStreamFinished: if (text) { page.success = false; page.message = text; } }
        onStarted: stdout.consumed = 0
        onExited: (code, status) => {
            page.pending = false;
            countdown.stop();
            if (code !== 0 && !page.message) { page.success = false; page.message = "Display helper stopped. Refresh and try again."; }
            if (page.refreshAfterExit) { page.refreshAfterExit = false; refreshTimer.start(); }
        }
    }
    Timer { id: countdown; interval: 1000; repeat: true; onTriggered: { page.seconds = Math.max(0, page.seconds - 1); if (!page.seconds) stop(); } }
    Timer {
        id: refreshTimer; interval: 100
        onTriggered: {
            // Keep the result message while refreshing live state after rollback/confirmation.
            if (!page.busy) {
                worker.command = ["python3", decodeURIComponent(Qt.resolvedUrl("settings/displays.py").toString().replace(/^file:\/\//, "")), "--request-json", '{"operation":"status"}'];
                worker.running = true;
            }
        }
    }
    SettingsCard {
        Layout.fillWidth: true
        title: page.pending ? "Keep these settings?" : "Connected displays"
        subtitle: page.pending ? "Reverting in " + page.seconds + " seconds unless you keep the changes." : "Duplicate shows the same desktop and cursor on your laptop and TV. Extend gives each screen its own desktop. Choose a layout, then apply and keep the changes."
        ColumnLayout {
            Layout.fillWidth: true
            visible: page.monitors.length > 1
            enabled: !page.busy
            Label { text: "Screen to duplicate"; color: Style.Theme.muted }
            SettingsComboBox {
                id: duplicateSource
                objectName: "duplicateSource"
                Layout.fillWidth: true
                model: page.monitors.map(m => m.name)
                currentIndex: Math.max(0, page.monitors.findIndex(m => /^(eDP|LVDS|DSI)-/.test(m.name)))
            }
            RowLayout {
                SettingsButton { objectName: "duplicateDisplays"; text: "Duplicate (mirror)"; onClicked: page.duplicate(duplicateSource.currentText) }
                SettingsButton { objectName: "extendDisplays"; text: "Extend"; onClicked: page.extend() }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            SettingsButton { objectName: "keepDisplays"; text: "Keep changes"; highlighted: true; visible: page.pending; enabled: !page.decisionSent && page.seconds > 0; onClicked: page.decide("keep") }
            SettingsButton { objectName: "revertDisplays"; text: "Revert"; visible: page.pending; enabled: !page.decisionSent; onClicked: page.decide("revert") }
            SettingsButton { objectName: "applyDisplays"; text: "Apply changes…"; highlighted: true; visible: !page.pending; enabled: page.loaded && page.entries.length > 0 && !page.busy; onClicked: page.request("preview") }
            SettingsButton { text: page.dirty ? "Discard edits & refresh" : "Refresh"; visible: !page.pending; enabled: !page.busy; onClicked: page.request("status") }
        }
        Label { visible: !!page.message; text: page.message; color: page.success ? Style.Theme.success : Style.Theme.danger; Layout.fillWidth: true; wrapMode: Text.Wrap }
        Label { visible: page.loaded && !page.monitors.length; text: "No active displays found."; color: Style.Theme.muted }
    }
    Repeater {
        model: page.monitors
        delegate: SettingsCard {
            id: card
            required property var modelData
            required property int index
            readonly property var entry: page.entries[index] || ({mode: "preferred", scale: "auto", transform: 0, position: "auto"})
            readonly property var modes: {
                let list = ["preferred"].concat(modelData.availableModes || []);
                if (!list.includes(entry.mode)) list.push(entry.mode);
                return list;
            }
            readonly property var resolutions: [...new Set(modes.map(m => m.split("@")[0]))]
            readonly property string resolution: entry.mode.split("@")[0]
            readonly property var rates: modes.filter(m => m.split("@")[0] === resolution)
            Layout.fillWidth: true
            title: modelData.name
            subtitle: modelData.description || "Connected display"
            enabled: !page.busy
            ColumnLayout {
                Layout.fillWidth: true
                visible: page.monitors.length > 1
                Label { text: "Use this screen as"; color: Style.Theme.muted }
                SettingsComboBox {
                    objectName: "displayMirror"
                    Layout.fillWidth: true
                    readonly property var sources: page.entries.filter(e => e.output !== card.modelData.name && !e.mirror).map(e => e.output)
                    model: ["Extended desktop"].concat(sources.map(s => "Duplicate " + s))
                    currentIndex: card.entry.mirror ? sources.indexOf(card.entry.mirror) + 1 : 0
                    onActivated: page.edit(card.index, "mirror", currentIndex ? sources[currentIndex - 1] : "")
                }
            }
            Label { visible: !!card.entry.mirror; text: "Showing the desktop and cursor from " + (card.entry.mirror || "") + ". Different screen shapes may stretch the picture."; Layout.fillWidth: true; wrapMode: Text.Wrap; color: Style.Theme.muted }
            GridLayout {
                Layout.fillWidth: true
                columns: card.width > 600 ? 2 : 1
                columnSpacing: 20; rowSpacing: 16
                ColumnLayout {
                    Layout.fillWidth: true
                    Label { text: "Resolution"; color: Style.Theme.muted }
                    SettingsComboBox {
                        objectName: "displayResolution"
                        Layout.fillWidth: true
                        model: card.resolutions.map(r => r === "preferred" ? "Recommended (automatic)" : r)
                        currentIndex: card.resolutions.indexOf(card.resolution)
                        onActivated: {
                            let res = card.resolutions[currentIndex];
                            page.edit(card.index, "mode", card.modes.find(m => m.split("@")[0] === res));
                        }
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    Label { text: "Refresh rate"; color: Style.Theme.muted }
                    SettingsComboBox {
                        objectName: "displayRefresh"
                        Layout.fillWidth: true
                        model: card.rates.map(m => m === "preferred" ? "Automatic" : m.split("@")[1].replace(/Hz$/, "") + " Hz")
                        currentIndex: card.rates.indexOf(card.entry.mode)
                        onActivated: page.edit(card.index, "mode", card.rates[currentIndex])
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    Label { text: "Scale"; color: Style.Theme.muted }
                    SettingsComboBox {
                        objectName: "displayScale"
                        Layout.fillWidth: true
                        readonly property var scales: {
                            let list = ["auto", 0.75, 1, 1.25, 1.5, 1.75, 2, 2.5, 3, 4];
                            if (!list.includes(card.entry.scale)) list.push(card.entry.scale);
                            return list;
                        }
                        model: scales.map(s => s === "auto" ? "Automatic" : Math.round(s * 100) + "%")
                        currentIndex: scales.indexOf(card.entry.scale)
                        onActivated: page.edit(card.index, "scale", scales[currentIndex])
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    Label { text: "Rotation"; color: Style.Theme.muted }
                    SettingsComboBox {
                        objectName: "displayRotation"
                        Layout.fillWidth: true
                        model: ["Normal", "90°", "180°", "270°", "Flipped", "Flipped 90°", "Flipped 180°", "Flipped 270°"]
                        currentIndex: card.entry.transform
                        onActivated: page.edit(card.index, "transform", currentIndex)
                    }
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                visible: page.monitors.length > 1
                Label { text: "Place this display next to"; color: Style.Theme.muted }
                SettingsComboBox {
                    id: anchorDisplay
                    Layout.fillWidth: true
                    model: page.monitors.filter(m => m.name !== card.modelData.name).map(m => m.name)
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: 8
                    SettingsButton { text: "← Left"; onClicked: page.place(card.index, anchorDisplay.currentText, "left") }
                    SettingsButton { text: "Right →"; onClicked: page.place(card.index, anchorDisplay.currentText, "right") }
                    SettingsButton { text: "↑ Above"; onClicked: page.place(card.index, anchorDisplay.currentText, "above") }
                    SettingsButton { text: "↓ Below"; onClicked: page.place(card.index, anchorDisplay.currentText, "below") }
                }
            }
            SettingsSwitch {
                text: "Arrange automatically"
                checked: card.entry.position === "auto"
                onToggled: page.edit(card.index, "position", checked ? "auto" : card.modelData.x + "x" + card.modelData.y)
            }
            RowLayout {
                Layout.fillWidth: true
                visible: card.entry.position !== "auto"
                Label { text: "X"; color: Style.Theme.muted }
                SpinBox {
                    objectName: "displayX"
                    Layout.fillWidth: true; editable: true; from: -32000; to: 32000
                    value: parseInt(card.entry.position.split("x")[0]) || 0
                    onValueModified: page.edit(card.index, "position", value + "x" + card.entry.position.split("x")[1])
                }
                Label { text: "Y"; color: Style.Theme.muted }
                SpinBox {
                    objectName: "displayY"
                    Layout.fillWidth: true; editable: true; from: -32000; to: 32000
                    value: parseInt(card.entry.position.split("x")[1]) || 0
                    onValueModified: page.edit(card.index, "position", card.entry.position.split("x")[0] + "x" + value)
                }
            }
            Label { text: "Place a second display beside the first using its width ÷ scale for X (use height ÷ scale when rotated). Negative X places it to the left."; Layout.fillWidth: true; wrapMode: Text.Wrap; color: Style.Theme.muted; font.pixelSize: Style.Theme.captionSize }
        }
    }
}
