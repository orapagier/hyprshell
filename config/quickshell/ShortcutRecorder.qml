pragma ComponentBehavior: Bound
import QtQuick
import "style" as Style
import QtQuick.Controls.Basic
import QtQuick.Layouts
import QtQuick.Window
import Quickshell.Wayland
import "ShortcutKeys.js" as KeysModel

Control {
    id: recorder
    property var targetWindow: null
    property string value: ""
    property bool recording: false
    property string pending: ""
    property string preview: ""
    property string error: ""
    property var pressed: []
    signal recorded(string shortcut)
    readonly property bool ready: inhibitor.active
    implicitHeight: Math.max(68, content.implicitHeight + topPadding + bottomPadding)
    padding: 12
    focusPolicy: Qt.StrongFocus
    function begin() {
        error = ""; pending = ""; preview = ""; pressed = [];
        recording = true;
        forceActiveFocus();
        readyTimeout.restart();
    }
    function cancel() {
        recording = false; pending = ""; preview = ""; pressed = [];
        readyTimeout.stop();
    }
    function handlePress(event) {
        event.accepted = true;
        if (event.isAutoRepeat) return;
        if (event.key === Qt.Key_Escape && event.modifiers === Qt.NoModifier) { cancel(); return; }
        if (event.key === Qt.Key_AltGr || (event.modifiers & Qt.GroupSwitchModifier)) {
            error = "Use Super, Ctrl, Alt or Shift."; return;
        }
        if (!pressed.includes(event.key)) pressed = pressed.concat([event.key]);
        let modifier = KeysModel.modifierFlag(event.key);
        if (modifier) {
            if (!pending) preview = KeysModel.modifiers(event.modifiers | modifier).join(" + ");
            return;
        }
        if (pending) return;
        let shortcut = KeysModel.combination(event.key, event.modifiers, event.nativeScanCode || 0);
        if (!shortcut) { error = "This key could not be recorded. Try another key."; return; }
        error = ""; pending = shortcut; preview = shortcut;
    }
    function handleRelease(event) {
        event.accepted = true;
        if (event.isAutoRepeat) return;
        pressed = pressed.filter(key => key !== event.key);
        let remaining = event.modifiers & ~KeysModel.modifierFlag(event.key);
        if (pending && !pressed.length && !KeysModel.modifiers(remaining).length) {
            let shortcut = pending;
            cancel();
            recorded(shortcut);
            recordButton.forceActiveFocus();
        } else if (!pending) preview = KeysModel.modifiers(remaining).join(" + ");
    }
    onActiveFocusChanged: Qt.callLater(() => { if (recording && !activeFocus) cancel(); })
    onVisibleChanged: if (!visible) cancel()
    onEnabledChanged: if (!enabled) cancel()
    Window.onActiveChanged: if (recording && !Window.active) cancel()
    Keys.priority: Keys.BeforeItem
    Keys.onShortcutOverride: event => { if (recording) event.accepted = true; }
    Keys.onPressed: event => {
        if (!recording) return;
        event.accepted = true;
        if (event.key === Qt.Key_Escape && event.modifiers === Qt.NoModifier) cancel();
        else if (ready) handlePress(event);
    }
    Keys.onReleased: event => { if (recording) { event.accepted = true; if (ready) handleRelease(event); } }
    ShortcutInhibitor {
        id: inhibitor
        window: recorder.targetWindow
        enabled: recorder.recording
        onActiveChanged: if (active) readyTimeout.stop()
        onCancelled: if (recorder.recording) { recorder.cancel(); recorder.error = "Recording cancelled. Try again."; }
    }
    Timer {
        id: readyTimeout
        interval: 1800
        onTriggered: {
            if (!recorder.ready) { recorder.cancel(); recorder.error = "Recording is unavailable in this session."; }
        }
    }
    background: Rectangle {
        radius: 12
        color: recorder.recording ? Style.Theme.selection : Style.Theme.field
        border.color: recorder.recording || recorder.activeFocus ? Style.Theme.accentText : Style.Theme.controlBorder
        Behavior on color { ColorAnimation { duration: Style.Theme.duration(recorder, 160) } }
        Behavior on border.color { ColorAnimation { duration: Style.Theme.duration(recorder, 160) } }
    }
    contentItem: ColumnLayout {
        id: content
        spacing: 8
        RowLayout {
            Layout.fillWidth: true
            Item {
                Layout.fillWidth: true
                implicitHeight: Math.max(27, badges.implicitHeight)
                ShortcutBadges { id: badges; width: parent.width; shortcut: recorder.recording ? recorder.preview : recorder.value; foreground: Style.Theme.text; fill: Style.Theme.button; outline: Style.Theme.border }
                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !badges.shortcut
                    text: recorder.recording ? "Press a combination…" : "No shortcut set"
                    color: recorder.recording ? Style.Theme.accentText : Style.Theme.muted; font.pixelSize: Style.Theme.bodySize
                }
            }
            SettingsButton {
                id: recordButton
                objectName: "recordShortcutButton"
                text: recorder.recording ? "Cancel" : recorder.value ? "Record again" : "Record shortcut"
                highlighted: recorder.recording
                focusPolicy: recorder.recording ? Qt.NoFocus : Qt.StrongFocus
                implicitHeight: 36
                onClicked: recorder.recording ? recorder.cancel() : recorder.begin()
            }
        }
        Label {
            Layout.fillWidth: true
            visible: recorder.recording || recorder.error !== ""
            text: recorder.error || (!recorder.ready ? "Preparing recorder…" : recorder.pending ? "Release the keys to confirm" : "Press your shortcut · Esc to cancel")
            color: recorder.error ? Style.Theme.danger : Style.Theme.muted; font.pixelSize: Style.Theme.captionSize
            wrapMode: Text.Wrap
        }
    }
}
