pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "ApplicationModel.js" as Apps
import "SettingsModel.js" as Settings

Item {
    id: service
    required property var store
    // Injectable inputs also let native checks exercise lifecycle without actions.
    property var entries: DesktopEntries.applications.values.slice().sort((a, b) => a.name.localeCompare(b.name))
    property var windows: Hyprland.toplevels.values
    readonly property var windowRows: windows.map(w => Apps.windowData(w, entries, store.config.pins.matches || {}))
    readonly property bool busy: writer.running
    property string error: ""
    signal windowSelectionRequested(var group)
    AppIcons { id: icons; visible: false }
    function iconSource(name) { return icons.source(name) || icons.source('application-x-executable'); }
    function entry(id) { return entries.find(e => Apps.desktopId(e) === id) || null; }
    function groups(component) {
        return Apps.groups(entries, windows, Settings.effectivePins(store.config, component), store.config.pins.matches || {});
    }
    function launch(application) {
        let app = typeof application === 'string' ? entry(application) : application;
        if (!app || !app.id) { error = 'This application is no longer installed.'; return false; }
        let command = Apps.launchCommand(app);
        // Preserve the launcher's UWSM service and unusual-ID fallback semantics.
        if (command.length) Quickshell.execDetached(command);
        else app.execute();
        error = '';
        return true;
    }
    function activate(group) {
        if (!group.windows.length) return launch(group.id);
        if (group.windows.length === 1) return windowAction('focus', group.windows[0].address);
        windowSelectionRequested(group);
        return false;
    }
    function windowAction(action, address, workspace) {
        // Recheck liveness; a menu can outlive its window.
        if (!windows.some(w => w.address === address)) { error = 'This window has closed.'; return false; }
        let command = Apps.windowCommand(action, address, workspace, Hyprland.usingLua);
        if (!command) { error = 'Unsupported window action or workspace.'; return false; }
        Hyprland.dispatch(command);
        error = '';
        return true;
    }
    function edit(action) {
        if (busy) return false;
        error = '';
        writer.command = ['python3', decodeURIComponent(Qt.resolvedUrl('settings/backend.py').toString().replace(/^file:\/\//, '')),
            '--app-action-json', JSON.stringify(action)];
        writer.running = true;
        return true;
    }
    Process {
        id: writer
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let result = JSON.parse(text);
                    if (result.ok) service.store.reload();
                    else service.error = result.message;
                } catch (error) { service.error = 'Application preferences could not be saved: ' + error; }
            }
        }
        stderr: StdioCollector { onStreamFinished: if (text.trim()) service.error = text.trim() }
    }
    // Coalesce compositor events; there is no periodic client-list polling.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (['openwindow', 'closewindow', 'movewindow', 'movewindowv2', 'windowtitle', 'windowtitlev2',
                 'activewindow', 'activewindowv2', 'urgent', 'monitoradded', 'monitorremoved'].indexOf(event.name) >= 0)
                refresh.restart();
        }
    }
    Timer { id: refresh; interval: 60; onTriggered: Hyprland.refreshToplevels() }
}
