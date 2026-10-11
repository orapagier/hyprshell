import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Services.Notifications
import ".."

ShellRoot {
    id: test
    property int phase: 0
    NotificationInbox { id: inbox; preferences: ({popups: true, doNotDisturb: false, criticalBypass: true, popupSeconds: 2, apps: {}}) }
    Window { visible: true; width: 380; height: 800; NotificationPopupStack { width: parent.width; inbox: inbox } }
    function sample(id, critical, restored) {
        return {id: id, appName: "Test App", desktopEntry: "org.test.App", summary: "Test", body: "Body", actions: [], lastGeneration: !!restored, urgency: critical ? NotificationUrgency.Critical : NotificationUrgency.Normal, dismiss: function() {}};
    }
    function check(value, message) { if (!value) { console.error("NOTIFICATIONS_FAILED", message); Qt.quit(); throw new Error(message); } }
    Timer {
        interval: 100; running: true; repeat: true
        onTriggered: {
            if (!inbox.initialized) return;
            if (test.phase === 0) {
                inbox.receive(test.sample(1, false));
                test.check(inbox.rows.length === 1 && inbox.popups.length === 1, "delivery");
                inbox.receive(test.sample(1, false));
                test.check(inbox.rows.length === 1 && inbox.popups.length === 1, "replacement");
                inbox.receive(test.sample(2, true));
                inbox.preferences = {popups: true, doNotDisturb: true, criticalBypass: true, popupSeconds: 2, apps: {}};
                test.check(inbox.popups.length === 1 && inbox.popups[0].critical, "dnd clears normal popups");
                inbox.receive(test.sample(3, false));
                test.check(inbox.rows.length === 3 && inbox.popups.length === 1, "dnd keeps inbox");
                inbox.hidePopup(inbox.popups[0].id);
                test.check(inbox.rows.length === 3, "close keeps history");
                inbox.preferences = {popups: true, doNotDisturb: false, criticalBypass: true, popupSeconds: 2, apps: {"org.test.App": "off"}};
                inbox.receive(test.sample(4, true));
                test.check(inbox.rows.length === 3 && inbox.popups.length === 0, "off blocks critical");
                inbox.preferences = {popups: true, doNotDisturb: false, criticalBypass: true, popupSeconds: 2, apps: {}};
                inbox.receive(test.sample(5, false, true));
                test.check(inbox.popups.length === 0, "reload does not replay popups");
                for (let i = 6; i < 10; ++i) inbox.receive(test.sample(i, false));
                test.check(inbox.popups.length === 3, "bounded stack");
                test.phase = 1;
                expiry.start();
            }
        }
    }
    Timer {
        id: expiry; interval: 2400
        onTriggered: {
            test.check(inbox.popups.length === 0 && inbox.rows.length === 8, "popup timeout retains history");
            inbox.receive(test.sample(10, true));
            criticalWait.start();
        }
    }
    Timer {
        id: criticalWait; interval: 2400
        onTriggered: {
            test.check(inbox.popups.length === 1, "critical remains visible");
            inbox.clear();
            test.check(inbox.rows.length === 0 && inbox.popups.length === 0, "clear");
            console.log("NOTIFICATIONS_OK"); Qt.quit();
        }
    }
    Timer { interval: 12000; running: true; onTriggered: { console.error("NOTIFICATIONS_FAILED timeout"); Qt.quit(); } }
}
