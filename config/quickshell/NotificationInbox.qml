pragma ComponentBehavior: Bound
import QtQuick
import QtQml.Models
import Quickshell
import Quickshell.Io
import "NotificationPolicy.js" as Policy
import Quickshell.Services.Notifications

Item {
    id: inbox
    property var preferences: ({})
    property var popups: []
    property var heldPopupIds: []
    readonly property var applications: Array.from(new Set(rows.map(r => r.appKey || r.app).filter(Boolean))).sort()
    property var rows: []
    onPreferencesChanged: popups = popups.filter(r => Policy.delivery(preferences, r.appKey, r.critical).popup)
    function hidePopup(id) { popups = popups.filter(r => r.id !== id); }
    function receive(notification) {
        let key = Policy.appKey(notification);
        let critical = notification.urgency === NotificationUrgency.Critical;
        let policy = Policy.delivery(preferences, key, critical);
        if (!policy.inbox) {
            rows = rows.filter(r => !(r.sourceId === notification.id && r.sessionToken === session.token));
            popups = popups.filter(r => !(r.sourceId === notification.id && r.sessionToken === session.token));
            notification.dismiss();
            save();
            return;
        }
        let entry = record(notification);
        if (notification.lastGeneration) return;
        popups = popups.filter(r => r.id !== entry.id);
        if (policy.popup) popups = popups.concat([Object.assign({}, entry, {popupDeadline: Date.now() + (preferences.popupSeconds || 5) * 1000})]).slice(-3);
    }
    property bool initialized: false
    readonly property int unread: rows.filter(r => r.unread).length
    readonly property var statusData: ({count: unread, tooltip: (unread ? unread + " unread notifications" : "Notifications") + (preferences.doNotDisturb ? " · Do Not Disturb" : ""), class: unread ? "unread" : "empty"})
    PersistentProperties {
        id: session
        reloadableId: "native-notification-session"
        property string token: Date.now().toString()
    }
    function save() { if (initialized) history.setText(JSON.stringify(rows)); }
    function record(notification) {
        let old = rows.find(r => r.sourceId === notification.id && r.sessionToken === session.token);
        let entry = {id: old ? old.id : Date.now() + "-" + notification.id, sessionToken: session.token, restored: notification.lastGeneration, sourceId: notification.id, app: notification.appName, summary: notification.summary, body: notification.body, actions: notification.actions.map(a => ({id: a.identifier, text: a.text})), received: notification.lastGeneration && old ? old.received : Date.now(), unread: notification.lastGeneration && old ? old.unread : true, active: true, appKey: Policy.appKey(notification), critical: notification.urgency === NotificationUrgency.Critical};
        rows = [entry].concat(rows.filter(r => r.id !== entry.id));
        popups = popups.map(r => r.id === entry.id ? Object.assign({}, entry, {popupDeadline: r.popupDeadline}) : r);
        save();
        return entry;
    }
    function markRead() { rows = rows.map(r => Object.assign({}, r, {unread: false})); save(); }
    function dismiss(id) {
        let row = rows.find(r => r.id === id);
        let live = row && row.sessionToken === session.token && server.trackedNotifications.values.find(n => n.id === row.sourceId);
        if (live) live.dismiss();
        hidePopup(id);
        rows = rows.filter(r => r.id !== id); save();
    }
    function clear() {
        for (let n of server.trackedNotifications.values.slice()) n.dismiss();
        popups = [];
        rows = []; save();
    }
    function invoke(id, actionId) {
        let row = rows.find(r => r.id === id);
        let n = row && row.sessionToken === session.token && server.trackedNotifications.values.find(n => n.id === row.sourceId);
        let action = n && n.actions.find(a => a.identifier === actionId);
        if (action) action.invoke();
    }
    FileView {
        id: history
        path: Quickshell.statePath("notifications.json")
        printErrors: false
        onLoaded: {
            try {
                let stored = JSON.parse(text());
                let current = inbox.rows.map(row => {
                    let old = stored.find(r => r.sessionToken === row.sessionToken && r.sourceId === row.sourceId);
                    return old && row.restored ? Object.assign({}, row, {id: old.id, received: old.received, unread: old.unread}) : row;
                });
                inbox.rows = current.concat(stored.filter(old => !current.some(row => row.id === old.id || (row.sessionToken === old.sessionToken && row.sourceId === old.sourceId))).map(row => Object.assign({}, row, {active: row.sessionToken === session.token && server.trackedNotifications.values.some(n => n.id === row.sourceId)})));
            }
            catch (error) { console.warn("Notification history:", error); }
            inbox.initialized = true;
            inbox.save();
        }
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound) legacyImport.running = true;
            else console.warn("Could not read notification history; leaving the file unchanged.");
        }
    }
    // One-time, read-only import of the previous inbox. No Python process is used.
    Process {
        id: legacyImport
        command: ["sqlite3", "-readonly", "-json", Quickshell.env("HOME") + "/.local/state/waybar/notifications/inbox.sqlite3", "SELECT id,app,summary,body,received,unread FROM notifications WHERE dismissed=0 ORDER BY received DESC"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let old = JSON.parse(text || "[]").map(r => ({id: "legacy-" + r.id, sourceId: -1, app: r.app, summary: r.summary, body: r.body, actions: [], received: r.received * 1000, unread: !!r.unread, active: false}));
                    inbox.rows = inbox.rows.concat(old);
                    inbox.save();
                } catch (error) { console.warn("Previous notification import:", error); }
            }
        }
        onExited: { inbox.initialized = true; inbox.save(); }
    }
    NotificationServer {
        id: server
        keepOnReload: true
        actionsSupported: true
        persistenceSupported: true
        bodySupported: true
        // Optional popups share the same tracked notifications as the inbox.
        onNotification: notification => { notification.tracked = true; inbox.receive(notification); }
    }
    Instantiator {
        model: server.trackedNotifications
        delegate: QtObject {
            id: tracked
            required property var modelData
            property Connections change: Connections {
                target: tracked.modelData
                function onSummaryChanged() { inbox.record(tracked.modelData); }
                function onBodyChanged() { inbox.record(tracked.modelData); }
                function onClosed() {
                    inbox.popups = inbox.popups.filter(r => !(r.sourceId === tracked.modelData.id && r.sessionToken === session.token));
                    inbox.rows = inbox.rows.map(r => r.sourceId === tracked.modelData.id && r.sessionToken === session.token ? Object.assign({}, r, {active: false}) : r);
                    inbox.save();
                }
            }
            property Timer expiry: Timer {
                interval: tracked.modelData.expireTimeout > 0 ? tracked.modelData.expireTimeout : (inbox.preferences.popupSeconds || 5) * 1000
                running: !inbox.popups.some(row => row.sourceId === tracked.modelData.id && inbox.heldPopupIds.includes(row.id)) && !tracked.modelData.resident && tracked.modelData.urgency !== NotificationUrgency.Critical && tracked.modelData.expireTimeout !== 0
                onTriggered: tracked.modelData.expire()
            }
        }
    }
}
