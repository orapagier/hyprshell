pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

Item {
    id: controller
    required property var store
    property var wallpaperSources: ({})
    property bool dockEnabled: false
    property var dockResolver: null
    property Item dockHost: null
    function hideEmbedded() {
        if (editor.item) editor.item.dockOpened = false;
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
    signal lockRequested()
    signal focusRequested(var settingsWindow)

    function open() {
        dockHost = dockEnabled && dockResolver ? dockResolver() : null;
        editor.active = true;
        let ui = editor.item;
        if (!ui) return;
        if (dockHost && ui.visible) { ui.visible = false; ui.dockOpened = true; }
        else if (!dockHost && ui.dockOpened) { ui.dockOpened = false; ui.visible = true; }
        ui.open();
    }
    function openDisplays() {
        open();
        if (window) {
            window.searchQuery = "";
            window.section = -7;
        }
    }
    // Cache the editor for this shell session; open() refreshes clean drafts.
    LazyLoader {
        id: editor
        active: false
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
}
