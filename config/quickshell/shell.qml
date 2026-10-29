//@ pragma ShellId ba883eebb89585aa1cc7a393f47bfdf8
// Keep the existing notification history when the configuration directory moves.
pragma ComponentBehavior: Bound
import QtQuick
import "style" as Style
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "SettingsModel.js" as Settings

ShellRoot {
    id: shell
    // Flush before Quickshell stops child JavaScript during generation teardown.
    Component.onDestruction: notificationInbox.flushHistory(true)
    property string clockText: ""
    property string dockClockText: ""
    readonly property bool dockEnabled: preferences.panelConfig.bar.dockEnabled === true
    function focusedDock() {
        let focused = Hyprland.focusedMonitor;
        return docks.instances.find(d => focused && d.screen.name === focused.name) || docks.instances[0];
    }
    onDockEnabledChanged: {
        let reopenSettings = settingsController.window?.uiOpened === true;
        dashboardWindow.close(); activityWindow.close();
        for (let panel of panels.instances) panel.closeMenu();
        for (let dock of docks.instances) dock.collapse();
        projectorWindow.dismiss();
        projectorWindow.dockHost = null;
        if (reopenSettings) Qt.callLater(() => settingsController.open());
    }
    // Root properties keep panel properties from shadowing service IDs.
    readonly property var services: desktopServices
    readonly property var settingsEditor: settingsController
    readonly property var inbox: notificationInbox
    readonly property var statusData: desktopServices.statusData
    readonly property var mediaData: desktopServices.mediaData
    readonly property var notificationData: notificationInbox.statusData
    readonly property int currentWorkspace: Hyprland.focusedMonitor && Hyprland.focusedMonitor.activeWorkspace ? Hyprland.focusedMonitor.activeWorkspace.id : 0
    function toggleWorkspacePanel(component) {
        let workspace = shell.currentWorkspace;
        if (workspace < 1 || workspace > 99) {
            console.warn(component + " toggle needs an active numbered workspace (1–99).");
            return;
        }
        console.info("HYPRPANE_TIMING", Date.now(), "handler-entry", workspace);
        panelVisibility.toggle(workspace);
        console.info("HYPRPANE_TIMING", Date.now(), "handler-return", workspace);
    }
    SettingsStore { id: preferences }
    PanelVisibilityController {
        id: panelVisibility
        store: preferences
        editor: settingsController.window
    }
    Binding { target: Style.Theme; property: "preferences"; value: preferences.config.accessibility || ({}) }
    ApplicationService {
        id: applications; store: preferences
    }
    Dashboard {
        id: dashboardWindow
        cornersEnabled: !shell.dockEnabled
        services: desktopServices
        wallpaperSource: wallpapers.sources[dashboardWindow.screen?.name] || ""
        translucency: preferences.panelConfig.bar.popdownTranslucency ?? 0.06
        onOpenedChanged: if (opened) {
            activityWindow.close();
            for (let panel of panels.instances) panel.closeMenu();
        }
        onSettingsRequested: settingsController.open()
        onLockRequested: locking.lockNow()
        onMenuRequested: name => {
            let focused = Hyprland.focusedMonitor;
            let panel = panels.instances.find(p => focused && p.screen.name === focused.name) || panels.instances[0];
            for (let other of panels.instances) other.closeMenu();
            if (panel) panel.toggleMenu(name);
        }
    }
    Dashboard {
        id: activityWindow
        cornersEnabled: !shell.dockEnabled
        services: desktopServices
        rightCorner: true
        wallpaperSource: wallpapers.sources[activityWindow.screen?.name] || ""
        translucency: preferences.panelConfig.bar.popdownTranslucency ?? 0.06
        onOpenedChanged: if (opened) {
            dashboardWindow.close();
            for (let panel of panels.instances) panel.closeMenu();
        }
        contentPage: Component {
            ActivityContent {
                inbox: notificationInbox
                store: preferences
                active: activityWindow.opened
                wallpaperSource: activityWindow.wallpaperSource
                screenWidth: activityWindow.width
                screenHeight: activityWindow.height
                wallpaperRegion: activityWindow.bodyRect
                onDismissRequested: activityWindow.close()
            }
        }
    }
    function toggleDashboard() {
        if (dockEnabled) { focusedDock()?.open("dashboard", true); return; }
        for (let panel of panels.instances) panel.closeMenu();
        let focused = Hyprland.focusedMonitor;
        let output = Quickshell.screens.find(s => focused && s.name === focused.name) || Quickshell.screens[0];
        dashboardWindow.toggle(output);
    }
    ProjectorWindow { id: projectorWindow }
    PresentationView { id: presentationView }
    Hyprview { id: hyprviewWindow }
    SettingsController {
        id: settingsController
        dockEnabled: shell.dockEnabled
        dockResolver: () => shell.focusedDock()?.prepareSettings() || null
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
        clockText = Qt.formatDateTime(now, preferences.panelConfig.bar.clockFormat);
        dockClockText = Qt.formatDateTime(now, "HH:mm");
    }
    ClipboardController { id: clipboard; store: preferences }
    LockingController { id: locking; store: preferences; onBattery: desktopServices.batteryInfo.present && !desktopServices.batteryInfo.pluggedIn }
    PowerController { id: power; store: preferences }
    DesktopServices { id: desktopServices }
    NotificationInbox { id: notificationInbox; preferences: preferences.config.notifications }
    NotificationPopups { inbox: notificationInbox; dockEnabled: shell.dockEnabled }
    Tray { id: tray }
    WallpaperWatcher { id: wallpapers }
    Component.onCompleted: updateClock()
    Timer { interval: 1000; running: true; repeat: true; onTriggered: shell.updateClock() }
    Variants {
        id: panels
        // Create layer surfaces with saved margins and attachment on the first map.
        model: preferences.loaded ? Quickshell.screens : []
        PanelWindow {
            id: panel
            required property var modelData
            MenuController { id: menuState; hoverEnabled: Settings.hoverPopdownsEnabled(preferences.panelConfig.bar, panel.workspace); dismissPinnedOnLeave: (!panel.shown || openedByShortcut) && !panelDropdown.managingApplications }
            screen: modelData
            // Keep the Wayland surface and scene graph ready, as Dashboard does.
            // Mapping a previously hidden window synchronously stalls the IPC handler.
            visible: true
            readonly property bool shown: {
                // The window's resolved screen can change while hiding/showing.
                // Read the stable Variants model instead of feeding that change
                // back into the window's own visibility binding.
                let monitor = Hyprland.monitorFor(panel.modelData);
                let ws = monitor && monitor.activeWorkspace;
                return !shell.dockEnabled && Settings.panelVisible(panelVisibility.config, "hyprpane", panel.modelData.name, ws ? ws.id : null);
            }
            // Setting exclusiveZone can reset exclusionMode; hidden panels must
            // explicitly reserve zero even when geometry changes while hidden.
            exclusiveZone: !shown || autoHide ? 0 : Math.ceil((vertical ? width : height) - bar.windowFacingInset) + (preferences.panelConfig.bar.paddingBottom || 0) + outerMargins[({top:"bottom", bottom:"top", left:"right", right:"left"})[edge]]
            exclusionMode: shown ? ExclusionMode.Normal : ExclusionMode.Ignore
            onShownChanged: {
                console.info("HYPRPANE_TIMING", Date.now(), "visible-request", shown);
                if (!shown) panel.closeMenu();
            }
            onBackingWindowVisibleChanged: console.info("HYPRPANE_TIMING", Date.now(), "surface-visible", backingWindowVisible)
            readonly property string edge: preferences.panelConfig.bar.position || "top"
            readonly property bool vertical: edge === "left" || edge === "right"
            readonly property bool autoHide: Settings.edgeAttachmentEnabled(preferences.panelConfig.bar) && preferences.panelConfig.bar.autoHide === true
            readonly property real revealProgress: panelReveal.progress
            mask: Region {
                x: panelReveal.inputRect.x; y: panelReveal.inputRect.y
                width: panel.shown ? panelReveal.inputRect.width : 0; height: panel.shown ? panelReveal.inputRect.height : 0
            }
            PanelReveal {
                id: panelReveal
                anchors.fill: parent
                opacity: panel.shown ? 1 : 0
                enabled: panel.shown
                edge: panel.edge
                autoHide: panel.autoHide
                menuOpen: menuState.section.length > 0 || keybindings.opened
                motionEnabled: preferences.config.accessibility?.reducedMotion !== true && preferences.config.hyprland?.animations !== false
            }
            readonly property var workspace: Hyprland.monitorFor(panel.modelData)?.activeWorkspace?.id ?? null
            readonly property rect menuBounds: Qt.rect(0, 0, modelData.width, modelData.height)
            onWorkspaceChanged: closeMenu()
            onMenuBoundsChanged: closeMenu()
            readonly property var outerMargins: Settings.screenMargins(preferences.panelConfig.bar)
            readonly property real availableHeight: Math.max(1, modelData.height)
            readonly property bool compact: vertical && preferences.panelConfig.bar.verticalPresentation === "compact"
            anchors {
                top: edge !== "bottom"
                bottom: edge !== "top" && !compact
                left: edge !== "right"
                right: edge !== "left"
            }
            margins {
                top: compact ? outerMargins.top + (availableHeight - outerMargins.top - outerMargins.bottom - implicitHeight) / 2 : outerMargins.top
                bottom: outerMargins.bottom
                left: outerMargins.left
                right: outerMargins.right
            }
            implicitWidth: bar.implicitWidth
            implicitHeight: vertical ? Math.min(bar.implicitHeight, Math.max(1, availableHeight - outerMargins.top - outerMargins.bottom)) : bar.implicitHeight
            readonly property real originX: edge === "right" ? screen.width - margins.right - width : margins.left
            readonly property real originY: edge === "bottom" ? screen.height - margins.bottom - height : margins.top
            color: "transparent"
            WlrLayershell.namespace: "hyprshell"
            Bar {
                id: bar
                // Keep controls beneath the hover tracker so their MouseAreas
                // cannot make auto-hide lose the pointer over the panel itself.
                parent: panelReveal
                settings: preferences.panelConfig
                hoverPopdowns: menuState.hoverEnabled
                anchors.fill: parent
                transform: [
                    Translate {
                        x: panel.vertical ? (panel.edge === "left" ? -1 : 1) * (1 - Math.min(1, panel.revealProgress)) * panel.width : 0
                        y: panel.vertical ? 0 : (panel.edge === "top" ? -1 : 1) * (1 - Math.min(1, panel.revealProgress)) * panel.height
                    },
                    Scale {
                        origin.x: bar.width / 2; origin.y: bar.height / 2
                        xScale: panel.vertical ? 1 : 1 + Math.max(0, panel.revealProgress - 1) * 0.15
                        yScale: panel.vertical ? 1 + Math.max(0, panel.revealProgress - 1) * 0.15 : 1
                    }
                ]
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
                    if (!menuState.hoverEnabled) return;
                    for (let other of panels.instances) if (other !== panel) other.closeMenu();
                    menuState.hover(name);
                }
                onMenuLeft: name => menuState.leave(name)
                onPreviewUnavailable: menuState.close()
                onAction: (name, argument) => {
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
                    for (let other of panels.instances) other.closeMenu();
                    if (button === Qt.MiddleButton) item.secondaryActivate();
                    else if (button === Qt.RightButton || item.onlyMenu) {
                        if (item.hasMenu) { let position = source.mapToItem(bar,0,source.height); item.display(panel,position.x,position.y); }
                    } else item.activate();
                }
                onTrayScroll: (item,event) => item.scroll(event.angleDelta.y || event.angleDelta.x,!event.angleDelta.y)
            }
            Dropdown {
                id: panelDropdown
                panelBounds: panel.menuBounds
                onManagingApplicationsChanged: if (managingApplications) menuState.pinned = true
                wallpaperSource: bar.wallpaperSource
                translucency: Settings.popdownTranslucency(preferences.panelConfig, bar.menuItemId(menuState.displayedSection))
                screen: panel.screen
                barEdge: connected ? panel.edge : "top"
                barRect: connected ? Qt.rect(panel.originX, panel.originY, panel.width, panel.height) : Qt.rect(0,0,0,0)
                connected: panel.shown && bar.menuHasTrigger(menuState.displayedSection)
                pointed: bar.menuPointed(menuState.displayedSection)
                movePointerOnOpen: !connected || menuState.openedByShortcut
                section: menuState.section
                displayedSection: menuState.displayedSection
                alignment: connected ? bar.side(menuState.displayedSection) : "center"
                alignToTrigger: connected && bar.centerItems
                pinned: menuState.pinned
                triggerRect: {
                    if (!connected) return Qt.rect(panel.screen.width / 2, 0, 0, 0);
                    let rect = bar.menuAnchorRect(menuState.displayedSection);
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
            KeybindingsPopup { id: keybindings; screen: panel.screen; wallpaperSource: bar.wallpaperSource; translucency: preferences.panelConfig.bar.popdownTranslucency ?? 0.06 }
            Hyprhover {
                id: hoverWindows
                screen: panel.modelData
                available: !shell.dockEnabled && !panel.shown
                workspace: panel.workspace
                settings: preferences.panelConfig
                services: shell.services
                applicationService: applications
                inbox: shell.inbox
                statusData: shell.statusData
                mediaData: shell.mediaData
                notificationData: shell.notificationData
                clockText: shell.clockText
                trayModel: tray.items
                wallpaperSource: bar.wallpaperSource
                onRevealed: {
                    dashboardWindow.close();
                    activityWindow.close();
                    menuState.close();
                    keybindings.opened = false;
                    for (let other of panels.instances) if (other !== panel) other.closeMenu();
                }
                onSettingsRequested: { close(); settingsController.open(); }
            }
            function closeMenu() { hoverWindows.close(); menuState.close(); keybindings.opened = false; }
            function refreshSettings() {
                if (!panel.shown || (menuState.section && !bar.itemEnabled(bar.menuItemId(menuState.section)))) menuState.close();
            }
            function toggleMenu(name) { if (shell.dockEnabled) { shell.focusedDock()?.open(name, true); return; } hoverWindows.close(); keybindings.opened = false; menuState.activate(name, true); }
            function toggleLauncher() { toggleMenu("launcher"); }
            function toggleKeybindings() { if (shell.dockEnabled) { shell.focusedDock()?.open("keybindings", true); return; } hoverWindows.close(); menuState.close(); keybindings.opened = !keybindings.opened; }
        }
    }
    Variants {
        id: docks
        model: preferences.loaded ? Quickshell.screens : []
        Hyprdock {
            id: dockPanel
            modeEnabled: shell.dockEnabled
            onActivated: { for (let other of docks.instances) if (other !== dockPanel) other.collapse(); }
            required property var modelData
            screen: modelData
            store: preferences
            services: desktopServices
            inbox: notificationInbox
            applicationService: applications
            settingsController: shell.settingsEditor
            projector: projectorWindow
            notificationTarget: modelData.name === (Hyprland.focusedMonitor?.name || Quickshell.screens[0]?.name)
            trayModel: tray.items
            clockText: shell.dockClockText
            wallpaperSource: wallpapers.sources[modelData.name] || ""
            available: shell.dockEnabled && (requested || Settings.panelVisible(panelVisibility.config, "hyprpane", modelData.name, Hyprland.monitorFor(modelData)?.activeWorkspace?.id ?? null))
            motionEnabled: preferences.config.accessibility?.reducedMotion !== true && preferences.config.hyprland?.animations !== false
            property var workspace: Hyprland.monitorFor(modelData)?.activeWorkspace?.id ?? null
            onWorkspaceChanged: collapse()
            onLockRequested: locking.lockNow()
        }
    }
    Connections {
        target: preferences
        function onPanelConfigChanged() {
            shell.updateClock();
            for (let panel of panels.instances) panel.refreshSettings();
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
            notificationInbox.flushHistory(true);
            Quickshell.reload(true);
        }
    }
    FrameTiming {
        id: frameTiming
        windows: [{name: "dashboard", window: dashboardWindow}, {name: "activity", window: activityWindow}]
            .concat(panels.instances.map(panel => ({name: "panel-" + panel.screen.name, window: panel})))
    }
    IpcHandler {
        target: "performance"
        function startFrames(seconds: int): string {
            return JSON.stringify({ok: frameTiming.start(seconds), instance: Quickshell.instanceId, capture: frameTiming.captureId});
        }
        function frameResults(): string {
            return JSON.stringify({instance: Quickshell.instanceId, capture: frameTiming.captureId, windows: frameTiming.finish(),
                limits: "Frame-swap intervals, not GPU render time; gaps over 250 ms reported separately; millisecond clock resolution."});
        }
    }
    IpcHandler {
        target: "bar"
        function dashboard(): void { shell.toggleDashboard(); }
        function restoreDesktop(): void { applications.desktop.run('restore'); }
        function ready(): bool {
            if (panels.instances.length === 0) return false;
            for (let panel of panels.instances) if (panel.shown && !panel.backingWindowVisible) return false;
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
            if (shell.dockEnabled) { shell.focusedDock()?.open("displays", true); return; }
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
        function dock(): void { if (shell.dockEnabled) shell.focusedDock()?.revealKeyboard(); }
        function activity(): void { if (shell.dockEnabled) shell.focusedDock()?.open("activity", true); }
        function toggleBar(): void {
            shell.toggleWorkspacePanel('hyprpane');
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
            for (let other of panels.instances) if (other !== panel) other.closeMenu();
            if (panel) panel.toggleLauncher();
        }
    }
}
