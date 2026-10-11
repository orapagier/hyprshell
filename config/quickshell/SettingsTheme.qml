import QtQuick
import "style" as Style
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Quickshell.Io

ColumnLayout {
    id: page
    property string mode: "light"
    property bool loaded: false
    property bool success: true
    property string message: ""
    property string revision: ""
    property var appearance: ({font: "", cursorTheme: "", cursorSize: 24})
    property var fonts: []
    property var cursors: []
    property string fontFamily: ""
    property int fontSize: 11
    property var retainedAppearance: null
    readonly property bool busy: worker.running
    readonly property bool dirty: loaded && (fontPicker.currentText !== fontFamily || fontPoints.value !== fontSize || cursorPicker.currentText !== appearance.cursorTheme || cursorPixels.value !== appearance.cursorSize)
    spacing: 16
    onVisibleChanged: if (visible && !busy && !dirty) request("status", mode)
    Component.onCompleted: if (visible) request("status", mode)
    function request(operation, nextMode, nextAppearance) {
        if (busy) return;
        retainedAppearance = operation === "save" && !nextAppearance && dirty ? {font: fontPicker.currentText, size: fontPoints.value, cursor: cursorPicker.currentText, pixels: cursorPixels.value} : null;
        let payload = {operation: operation, mode: nextMode, expected: mode};
        if (revision) payload.expectedRevision = revision;
        if (nextAppearance) { payload.appearance = nextAppearance; payload.expectedAppearance = appearance; }
        worker.command = ["python3", decodeURIComponent(Qt.resolvedUrl("settings/theme.py").toString().replace(/^file:\/\//, "")), "--request-json", JSON.stringify(payload)];
        worker.running = true;
    }
    Process {
        id: worker
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let result = JSON.parse(text);
                    page.success = result.ok;
                    page.message = result.message || "";
                    if (result.ok) {
                        page.mode = result.mode; page.loaded = true;
                        page.revision = result.revision || "";
                        if (result.font) {
                            page.appearance = {font: result.font, cursorTheme: result.cursorTheme, cursorSize: result.cursorSize};
                            page.fonts = result.fonts; page.cursors = result.cursors;
                            page.fontFamily = result.fontFamily; page.fontSize = result.fontSize;
                            // A color-only save must keep unapplied font/cursor edits.
                            fontPicker.currentIndex = page.fonts.indexOf(page.retainedAppearance ? page.retainedAppearance.font : page.fontFamily);
                            fontPoints.value = page.retainedAppearance ? page.retainedAppearance.size : page.fontSize;
                            cursorPicker.currentIndex = page.cursors.indexOf(page.retainedAppearance ? page.retainedAppearance.cursor : result.cursorTheme);
                            cursorPixels.value = page.retainedAppearance ? page.retainedAppearance.pixels : result.cursorSize;
                        }
                    }
                    themeToggle.checked = Qt.binding(() => page.mode === "dark");
                } catch (e) { page.success = false; page.message = "Could not read application appearance. Try refreshing."; }
            }
        }
        stderr: StdioCollector { onStreamFinished: if (text) { page.success = false; page.message = text; } }
    }
    SettingsCard {
        Layout.fillWidth: true
        title: "Application windows"
        subtitle: "Choose a system color preference for apps. The topbar keeps its own appearance."
        SettingsSwitch {
            id: themeToggle
            objectName: "applicationDarkTheme"
            text: "Dark theme"
            enabled: page.loaded && !page.busy
            checked: page.mode === "dark"
            onToggled: page.request("save", checked ? "dark" : "light")
        }
        Label { text: page.mode === "dark" ? "Dark" : "Light"; color: Style.Theme.accentText }
        Label { text: "Apps with their own appearance setting should use Follow system. Reopen apps that do not change automatically."; color: Style.Theme.muted; Layout.fillWidth: true; wrapMode: Text.Wrap }
        Label { visible: !!page.message; text: page.message; color: page.success ? Style.Theme.success : Style.Theme.danger; Layout.fillWidth: true; wrapMode: Text.Wrap }
        SettingsButton { text: page.dirty ? "Discard edits & refresh" : "Refresh"; enabled: !page.busy; onClicked: page.request("status", page.mode) }
    }
    SettingsCard {
        Layout.fillWidth: true
        title: "Application font and cursor"
        subtitle: "GTK apps and Qt apps using GTK integration share these preferences. Reopen apps that do not update automatically."
        Label { text: "Application font"; color: Style.Theme.text }
        RowLayout {
            Layout.fillWidth: true
            SettingsComboBox { id: fontPicker; objectName: "applicationFont"; Layout.fillWidth: true; model: page.fonts; enabled: page.loaded && !page.busy }
            SettingsSpinBox { id: fontPoints; objectName: "applicationFontSize"; from: 6; to: 32; value: 11; enabled: page.loaded && !page.busy }
            Label { text: "pt"; color: Style.Theme.muted }
        }
        Label { text: "Cursor theme and size"; color: Style.Theme.text }
        RowLayout {
            Layout.fillWidth: true
            SettingsComboBox { id: cursorPicker; objectName: "applicationCursor"; Layout.fillWidth: true; model: page.cursors; enabled: page.loaded && !page.busy }
            SettingsSpinBox { id: cursorPixels; objectName: "applicationCursorSize"; from: 16; to: 64; value: 24; stepSize: 4; enabled: page.loaded && !page.busy }
            Label { text: "px"; color: Style.Theme.muted }
        }
        SettingsButton {
            objectName: "saveApplicationAppearance"
            text: "Apply font and cursor"
            highlighted: page.dirty
            enabled: page.loaded && !page.busy && page.dirty && fontPicker.currentIndex >= 0 && cursorPicker.currentIndex >= 0
            onClicked: page.request("save", page.mode, {font: page.fonts[fontPicker.currentIndex] + " " + fontPoints.value, cursorTheme: page.cursors[cursorPicker.currentIndex], cursorSize: cursorPixels.value})
        }
        Label { text: "Apps with custom fonts or themes keep their own choices. The topbar uses its separate appearance controls."; color: Style.Theme.muted; Layout.fillWidth: true; wrapMode: Text.Wrap }
    }
}
