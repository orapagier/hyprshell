pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Quickshell.Io
import "SettingsModel.js" as Model
import "style" as Style

ColumnLayout {
    id: page
    property var draft: ({version: 1, general: {}, workspaces: [], rules: []})
    property var classes: []
    property string revision: ""
    property string message: ""
    property string discoveryMessage: ""
    property bool success: true
    property bool loaded: false
    property bool pending: false
    readonly property bool dirty: pending
    readonly property bool busy: worker.running
    readonly property var layouts: ["inherit", "dwindle", "master", "scrolling"]
    spacing: 16
    Component.onCompleted: if (visible) request("status")
    onVisibleChanged: if (visible && !busy && !dirty) request("status")
    function request(operation) {
        if (busy) return;
        let payload = {operation: operation, expected: revision, settings: draft};
        worker.command = ["python3", decodeURIComponent(Qt.resolvedUrl("settings/behavior.py").toString().replace(/^file:\/\//, "")), "--request-json", JSON.stringify(payload)]; worker.running = true;
    }
    function editGeneral(key, value) { if (value === undefined) delete draft.general[key]; else draft.general[key] = value; pending = true; }
    function editRow(group, index, key, value) { draft[group][index][key] = value; pending = true; }
    function editWorkspacePlacement(index, key, value) {
        let next = Model.copy(draft);
        next.workspaces[index][key] = value;
        if (value) next.workspaces[index][key === "floating" ? "pseudotiled" : "floating"] = false;
        draft = next; pending = true;
    }
    function add(group) {
        let next = Model.copy(draft);
        if (group === "workspaces") {
            let ident = 1; while (next.workspaces.some(row => row.id === ident)) ident++;
            if (ident > 99) return;
            next.workspaces.push({id: ident, name: "", layout: "inherit", persistent: false, floating: false, pseudotiled: false});
        } else next.rules.push({class: "", mode: "inherit", workspace: 0, pin: false, noAnimations: false, width: 0, height: 0});
        draft = next; pending = true;
    }
    function remove(group, index) { let next = Model.copy(draft); next[group].splice(index, 1); draft = next; pending = true; }
    Process {
        id: worker
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let result = JSON.parse(text); page.success = result.ok; page.message = result.message || "";
                    if (result.ok && result.settings) { page.draft = result.settings; page.classes = result.classes; page.discoveryMessage = result.discoveryMessage; page.revision = result.revision; page.loaded = true; page.pending = false; }
                } catch (e) { page.success = false; page.message = "Could not read workspace and rule settings. Refresh and retry."; }
            }
        }
        onExited: (code, status) => { if (code !== 0 && page.success) { page.success = false; page.message = "Workspace/rule helper failed. Refresh and retry."; } }
    }
    SettingsLabel { visible: !!page.message; text: page.message; color: page.success ? Style.Theme.success : Style.Theme.danger; Layout.fillWidth: true; wrapMode: Text.Wrap }
    Flow {
        Layout.fillWidth: true; spacing: 8
        SettingsButton { objectName: "saveBehavior"; text: "Apply changes"; highlighted: page.pending; enabled: page.loaded && page.pending && !page.busy; onClicked: page.request("save") }
        SettingsButton { text: page.pending ? "Discard edits & refresh" : "Refresh"; enabled: !page.busy; onClicked: page.request("status") }
    }
    SettingsCard {
        title: "Window behavior"
        subtitle: "Use config keeps your existing desktop behavior. Choose an override only where needed."
        Layout.fillWidth: true; enabled: page.loaded && !page.busy
        SettingsLabel { text: "Default tiling layout"; color: Style.Theme.text; font.pixelSize: Style.Theme.bodySize }
        SettingsComboBox { Layout.fillWidth: true; model: ["Use config", "Dwindle", "Master", "Scrolling"]; currentIndex: page.layouts.indexOf(page.draft.general.layout || "inherit"); onActivated: index => page.editGeneral("layout", index ? page.layouts[index] : undefined) }
        SettingsLabel { text: "Resize windows from borders"; color: Style.Theme.text; font.pixelSize: Style.Theme.bodySize }
        SettingsComboBox { Layout.fillWidth: true; model: ["Use config", "Enabled", "Disabled"]; currentIndex: page.draft.general.resizeOnBorder === undefined ? 0 : page.draft.general.resizeOnBorder ? 1 : 2; onActivated: index => page.editGeneral("resizeOnBorder", index ? index === 1 : undefined) }
        SettingsLabel { text: "Focus follows pointer"; color: Style.Theme.text; font.pixelSize: Style.Theme.bodySize }
        SettingsComboBox { Layout.fillWidth: true; model: ["Use config", "Click to focus", "Focus under pointer", "Pointer focus without switching keyboard focus", "Separate pointer and keyboard focus, including clicks"]; currentIndex: page.draft.general.followMouse === undefined ? 0 : page.draft.general.followMouse + 1; onActivated: index => page.editGeneral("followMouse", index ? index - 1 : undefined) }
    }
    SettingsCard {
        title: "Workspace preferences"
        subtitle: "Give numbered workspaces a name or their own layout. Persistent workspaces stay available even when empty. Monitor assignment stays automatic. Floating workspaces float existing windows, new windows and windows moved in, overriding application tiling rules. Turning this off stops automatic floating; existing windows keep their placement."
        Layout.fillWidth: true; enabled: page.loaded && !page.busy
        Repeater {
            model: page.draft.workspaces
            delegate: ColumnLayout {
                id: workspaceRow
                required property var modelData
                required property int index
                Layout.fillWidth: true
                RowLayout {
                    Layout.fillWidth: true
                    SettingsLabel { text: "Workspace"; color: Style.Theme.text; font.pixelSize: Style.Theme.bodySize }
                    SettingsSpinBox { from: 1; to: 99; value: workspaceRow.modelData.id; onValueModified: page.editRow("workspaces", workspaceRow.index, "id", value) }
                }
                SettingsTextField { Layout.fillWidth: true; placeholderText: "Name (optional)"; text: workspaceRow.modelData.name; color: Style.Theme.text; onTextEdited: page.editRow("workspaces", workspaceRow.index, "name", text); selectByMouse: true }
                SettingsComboBox { Layout.fillWidth: true; model: ["Use default layout", "Dwindle", "Master", "Scrolling"]; currentIndex: page.layouts.indexOf(workspaceRow.modelData.layout); onActivated: index => page.editRow("workspaces", workspaceRow.index, "layout", page.layouts[index]) }
                SettingsSwitch { objectName: "workspaceFloating-" + workspaceRow.index; text: "Floating windows"; checked: workspaceRow.modelData.floating === true; Layout.fillWidth: true; onToggled: page.editWorkspacePlacement(workspaceRow.index, "floating", checked) }
                SettingsSwitch { objectName: "workspacePseudotiled-" + workspaceRow.index; text: "Pseudotiled windows"; checked: workspaceRow.modelData.pseudotiled === true; Layout.fillWidth: true; onToggled: page.editWorkspacePlacement(workspaceRow.index, "pseudotiled", checked) }
                SettingsLabel { text: "Pseudotiling keeps windows tiled at their preferred size. Use the Dwindle layout. Floating and pseudotiling are alternative choices. Changes cover existing, new and moved-in windows; turning either off keeps existing placement."; color: Style.Theme.muted; font.pixelSize: Style.Theme.captionSize; Layout.fillWidth: true; wrapMode: Text.Wrap }
                SettingsSwitch { text: "Keep available when empty"; checked: workspaceRow.modelData.persistent; Layout.fillWidth: true; onToggled: page.editRow("workspaces", workspaceRow.index, "persistent", checked) }
                SettingsButton { text: "Remove preference"; onClicked: page.remove("workspaces", workspaceRow.index) }
            }
        }
        SettingsButton { objectName: "addWorkspacePreference"; text: "Add workspace preference"; onClicked: page.add("workspaces") }
    }
    SettingsCard {
        title: "Application window rules"
        subtitle: "Rules match one exact application class. Placement and size apply when a window opens; close and reopen the app to check the result."
        Layout.fillWidth: true; enabled: page.loaded && !page.busy
        SettingsLabel { visible: !!page.discoveryMessage; text: page.discoveryMessage; color: Style.Theme.muted; font.pixelSize: Style.Theme.captionSize; Layout.fillWidth: true; wrapMode: Text.Wrap }
        Repeater {
            model: page.draft.rules
            delegate: ColumnLayout {
                id: ruleRow
                required property var modelData
                required property int index
                Layout.fillWidth: true
                SettingsTextField { objectName: "ruleClass-" + ruleRow.index; Layout.fillWidth: true; placeholderText: "Application class, e.g. kitty"; text: ruleRow.modelData.class; color: Style.Theme.text; selectByMouse: true; onTextEdited: page.editRow("rules", ruleRow.index, "class", text) }
                SettingsComboBox { visible: page.classes.length > 0; Layout.fillWidth: true; model: ["Choose a running application"].concat(page.classes); onActivated: index => { if (index > 0) { page.editRow("rules", ruleRow.index, "class", page.classes[index - 1]); page.draft = Model.copy(page.draft); } } }
                SettingsComboBox { Layout.fillWidth: true; model: ["Use existing placement", "Float", "Tile"]; currentIndex: ["inherit", "float", "tile"].indexOf(ruleRow.modelData.mode); onActivated: index => page.editRow("rules", ruleRow.index, "mode", ["inherit", "float", "tile"][index]) }
                RowLayout {
                    Layout.fillWidth: true
                    SettingsLabel { text: "Open on workspace · 0 uses default"; color: Style.Theme.text; Layout.fillWidth: true; wrapMode: Text.Wrap }
                    SettingsSpinBox { from: 0; to: 99; value: ruleRow.modelData.workspace; onValueModified: page.editRow("rules", ruleRow.index, "workspace", value) }
                }
                SettingsSwitch { text: "Pin floating windows to all workspaces"; checked: ruleRow.modelData.pin; Layout.fillWidth: true; onToggled: page.editRow("rules", ruleRow.index, "pin", checked) }
                SettingsSwitch { text: "Disable animations for this app"; checked: ruleRow.modelData.noAnimations; Layout.fillWidth: true; onToggled: page.editRow("rules", ruleRow.index, "noAnimations", checked) }
                SettingsLabel { text: "Floating size · 0 / 0 uses app size"; color: Style.Theme.text; font.pixelSize: Style.Theme.captionSize; Layout.fillWidth: true; wrapMode: Text.Wrap }
                RowLayout {
                    SettingsSpinBox { from: 0; to: 4096; stepSize: 100; editable: true; value: ruleRow.modelData.width; onValueModified: page.editRow("rules", ruleRow.index, "width", value) }
                    SettingsLabel { text: "×"; color: Style.Theme.text }
                    SettingsSpinBox { from: 0; to: 4096; stepSize: 100; editable: true; value: ruleRow.modelData.height; onValueModified: page.editRow("rules", ruleRow.index, "height", value) }
                }
                SettingsButton { text: "Remove rule"; onClicked: page.remove("rules", ruleRow.index) }
            }
        }
        SettingsButton { objectName: "addApplicationRule"; text: "Add application rule"; onClicked: page.add("rules") }
    }
}
