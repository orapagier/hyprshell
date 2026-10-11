import QtQuick
import Quickshell
import ".."
import "../style" as Style

ShellRoot {
    id: test
    property int phase: 0
    SettingsStore { id: prefs }
    SettingsWindow { id: editor; store: prefs }
    function find(root, name) { if (!root) return null; if (root.objectName === name) return root; for (let child of root.children || []) { let result = find(child, name); if (result) return result; } return null; }
    function fail(message) { console.error("ACCESSIBILITY_FAILED", message); Qt.quit(); }
    Timer {
        interval: 80; running: true; repeat: true
        onTriggered: {
            if (!prefs.loaded) return;
            if (test.phase === 0) {
                editor.open(); editor.section = -16;
                let picker = test.find(editor.contentItem, "accessibleTextSize"); picker.activated(3);
                let contrast = test.find(editor.contentItem, "accessibleContrast"); contrast.checked = true; contrast.toggled();
                let motion = test.find(editor.contentItem, "accessibleMotion"); motion.checked = true; motion.toggled();
                if (Style.Theme.bodySize !== 21 || Style.Theme.background.toString() !== "#000000" || Style.Theme.duration(null, 180) !== 0) { test.fail("reactive appearance"); return; }
                test.phase = 1;
            } else if (test.phase === 1 && !editor.dirty && !editor.saving) {
                editor.visible = false; test.phase = 2;
            } else if (test.phase === 2) {
                editor.open();
                if (editor.draft.accessibility.textScale !== 1.5 || !editor.draft.accessibility.highContrast || !editor.draft.accessibility.reducedMotion) { test.fail("persistence"); return; }
                console.log("ACCESSIBILITY_OK"); Qt.quit();
            }
        }
    }
    Timer { interval: 12000; running: true; onTriggered: test.fail("timeout " + editor.message) }
}
