import QtQuick
import QtQuick.Window
import Quickshell
import ".."
import "../style" as Style

ShellRoot {
    id: test
    property int phase: 0
    property bool capturing: false
    SettingsStore { id: prefs }
    SettingsWindow { id: editor; store: prefs }
    function find(item, name) {
        if (!item) return null;
        if (item.objectName === name) return item;
        for (let child of item.children || []) { let result = find(child, name); if (result) return result; }
        return null;
    }
    function check(ok, message) { if (!ok) { console.error("REDESIGN_FAILED", phase, message); Qt.exit(1); } }
    function capture(name) {
        capturing = true;
        find(editor.contentItem, "settingsRoot").grabToImage(result => {
            check(result.saveToFile(Quickshell.env("HYPRSETTINGS_CAPTURE_DIR") + "/" + name + ".png"), "capture " + name);
            capturing = false;
            phase++;
        });
    }
    Timer {
        interval: 250; running: true; repeat: true
        onTriggered: {
            if (!prefs.loaded || test.capturing) return;
            if (test.phase === 0) {
                editor.open();
                editor.contentItem.Window.window.width = 1180;
                editor.contentItem.Window.window.height = 850;
                test.phase++;
            } else if (test.phase === 1) {
                test.check(test.find(editor.contentItem, "settingsHomePage-25").visible, "Bluetooth overview link");
                test.capture("overview");
            } else if (test.phase === 2) {
                editor.section = -9;
                test.phase++;
            } else if (test.phase === 3) {
                test.check(test.find(editor.contentItem, "settingsNav-9").visible, "destination group revealed");
                test.capture("input");
            } else if (test.phase === 4) {
                editor.section = -25;
                test.phase++;
            } else if (test.phase === 5) {
                test.check(test.find(editor.contentItem, "bluetoothPower") !== null, "Bluetooth page loads");
                test.check(!test.find(editor.contentItem, "bluetoothPair").enabled, "unavailable adapter is disabled");
                test.capture("bluetooth");
            } else if (test.phase === 6) {
                editor.goHome();
                editor.contentItem.Window.window.width = 720;
                test.phase++;
            } else if (test.phase === 7) {
                let page = test.find(editor.contentItem, "settingsPageContent");
                let scroll = test.find(editor.contentItem, "settingsEditorScroll");
                test.check(page.width <= scroll.availableWidth + 1, "narrow page overflow");
                test.capture("narrow");
            } else if (test.phase === 8) {
                Style.Theme.preferences = {textScale: 1.5, highContrast: true, reducedMotion: true};
                editor.section = -16;
                test.phase++;
            } else if (test.phase === 9) {
                test.check(Style.SettingsTheme.background.toString() === "#000000", "high contrast");
                test.check(Style.SettingsTheme.bodySize === 21 && Style.SettingsTheme.duration(null, 220) === 0, "accessible typography and motion");
                test.capture("accessible");
            } else if (test.phase === 10) {
                test.check(!editor.dirty && !editor.saving, "browsing wrote preferences");
                console.log("REDESIGN_OK"); Qt.quit();
            }
        }
    }
    Timer { interval: 14000; running: true; onTriggered: { console.error("REDESIGN_TIMEOUT", test.phase); Qt.exit(2); } }
}
