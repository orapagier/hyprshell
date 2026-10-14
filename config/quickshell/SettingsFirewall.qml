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
    property var original: null
    property bool dnsDirty: false
    property string dnsModeDraft: "automatic"
    property string dnsServersDraft: ""
    readonly property var dnsModes: ["automatic", "custom", "malicious", "family"]
    readonly property var dnsLabels: ["Automatic (network DNS)", "Custom DNS", "Block malicious sites", "Block adult + malicious sites"]
    function resetDnsDraft() {
        dnsDirty = false;
        dnsModeDraft = snapshot.dnsMode || "automatic";
        dnsServersDraft = (snapshot.dnsServers || []).join(", ");
    }
    onSnapshotChanged: if (!dnsDirty) resetDnsDraft()
    property bool editing: false
    property bool details: false
    property bool help: false
    property string zone: ""
    property string message: ""
    property string lastOperation: "status"
    property bool success: true
    property bool loaded: false
    signal reviewRequested(var card)
    property bool startingRequest: false
    readonly property bool busy: worker.running || startingRequest
    readonly property bool dirty: editing || dnsDirty || pending !== null
    readonly property var rules: (snapshot.rules || []).concat(snapshot.websites || [])
    readonly property var serviceIds: {
        let common = ["ssh", "http", "https", "samba"];
        let catalog = snapshot.catalog || [];
        return common.filter(value => catalog.indexOf(value) >= 0).concat(catalog.filter(value => common.indexOf(value) < 0));
    }
    readonly property var activeNetworks: (snapshot.active || "").split("\n").filter(line => line && line[0] !== " ").map(line => line.split(" ")[0])
    spacing: 16
    Component.onCompleted: if (visible) refresh()
    onVisibleChanged: if (visible && !busy && !dirty) refresh()
    function name(value) { return ({ssh: "Remote login (SSH)", http: "Web server (HTTP)", https: "Secure web server (HTTPS)", samba: "File sharing (Samba)", "dhcpv6-client": "IPv6 network setup", mdns: "Device discovery"})[value] || value; }
    function refresh() { request({operation: "status", zone: zone, scope: "both"}); }
    function discard() { editing = false; original = null; pending = null; }
    function request(payload) {
        if (busy) return;
        startingRequest = true;
        lastOperation = payload.operation;
        worker.command = ["pkexec", "/usr/bin/python3", decodeURIComponent(Qt.resolvedUrl("settings/firewall.py").toString().replace(/^file:\/\//, "")), "--request-json", JSON.stringify(payload)];
        worker.running = true;
    }
    function openEditor(row) {
        original = row; pending = null;
        kind.currentIndex = row ? ["service", "port", "block", "website"].indexOf(row.kind) : (snapshot.running ? 0 : 3);
        service.currentIndex = row && row.kind === "service" ? serviceIds.indexOf(row.value) : 0;
        port.text = row && row.kind === "port" ? row.value.split("/")[0] : "";
        protocol.currentIndex = row && row.kind === "port" && row.value.endsWith("/udp") ? 1 : 0;
        subdomains.checked = row && row.kind === "website" ? row.subdomains === true : true;
        website.text = row && row.kind === "website" ? row.value : "";
        address.text = row && row.kind === "block" ? row.value : "";
        editing = true;
        Qt.callLater(() => reviewRequested(editor));
    }
    function saveRule() {
        let type = ["service", "port", "block", "website"][kind.currentIndex];
        let value = type === "service" ? serviceIds[service.currentIndex] : type === "port" ? port.text.trim() + "/" + protocol.currentText.toLowerCase() : type === "website" ? website.text.trim() : address.text.trim();
        request({operation: original ? (original.kind === "website" ? "edit-website" : "edit-rule") : ({service: "add-service", port: "add-port", block: "block-source", website: "add-website"})[type], kind: type, subdomains: subdomains.checked, value: value, old: original ? original.value : "", expectedWebsite: snapshot.websiteRevision, id: original ? original.id : "", zone: zone, scope: "both", expected: snapshot.revision, confirmed: true});
    }
    function removeRule(row) {
        pending = {operation: ({service: "remove-service", port: "remove-port", block: "remove-rich", rich: "remove-rich", website: "remove-website"})[row.kind], value: row.raw, expectedWebsite: snapshot.websiteRevision, zone: zone, scope: "both", expected: snapshot.revision, confirmed: true, title: row.title + (row.kind === "rich" ? "\n" + row.raw : "")};
        Qt.callLater(() => reviewRequested(confirmation));
    }
    function switchFirewall() {
        pending = {operation: snapshot.running ? "disable" : "enable", confirmed: true};
        Qt.callLater(() => reviewRequested(confirmation));
    }
    Process {
        id: worker
        onExited: (code, status) => { page.startingRequest = false; if (code !== 0) { page.success = false; page.message = code === 126 ? "Authentication cancelled. Nothing was requested." : "Administrator access was not granted or the request could not finish. Refresh to check the result."; } }
        stdout: StdioCollector {
            onStreamFinished: {
                if (!text.trim()) return;
                try {
                    let result = JSON.parse(text);
                    page.success = result.ok; page.message = result.message || "";
                    if (!result.ok && (result.websiteRevision !== undefined || result.dnsFilterInstalled !== undefined)) page.snapshot = Object.assign({}, page.snapshot, result);
                    if (result.ok && (result.running !== undefined || result.websiteRevision !== undefined)) {
                        page.snapshot = result.running !== undefined ? result : Object.assign({}, page.snapshot, result); page.zone = result.zone || ""; page.loaded = true;
                    } else if (!result.ok && page.lastOperation === "status") page.loaded = false;
                    if (result.ok && ["configure-website-dns", "restore-website-dns"].indexOf(page.lastOperation) >= 0) page.resetDnsDraft();
                    if (result.ok && ["status", "setup-website-dns", "restore-website-dns", "configure-website-dns"].indexOf(page.lastOperation) < 0) page.discard();
                    else page.pending = null;
                } catch (e) { page.success = false; page.loaded = false; page.message = "Could not read the firewall status. Try Refresh."; }
            }
        }
        stderr: StdioCollector {}
    }
    SettingsCard {
        title: "Firewall"
        subtitle: "Controls incoming connections to this laptop."
        Layout.fillWidth: true
        RowLayout {
            Layout.fillWidth: true
            Label { objectName: "firewallStatus"; text: !page.loaded ? (page.busy ? "Checking…" : "Status unavailable") : page.snapshot.firewallUnavailable ? "Status unavailable" : page.snapshot.running ? "On" : "Off"; color: !page.loaded ? Style.Theme.muted : page.snapshot.running ? Style.Theme.success : Style.Theme.warning; Layout.fillWidth: true; font.bold: true }
            SettingsSwitch {
                objectName: "firewallSwitch"
                text: ""
                checked: page.loaded && page.snapshot.running === true
                enabled: page.loaded && !page.snapshot.firewallUnavailable && !page.busy && !page.dirty
                Accessible.name: "Firewall on or off"
                onClicked: { checked = Qt.binding(() => page.loaded && page.snapshot.running === true); page.switchFirewall(); }
            }
            SettingsButton { objectName: "refreshFirewall"; text: "Refresh"; enabled: !page.busy; onClicked: { page.pending = null; page.refresh(); } }
        }
        Label { visible: page.loaded && !page.snapshot.running && !page.snapshot.firewallUnavailable; text: "Your network rules are kept. Turn on the firewall to edit them. Website blocks remain active."; color: Style.Theme.muted; Layout.fillWidth: true; wrapMode: Text.Wrap }
        Label { visible: !page.loaded && !page.busy; text: "Refresh to try again. The switch becomes available when the system reports its status."; color: Style.Theme.muted; Layout.fillWidth: true; wrapMode: Text.Wrap }
    }
    Label { visible: page.busy && ["setup-website-dns", "configure-website-dns"].indexOf(page.lastOperation) >= 0; text: "Applying DNS setup… Package installation may take a few minutes."; color: Style.Theme.muted; Layout.fillWidth: true; wrapMode: Text.Wrap }
    Label { objectName: "firewallMessage"; visible: !!page.message; text: page.message; color: page.success ? Style.Theme.success : Style.Theme.danger; Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText }
    Label { visible: !!page.snapshot.websiteError; text: page.snapshot.websiteError || ""; color: Style.Theme.danger; Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText }
    SettingsCard {
        title: "DNS & website protection"
        subtitle: "Choose DNS for this laptop. Manual website blocks work alongside it."
        Layout.fillWidth: true
        Label { objectName: "dnsModeStatus"; text: !page.loaded || !page.snapshot.websiteRevision ? "Refresh to read DNS settings." : page.snapshot.dnsFilterInstalled && !page.snapshot.dnsFilterReady ? "DNS setup needs recovery. Restore it before applying a mode." : "Saved mode: " + page.dnsLabels[Math.max(0, page.dnsModes.indexOf(page.snapshot.dnsMode || "automatic"))]; color: Style.Theme.muted; Layout.fillWidth: true; wrapMode: Text.Wrap }
        SettingsComboBox {
            objectName: "dnsMode"
            Layout.fillWidth: true
            model: page.dnsLabels
            currentIndex: page.dnsModes.indexOf(page.dnsModeDraft)
            enabled: page.loaded && !page.busy && !page.pending
            Accessible.name: "DNS mode"
            onActivated: { page.dnsModeDraft = page.dnsModes[currentIndex]; page.dnsDirty = true; }
        }
        SettingsTextField {
            objectName: "customDnsServers"
            visible: page.dnsModeDraft === "custom"
            Layout.fillWidth: true
            placeholderText: "DNS IP addresses, e.g. 1.1.1.1, 1.0.0.1"
            text: page.dnsServersDraft
            enabled: !page.busy && !page.pending
            selectByMouse: true
            Accessible.name: "Custom DNS server addresses"
            onTextEdited: { page.dnsServersDraft = text; page.dnsDirty = true; }
        }
        Label { text: page.dnsModeDraft === "automatic" ? "Use DNS from your network and VPN. Any local website blocks remain active." : page.dnsModeDraft === "custom" ? "Enter IPv4 or IPv6 addresses separated by commas or spaces. Filtering depends on your chosen DNS provider." : "Uses Cloudflare for Families to filter known malware and phishing domains" + (page.dnsModeDraft === "family" ? " and adult domains." : "."); color: Style.Theme.muted; Layout.fillWidth: true; wrapMode: Text.Wrap }
        Label { visible: page.dnsModeDraft !== "automatic"; text: "Applies across networks and replaces network/VPN DNS for system lookups. Private network names may require Automatic mode. No separate app is needed."; color: Style.Theme.muted; Layout.fillWidth: true; wrapMode: Text.Wrap }
        Label { text: "DNS filtering cannot catch every harmful site or filter content inside a shared website. Browsers with their own secure DNS, VPNs and proxies may bypass it."; color: Style.Theme.muted; Layout.fillWidth: true; wrapMode: Text.Wrap }
        RowLayout {
            SettingsButton {
                objectName: "applyDnsMode"
                text: "Apply DNS mode…"
                enabled: page.loaded && !!page.snapshot.websiteRevision && page.dnsDirty && !page.busy && !page.pending && !(page.snapshot.dnsFilterInstalled && !page.snapshot.dnsFilterReady) && (page.dnsModeDraft !== "custom" || !!page.dnsServersDraft.trim())
                onClicked: {
                    page.pending = {operation: "configure-website-dns", mode: page.dnsModeDraft, servers: page.dnsServersDraft, expectedWebsite: page.snapshot.websiteRevision, confirmed: true, title: page.dnsLabels[page.dnsModes.indexOf(page.dnsModeDraft)] + (page.dnsModeDraft === "custom" ? " (" + page.dnsServersDraft + ")" : "")};
                    Qt.callLater(() => page.reviewRequested(confirmation));
                }
            }
            SettingsButton { objectName: "cancelDnsDraft"; text: "Cancel changes"; visible: page.dnsDirty; enabled: !page.busy && !page.pending; onClicked: page.resetDnsDraft() }
            SettingsButton { objectName: "recoverDnsMode"; text: "Restore DNS setup…"; visible: !!page.snapshot.dnsFilterInstalled; enabled: !page.busy && !page.pending; onClicked: { page.pending = {operation: "restore-website-dns", confirmed: true}; Qt.callLater(() => page.reviewRequested(confirmation)); } }
        }
    }
    SettingsCard {
        id: confirmation
        visible: page.pending !== null
        title: page.pending && page.pending.operation === "configure-website-dns" ? "Apply DNS mode?" : page.pending && page.pending.operation === "setup-website-dns" ? "Set up DNS filter?" : page.pending && page.pending.operation === "restore-website-dns" ? "Restore previous DNS setup?" : page.pending && page.pending.operation === "disable" ? "Turn off firewall?" : page.pending && page.pending.operation === "enable" ? "Turn on firewall?" : "Remove this rule?"
        Layout.fillWidth: true
        Label { text: !page.pending ? "" : page.pending.operation === "configure-website-dns" ? "Apply “" + page.pending.title + "”? This is saved across restarts. DNS will be checked and the previous mode restored if the check fails. Initial setup uses the small dnsmasq system package. You may be asked for your administrator password." : page.pending.operation === "setup-website-dns" ? "Install the small dnsmasq package if needed and connect it to NetworkManager and systemd-resolved. Wi-Fi and VPN DNS servers remain managed by your connections. Setup tests DNS and restores the previous configuration if it fails." : page.pending.operation === "restore-website-dns" ? "Remove Hyprshell’s DNS filter setup and use your previous DNS configuration. Exact website blocks remain; all-subdomain rules need the filter to be set up again." : page.pending.operation === "disable" ? "Incoming connections will no longer be filtered by firewalld. Your rules are kept. It will stay off after restart." : page.pending.operation === "enable" ? "The firewall will use your saved rules now and after restart. You may be asked for your administrator password." : "Remove “" + page.pending.title + "”? The change is saved automatically. Website blocks are separate from network permissions."; color: Style.Theme.text; Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText }
        RowLayout {
            SettingsButton { objectName: "confirmFirewall"; text: !page.pending ? "Confirm" : page.pending.operation === "configure-website-dns" ? "Apply DNS" : page.pending.operation === "setup-website-dns" ? "Set up filter" : page.pending.operation === "restore-website-dns" ? "Restore DNS" : page.pending.operation === "disable" ? "Turn off" : page.pending.operation === "enable" ? "Turn on" : "Remove rule"; enabled: !page.busy; onClicked: page.request(page.pending) }
            SettingsButton { objectName: "cancelFirewall"; text: "Cancel"; enabled: !page.busy; onClicked: page.pending = null }
        }
    }
    SettingsCard {
        id: editor
        objectName: "firewallEditor"
        visible: page.editing
        title: page.original ? "Edit rule" : "Add rule"
        subtitle: "Saved automatically when you click Save."
        Layout.fillWidth: true
        Label { text: "What should this rule do?"; color: Style.Theme.text }
        SettingsComboBox { id: kind; objectName: "firewallRuleKind"; Layout.fillWidth: true; model: page.original && page.original.kind !== "website" ? ["Allow a service", "Allow a port", "Block an IP address"] : ["Allow a service", "Allow a port", "Block an IP address", "Block a website"]; enabled: !page.busy && (!page.original || page.original.kind !== "website") }
        SettingsComboBox { id: service; objectName: "firewallPreset"; visible: kind.currentIndex === 0; Layout.fillWidth: true; model: page.serviceIds.map(value => page.name(value)); enabled: !page.busy }
        Label { visible: kind.currentIndex === 0; text: "Allows other devices to reach this service on your laptop. The service must be installed and running separately."; color: Style.Theme.muted; Layout.fillWidth: true; wrapMode: Text.Wrap }
        SettingsTextField { id: port; objectName: "firewallPort"; visible: kind.currentIndex === 1; Layout.fillWidth: true; placeholderText: "Port number from your app, e.g. 8080"; enabled: !page.busy; selectByMouse: true }
        SettingsComboBox { id: protocol; objectName: "firewallProtocol"; visible: kind.currentIndex === 1; Layout.fillWidth: true; model: ["TCP", "UDP"]; enabled: !page.busy }
        Label { visible: kind.currentIndex === 1; text: "Use the number and TCP/UDP given in your app’s instructions."; color: Style.Theme.muted; Layout.fillWidth: true; wrapMode: Text.Wrap }
        SettingsTextField { id: address; objectName: "firewallSource"; visible: kind.currentIndex === 2; Layout.fillWidth: true; placeholderText: "Numeric IP address, e.g. 192.0.2.10"; enabled: !page.busy; selectByMouse: true }
        Label { visible: kind.currentIndex === 2; text: "Stops incoming traffic from this address in the selected network. Existing advanced policies can also affect access."; color: Style.Theme.muted; Layout.fillWidth: true; wrapMode: Text.Wrap }
        SettingsTextField { id: website; objectName: "firewallWebsite"; visible: kind.currentIndex === 3; Layout.fillWidth: true; placeholderText: "Website name, e.g. example.com"; enabled: !page.busy; selectByMouse: true }
        SettingsSwitch { id: subdomains; objectName: "firewallSubdomains"; visible: kind.currentIndex === 3; text: "Block all subdomains"; checked: true; enabled: !page.busy; Layout.fillWidth: true }
        Label { visible: kind.currentIndex === 3; text: subdomains.checked ? "Includes every subdomain, such as videos.example.com. Requires the DNS filter below." : "Blocks this website and its www name only."; color: Style.Theme.muted; Layout.fillWidth: true; wrapMode: Text.Wrap }
        RowLayout {
            visible: kind.currentIndex === 3
            Layout.fillWidth: true
            Label { text: page.snapshot.dnsFilterReady ? "DNS filter is set up" : page.snapshot.dnsFilterInstalled ? "DNS setup needs recovery" : "DNS filter is not set up"; color: Style.Theme.muted; Layout.fillWidth: true; wrapMode: Text.Wrap }
            SettingsButton { objectName: "setupWebsiteDns"; text: "Set up DNS filter…"; visible: !page.snapshot.dnsFilterReady && !page.snapshot.dnsFilterInstalled; enabled: !page.busy && !page.pending; onClicked: { page.pending = {operation: "setup-website-dns", confirmed: true}; Qt.callLater(() => page.reviewRequested(confirmation)); } }
        }
        SettingsButton { objectName: "repairWebsiteDns"; text: "Restore DNS setup…"; visible: kind.currentIndex === 3; enabled: !page.busy && !page.pending; onClicked: { page.pending = {operation: "restore-website-dns", confirmed: true}; Qt.callLater(() => page.reviewRequested(confirmation)); } }
        Label { visible: kind.currentIndex === 3; text: "Website blocks apply through system DNS. Restart your browser if it caches a result; apps using their own DNS can bypass them."; color: Style.Theme.muted; Layout.fillWidth: true; wrapMode: Text.Wrap }
        Label { visible: kind.currentIndex !== 3 && !page.snapshot.running; text: "Turn on the firewall to add or edit network rules. Website blocks can be changed while it is off."; color: Style.Theme.warning; Layout.fillWidth: true; wrapMode: Text.Wrap }
        RowLayout {
            SettingsButton { objectName: "saveFirewallRule"; text: page.busy ? "Saving…" : "Save rule"; enabled: page.loaded && !page.busy && (kind.currentIndex === 3 ? !!website.text.trim() && !!page.snapshot.websiteRevision && (!subdomains.checked || !!page.snapshot.dnsFilterReady) : page.snapshot.running && (kind.currentIndex === 0 ? service.currentIndex >= 0 : kind.currentIndex === 1 ? !!port.text.trim() : !!address.text.trim())); onClicked: page.saveRule() }
            SettingsButton { objectName: "cancelFirewallEdit"; text: "Cancel"; enabled: !page.busy; onClicked: page.discard() }
        }
    }
    SettingsCard {
        title: "Rules"
        subtitle: "Changes apply immediately and are kept after restart."
        visible: !page.editing && page.loaded
        Layout.fillWidth: true
        RowLayout {
            Layout.fillWidth: true
            SettingsButton { objectName: "addFirewallRule"; text: "Add rule"; enabled: !page.busy && !page.pending; onClicked: page.openEditor(null) }
            SettingsComboBox { objectName: "firewallZone"; visible: page.activeNetworks.length > 1; Layout.fillWidth: true; model: page.activeNetworks; currentIndex: model.indexOf(page.zone); enabled: !page.busy && !page.dirty; Accessible.name: "Network rules to edit"; onActivated: { page.zone = currentText; page.refresh(); } }
        }
        Label { visible: page.activeNetworks.length > 1; text: "Network: " + page.zone; color: Style.Theme.muted; Layout.fillWidth: true; wrapMode: Text.Wrap }
        Label { visible: page.rules.length === 0; text: "No rules to show. Click Add rule to allow a service or block a website or IP address."; color: Style.Theme.muted; Layout.fillWidth: true; wrapMode: Text.Wrap }
        Repeater {
            model: page.rules
            delegate: ColumnLayout {
                id: ruleRow
                required property var modelData
                Layout.fillWidth: true
                spacing: 6
                Label { text: ruleRow.modelData.title; color: Style.Theme.text; font.bold: true; Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText }
                Label { text: ruleRow.modelData.kind === "website" ? (ruleRow.modelData.subdomains ? (ruleRow.modelData.now ? "Website and all subdomains · all networks" : "All-subdomain block needs DNS filter setup") : "Website and www name · all networks") : !ruleRow.modelData.now ? "Saved; takes effect after restart" : !ruleRow.modelData.saved ? "Active only until restart" : (ruleRow.modelData.kind === "block" ? "Blocked" : ruleRow.modelData.kind === "rich" ? "Advanced" : "Allowed"); color: Style.Theme.muted; Layout.fillWidth: true; wrapMode: Text.Wrap }
                Flow {
                    Layout.fillWidth: true; spacing: 8
                    SettingsButton { objectName: "editFirewall-" + ruleRow.modelData.id; text: "Edit"; visible: ruleRow.modelData.editable; enabled: !page.busy && !page.pending; onClicked: page.openEditor(ruleRow.modelData) }
                    SettingsButton { objectName: "removeFirewall-" + ruleRow.modelData.id; text: "Remove"; enabled: !page.busy && !page.pending; onClicked: page.removeRule(ruleRow.modelData) }
                }
            }
        }
    }
    RowLayout {
        SettingsButton { text: page.help ? "Hide help" : "How does this work?"; onClicked: page.help = !page.help }
        SettingsButton { text: page.details ? "Hide details" : "Technical details"; onClicked: page.details = !page.details }
    }
    Label { visible: page.help; text: "Leave the firewall on for normal use. Browsing, email and downloads usually need no extra rule. Add an Allow rule when other devices need to reach a service running here. Block an IP address stops incoming traffic from that device. Block a website covers its domain and www name. With Block all subdomains switched on, the DNS filter covers the entire domain family. Website blocks remain active when firewalld is off. Edit changes a rule; Remove deletes it. Other rules and network policies may also affect access."; color: Style.Theme.muted; Layout.fillWidth: true; wrapMode: Text.Wrap }
    SettingsComboBox { objectName: "firewallAdvancedZone"; visible: page.details && page.loaded && page.snapshot.running; Layout.fillWidth: true; model: page.snapshot.zones || []; currentIndex: model.indexOf(page.zone); enabled: !page.busy && !page.dirty; Accessible.name: "Advanced firewall zone"; onActivated: { page.zone = currentText; page.refresh(); } }
    SettingsButton { objectName: "restoreWebsiteDns"; visible: page.details; text: "Restore DNS setup…"; enabled: !page.busy && !page.pending; onClicked: { page.pending = {operation: "restore-website-dns", confirmed: true}; Qt.callLater(() => page.reviewRequested(confirmation)); } }
    Label { visible: page.details; text: "Current rules:\n" + (page.snapshot.details || "Unavailable") + "\n\nSaved rules:\n" + ((page.snapshot.saved || {}).details || "Unavailable"); color: Style.Theme.muted; Layout.fillWidth: true; wrapMode: Text.Wrap; textFormat: Text.PlainText }
}
