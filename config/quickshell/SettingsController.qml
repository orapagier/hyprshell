pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import "SettingsModel.js" as Model

Item {
    id: controller
    required property var store
    property var wallpaperSources: ({})
    property bool dockEnabled: false
    property var dockResolver: null
    property Item dockHost: null
    function hideEmbedded() {
        if (editor.item) editor.item.dockOpened = false;
        release.restart();
    }
    property string lockingError: ""
    property string powerError: ""
    property var audioServices: null
    property var notificationApps: []
    property string clipboardError: ""
    property var batteryInfo: ({})
    property int currentWorkspace: 1
    readonly property var window: editor.item
    readonly property bool loaded: editor.active
    // Only failed, unsaved edits survive unloading; the controls do not.
    property var retainedSession: null
    signal lockRequested()
    signal focusRequested(var settingsWindow)

    function open() {
        dockHost = dockEnabled && dockResolver ? dockResolver() : null;
        editor.active = true;
        let ui = editor.item;
        if (!ui) return;
        if (dockHost && ui.visible) { ui.visible = false; ui.dockOpened = true; }
        else if (!dockHost && ui.dockOpened) { ui.dockOpened = false; ui.visible = true; }
        if (retainedSession) {
            ui.editingSession = false;
            ui.initial = Model.copy(retainedSession.initial);
            ui.draft = Model.copy(retainedSession.draft);
            ui.section = retainedSession.section;
            ui.message = retainedSession.message;
            ui.success = retainedSession.success;
            ui.editingSession = true;
            retainedSession = null;
        }
        ui.open();
    }
    function openDisplays() {
        open();
        if (window) {
            window.searchQuery = "";
            window.section = -7;
        }
    }
    function releaseIfClosed() {
        let ui = editor.item;
        // Process startup is deferred. Dirty edits without a reported error
        // may still be waiting to start, even while running is briefly false.
        if (!ui || ui.uiOpened || !ui.idle || ui.manualDirty || (ui.dirty && ui.success)) return;
        retainedSession = ui.dirty ? {
            initial: Model.copy(ui.initial),
            draft: Model.copy(ui.draft),
            section: ui.section,
            message: ui.message,
            success: ui.success
        } : null;
        editor.active = false;
    }
    LazyLoader {
        id: editor
        active: false
        onItemChanged: release.restart()
        SettingsWindow {
            id: settingsWindow
            store: controller.store
            dockHost: controller.dockHost
            wallpaperSources: controller.wallpaperSources
            lockingError: controller.lockingError
            powerError: controller.powerError
            audioServices: controller.audioServices
            notificationApps: controller.notificationApps
            clipboardError: controller.clipboardError
            batteryInfo: controller.batteryInfo
            currentWorkspace: controller.currentWorkspace
            onFocusRequested: controller.focusRequested(settingsWindow)
            onLockRequested: controller.lockRequested()
        }
    }
    Connections {
        target: editor.item
        function onVisibleChanged() { release.restart(); }
        function onDockOpenedChanged() { release.restart(); }
        function onIdleChanged() { release.restart(); }
        function onDirtyChanged() { release.restart(); }
        function onSuccessChanged() { release.restart(); }
        function onManualDirtyChanged() { release.restart(); }
    }
    // Defer destruction until close handlers and process collectors finish.
    Timer { id: release; interval: 0; onTriggered: controller.releaseIfClosed() }
}
