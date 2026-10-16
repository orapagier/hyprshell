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
    property bool geometryTracking: false
    property var entries: DesktopEntries.applications.values.slice().sort((a, b) => a.name.localeCompare(b.name))
    property var windows: Hyprland.toplevels.values
    readonly property var matches: store.config.pins.matches || {}
    readonly property var windowRows: rowCache.value
    QtObject { id: rowCache; property var value: [] }
    // Matching native desktop entries inside Hyprland's grouped property
    // notifications can crash Qt. Signals only queue work; read both models
    // after the notification stack has unwound, without a binding capture.
    function scheduleRows() { Qt.callLater(service.rebuildRows); }
    function rebuildRows() {
        rowCache.value = windows.map(w => Apps.windowData(w, entries, matches));
    }
    onWindowsChanged: scheduleRows()
    onEntriesChanged: scheduleRows()
    onMatchesChanged: scheduleRows()
    Component.onCompleted: scheduleRows()
    readonly property bool busy: writer.running
    property string error: ""
    signal windowSelectionRequested(var group)
    AppIcons { id: icons; visible: false }
    function iconSource(name) { return icons.source(name) || icons.source('application-x-executable'); }
    function entry(id) { return entries.find(e => Apps.desktopId(e) === id) || null; }
    function groups(component) {
        return Apps.groups(entries, [], Settings.effectivePins(store.config, component), matches, windowRows);
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
    Instantiator {
        model: service.entries
        delegate: Connections {
            required property var modelData
            target: modelData && modelData.objectName !== undefined ? modelData : null
            ignoreUnknownSignals: true
            function onIdChanged() { service.scheduleRows(); }
            function onNameChanged() { service.scheduleRows(); }
            function onIconChanged() { service.scheduleRows(); }
            function onStartupClassChanged() { service.scheduleRows(); }
        }
    }
    Instantiator {
        model: service.windows
        delegate: Item {
            required property var modelData
            Connections {
                target: modelData && modelData.objectName !== undefined ? modelData : null
                ignoreUnknownSignals: true
                function onLastIpcObjectChanged() { service.scheduleRows(); }
                function onTitleChanged() { service.scheduleRows(); }
                function onActivatedChanged() { service.scheduleRows(); }
                function onUrgentChanged() { service.scheduleRows(); }
                function onWorkspaceChanged() { service.scheduleRows(); }
                function onMonitorChanged() { service.scheduleRows(); }
                function onWaylandChanged() { service.scheduleRows(); }
            }
            Connections {
                target: modelData.workspace && modelData.workspace.objectName !== undefined ? modelData.workspace : null
                ignoreUnknownSignals: true
                function onIdChanged() { service.scheduleRows(); }
                function onNameChanged() { service.scheduleRows(); }
            }
            Connections {
                target: modelData.monitor && modelData.monitor.objectName !== undefined ? modelData.monitor : null
                ignoreUnknownSignals: true
                function onNameChanged() { service.scheduleRows(); }
            }
            Connections {
                target: modelData.wayland && modelData.wayland.objectName !== undefined ? modelData.wayland : null
                ignoreUnknownSignals: true
                function onAppIdChanged() { service.scheduleRows(); }
            }
        }
    }
    // Coalesce compositor events; there is no periodic client-list polling.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (['openwindow', 'closewindow', 'movewindow', 'movewindowv2', 'windowtitle', 'windowtitlev2',
                 'activewindow', 'activewindowv2', 'urgent', 'monitoradded', 'monitorremoved',
                 'fullscreen', 'changefloatingmode', 'workspace', 'workspacev2', 'focusedmon'].indexOf(event.name) >= 0)
                refresh.restart();
        }
    }
    // Hyprland has no continuous move/resize event. Sample geometry only while
    // an enabled dodge dock needs it, using the existing shared toplevel model.
    Timer {
        interval: 350; repeat: true
        running: service.geometryTracking
        onTriggered: Hyprland.refreshToplevels()
    }
    Timer { id: refresh; interval: 60; onTriggered: Hyprland.refreshToplevels() }
}
