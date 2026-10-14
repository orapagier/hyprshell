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
    signal reviewRequested(var card)
    property string zone: ""
    property string scope: "both"
    property bool advanced: false
    property string message: ""
    property bool success: true
    property bool loaded: false
    readonly property bool busy: worker.running
    readonly property bool dirty: service.text.length > 0 || port.text.length > 0 || source.text.length > 0 || pending !== null
    readonly property var commonServices: [
        {name: "ssh", title: "Remote login (SSH)", description: "Let another computer connect to this laptop’s SSH server. You do not need this to log in to another computer."},
        {name: "http", title: "Website hosted here (HTTP)", description: "Let other devices visit a website served by this laptop on port 80. Browsing websites does not need this."},
        {name: "https", title: "Secure website hosted here (HTTPS)", description: "Let other devices visit a secure website served by this laptop on port 443."},
        {name: "samba", title: "Windows file sharing (Samba)", description: "Let other devices access shared folders served by this laptop. Your sharing app must be configured separately."}
    ].filter(row => (snapshot.catalog || []).indexOf(row.name) >= 0)
    readonly property var allowedServices: rules("services")
    readonly property var allowedPorts: rules("ports")
    spacing: 16
    Component.onCompleted: if (visible) refresh()
    onVisibleChanged: if (visible && !busy && !dirty) refresh()
    function rules(key) {
        let current = snapshot[key] || [];
        return scope === "both" ? Array.from(new Set(current.concat((snapshot.saved || {})[key] || []))) : current;
    }
    function serviceName(value) { let row = commonServices.find(row => row.name === value); return row ? row.title : value; }
    function lifetime(key, value) {
        if (scope !== "both") return "";
        let now = (snapshot[key] || []).indexOf(value) >= 0;
        let saved = ((snapshot.saved || {})[key] || []).indexOf(value) >= 0;
        return now && saved ? "Allowed now and after restart" : now ? "Allowed now only" : "Saved for after restart; not allowed now by this rule";
    }
    function refresh() { request({operation: "status", zone: zone, scope: scope}); }
    function discard() { service.text = ""; port.text = ""; source.text = ""; pending = null; }
    function request(payload) {
        if (busy) return;
        worker.command = ["python3", decodeURIComponent(Qt.resolvedUrl("settings/firewall.py").toString().replace(/^file:\/\//, "")), "--request-json", JSON.stringify(payload)];
        worker.running = true;
    }
    function review(operation, value) {
        pending = {operation: operation, value: value, zone: zone, scope: scope, expected: snapshot.revision, confirmed: true};
        Qt.callLater(() => reviewRequested(reviewCard));
    }
    function reviewText() {
        if (!pending) return "";
        if (pending.operation === "enable") return "Turn on the firewall now and whenever this laptop starts? A terminal will ask for your administrator password.";
        let text;
        if (pending.operation === "add-service") text = "Allow other devices to connect for “" + serviceName(pending.value) + "”?";
        else if (pending.operation === "add-port") text = "Allow other devices to connect on port " + pending.value + "?";
        else if (pending.operation === "remove-service") text = "Remove permission for “" + serviceName(pending.value) + "”? Devices using it may lose access.";
        else if (pending.operation === "remove-port") text = "Remove permission for port " + pending.value + "? Devices using it may lose access.";
        else if (pending.operation === "block-source") text = "Block incoming connections from " + pending.value + "?";
        else text = "Remove this advanced rule?\n" + pending.value;
        return text + "\nApplies to network group: " + pending.zone + "\n" + ({both: "Takes effect now and stays after restart.", runtime: "Temporary: lasts until the firewall reloads or restarts.", permanent: "Saved only: takes effect when the firewall reloads or restarts."})[pending.scope] + "\nYou may be asked for your administrator password.";
    }
    Process {
        id: worker
        onExited: (code, status) => { if (code !== 0) { page.success = false; page.loaded = false; page.message = "Could not finish the firewall request. Check again to see its status."; } }
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
                } catch (e) { page.success = false; page.loaded = false; page.message = "Could not read the firewall response. Check again to see its status."; }
            }
        }
        stderr: StdioCollector {}
    }
    SettingsCard {
        title: "What does a firewall do?"
        subtitle: "It controls which connections other devices can make to this laptop."
        Layout.fillWidth: true
        Label { text: "For everyday browsing, streaming, email and downloads, you usually do not need to add a rule. Add one when you want other devices to reach something running here, such as a shared folder, a game server or a website you host."; color: Style.Theme.text; wrapMode: Text.Wrap; Layout.fillWidth: true }
        Label { text: "Allowing a connection opens a door for that service. It does not install or start the service. Keep the firewall on and add only permissions you need."; color: Style.Theme.muted; wrapMode: Text.Wrap; Layout.fillWidth: true }
    }
    Label { objectName: "firewallMessage"; visible: !!page.message; text: page.message; color: page.success ? Style.Theme.success : Style.Theme.danger; Layout.fillWidth: true; wrapMode: Text.Wrap }
    SettingsCard {
        title: page.loaded ? "Firewall is on" : "Firewall status could not be checked"
        subtitle: page.loaded ? "Network group being edited: " + page.zone + ". Each group has its own permissions." : "Check its status before changing permissions. An unavailable status does not mean the firewall is off."
        Layout.fillWidth: true
        Flow {
            Layout.fillWidth: true; spacing: 8
            SettingsButton { objectName: "refreshFirewall"; text: page.busy ? "Checking…" : "Check again"; enabled: !page.busy; onClicked: { page.pending = null; page.refresh(); } }
            SettingsButton { text: "Turn on firewall…"; visible: !page.loaded; enabled: !page.busy; onClicked: page.review("enable", "firewalld") }
            SettingsButton { text: "Discard what I typed"; visible: page.dirty; enabled: !page.busy; onClicked: page.discard() }
        }
        Label { text: page.scope === "both" ? "Changes work immediately and are kept after restart. You only need to confirm once." : "Advanced mode: " + (page.scope === "runtime" ? "changes are temporary." : "changes are saved for the next firewall reload or restart."); color: Style.Theme.muted; wrapMode: Text.Wrap; Layout.fillWidth: true }
        Label { visible: page.loaded && (page.snapshot.active || "").split("\n").filter(line => line && line[0] !== " ").length !== 1; text: "More than one network group, or none, is active. Open Advanced options to check which group your connection uses before adding a permission."; color: Style.Theme.warning; wrapMode: Text.Wrap; Layout.fillWidth: true }
    }
    SettingsCard {
        id: reviewCard
        title: "Confirm this change"
        visible: page.pending !== null
        Layout.fillWidth: true
        Label { objectName: "firewallReview"; text: page.reviewText(); color: Style.Theme.warning; Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText }
        RowLayout {
            SettingsButton { objectName: "confirmFirewall"; text: "Confirm change"; enabled: !page.busy; onClicked: page.request(page.pending) }
            SettingsButton { text: "Cancel"; enabled: !page.busy; onClicked: page.pending = null }
        }
    }
    SettingsCard {
        title: "1. Choose what other devices may access"
        subtitle: "Choose a service only if you run it on this laptop. You can remove its permission later."
        Layout.fillWidth: true
        SettingsComboBox { id: preset; objectName: "firewallPreset"; Layout.fillWidth: true; model: page.commonServices.map(row => row.title); enabled: page.loaded && !page.busy }
        Label { text: page.commonServices[preset.currentIndex] ? page.commonServices[preset.currentIndex].description : "Check the firewall status to see available services."; color: Style.Theme.muted; wrapMode: Text.Wrap; Layout.fillWidth: true }
        SettingsButton { objectName: "allowFirewallPreset"; text: "Allow this service…"; enabled: page.loaded && !page.busy && preset.currentIndex >= 0; onClicked: page.review("add-service", page.commonServices[preset.currentIndex].name) }
    }
    SettingsCard {
        title: "Or allow a specific app’s port"
        subtitle: "Use this when the app’s instructions give you a port number and TCP or UDP. A port is a numbered connection point."
        Layout.fillWidth: true
        SettingsTextField { id: port; objectName: "firewallPort"; Layout.fillWidth: true; placeholderText: "Port number, e.g. 8080 (or a range: 8000-8010)"; enabled: !page.busy; selectByMouse: true }
        SettingsComboBox { id: protocol; Layout.fillWidth: true; model: ["TCP", "UDP"]; enabled: !page.busy }
        Label { text: "Match TCP or UDP to the app’s instructions. For example, a web server using port 8080/TCP needs number 8080 and TCP. Browsing that server from this laptop does not need an incoming permission."; color: Style.Theme.muted; Layout.fillWidth: true; wrapMode: Text.Wrap }
        SettingsButton { text: "Allow this port…"; enabled: page.loaded && !page.busy && !!port.text.trim(); onClicked: page.review("add-port", port.text.trim() + "/" + protocol.currentText.toLowerCase()) }
    }
    SettingsCard {
        title: "2. Review existing permissions"
        subtitle: "These rules let other devices connect to services on this laptop. Removing one permission may still leave access through another rule."
        Layout.fillWidth: true
        Label { visible: page.loaded && page.allowedServices.length === 0 && page.allowedPorts.length === 0; text: "No named services or ports are allowed in this group. Advanced rules and the group’s overall policy can also affect access."; color: Style.Theme.muted; wrapMode: Text.Wrap; Layout.fillWidth: true }
        Repeater {
            model: page.allowedServices
            delegate: ColumnLayout {
                id: serviceRow
                required property string modelData
                Layout.fillWidth: true
                Label { text: page.serviceName(serviceRow.modelData) + "\n" + page.lifetime("services", serviceRow.modelData); color: Style.Theme.text; Layout.fillWidth: true; wrapMode: Text.Wrap }
                SettingsButton { text: "Remove permission…"; enabled: page.loaded && !page.busy; onClicked: page.review("remove-service", serviceRow.modelData) }
            }
        }
        Repeater {
            model: page.allowedPorts
            delegate: ColumnLayout {
                id: portRow
                required property string modelData
                Layout.fillWidth: true
                Label { text: "Port " + portRow.modelData + "\n" + page.lifetime("ports", portRow.modelData); color: Style.Theme.text; Layout.fillWidth: true; wrapMode: Text.Wrap }
                SettingsButton { text: "Remove permission…"; enabled: page.loaded && !page.busy; onClicked: page.review("remove-port", portRow.modelData) }
            }
        }
    }
    SettingsButton { objectName: "firewallAdvanced"; text: page.advanced ? "Hide Advanced options" : "Show Advanced options"; enabled: !page.busy; onClicked: page.advanced = !page.advanced }
    SettingsCard {
        title: "Advanced: network groups and timing"
        visible: page.advanced
        Layout.fillWidth: true
        Label { text: "firewalld calls a network group a zone. The list below shows which network interfaces or source addresses use each zone. Selecting a zone edits its rules; it does not move your connection to that zone."; color: Style.Theme.muted; wrapMode: Text.Wrap; Layout.fillWidth: true }
        Label { text: page.snapshot.active || "No active zone bindings reported."; color: Style.Theme.text; wrapMode: Text.Wrap; Layout.fillWidth: true; textFormat: Text.PlainText }
        SettingsComboBox { objectName: "firewallZone"; Layout.fillWidth: true; model: page.snapshot.zones || []; currentIndex: model.indexOf(page.zone); enabled: page.loaded && !page.busy && !page.dirty; onActivated: { page.zone = currentText; page.refresh(); } }
        SettingsComboBox { objectName: "firewallScope"; Layout.fillWidth: true; model: ["Apply now and keep after restart", "Temporary: apply now only", "Save only: apply after reload or restart"]; currentIndex: ["both", "runtime", "permanent"].indexOf(page.scope); enabled: !page.busy && !page.dirty; onActivated: { page.scope = ["both", "runtime", "permanent"][currentIndex]; page.refresh(); } }
        Label { text: "Temporary changes disappear when the firewall reloads or restarts. Save-only changes do not work immediately. The default changes only the rule you confirm in both configurations."; color: Style.Theme.muted; Layout.fillWidth: true; wrapMode: Text.Wrap }
        SettingsTextField { id: service; objectName: "firewallService"; Layout.fillWidth: true; placeholderText: "Another firewalld service name"; enabled: !page.busy; selectByMouse: true }
        SettingsButton { objectName: "addFirewallService"; text: "Allow named service…"; enabled: page.loaded && !page.busy && !!service.text.trim(); onClicked: page.review("add-service", service.text.trim()) }
    }
    SettingsCard {
        title: "Advanced: block an address"
        subtitle: "Block incoming traffic from a specific IPv4/IPv6 address or network in this zone. Earlier advanced rules or policies can take precedence."
        visible: page.advanced
        Layout.fillWidth: true
        SettingsTextField { id: source; objectName: "firewallSource"; Layout.fillWidth: true; placeholderText: "IP address or CIDR, e.g. 192.0.2.10"; enabled: !page.busy; selectByMouse: true }
        SettingsButton { text: "Block this address…"; enabled: page.loaded && !page.busy && !!source.text.trim(); onClicked: page.review("block-source", source.text.trim()) }
        Repeater {
            model: page.rules("rich")
            delegate: ColumnLayout {
                id: richRow
                required property string modelData
                Layout.fillWidth: true
                Label { text: richRow.modelData; color: Style.Theme.text; Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText }
                SettingsButton { text: "Remove advanced rule…"; enabled: page.loaded && !page.busy; onClicked: page.review("remove-rich", richRow.modelData) }
            }
        }
    }
    SettingsCard {
        title: "Advanced: full details"
        visible: page.advanced
        Layout.fillWidth: true
        Label { text: page.snapshot.details || "Check status to inspect the zone’s policy and full rules."; color: Style.Theme.text; Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText }
        Label { visible: page.scope === "both"; text: "Saved for restart:\n" + ((page.snapshot.saved || {}).details || "Unavailable"); color: Style.Theme.muted; Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText }
        Label { text: "These controls manage incoming zone rules. Outgoing restrictions, forwarding, policies and connection zone assignments use advanced firewalld/NetworkManager tools. Firewall rules stay on this machine and are outside GitHub desktop sync."; color: Style.Theme.muted; Layout.fillWidth: true; wrapMode: Text.Wrap }
        SettingsButton { text: "Open firewalld documentation"; onClicked: Qt.openUrlExternally("https://firewalld.org/documentation/howto/open-a-port-or-service.html") }
    }
}
