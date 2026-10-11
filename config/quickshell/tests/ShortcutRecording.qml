import QtQuick
import QtQuick.Window
import Quickshell
import ".."

ShellRoot {
    id: test
    property string captured: ""
    Window {
        visible: true; width: 640; height: 480
        ShortcutRecorder { id: recorder; width: 600; onRecorded: shortcut => test.captured = shortcut }
        SettingsKeybindings { id: editor; visible: false; width: 600 }
    }
    function fail(message) { console.error("SHORTCUT_RECORDING_FAILED", message); Qt.quit(); }
    Timer {
        interval: 100; running: true
        onTriggered: {
            recorder.begin();
            recorder.handlePress({key: Qt.Key_Control, modifiers: Qt.ControlModifier});
            recorder.handlePress({key: Qt.Key_N, modifiers: Qt.ControlModifier});
            recorder.handleRelease({key: Qt.Key_N, modifiers: Qt.ControlModifier});
            if (test.captured || !recorder.recording) { test.fail("confirmed before modifiers released"); return; }
            recorder.handleRelease({key: Qt.Key_Control, modifiers: Qt.ControlModifier});
            if (test.captured !== "CTRL + N" || recorder.recording) { test.fail("release did not confirm"); return; }
            recorder.begin();
            recorder.handlePress({key: Qt.Key_Escape, modifiers: Qt.NoModifier});
            if (recorder.recording || recorder.pending) { test.fail("Escape did not cancel"); return; }
            editor.loaded = true;
            editor.add();
            editor.edit("shortcut", "SUPER + SHIFT + N");
            editor.edit("description", "Notes");
            editor.edit("command", "kitty");
            if (!editor.dirty || !editor.canSave) { test.fail("new shortcut editor flow"); return; }
            editor.closeEditor();
            if (editor.editing) { test.fail("editor did not close"); return; }
            console.log("SHORTCUT_RECORDING_OK"); Qt.quit();
        }
    }
    Timer { interval: 5000; running: true; onTriggered: test.fail("timeout") }
}
