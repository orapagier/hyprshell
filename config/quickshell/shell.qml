//@ pragma ShellId ba883eebb89585aa1cc7a393f47bfdf8
// Keep the existing notification history when the configuration directory moves.
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "SettingsModel.js" as Settings
import "DockModel.js" as DockModel

ShellRoot {
    id: shell
    property string clockText: ""
    // Root properties keep panel properties from shadowing service IDs.
    readonly property var services: desktopServices
    readonly property var inbox: notificationInbox
    readonly property var statusData: desktopServices.statusData
    readonly property var mediaData: desktopServices.mediaData
    readonly property var notificationData: notificationInbox.statusData
    readonly property int currentWorkspace: Hyprland.focusedMonitor && Hyprland.focusedMonitor.activeWorkspace ? Hyprland.focusedMonitor.activeWorkspace.id : 0
    property var pendingBarToggles: []
    SettingsStore { id: preferences }
    ApplicationService {
        id: applications; store: preferences
        geometryTracking: docks.instances.concat(taskbars.instances).some(d => d.shown && d.panel.hideMode === 'dodge')
    }
    DockUtilities { id: dockUtilities; watching: ['hyprdock','hyprbar'].some(name => preferences.config.panels[name].enabled && preferences.config.panels[name].showTrash) }
    ProjectorWindow { id: projectorWindow }
    PresentationView { id: presentationView }
    Hyprview { id: hyprviewWindow }
    SettingsController {
        id: settingsController
        store: preferences
        wallpaperSources: wallpapers.sources
        lockingError: locking.error
        powerError: [locking.error, power.error].filter(Boolean).join("\n")
        audioServices: desktopServices
        notificationApps: notificationInbox.applications
        clipboardError: clipboard.error
        batteryInfo: desktopServices.batteryInfo
        currentWorkspace: shell.currentWorkspace
        onLockRequested: locking.lockNow()
        // Reopening an existing window must activate it, even on another
        // workspace. Do not remap it or reset a user's tiled/floating choice.
        onFocusRequested: settingsWindow => {
            let existing = Hyprland.toplevels.values.find(t => t.title === settingsWindow.title);
            if (existing)
                Hyprland.dispatch("hl.dsp.focus({ window = 'address:" + existing.address + "' })");
        }
    }
    function updateClock() {
        let now = new Date();
        clockText = Qt.formatDateTime(now, preferences.config.bar.clockFormat);
    }
    ClipboardController { id: clipboard; store: preferences }
    LockingController { id: locking; store: preferences; onBattery: desktopServices.batteryInfo.present && !desktopServices.batteryInfo.pluggedIn }
    PowerController { id: power; store: preferences }
    DesktopServices { id: desktopServices }
    NotificationInbox { id: notificationInbox; preferences: preferences.config.notifications }
    NotificationPopups { inbox: notificationInbox }
    Tray { id: tray }
    WallpaperWatcher { id: wallpapers }
    Component.onCompleted: updateClock()
    Timer { interval: 1000; running: true; repeat: true; onTriggered: shell.updateClock() }
    Variants {
        id: panels
        model: Quickshell.screens
        PanelWindow {
            id: panel
            required property var modelData
            MenuController { id: menuState; dismissPinnedOnLeave: (!panel.visible || openedByShortcut) && !panelDropdown.managingApplications }
            screen: modelData
            visible: {
                // The window's resolved screen can change while hiding/showing.
                // Read the stable Variants model instead of feeding that change
                // back into the window's own visibility binding.
                let monitor = Hyprland.monitorFor(panel.modelData);
                let ws = monitor && monitor.activeWorkspace;
                return Settings.panelVisible(preferences.config, "hyprpane", panel.modelData.name, ws ? ws.id : null);
            }
            exclusiveZone: (vertical ? width : height) + (preferences.config.bar.paddingBottom || 0)
            exclusionMode: visible ? ExclusionMode.Normal : ExclusionMode.Ignore
            onVisibleChanged: if (!visible) menuState.close()
            readonly property string edge: preferences.config.bar.position || "top"
            readonly property bool vertical: edge === "left" || edge === "right"
            readonly property var cornerInsets: DockModel.insets(preferences.config, "hyprpane", panel.modelData.name,
                Hyprland.monitorFor(panel.modelData)?.activeWorkspace?.id ?? null, 0)
            readonly property real availableHeight: Math.max(1, modelData.height - cornerInsets.top - cornerInsets.bottom)
            readonly property bool compact: vertical && preferences.config.bar.verticalPresentation === "compact"
            anchors {
                top: edge !== "bottom"
                bottom: edge !== "top" && !compact
                left: edge !== "right"
                right: edge !== "left"
            }
            margins {
                top: edge === "top" ? preferences.config.bar.marginTop : vertical ? (compact ? cornerInsets.top + (availableHeight - implicitHeight) / 2 : cornerInsets.top + preferences.config.bar.marginSide) : 0
                bottom: edge === "bottom" ? preferences.config.bar.marginTop : vertical ? cornerInsets.bottom + preferences.config.bar.marginSide : 0
                left: edge === "left" ? preferences.config.bar.marginTop : !vertical ? preferences.config.bar.marginSide : 0
                right: edge === "right" ? preferences.config.bar.marginTop : !vertical ? preferences.config.bar.marginSide : 0
            }
            implicitWidth: bar.implicitWidth
            implicitHeight: vertical ? Math.min(bar.implicitHeight, Math.max(1, availableHeight - 2*preferences.config.bar.marginSide)) : bar.implicitHeight
            readonly property real originX: edge === "right" ? screen.width - margins.right - width : margins.left
            readonly property real originY: edge === "bottom" ? screen.height - margins.bottom - height : margins.top
            color: "transparent"
            WlrLayershell.namespace: "hyprshell"
            Bar {
                id: bar
                settings: preferences.config
                anchors.fill: parent
                statusData: shell.statusData
                mediaData: shell.mediaData
                notificationData: shell.notificationData
                outputName: panel.screen.name
                wallpaperSource: wallpapers.sources[panel.screen.name] || ""
                screenWidth: panel.screen.width
                screenHeight: panel.screen.height
                screenOffsetX: panel.originX
                screenOffsetY: panel.originY
                clockText: shell.clockText
                trayModel: tray.items
                activeMenu: menuState.section
                onMenuHovered: name => {
                    panel.closeDockMenus();
                    for (let other of panels.instances) if (other !== panel) other.closeMenu();
                    menuState.hover(name);
                }
                onMenuLeft: name => menuState.leave(name)
                onPreviewUnavailable: menuState.close()
                onAction: (name, argument) => {
                    panel.closeDockMenus();
                    if (name === "workspace") { menuState.close(); shell.services.workspace(argument); }
                    else if (name === "workspace-scroll") shell.services.scrollWorkspace(argument);
                    else if (name === "settings") {
                        for (let panel of panels.instances) panel.closeMenu();
                        settingsController.open();
                    }
                    else {
                        for (let other of panels.instances) if (other !== panel) other.closeMenu();
                        menuState.activate(name);
                    }
                }
                onTrayAction: (item, source, button) => {
                    if (button === Qt.MiddleButton) item.secondaryActivate();
                    else if (button === Qt.RightButton || item.onlyMenu) {
                        if (item.hasMenu) { let position = source.mapToItem(bar,0,source.height); item.display(panel,position.x,position.y); }
                    } else item.activate();
                }
                onTrayScroll: (item,event) => item.scroll(event.angleDelta.y || event.angleDelta.x,!event.angleDelta.y)
            }
            Dropdown {
                id: panelDropdown
                onManagingApplicationsChanged: if (managingApplications) menuState.pinned = true
                wallpaperSource: bar.wallpaperSource
                translucency: Settings.popdownTranslucency(preferences.config, bar.menuItemId(menuState.displayedSection))
                screen: panel.screen
                barEdge: panel.visible ? panel.edge : "top"
                barRect: panel.visible ? Qt.rect(panel.originX, panel.originY, panel.width, panel.height) : Qt.rect(0,0,0,0)
                connected: panel.visible
                movePointerOnOpen: !panel.visible || menuState.openedByShortcut
                section: menuState.section
                displayedSection: menuState.displayedSection
                alignment: panel.visible ? bar.side(menuState.displayedSection) : "center"
                pinned: menuState.pinned
                triggerRect: {
                    if (!panel.visible) return Qt.rect(panel.screen.width / 2, 0, 0, 0);
                    let rect = bar.menuRect(menuState.displayedSection);
                    return Qt.rect(rect.x + panel.originX, rect.y + panel.originY, rect.width, rect.height);
                }
                accent: bar.menuAccent(menuState.displayedSection)
                previewWorkspace: bar.previewWorkspace
                mediaData: shell.mediaData
                services: shell.services
                applicationService: applications
                inbox: shell.inbox
                onCloseRequested: menuState.close()
                onSettingsRequested: settingsController.open()
                onHoverChanged: inside => menuState.retain(inside)
            }
            KeybindingsPopup { id: keybindings; screen: panel.screen; wallpaperSource: bar.wallpaperSource; translucency: preferences.config.bar.popdownTranslucency ?? 0.06 }
            function closeDockMenus() { for (let dock of docks.instances) dock.closeMenu(); for (let bar of taskbars.instances) bar.closeMenu(); }
            function closeMenu() { menuState.close(); keybindings.opened = false; }
            function refreshSettings() {
                if (!panel.visible || (menuState.section && !bar.itemEnabled(bar.menuItemId(menuState.section)))) menuState.close();
            }
            function toggleMenu(name) { closeDockMenus(); keybindings.opened = false; menuState.activate(name, true); }
            function toggleLauncher() { toggleMenu("launcher"); }
            function toggleKeybindings() { closeDockMenus(); menuState.close(); keybindings.opened = !keybindings.opened; }
        }
    }
    Variants {
        id: docks
        model: Quickshell.screens
        DockWindow {
            id: dockWindow
            desktopServices:shell.services; inbox:shell.inbox
            statusData:shell.statusData; mediaData:shell.mediaData; notificationData:shell.notificationData
            trayModel:tray.items; clockText:shell.clockText
            required property var modelData
            output: modelData
            utilities: dockUtilities
            onSettingsRequested: settingsController.open()
            service: applications
            config: preferences.config
            wallpaperSource: wallpapers.sources[modelData.name] || ""
            paneThickness: {
                let pane = panels.instances.find(p => p.modelData.name === modelData.name);
                return pane ? pane.implicitHeight : preferences.config.bar.height;
            }
            onInteractionStarted: {
                for (let panel of panels.instances) panel.closeMenu();
                for (let dock of docks.instances) if (dock !== dockWindow) dock.closeMenu();
                for (let bar of taskbars.instances) bar.closeMenu();
            }
        }
    }
    Variants {
        id: taskbars
        model: Quickshell.screens
        DockWindow {
            id: taskbarWindow
            required property var modelData
            component: 'hyprbar'
            desktopServices:shell.services; inbox:shell.inbox
            statusData:shell.statusData; mediaData:shell.mediaData; notificationData:shell.notificationData
            trayModel:tray.items; clockText:shell.clockText
            output: modelData
            utilities: dockUtilities
            onSettingsRequested: settingsController.open()
            service: applications
            config: preferences.config
            wallpaperSource: wallpapers.sources[modelData.name] || ""
            paneThickness: {
                let pane = panels.instances.find(p => p.modelData.name === modelData.name);
                return pane ? pane.implicitHeight : preferences.config.bar.height;
            }
            onInteractionStarted: {
                for (let panel of panels.instances) panel.closeMenu();
                for (let dock of docks.instances) dock.closeMenu();
                for (let bar of taskbars.instances) if (bar !== taskbarWindow) bar.closeMenu();
            }
        }
    }
    Connections {
        target: preferences
        function onConfigChanged() {
            shell.updateClock();
            for (let panel of panels.instances) panel.refreshSettings();
        }
    }
    Process {
        id: barVisibilityWriter
        onExited: barToggleQueue.restart()
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let result = JSON.parse(text);
                    if (result.ok) preferences.reload();
                    else console.warn("Hyprpane toggle: " + result.message);
                } catch (error) { console.warn("Hyprpane toggle failed: " + error); }
            }
        }
    }
    Timer {
        id: barToggleQueue
        interval: 0
        onTriggered: {
            if (barVisibilityWriter.running || shell.pendingBarToggles.length === 0) return;
            let workspace = shell.pendingBarToggles.shift();
            barVisibilityWriter.command = ["python3", decodeURIComponent(Qt.resolvedUrl("settings/backend.py").toString().replace(/^file:\/\//, "")), "--toggle-bar", String(workspace)];
            barVisibilityWriter.running = true;
        }
    }
    Process {
        id: desktopReloader
        command: ["timeout", "15", "hyprctl", "reload"]
        stderr: StdioCollector {
            onStreamFinished: if (text.trim()) console.warn("Hyprland reload: " + text.trim())
        }
        onExited: (code, status) => {
            if (code !== 0) console.warn("Hyprland reload failed (exit " + code + "); reloading Quickshell.");
            // Reload Quickshell after Hyprland has loaded the saved shortcuts.
            Quickshell.reload(true);
        }
    }
    IpcHandler {
        target: "bar"
        function ready(): bool {
            if (panels.instances.length === 0) return false;
            for (let panel of panels.instances) if (panel.visible && !panel.backingWindowVisible) return false;
            return true;
        }
        function reload(): void {
            if (!desktopReloader.running) desktopReloader.running = true;
        }
        function settings(): void {
            for (let panel of panels.instances) panel.closeMenu();
            settingsController.open();
        }
        function displays(): void {
            for (let panel of panels.instances) panel.closeMenu();
            let focused = Hyprland.focusedMonitor;
            let panel = panels.instances.find(p => focused && p.screen.name === focused.name) || panels.instances[0];
            if (panel) projectorWindow.screen = panel.screen;
            projectorWindow.open();
        }
        function hyprview(): void {
            hyprviewWindow.projectActive();
        }
        function closeHyprview(): void {
            hyprviewWindow.dismiss();
        }
        function toggleBar(): void {
            let workspace = shell.currentWorkspace;
            if (workspace < 1 || workspace > 99) {
                console.warn("Hyprpane toggle needs an active numbered workspace (1–99).");
                return;
            }
            let ui = settingsController.window;
            if (ui) ui.toggleWorkspaceBar(workspace);
            else {
                shell.pendingBarToggles.push(workspace);
                barToggleQueue.restart();
            }
        }
        function toggleMenu(name: string): void {
            if (!["calendar", "notifications", "audio", "wifi", "bluetooth", "battery", "power", "launcher"].includes(name)) return;
            let focused = Hyprland.focusedMonitor;
            let panel = panels.instances.find(p => focused && p.screen.name === focused.name) || panels.instances[0];
            for (let other of panels.instances) if (other !== panel) other.closeMenu();
            if (panel) panel.toggleMenu(name);
        }
        function toggleKeybindings(): void {
            let focused = Hyprland.focusedMonitor;
            let panel = panels.instances.find(p => focused && p.screen.name === focused.name) || panels.instances[0];
            for (let other of panels.instances) if (other !== panel) other.closeMenu();
            if (panel) panel.toggleKeybindings();
        }
        function toggleLauncher(): void {
            let focused = Hyprland.focusedMonitor;
            let panel = panels.instances.find(p => focused && p.screen.name === focused.name) || panels.instances[0];
            if (panel) panel.toggleLauncher();
        }
    }
}
