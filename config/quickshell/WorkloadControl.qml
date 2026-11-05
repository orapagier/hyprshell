import QtQuick

// Explicit IPC actions only: no timers, observers or changes during normal use.
QtObject {
    property bool supported: false
    property bool otherUiOpen: false
    property var dock: null
    property var settings: null
    readonly property var pages: ["launcher", "settings", "dashboard", "activity",
        "calendar", "audio", "wifi", "bluetooth", "battery", "notifications", "power"]
    function settingsSafe() {
        let window = settings?.window;
        return !window || (!window.dirty && !window.manualDirty && !window.saving && window.idle);
    }
    function snapshot() {
        let window = settings?.window;
        return {version: 1, supported: supported && !!dock, otherUiOpen: otherUiOpen,
            safe: !window || (!window.dirty && !window.manualDirty),
            busy: !!window && (window.saving || !window.idle),
            settingsOpen: window?.uiOpened === true,
            dock: dock ? dock.workloadState() : null};
    }
    function openPage(name) {
        if (!supported || !dock || otherUiOpen || !settingsSafe())
            return {ok: false, error: "Unsupported desktop, another overlay, or pending Settings edits"};
        if (!pages.includes(name)) return {ok: false, error: "Unsupported workload page"};
        if (dock.expanded || settings?.window?.uiOpened)
            return {ok: false, error: "Close shell UI before opening a workload page"};
        if (name === "settings") settings.open();
        else dock.open(name, true);
        return {ok: true};
    }
    function closePage() {
        if (!supported || !dock || otherUiOpen || !settingsSafe())
            return {ok: false, error: "UI changed or Settings has pending edits; leave it for the user"};
        if (settings?.window?.uiOpened) settings.window.hideEditor();
        dock.dismissWithEscape();
        return {ok: true};
    }
}
