pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Quickshell.Io
import "style" as Style

ColumnLayout {
    id: page
    property var snapshot: ({})
    property var pending: null
    property string zone: ""
    property string scope: "runtime"
    property string message: ""
    property bool success: true
    property bool loaded: false
    readonly property bool busy: worker.running
    readonly property bool dirty: service.text.length > 0 || port.text.length > 0 || source.text.length > 0 || pending !== null
    spacing: 16
    Component.onCompleted: if (visible) refresh()
    onVisibleChanged: if (visible && !busy && !dirty) refresh()
    function refresh() { request({operation: "status", zone: zone, scope: scope}); }
    function discard() { service.text = ""; port.text = ""; source.text = ""; pending = null; }
    function request(payload) {
        if (busy) return;
        worker.command = ["python3", decodeURIComponent(Qt.resolvedUrl("settings/firewall.py").toString().replace(/^file:\/\//, "")), "--request-json", JSON.stringify(payload)];
        worker.running = true;
    }
    function review(operation, value) {
        pending = {operation: operation, value: value, zone: zone, scope: scope, expected: snapshot.revision, confirmed: true};
    }
    Process {
        id: worker
        onExited: (code, status) => { if (code !== 0) { page.success = false; page.loaded = false; page.message = "Firewall helper failed. Refresh to check the result."; } }
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let result = JSON.parse(text);
                    page.success = result.ok;
                    page.message = result.message || "";
                    if (result.ok && result.zones !== undefined) {
                        page.snapshot = result; page.zone = result.zone; page.loaded = true;
                    } else page.loaded = false;
                    if (result.ok && page.pending) page.discard();
                    else page.pending = null;
                } catch (e) { page.success = false; page.loaded = false; page.message = "Could not read firewall response. Refresh to check the result."; }
            }
        }
        stderr: StdioCollector {}
    }
    Label { objectName: "firewallMessage"; visible: !!page.message; text: page.message; color: page.success ? Style.Theme.success : Style.Theme.danger; Layout.fillWidth: true; wrapMode: Text.Wrap }
    SettingsCard {
        title: "Firewall status and zone"
        subtitle: "firewalld controls incoming connections using zones. Refresh reads the system firewall; opening this page does not change rules."
        Layout.fillWidth: true
        Flow {
            Layout.fillWidth: true; spacing: 8
            SettingsButton { objectName: "refreshFirewall"; text: page.busy ? "Working…" : "Refresh"; enabled: !page.busy; onClicked: { page.pending = null; page.refresh(); } }
            SettingsButton { text: "Enable and start…"; enabled: !page.busy; onClicked: page.review("enable", "firewalld") }
            SettingsButton { text: "Discard draft"; visible: page.dirty; enabled: !page.busy; onClicked: page.discard() }
        }
        Label { text: page.loaded ? "firewalld is running. Active zones and interfaces:\n" + (page.snapshot.active || "No zone bindings reported") : "Firewall status is unavailable until a successful Refresh."; color: Style.Theme.muted; wrapMode: Text.Wrap; Layout.fillWidth: true }
        SettingsComboBox { objectName: "firewallZone"; Layout.fillWidth: true; model: page.snapshot.zones || []; currentIndex: model.indexOf(page.zone); enabled: page.loaded && !page.busy && !page.dirty; onActivated: { page.zone = currentText; page.refresh(); } }
        SettingsComboBox { objectName: "firewallScope"; Layout.fillWidth: true; model: ["Current rules · effective now", "Saved rules · after reload or restart"]; enabled: !page.busy && !page.dirty; onActivated: { page.scope = currentIndex === 0 ? "runtime" : "permanent"; page.refresh(); } }
        Label { text: "Choose the zone bound to your connection. Current and saved rules are separate: apply a change in both views to activate it now and keep it after restart. Saved-only changes do not take effect immediately."; color: Style.Theme.muted; wrapMode: Text.Wrap; Layout.fillWidth: true }
    }
    SettingsCard {
        title: "Allow incoming connections"
        subtitle: "Open only the service or port you need. Removing an allowance may still leave access through other rules or a permissive zone."
        Layout.fillWidth: true
        SettingsTextField { id: service; objectName: "firewallService"; Layout.fillWidth: true; placeholderText: "Service name, e.g. ssh, http, https"; enabled: !page.busy; selectByMouse: true }
        SettingsButton { objectName: "addFirewallService"; text: "Allow service…"; enabled: page.loaded && !page.busy && !!service.text.trim(); onClicked: page.review("add-service", service.text.trim()) }
        Label { text: "Allowed services: " + (page.snapshot.services || []).join(", "); color: Style.Theme.muted; Layout.fillWidth: true; wrapMode: Text.Wrap }
        Repeater { model: page.snapshot.services || []; delegate: SettingsButton { required property string modelData; text: "Remove allowance: " + modelData; enabled: page.loaded && !page.busy; onClicked: page.review("remove-service", modelData) } }
        SettingsTextField { id: port; objectName: "firewallPort"; Layout.fillWidth: true; placeholderText: "Port/protocol, e.g. 8080/tcp or 8000-8010/udp"; enabled: !page.busy; selectByMouse: true }
        SettingsButton { text: "Allow port…"; enabled: page.loaded && !page.busy && !!port.text.trim(); onClicked: page.review("add-port", port.text.trim()) }
        Repeater { model: page.snapshot.ports || []; delegate: SettingsButton { required property string modelData; text: "Remove allowance: " + modelData; enabled: page.loaded && !page.busy; onClicked: page.review("remove-port", modelData) } }
    }
    SettingsCard {
        title: "Block a source"
        subtitle: "Drop incoming traffic from an IPv4/IPv6 address or CIDR network in the selected zone. The rule takes priority over ordinary zone allowances."
        Layout.fillWidth: true
        SettingsTextField { id: source; objectName: "firewallSource"; Layout.fillWidth: true; placeholderText: "IP address or CIDR, e.g. 192.0.2.10 or 2001:db8::/64"; enabled: !page.busy; selectByMouse: true }
        SettingsButton { text: "Block source…"; enabled: page.loaded && !page.busy && !!source.text.trim(); onClicked: page.review("block-source", source.text.trim()) }
        Repeater {
            model: page.snapshot.rich || []
            delegate: ColumnLayout {
                required property string modelData
                Layout.fillWidth: true
                Label { text: parent.modelData; color: Style.Theme.text; Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText }
                SettingsButton { text: "Remove rich rule…"; enabled: page.loaded && !page.busy; onClicked: page.review("remove-rich", parent.modelData) }
            }
        }
    }
    SettingsCard {
        title: "Review change"
        visible: page.pending !== null
        Layout.fillWidth: true
        Label { text: page.pending ? (page.pending.operation === "enable" ? "Enable firewalld at boot and start it now? Authentication opens in a terminal." : page.pending.operation + ": " + page.pending.value + "\nZone: " + page.pending.zone + " · " + page.pending.scope + "\nThis can affect network access. Complete the administrator prompt if shown.") : ""; color: Style.Theme.warning; Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText }
        RowLayout {
            SettingsButton { objectName: "confirmFirewall"; text: "Apply change"; enabled: !page.busy; onClicked: page.request(page.pending) }
            SettingsButton { text: "Cancel"; enabled: !page.busy; onClicked: page.pending = null }
        }
    }
    SettingsCard {
        title: "Zone details and firewall help"
        Layout.fillWidth: true
        Label { text: page.snapshot.details || "Refresh to inspect target, interfaces, services, ports, forwarding and rich rules."; color: Style.Theme.text; Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText }
        Label { text: "A firewall filters network traffic; it does not replace software updates or application authentication. These controls manage incoming zone rules. Outgoing restrictions, forwarding, policies and connection zone assignment need advanced configuration. Existing system rules stay on this machine and are outside GitHub desktop sync."; color: Style.Theme.muted; Layout.fillWidth: true; wrapMode: Text.Wrap }
        SettingsButton { text: "Open firewalld documentation"; onClicked: Qt.openUrlExternally("https://firewalld.org/documentation/howto/open-a-port-or-service.html") }
    }
}
