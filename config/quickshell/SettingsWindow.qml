pragma ComponentBehavior: Bound
import QtQuick
import "style" as Style
import QtQuick.Controls.Basic
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "SettingsModel.js" as Model

FloatingWindow {
    id: window
    required property var store
    property Item dockHost: null
    property bool dockOpened: false
    readonly property bool uiOpened: visible || dockOpened
    readonly property real hostWidth: dockHost ? dockHost.width : width
    readonly property real hostHeight: dockHost ? dockHost.height : height
    function showEditor() {
        if (dockHost) { dockOpened = true; Qt.callLater(focusSearch); }
        else visible = true;
    }
    function hideEditor() { dockOpened = false; visible = false; }
    onDockOpenedChanged: {
        if (dockOpened) Qt.callLater(focusSearch);
        else if (editingSession && dirty) apply();
    }
    property var wallpaperSources: ({})
    readonly property var wallpaperScreen: dockHost?.output || screen
    // Sample the current output once at thumbnail size. Window resizing and
    // page navigation reuse these pixels; moving to another output resamples.
    WallpaperColors {
        id: windowWallpaper
        objectName: "settingsWallpaperSampler"
        source: window.wallpaperSources[window.wallpaperScreen?.name] || ""
        screenWidth: window.wallpaperScreen?.width || 1366
        screenHeight: window.wallpaperScreen?.height || 768
        offsetY: 0
        bandHeight: screenHeight
        sampleWidth: 96
        sampleHeight: 64
    }
    Binding {
        target: Style.SettingsTheme
        property: "wallpaperSample"
        value: windowWallpaper.sampleRect(Qt.rect(0, 0, windowWallpaper.screenWidth, windowWallpaper.screenHeight))
        restoreMode: Binding.RestoreBindingOrValue
    }
    property string lockingError: ""
    property string powerError: ""
    property var audioServices: null
    property var notificationApps: []
    property string clipboardError: ""
    property var batteryInfo: ({})
    property int currentWorkspace: 1
    signal lockRequested()
    signal focusRequested()
    // A compositor close hides the native window without clearing the
    // FloatingWindow visibility request. Reset it so the next open remaps.
    onClosed: visible = false
    property var draft: Model.copy(store.defaults)
    property var initial: Model.copy(store.defaults)
    property var submitted: Model.copy(store.defaults)
    property bool editingSession: false
    Binding {
        target: window.store
        property: "panelPreview"
        value: {
            if (!window.editingSession || !window.success || window.store.error) return {};
            let preview = {};
            // Keep the latest appearance through close-flush and queued saves.
            for (let key of Object.keys(window.draft.bar)) {
                if (JSON.stringify(window.draft.bar[key]) !== JSON.stringify(window.store.config.bar[key]))
                    preview[key] = window.draft.bar[key];
            }
            return preview;
        }
        restoreMode: Binding.RestoreBindingOrValue
    }
    Binding {
        target: window.store
        property: "itemPreview"
        value: window.editingSession && window.success && !window.store.error
            && JSON.stringify(window.draft.items) !== JSON.stringify(window.store.config.items)
            ? Model.previewItems(window.draft.items, window.store.config.items) : null
        restoreMode: Binding.RestoreBindingOrValue
    }
    readonly property bool saving: writer.running
    readonly property bool idle: !writer.running && !autoSave.running && !displayPage.busy && !cleanupPage.busy && !hyprskillPage.busy && !githubSync.running && !githubUpdate.busy && !keybindingsPage.busy && !themePage.busy && !applicationsPage.busy && !recoveryPage.busy && !powerPage.busy && !soundPage.busy && !networkPage.busy && !firewallPage.busy && !regionalPage.busy && !helpPage.busy && !behaviorPage.busy && !clipboardPage.busy && !peripheralsPage.busy && !setupBackupPage.busy
    readonly property bool manualDirty: lockPage.dirty || themePage.dirty || displayPage.dirty || keybindingsPage.dirty || cleanupPage.dirty || regionalPage.dirty || firewallPage.dirty || behaviorPage.dirty || recoveryPage.dirty
    readonly property bool pageDirty: section === -3 ? lockPage.dirty : section === -8 ? themePage.dirty : section === -7 ? displayPage.dirty : section === -6 ? keybindingsPage.dirty : section === -4 ? cleanupPage.dirty : section === -17 ? regionalPage.dirty : section === -22 ? firewallPage.dirty : section === -19 ? behaviorPage.dirty : section === -14 ? recoveryPage.dirty : false
    function savingPolicy() {
        if (section === homeSection) return "Choose a category or search for a setting";
        if (section === -3) return "Timers save automatically · Use Apply lock command to change the locker";
        if (section === -8) return "Colors save immediately · Apply font and cursor to save them";
        if (section === -7) return "Apply and confirm display changes before they are saved";
        if (section === -6) return "Use Save shortcut to apply your edits";
        if (section === -4) return "Save schedules separately · Preview and confirm manual cleanup or reset";
        if (section === -17) return "Use Save for next login to save language and region";
        if (section === -19) return "Use Apply changes to save workspaces and rules";
        if (section === -14) return "Backup plans require Save · Recovery and updates require an explicit action";
        if (section === -23) return "Back up now · Select a dated backup, preview, then restore";
        if ([-5, -15, -18, -21, -22].indexOf(section) >= 0) return "Use this page’s action buttons";
        if (section === -25) return "Bluetooth changes apply immediately";
        if (section === -12) return "Sound changes apply immediately and are remembered by the audio service";
        if (section === -10) return "Timers save automatically · Hardware controls apply immediately";
        if (section === -13) return "Choices save immediately · Startup changes take effect at next login";
        return "Changes save automatically";
    }
    onDraftChanged: { Style.Theme.preferences = draft.accessibility || {}; if (editingSession) autoSave.restart(); }
    Component.onCompleted: { Style.Theme.preferences = draft.accessibility || {}; searchIndexer.running = true; }
    onVisibleChanged: {
        if (visible) Qt.callLater(focusSearch);
        else if (editingSession && dirty) apply();
    }
    function goHome() {
        searchField.clear();
        section = homeSection;
    }
    function focusSearch() {
        if (!uiOpened) return;
        searchField.forceActiveFocus();
        searchField.selectAll();
    }
    readonly property int homeSection: -24
    property int section: homeSection
    property var scrollPositions: ({})
    property int previousSection: homeSection
    property string searchQuery: ""
    property var searchCaptions: ({})
    property bool searchIndexLoaded: false
    property int searchResultIndex: -1
    onSearchResultsChanged: {
        searchResultIndex = searchQuery.trim() && searchResults.length ? 0 : -1;
        if (searchQuery.trim()) Qt.callLater(() => { if (searchQuery.trim()) moveSearchSelection(0); });
    }
    function moveSearchSelection(step) {
        if (!searchResults.length) return;
        searchResultIndex = searchResultIndex < 0 ? 0
            : Math.max(0, Math.min(searchResults.length - 1, searchResultIndex + step));
        let index = searchResultIndex;
        let button = null;
        for (let i = 0; i < navigationGroups.count; ++i) {
            let group = navigationGroups.itemAt(i);
            if (index < group.pages.length) {
                button = group.buttons.itemAt(index);
                break;
            }
            index -= group.pages.length;
        }
        if (!button) {
            barItemsExpanded = true;
            button = barResults.itemAt(index);
        }
        if (button) Qt.callLater(() => {
            let y = button.mapToItem(sidebar.contentItem, 0, 0).y;
            let view = sidebar.contentItem;
            view.contentY = Math.max(0, Math.min(view.contentHeight - view.height,
                Math.max(y + button.height - view.height, Math.min(view.contentY, y))));
        });
    }
    function revealCurrentNavigation() {
        if (searchQuery.trim()) return;
        let button = null;
        for (let i = 0; i < navigationGroups.count; ++i) {
            let group = navigationGroups.itemAt(i);
            let index = group.pages.findIndex(page => page.section === section);
            if (index >= 0) { button = group.buttons.itemAt(index); break; }
        }
        if (section >= 0) button = barResults.itemAt(section);
        if (!button) return;
        let y = button.mapToItem(sidebar.contentItem, 0, 0).y;
        let view = sidebar.contentItem;
        view.contentY = Math.max(0, Math.min(view.contentHeight - view.height,
            Math.max(y + button.height - view.height, Math.min(view.contentY, y))));
    }
    property bool barItemsExpanded: true
    readonly property var navigation: [
        {group: "Personalize", pages: [
            {section: -8, title: "Appearance", symbol: "󰔎", hint: "Theme, colors, fonts & cursor", keywords: "theme colors font cursor"},
            {section: -2, title: "Windows", symbol: "󰖲", hint: "Blur, gaps, shadows & motion", keywords: "hyprland transparency blur gaps animations"},
            {section: -1, title: "Hyprpane", symbol: "󰕮", hint: "Panel layout, spacing & menus", keywords: "hyprpane panel topbar position screen edge top bottom left right spacing workspace workspaces"},
            {section: -19, title: "Workspaces & rules", symbol: "󰍹", hint: "Tiling, focus & window rules", keywords: "workspace rules tiling layout focus pointer"},
            {section: -13, title: "Applications", symbol: "󰀻", hint: "Default apps & startup", keywords: "default apps startup"}
        ]},
        {group: "Devices & connections", pages: [
            {section: -7, title: "Displays", symbol: "󰍹", hint: "Resolution, scale & arrangement", keywords: "monitor resolution scale rotation duplicate mirror extend HDMI TV projection"},
            {section: -12, title: "Sound", symbol: "󰕾", hint: "Output, microphone & app volume", keywords: "audio volume microphone speakers"},
            {section: -25, title: "Bluetooth", symbol: "󰂯", hint: "Pair devices & wireless", keywords: "pair devices headphones wireless discoverable trusted wake battery"},
            {section: -15, title: "Network", symbol: "󰤨", hint: "Wi-Fi, Ethernet & VPN", keywords: "wifi wi-fi hidden enterprise vpn wireguard ethernet connections dns"},
            {section: -9, title: "Mouse & keyboard", symbol: "󰍽", hint: "Pointer, scrolling & layouts", keywords: "input touchpad scrolling typing layouts"},
            {section: -6, title: "Keyboard shortcuts", symbol: "󰌌", hint: "Hotkeys & keybindings", keywords: "keybindings hotkeys"},
            {section: -21, title: "Printing & scanning", symbol: "󰐪", hint: "Printers & scanners", keywords: "printer scanner cups paper documents"}
        ]},
        {group: "Preferences", pages: [
            {section: -11, title: "Notifications", symbol: "󰂚", hint: "Popups, Do Not Disturb & apps", keywords: "delivery popups disturb"},
            {section: -20, title: "Clipboard history", symbol: "󰅍", hint: "Copied text & images", keywords: "copy paste clips text images"},
            {section: -16, title: "Accessibility", symbol: "󰋁", hint: "Text size, contrast & motion", keywords: "large text size contrast reduced motion animations"},
            {section: -17, title: "Language & region", symbol: "󰗊", hint: "Language, timezone & formats", keywords: "locale timezone date time number formats"},
            {section: -10, title: "Power & battery", symbol: "󰁹", hint: "Brightness, sleep & profiles", keywords: "brightness sleep lid profiles"},
            {section: -3, title: "Screen locking", symbol: "󰌾", hint: "Idle timeout & security", keywords: "security idle lock"}
        ]},
        {group: "System", pages: [
            {section: -22, title: "Firewall", symbol: "󰒃", hint: "Network rules & blocked sites", keywords: "firewalld security rules ports services zones block incoming tcp udp website dns custom cloudflare adult porn malware malicious phishing protection"},
            {section: -4, title: "Cleanup", symbol: "󰃢", hint: "Storage & maintenance", keywords: "storage files maintenance"},
            {section: -23, title: "Backup & restore", symbol: "󰁯", hint: "Setup snapshots & restore", keywords: "hyprshell setup backup restore date time configuration checkpoints snapshots"},
            {section: -14, title: "Updates & recovery", symbol: "󰚰", hint: "System updates & recovery", keywords: "backup restore checkpoints"},
            {section: -18, title: "Help & diagnostics", symbol: "󰋖", hint: "Guide, health & support", keywords: "welcome guide health diagnostics support getting started version build rolling"},
            {section: -5, title: "Hyprskill", symbol: "󰒓", hint: "Agent knowledge & tools", keywords: "agents coding knowledge"}
        ]}
    ]
    readonly property var barNavigation: draft.items.map((item, index) => ({section: index, title: names[item.id] || item.id, symbol: symbols[item.id] || "󰒓", keywords: "bar item " + item.id, itemEnabled: item.enabled}))
    readonly property var searchResults: navigation.reduce((pages, group) => pages.concat(matchingPages(group.pages)), []).concat(matchingPages(barNavigation))
    readonly property var flatPages: navigation.reduce((pages, group) => pages.concat(group.pages), [])
    function cycleSection(step) {
        let pages = [homeSection].concat(flatPages.map(page => page.section));
        let index = pages.indexOf(section);
        if (index < 0) index = 0;
        searchField.clear();
        section = pages[(index + step + pages.length) % pages.length];
    }
    function goBack() {
        if (section === homeSection) return;
        searchField.clear();
        section = section >= 0 ? -1 : homeSection;
    }
    function matchingPages(pages) {
        let query = searchQuery.toLowerCase().replace(/\s+/g, " ").trim();
        return pages.filter(page => {
            let captions = searchCaptions[page.section >= 0 ? "*" : String(page.section)] || [];
            let text = [page.title, page.keywords].concat(captions).join(" ").toLowerCase().replace(/\s+/g, " ");
            return !query || text.includes(query);
        });
    }
    Process {
        id: searchIndexer
        command: ["python3", decodeURIComponent(Qt.resolvedUrl("settings/search.py").toString().replace(/^file:\/\//, ""))]
        stdout: StdioCollector { onStreamFinished: {
            try { window.searchCaptions = JSON.parse(text); window.searchIndexLoaded = true; }
            catch (error) { console.warn("Settings caption search index could not be loaded; page names and keywords remain searchable."); }
        } }
        stderr: StdioCollector {}
    }
    onSectionChanged: {
        if (editorScroll.contentItem) scrollPositions[previousSection] = editorScroll.contentItem.contentY;
        previousSection = section;
        Qt.callLater(() => Qt.callLater(window.revealCurrentNavigation));
        if (section >= 0) barItemsExpanded = true;
        Qt.callLater(() => {
            if (editorScroll.contentItem) editorScroll.contentItem.contentY = scrollPositions[section] || 0;
        });
    }
    property string message: ""
    property bool success: true
    property string savedNotice: ""
    property string submittedNotice: ""
    readonly property bool dirty: JSON.stringify(draft) !== JSON.stringify(initial)
    readonly property var selected: section >= 0 ? draft.items[section] : ({})
    readonly property var names: ({
            launcher: "App launcher",
            settings: "Settings shortcut",
            workspaces: "Workspaces",
            media: "Media & spectrum",
            calendar: "Clock & calendar",
            tray: "System tray",
            notifications: "Notifications",
            audio: "Audio",
            wifi: "Wi-Fi",
            bluetooth: "Bluetooth",
            battery: "Battery",
            power: "Power"
        })
    readonly property var symbols: ({
            launcher: "",
            settings: "󰒓",
            workspaces: "󰍹",
            media: "󰎆",
            calendar: "󰃭",
            tray: "󰕰",
            notifications: "󰂚",
            audio: "󰕾",
            wifi: "󰤨",
            bluetooth: "󰂯",
            battery: "󰁹",
            power: "󰐥"
        })
    visible: false
    title: "Hyprshell Settings"
    implicitWidth: screen ? Math.min(1180, Math.round(screen.width * 0.9)) : 1180
    implicitHeight: screen ? Math.min(860, Math.round(screen.height * 0.85)) : 810
    color: Style.SettingsTheme.background
    property bool firstRunPending: {
        try { return JSON.parse(welcomeFile.text()).completed !== true; } catch (e) { return true; }
    }
    FileView {
        id: welcomeFile
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/hyprshell/welcome.json"
        blockLoading: true
        printErrors: false
    }
    function open() {
        minimized = false;
        if (uiOpened) {
            if (!dockHost) focusRequested();
            Qt.callLater(focusSearch);
            return;
        }
        if (editingSession && (dirty || saving || manualDirty)) {
            showEditor();
            return;
        }
        savedNotice = "";
        savedNoticeTimer.stop();
        editingSession = false;
        initial = Model.copy(store.config);
        draft = Model.copy(store.config);
        message = store.error;
        success = !store.error;
        editingSession = true;
        showEditor();
    }
    function updateItem(key, value) {
        let next = Model.copy(draft);
        if (key === "pillGroup") next = Model.setPillGroup(draft, selected.id, value);
        else if (key === "sharedBackground") next = Model.setSharedBackground(draft, selected.id, value);
        else if (key === "side") next = Model.setItemSide(draft, selected.id, value);
        else next.items[section][key] = value;
        draft = next;
    }
    function resetItem() {
        if (saving || section < 0) return;
        draft = Model.restoreItem(draft, initial, selected.id);
    }
    function rearrangeItem(id, side, beforeId) {
        draft = Model.reorder(draft, id, side, beforeId);
    }
    function updateBar(key, value) {
        let next = Model.copy(draft);
        next.bar[key] = value;
        draft = next;
    }
    function updateBarSettings(bar) {
        let next = Model.copy(draft);
        next.bar = bar;
        draft = next;
    }
    function toggleWorkspaceBar(workspace) {
        updateBarSettings(Model.withWorkspaceVisibility(draft.bar, workspace, !Model.barVisible(draft.bar, workspace)));
    }
    function toggleWorkspacePanel(component, workspace) {
        if (component === 'hyprpane') toggleWorkspaceBar(workspace);
    }
    function updateHypr(key, value) {
        let next = Model.copy(draft);
        if (value === "")
            delete next.hyprland[key];
        else
            next.hyprland[key] = value;
        draft = next;
    }
    function updateNotifications(key, value) {
        let next = Model.copy(draft);
        next.notifications[key] = value;
        draft = next;
    }
    function updateAccessibility(key, value) {
        let next = Model.copy(draft); next.accessibility[key] = value; draft = next;
    }
    function updateClipboard(key, value) { let next = Model.copy(draft); next.clipboard[key] = value; draft = next; }
    function updatePower(key, value) {
        let next = Model.copy(draft);
        next.power[key] = value;
        draft = next;
    }
    function updateLocking(key, value) {
        let next = Model.copy(draft);
        next.locking[key] = value;
        draft = next;
    }
    function moveItem(direction) {
        let next = Model.copy(draft);
        let current = next.items[section];
        let group = next.items.filter(i => i.side === current.side).sort((a, b) => a.order - b.order);
        let index = group.findIndex(i => i.id === current.id), other = index + direction;
        if (other < 0 || other >= group.length)
            return;
        [group[index], group[other]] = [group[other], group[index]];
        group.forEach((item, n) => item.order = n);
        draft = next;
    }
    function saveNotice(before, after) {
        let labels = [];
        if (JSON.stringify(before.panels) !== JSON.stringify(after.panels)) labels.push("Panel placement");
        if (JSON.stringify(before.pins) !== JSON.stringify(after.pins)) labels.push("Application matching");
        if (JSON.stringify(before.bar) !== JSON.stringify(after.bar)) labels.push("Hyprpane");
        let inputKeys = ["pointerSpeed", "mouseNaturalScroll", "touchpadNaturalScroll", "tapToClick", "disableWhileTyping", "repeatRate", "repeatDelay", "keyboardLayouts", "layoutSwitch"];
        if (inputKeys.some(key => before.hyprland[key] !== after.hyprland[key])) labels.push("Mouse, touchpad & keyboard");
        if (Object.keys(Object.assign({}, before.hyprland, after.hyprland)).some(key => inputKeys.indexOf(key) < 0 && before.hyprland[key] !== after.hyprland[key])) labels.push("Hyprland appearance");
        if (JSON.stringify(before.notifications) !== JSON.stringify(after.notifications)) labels.push("Notification delivery");
        if (JSON.stringify(before.accessibility) !== JSON.stringify(after.accessibility)) labels.push("Accessibility");
        if (JSON.stringify(before.clipboard) !== JSON.stringify(after.clipboard)) labels.push("Clipboard history");
        if (JSON.stringify(before.power) !== JSON.stringify(after.power)) labels.push("Power & battery");
        if (JSON.stringify(before.locking) !== JSON.stringify(after.locking)) labels.push("Screen locking");
        after.items.forEach(item => {
            let previous = before.items.find(entry => entry.id === item.id);
            if (JSON.stringify(previous) !== JSON.stringify(item)) labels.push(names[item.id] || item.id);
        });
        return labels.length ? labels.join(", ") + " settings saved!" : "Settings saved!";
    }
    function apply() {
        if (writer.running || !dirty) return;
        if (store.error || !store.loaded) {
            message = store.error;
            success = false;
            return;
        }
        autoSave.stop();
        submitted = Model.copy(draft);
        submittedNotice = saveNotice(initial, submitted);
        savedNotice = "";
        savedNoticeTimer.stop();
        success = true;
        message = "Saving changes…";
        writer.command = ["python3", decodeURIComponent(Qt.resolvedUrl("settings/backend.py").toString().replace(/^file:\/\//, "")), "--save-json", JSON.stringify(submitted), "--expected-json", JSON.stringify(initial)];
        writer.running = true;
    }
    Timer {
        id: autoSave
        interval: 200
        onTriggered: window.apply()
    }
    Timer {
        id: savedNoticeTimer
        interval: 2000
        onTriggered: window.savedNotice = ""
    }
    Process {
        id: writer
        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0 && window.success) {
                window.success = false;
                window.message = "Could not save settings. Your last saved values are still active.";
            }
            if (window.dirty && (window.success || JSON.stringify(window.draft) !== JSON.stringify(window.submitted))) autoSave.restart();
        }
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let result = JSON.parse(text);
                    window.success = result.ok;
                    window.message = result.ok ? "" : result.message;
                    if (result.ok) {
                        window.savedNotice = window.submittedNotice;
                        savedNoticeTimer.restart();
                        window.initial = Model.copy(window.submitted);
                        window.store.acceptConfig(window.submitted);
                    }
                } catch (e) {
                    window.success = false;
                    window.message = "Could not save settings. Check that Python 3 is installed.";
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: if (text) {
                window.success = false;
                window.message = text;
            }
        }
    }
    property string syncMessage: ""
    property bool syncSuccess: true
    property bool syncReady: false
    property string syncRepository: ""
    property string syncForkUrl: ""
    property string syncCreateUrl: ""
    Process {
        id: githubSync
        property string action: ""
        function request(action, extra) {
            githubSync.action = action;
            window.syncReady = false;
            window.syncForkUrl = "";
            window.syncCreateUrl = "";
            window.syncSuccess = true;
            window.syncMessage = action === "--status" ? "Checking GitHub setup…" : action === "--authenticate" ? "Complete sign-in in the authentication window…" : "Saving live desktop to the local repo, then syncing to GitHub…";
            command = ["python3", decodeURIComponent(Qt.resolvedUrl("settings/github_sync.py").toString().replace(/^file:\/\//, ""))].concat(action ? [action] : []).concat(extra || []);
            running = true;
        }
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let result = JSON.parse(text);
                    window.syncSuccess = result.ok;
                    window.syncMessage = result.message;
                    window.syncReady = result.ok && result.ready === true;
                    // Sync acknowledgements omit repository; discovery owns it.
                    if (githubSync.action === "--status" || githubSync.action === "--authenticate")
                        window.syncRepository = result.repository || "";
                    window.syncForkUrl = result.forkUrl || "";
                    window.syncCreateUrl = result.createUrl || "";
                } catch (e) {
                    window.syncSuccess = false;
                    window.syncMessage = "Could not read GitHub sync results.";
                }
            }
        }
        stderr: StdioCollector { onStreamFinished: if (text) { window.syncSuccess = false; window.syncMessage = text; } }
        onExited: (code, status) => {
            if (code !== 0 && window.syncSuccess) {
                window.syncSuccess = false;
                window.syncMessage = "GitHub sync failed. Check Git and GitHub authentication.";
            }
        }
    }
    Shortcut {
        sequence: "Ctrl+F"
        context: Qt.ApplicationShortcut
        enabled: window.uiOpened
        onActivated: { searchField.forceActiveFocus(); searchField.selectAll(); }
    }
    Shortcut {
        sequence: "Ctrl+Tab"
        context: Qt.ApplicationShortcut
        enabled: window.uiOpened
        onActivated: window.cycleSection(1)
    }
    Shortcut {
        sequence: "Ctrl+Shift+Tab"
        context: Qt.ApplicationShortcut
        enabled: window.uiOpened
        onActivated: window.cycleSection(-1)
    }
    Shortcut {
        sequence: "Alt+Left"
        context: Qt.ApplicationShortcut
        enabled: window.uiOpened
        onActivated: window.goBack()
    }
    SettingsGithubUpdate { id: githubUpdate; parent: settingsRoot; hostWidth: window.hostWidth; hostHeight: window.hostHeight }
    Popup {
        id: githubDialog
        parent: settingsRoot
        objectName: "githubSyncDialog"
        anchors.centerIn: parent
        width: Math.min(480, window.hostWidth - 40)
        padding: 24
        modal: true
        closePolicy: githubSync.running ? Popup.NoAutoClose : Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle { color: Style.SettingsTheme.surface; radius: 14; border.color: Style.SettingsTheme.controlBorder }
        contentItem: ColumnLayout {
            spacing: 14
            Label { text: "Sync to GitHub"; color: Style.SettingsTheme.text; font.pixelSize: 20; font.bold: true }
            Label { Layout.fillWidth: true; text: "Sync saves your current desktop to a local commit, then pushes it to GitHub."; wrapMode: Text.WordWrap; color: Style.SettingsTheme.muted }
            Label { objectName: "githubRepositoryLabel"; text: window.syncRepository || "Sign in to find your repository"; color: Style.SettingsTheme.accentText }
            Label { Layout.fillWidth: true; text: window.syncMessage; wrapMode: Text.WordWrap; color: window.syncSuccess ? Style.SettingsTheme.muted : Style.SettingsTheme.danger }
            RowLayout {
                SettingsButton {
                    objectName: "githubForkButton"
                    text: "Fork Hyprshell"
                    visible: window.syncForkUrl !== ""
                    enabled: !githubSync.running
                    onClicked: Qt.openUrlExternally(window.syncForkUrl)
                }
                SettingsButton {
                    objectName: "githubCreateButton"
                    text: "Create repository"
                    visible: window.syncCreateUrl !== ""
                    enabled: !githubSync.running
                    onClicked: Qt.openUrlExternally(window.syncCreateUrl)
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                SettingsButton {
                    objectName: "githubCheckButton"
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    implicitWidth: 0
                    leftPadding: 8; rightPadding: 8
                    text: "Check again"
                    enabled: !githubSync.running
                    onClicked: githubSync.request("--status", [])
                }
                SettingsButton {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    implicitWidth: 0
                    leftPadding: 8; rightPadding: 8
                    text: "Authenticate"
                    enabled: !githubSync.running
                    onClicked: githubSync.request("--authenticate", [])
                }
                SettingsButton {
                    objectName: "githubConfirmSync"
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    implicitWidth: 0
                    leftPadding: 8; rightPadding: 8
                    text: githubSync.running ? "Working…" : "Sync"
                    highlighted: true
                    enabled: !githubSync.running && window.syncReady && !window.dirty && !window.saving && window.success
                    onClicked: githubSync.request("", [])
                }
                SettingsButton {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    implicitWidth: 0
                    leftPadding: 8; rightPadding: 8
                    text: "Close"
                    enabled: !githubSync.running
                    onClicked: githubDialog.close()
                }
            }
        }
    }
    Pane {
        id: settingsRoot
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Tab && (event.modifiers & Qt.ControlModifier)) {
                window.cycleSection(event.modifiers & Qt.ShiftModifier ? -1 : 1); event.accepted = true;
            } else if (event.key === Qt.Key_Left && (event.modifiers & Qt.AltModifier)) {
                window.goBack(); event.accepted = true;
            } else if (event.key === Qt.Key_F && (event.modifiers & Qt.ControlModifier)) {
                window.focusSearch(); event.accepted = true;
            }
        }
        parent: window.dockHost || window.contentItem
        visible: window.uiOpened
        objectName: "settingsRoot"
        anchors.fill: parent
        padding: 0
        property bool settingsMotionEnabled: window.draft.hyprland.animations !== false && !window.draft.accessibility.reducedMotion
        palette.window: Style.SettingsTheme.background
        palette.windowText: Style.SettingsTheme.text
        palette.text: Style.SettingsTheme.text
        palette.base: Style.SettingsTheme.surface
        palette.button: Style.SettingsTheme.button
        palette.buttonText: Style.SettingsTheme.text
        palette.highlight: Style.SettingsTheme.accent
        palette.highlightedText: Style.SettingsTheme.accentForeground
        palette.brightText: Style.SettingsTheme.accentForeground
        palette.dark: Style.SettingsTheme.accentText
        palette.mid: Style.SettingsTheme.border
        font.family: "Noto Sans"
        font.pixelSize: Style.SettingsTheme.bodySize
        background: Rectangle { color: Style.SettingsTheme.background }
        contentItem: ColumnLayout {
            spacing: 0
            RowLayout {
                id: appBar
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.preferredHeight: Math.max(56, Math.round(64 * Style.SettingsTheme.textScale))
                Layout.leftMargin: window.hostWidth < 900 ? 12 : 18
                Layout.rightMargin: window.hostWidth < 900 ? 12 : 18
                spacing: 6
                ToolButton {
                    id: homeButton
                    objectName: "settingsHomeButton"
                    Accessible.name: "Hyprshell Settings overview"
                    hoverEnabled: true
                    implicitHeight: Math.max(42, Math.round(44 * Style.SettingsTheme.textScale))
                    leftPadding: 7; rightPadding: 14
                    onClicked: window.goHome()
                    Keys.onReturnPressed: clicked()
                    Keys.onEnterPressed: clicked()
                    contentItem: RowLayout {
                        spacing: 10
                        Rectangle {
                            implicitWidth: Math.round(32 * Style.SettingsTheme.textScale)
                            implicitHeight: Math.round(32 * Style.SettingsTheme.textScale)
                            radius: width / 2
                            color: Style.SettingsTheme.iconBadge
                            border.width: Style.SettingsTheme.highContrast ? 1 : 0
                            border.color: Style.SettingsTheme.controlBorder
                            Label {
                                anchors.centerIn: parent
                                text: "󰒓"; font.family: "GoMono Nerd Font"
                                font.pixelSize: Math.round(18 * Style.SettingsTheme.textScale)
                                color: Style.SettingsTheme.iconBadgeText
                            }
                        }
                        Label { text: "Hyprsettings"; font.pixelSize: Math.round(17 * Style.SettingsTheme.textScale); font.weight: Font.DemiBold; color: Style.SettingsTheme.text }
                    }
                    background: Rectangle {
                        radius: Math.round(height / 2)
                        color: homeButton.hovered ? Style.SettingsTheme.hover : "transparent"
                        border.width: homeButton.activeFocus ? 2 : 0
                        border.color: homeButton.activeFocus ? Style.SettingsTheme.accentText : "transparent"
                    }
                }
                Item {
                    Layout.fillWidth: true
                }
                SettingsGithubButton {
                    objectName: "githubSyncButton"
                    flat: true
                    text: githubSync.running ? "Syncing…" : "Sync to GitHub"
                    enabled: window.idle && !window.dirty && !window.manualDirty && window.success && window.store.loaded
                    Accessible.description: "Commit and push your desktop setup to your GitHub hyprshell repository"
                    onClicked: {
                        githubDialog.open();
                        githubSync.request("--status", []);
                    }
                }
                SettingsGithubButton {
                    objectName: "githubUpdateButton"
                    flat: true
                    text: "Sync from GitHub"
                    enabled: window.idle && !window.dirty && !window.manualDirty && window.success && window.store.loaded
                    Accessible.description: "Review incoming changes and compatibility before updating Hyprshell"
                    onClicked: githubUpdate.open()
                }
                SettingsButton {
                    text: "Reset unsaved changes"
                    visible: !window.success && window.dirty
                    enabled: !writer.running
                    onClicked: {
                        autoSave.stop();
                        window.draft = Model.copy(window.initial);
                        window.success = true;
                        window.message = "Restored your last saved settings.";
                    }
                }
            }
            RowLayout {
                enabled: !githubSync.running && !githubUpdate.busy && !recoveryPage.busy
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: window.hostWidth < 900 ? 10 : 14
                Layout.rightMargin: window.hostWidth < 900 ? 10 : 14
                Layout.topMargin: 4
                Layout.bottomMargin: window.hostWidth < 900 ? 10 : 14
                spacing: 12
                Rectangle {
                    id: sidebarPane
                    Layout.preferredWidth: window.hostWidth < 820 ? 224 : window.hostWidth < 1000 ? 260 : 292
                    Layout.fillHeight: true
                    radius: Style.SettingsTheme.paneRadius
                    color: Style.SettingsTheme.sidebar
                    border.width: Style.SettingsTheme.highContrast ? 1 : 0
                    border.color: Style.SettingsTheme.border
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 10
                        TextField {
                            id: searchField
                            objectName: "settingsSearch"
                            Layout.fillWidth: true
                            implicitHeight: Math.max(42, Math.round(46 * Style.SettingsTheme.textScale))
                            placeholderText: "Search settings"
                            color: Style.SettingsTheme.text
                            placeholderTextColor: Style.SettingsTheme.muted
                            selectionColor: Style.SettingsTheme.selection
                            selectedTextColor: Style.SettingsTheme.text
                            font.pixelSize: Style.SettingsTheme.bodySize
                            leftPadding: Math.round(42 * Style.SettingsTheme.textScale)
                            rightPadding: searchClear.visible ? 40 : searchHint.visible ? 62 : 14
                            selectByMouse: true
                            Accessible.name: "Search settings"
                            onTextChanged: window.searchQuery = text
                            onAccepted: if (window.searchResults.length) window.section = window.searchResults[Math.max(0, window.searchResultIndex)].section
                            Keys.onDownPressed: window.moveSearchSelection(1)
                            Keys.onUpPressed: window.moveSearchSelection(-1)
                            Keys.onPressed: event => {
                                if (event.key === Qt.Key_Tab && (event.modifiers & Qt.ControlModifier)) {
                                    window.cycleSection(event.modifiers & Qt.ShiftModifier ? -1 : 1); event.accepted = true;
                                } else if (event.key === Qt.Key_Left && (event.modifiers & Qt.AltModifier)) {
                                    window.goBack(); event.accepted = true;
                                }
                            }
                            Keys.onEscapePressed: event => {
                                if (text.length) { clear(); event.accepted = true; }
                                else event.accepted = false;
                            }
                            background: Rectangle {
                                radius: Math.round(height / 2)
                                color: searchField.hovered && !searchField.activeFocus ? Style.SettingsTheme.hover : Style.SettingsTheme.field
                                border.width: searchField.activeFocus ? 2 : 1
                                border.color: searchField.activeFocus ? Style.SettingsTheme.accentText : Style.SettingsTheme.border
                                Behavior on border.color { ColorAnimation { duration: Style.SettingsTheme.duration(searchField, 150) } }
                                Behavior on color { ColorAnimation { duration: Style.SettingsTheme.duration(searchField, 150) } }
                            }
                            Text {
                                x: Math.round(15 * Style.SettingsTheme.textScale); anchors.verticalCenter: parent.verticalCenter
                                text: "󰍉"; font.family: "GoMono Nerd Font"; font.pixelSize: Math.round(17 * Style.SettingsTheme.textScale)
                                color: Style.SettingsTheme.muted
                            }
                            Label {
                                id: searchHint
                                anchors.right: parent.right
                                anchors.rightMargin: 14
                                anchors.verticalCenter: parent.verticalCenter
                                visible: searchField.text.length === 0 && window.hostWidth >= 820
                                text: "Ctrl F"
                                color: Style.SettingsTheme.muted
                                font.pixelSize: Style.SettingsTheme.captionSize
                            }
                            ToolButton {
                                id: searchClear
                                objectName: "settingsSearchClear"
                                anchors.right: parent.right
                                anchors.rightMargin: 7
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.round(30 * Style.SettingsTheme.textScale); height: width
                                text: "×"
                                visible: searchField.text.length > 0
                                Accessible.name: "Clear search"
                                onClicked: { searchField.clear(); searchField.forceActiveFocus(); }
                                contentItem: Text { text: searchClear.text; color: Style.SettingsTheme.muted; font.pixelSize: Math.round(20 * Style.SettingsTheme.textScale); horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                background: Rectangle { radius: width / 2; color: searchClear.hovered ? Style.SettingsTheme.hover : "transparent"; border.width: searchClear.activeFocus ? 2 : 0; border.color: Style.SettingsTheme.accentText }
                            }
                        }
                        ScrollView {
                            id: sidebar
                            objectName: "settingsSidebar"
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            contentWidth: availableWidth
                            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                            ColumnLayout {
                                width: sidebar.availableWidth
                                spacing: 2
                                SettingsNavButton {
                                    objectName: "settingsOverviewNav"
                                    Layout.fillWidth: true
                                    Layout.bottomMargin: 6
                                    visible: !window.searchQuery.trim()
                                    text: "Overview"; symbol: "󰋜"
                                    hint: "All settings at a glance"
                                    highlighted: window.section === window.homeSection
                                    onClicked: window.goHome()
                                }
                                Repeater {
                                    id: navigationGroups
                                    model: window.navigation
                                    delegate: ColumnLayout {
                                        id: navGroup
                                        required property var modelData
                                        required property int index
                                        readonly property var pages: window.matchingPages(modelData.pages)
                                        property alias buttons: pageResults
                                        readonly property bool containsCurrent: modelData.pages.some(page => page.section === window.section)
                                        visible: pages.length > 0
                                        Layout.fillWidth: true
                                        spacing: 1
                                        Label {
                                            Layout.fillWidth: true
                                            Layout.topMargin: navGroup.index === 0 ? 2 : 12
                                            Layout.bottomMargin: 4
                                            text: navGroup.modelData.group
                                            color: Style.SettingsTheme.muted
                                            font.pixelSize: Style.SettingsTheme.captionSize
                                            font.weight: Font.DemiBold
                                            font.letterSpacing: 0.5
                                            elide: Text.ElideRight
                                        }
                                        Rectangle {
                                            id: navGroupCard
                                            Layout.fillWidth: true
                                            implicitHeight: navGroupCardColumn.implicitHeight + 6
                                            radius: 16
                                            color: Style.SettingsTheme.navRow
                                            border.width: Style.SettingsTheme.highContrast ? 1 : 0
                                            border.color: Style.SettingsTheme.border
                                            ColumnLayout {
                                                id: navGroupCardColumn
                                                anchors.left: parent.left
                                                anchors.right: parent.right
                                                anchors.top: parent.top
                                                anchors.margins: 3
                                                spacing: 1
                                                Repeater {
                                                    id: pageResults
                                                    model: navGroup.pages
                                                    delegate: SettingsNavButton {
                                                        required property var modelData
                                                        objectName: "settingsNav" + modelData.section
                                                        text: modelData.title
                                                        symbol: modelData.symbol
                                                        hint: modelData.hint || ""
                                                        Layout.fillWidth: true
                                                        keyboardSelected: searchField.activeFocus && window.searchResultIndex >= 0 && window.searchResults[window.searchResultIndex]?.section === modelData.section
                                                        highlighted: window.section === modelData.section
                                                        onClicked: window.section = modelData.section
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                                SettingsButton {
                                    objectName: "settingsBarItemsToggle"
                                    Layout.fillWidth: true
                                    Layout.topMargin: 10
                                    flat: true
                                    text: "Hyprpane items  " + (window.barItemsExpanded || window.searchQuery.trim() ? "⌃" : "⌄")
                                    visible: window.matchingPages(window.barNavigation).length > 0
                                    Accessible.description: window.barItemsExpanded ? "Expanded" : "Collapsed"
                                    onClicked: window.barItemsExpanded = !window.barItemsExpanded
                                }
                                Rectangle {
                                    id: barItemsCard
                                    Layout.fillWidth: true
                                    visible: barResults.count > 0
                                    implicitHeight: barResultsColumn.implicitHeight + 6
                                    radius: 16
                                    color: Style.SettingsTheme.navRow
                                    border.width: Style.SettingsTheme.highContrast ? 1 : 0
                                    border.color: Style.SettingsTheme.border
                                    ColumnLayout {
                                        id: barResultsColumn
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.top: parent.top
                                        anchors.margins: 3
                                        spacing: 1
                                        Repeater {
                                            id: barResults
                                            model: window.barItemsExpanded || window.searchQuery.trim() ? window.matchingPages(window.barNavigation) : []
                                            delegate: SettingsNavButton {
                                                required property var modelData
                                                text: modelData.title
                                                symbol: modelData.symbol
                                                hint: modelData.itemEnabled ? "Hyprpane item" : "Hidden from Hyprpane"
                                                itemEnabled: modelData.itemEnabled
                                                Layout.fillWidth: true
                                                keyboardSelected: searchField.activeFocus && window.searchResultIndex >= 0 && window.searchResults[window.searchResultIndex]?.section === modelData.section
                                                highlighted: window.section === modelData.section
                                                onClicked: window.section = modelData.section
                                            }
                                        }
                                    }
                                }
                                Label {
                                    objectName: "settingsSearchEmpty"
                                    visible: window.searchResults.length === 0
                                    Layout.fillWidth: true
                                    Layout.margins: 12
                                    text: "No settings found. Try another search."
                                    color: Style.SettingsTheme.muted
                                    font.pixelSize: Style.SettingsTheme.bodySize
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }
                    }
                }
                Rectangle {
                    id: contentPane
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Style.SettingsTheme.paneRadius
                    color: Style.SettingsTheme.pane
                    border.width: Style.SettingsTheme.highContrast ? 1 : 0
                    border.color: Style.SettingsTheme.border
                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 0
                        ScrollView {
                            id: editorScroll
                            objectName: "settingsEditorScroll"
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            contentWidth: availableWidth
                            leftPadding: window.hostWidth < 900 ? 22 : 36
                            rightPadding: window.hostWidth < 900 ? 22 : 36
                            topPadding: 26
                            bottomPadding: 34
                            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                            background: Rectangle { color: "transparent" }
                            ColumnLayout {
                                id: pageContent
                                objectName: "settingsPageContent"
                                // Section folding is scoped to settings pages, outside review dialogs.
                                readonly property string settingsSectionQuery: window.searchQuery
                                width: Math.min(Style.SettingsTheme.pageMaxWidth, editorScroll.availableWidth)
                                x: Math.max(0, (editorScroll.availableWidth - width) / 2)
                                spacing: 24
                                Connections {
                                    target: window
                                    function onSectionChanged() { pageReveal.restart(); }
                                }
                                transform: Translate { id: pageOffset }
                                ParallelAnimation {
                                    id: pageReveal
                                    NumberAnimation { target: pageContent; property: "opacity"; from: 0.6; to: 1; duration: Style.SettingsTheme.duration(pageContent, 180); easing.type: Easing.OutCubic }
                                    NumberAnimation { target: pageOffset; property: "y"; from: 8; to: 0; duration: Style.SettingsTheme.duration(pageContent, 220); easing.type: Easing.OutCubic }
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    visible: window.section !== window.homeSection
                                    spacing: 12
                                    ToolButton {
                                        id: pageBack
                                        objectName: "settingsBackButton"
                                        Layout.alignment: Qt.AlignVCenter
                                        implicitWidth: Math.max(38, Math.round(40 * Style.SettingsTheme.textScale))
                                        implicitHeight: implicitWidth
                                        hoverEnabled: true
                                        Accessible.name: "Back"
                                        Accessible.description: window.section >= 0 ? "Back to Hyprpane settings" : "Back to overview"
                                        onClicked: window.goBack()
                                        Keys.onReturnPressed: clicked()
                                        Keys.onEnterPressed: clicked()
                                        contentItem: Text {
                                            text: "←"
                                            color: pageBack.activeFocus ? Style.SettingsTheme.accentText : Style.SettingsTheme.text
                                            font.pixelSize: Math.round(20 * Style.SettingsTheme.textScale)
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                        }
                                        background: Rectangle {
                                            radius: width / 2
                                            color: pageBack.hovered ? Style.SettingsTheme.hover : Style.SettingsTheme.field
                                            border.width: pageBack.activeFocus ? 2 : 1
                                            border.color: pageBack.activeFocus ? Style.SettingsTheme.accentText : Style.SettingsTheme.border
                                        }
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        spacing: 1
                                        Label {
                                            Layout.fillWidth: true
                                            text: window.section >= 0 ? "Hyprpane  /  Items" : window.navigation.find(group => group.pages.some(page => page.section === window.section))?.group || "Settings"
                                            color: Style.SettingsTheme.muted
                                            font.pixelSize: Style.SettingsTheme.captionSize
                                            elide: Text.ElideRight
                                        }
                                        Label {
                                            objectName: "settingsPageTitle"
                                            text: window.section >= 0 ? window.names[window.selected.id] || "" : window.navigation.reduce((pages, group) => pages.concat(group.pages), []).find(page => page.section === window.section)?.title || "Settings"
                                            font.pixelSize: window.hostWidth < 900 ? Style.SettingsTheme.pageTitleCompactSize : Style.SettingsTheme.pageTitleSize
                                            font.weight: Font.DemiBold
                                            Layout.fillWidth: true
                                            wrapMode: Text.WordWrap
                                        }
                                    }
                                }
                                Label {
                                    Layout.fillWidth: true
                                    Layout.topMargin: -14
                                    Layout.leftMargin: Math.round(52 * Style.SettingsTheme.textScale)
                                    visible: window.section !== window.homeSection
                                    font.pixelSize: Style.SettingsTheme.bodySize
                                    text: window.section === -25 ? "Your headphones, keyboards, and other wireless devices." : window.section === -23 ? "Save your Hyprshell setup and choose a dated backup to restore." : window.section === -22 ? "Manage network rules and blocked websites." : window.section === -20 ? "Optional local clipboard history" : window.section === -21 ? "Printers and scanners when you need them" : window.section === -19 ? "Choose workspace layouts and rules for application windows." : window.section === -18 ? "Get started, check desktop services, and create a private diagnostic report." : window.section === -17 ? "Choose application language, timezone, and regional formats." : window.section === -16 ? "Make controls easier to read and reduce desktop motion." : window.section === -15 ? "Manage saved connections, hidden and enterprise Wi-Fi, and VPNs." : window.section === -14 ? "Keep your system updated, recover personal configuration, and back up personal files." : window.section === -13 ? "Choose which apps open files and which start when you log in." : window.section === -12 ? "Choose sound devices, check your microphone, and adjust application volumes." : window.section === -11 ? "Choose popups, Do Not Disturb, and preferences for each application." : window.section === -10 ? "Adjust brightness, inactivity timers, laptop lid behavior, and supported power profiles." : window.section === -9 ? "Adjust pointing, scrolling, typing, and keyboard layouts. Changes save and apply automatically." : window.section === -8 ? "Choose application colors, fonts, and cursors." : window.section === -7 ? "Set resolution, refresh rate, scale, rotation, and monitor positions. Confirm changes before they are saved." : window.section === -6 ? "Record a shortcut, choose its action, and save. Changes appear in Super + K." : window.section === -5 ? "Give your coding agents reusable knowledge of your machine." : window.section === -4 ? "Schedule cleanup and review files before removing them." : window.section === -3 ? "Choose your lock screen and when it activates." : window.section === -1 ? "Browse layout, visibility, item spacing, appearance, menus, and clock settings." : window.section === -2 ? "Fine-tune transparency, frosted glass, and window details. Changes save and apply automatically." : "Customize this item. Empty fields follow the original appearance."
                                    wrapMode: Text.WordWrap
                                    color: Style.SettingsTheme.muted
                                }
                                SettingsButton {
                                    objectName: "hyprpaneBackToSettings"
                                    visible: window.section >= 0
                                    text: "← Hyprpane settings"
                                    onClicked: window.section = -1
                                }
                                Rectangle {
                                    objectName: "settingsBarPreview"
                                    Layout.fillWidth: true
                                    visible: window.section >= -1
                                    Layout.preferredHeight: previewBar.y + previewBar.height * previewBar.scale + 16
                                    radius: Style.SettingsTheme.radius
                                    color: Style.SettingsTheme.surface
                                    border.color: Style.SettingsTheme.border
                                    Label {
                                        id: previewLabel
                                        x: 16
                                        y: 12
                                        width: parent.width - 32
                                        wrapMode: Text.WordWrap
                                        text: "Hyprpane preview · drag to rearrange, click to customize"
                                        color: Style.SettingsTheme.muted
                                        font.pixelSize: Style.SettingsTheme.captionSize
                                        font.letterSpacing: 0
                                    }
                                    Bar {
                                        id: previewBar
                                        x: 12
                                        y: previewLabel.y + previewLabel.height + 12
                                        width: vertical ? implicitWidth : Math.max(1000, parent.width - 24)
                                        height: vertical && !compact ? Math.max(720, window.screen ? window.screen.height - 2 * (window.draft.bar.marginSide || 0) : 720) : implicitHeight
                                        scale: vertical ? Math.min(1, 320 / height) : Math.min(1, (parent.width - 24) / width)
                                        transformOrigin: Item.TopLeft
                                        settings: window.draft
                                        screenHeight: window.screen ? window.screen.height : 768
                                        wallpaperSource: window.screen ? window.wallpaperSources[window.screen.name] || "" : ""
                                        trayModel: [{icon: Qt.resolvedUrl("icons/preview-tray.svg")} ]
                                        clockText: Qt.formatDateTime(new Date(), window.draft.bar.clockFormat)
                                        statusData: ({
                                                workspaces: [
                                                    {
                                                        id: 1,
                                                        name: "1",
                                                        active: true
                                                    },
                                                    {
                                                        id: 2,
                                                        name: "2"
                                                    }
                                                ],
                                                audio: {
                                                    text: "64%",
                                                    icon: "󰕾"
                                                },
                                                network: {
                                                    text: "󰤨",
                                                    connected: true
                                                },
                                                bluetooth: {
                                                    text: "󰂯",
                                                    powered: true
                                                },
                                                battery: {
                                                    present: true,
                                                    text: "󰁹 86%"
                                                }
                                            })
                                        mediaData: ({
                                                playing: true,
                                                title: "Your favorite track",
                                                levels: [0.2, 0.5, 0.8, 0.4, 0.9, 0.6, 0.3, 0.7, 0.5, 0.9, 0.3, 0.6]
                                            })
                                        notificationData: ({
                                                count: 2
                                            })
                                        PreviewLayoutEditor {
                                            anchors.fill: parent
                                            bar: previewBar
                                            names: window.names
                                            onItemSelected: id => window.section = window.draft.items.findIndex(i => i.id === id)
                                            onItemDropped: (id, side, beforeId) => window.rearrangeItem(id, side, beforeId)
                                        }
                                    }
                                }
                                SettingsHome {
                                    objectName: "settingsHome"
                                    Layout.fillWidth: true
                                    visible: window.section === window.homeSection
                                    navigation: window.navigation
                                    firstRunPending: window.firstRunPending
                                    onNavigate: section => window.section = section
                                    onSearchRequested: window.focusSearch()
                                }
                                SettingsAccessibility {
                                    visible: window.section === -16
                                    Layout.fillWidth: true
                                    settings: window.draft.accessibility
                                    onEdited: (key, value) => window.updateAccessibility(key, value)
                                    onNavigate: section => window.section = section
                                }
                                Loader {
                                    objectName: "settingsBarEditorLoader"
                                    active: false
                                    onVisibleChanged: if (visible) active = true
                                    Component.onCompleted: if (visible) active = true
                                    visible: window.uiOpened && (window.section === -1)
                                    Layout.fillWidth: true
                                    sourceComponent: SettingsBarEditor {
                                        settings: window.draft.bar
                                        searchQuery: window.searchQuery
                                        itemPages: window.barNavigation
                                        onItemChosen: section => window.section = section
                                        fullConfig: window.draft
                                        onLayoutChosen: config => window.draft = config
                                        currentWorkspace: window.currentWorkspace
                                        onVisibilityEdited: bar => window.updateBarSettings(bar)
                                        onEdited: (key, value) => window.updateBar(key, value)
                                    }
                                }
                                Loader {
                                    objectName: "settingsItemEditorLoader"
                                    active: false
                                    onVisibleChanged: if (visible) active = true
                                    Component.onCompleted: if (visible) active = true
                                    visible: window.uiOpened && (window.section >= 0)
                                    Layout.fillWidth: true
                                    sourceComponent: SettingsItemEditor {
                                        settings: window.selected
                                        allItems: window.draft.items
                                        barSettings: window.draft.bar
                                        saving: window.saving
                                        onEdited: (key, value) => window.updateItem(key, value)
                                        onMoveRequested: direction => window.moveItem(direction)
                                        onResetRequested: window.resetItem()
                                    }
                                }
                                SettingsLocking {
                                    id: lockPage
                                    visible: window.section === -3
                                    Layout.fillWidth: true
                                    settings: window.draft.locking
                                    saved: !window.dirty && !window.saving && window.success
                                    runtimeError: window.lockingError
                                    onLockRequested: window.lockRequested()
                                    onEdited: (key, value) => window.updateLocking(key, value)
                                }
                                SettingsTheme {
                                    id: themePage
                                    visible: window.section === -8
                                    Layout.fillWidth: true
                                }
                                SettingsApplications {
                                    id: applicationsPage
                                    visible: window.section === -13
                                    Layout.fillWidth: true
                                }
                                SettingsPageLoader {
                                    id: firewallPage
                                    objectName: "settingsFirewallLoader"
                                    Layout.fillWidth: true
                                    visible: window.uiOpened && window.section === -22
                                    sourceComponent: SettingsFirewall {
                                        onReviewRequested: card => {
                                            let viewport = editorScroll.contentItem;
                                            let position = card.mapToItem(viewport.contentItem, 0, 0);
                                            viewport.contentY = Math.max(0, Math.min(position.y, viewport.contentHeight - viewport.height));
                                        }
                                    }
                                }
                                SettingsPageLoader {
                                    id: networkPage
                                    objectName: "settingsNetworkLoader"
                                    Layout.fillWidth: true
                                    visible: window.uiOpened && window.section === -15
                                    sourceComponent: SettingsNetwork {}
                                }
                                SettingsPageLoader {
                                    id: regionalPage
                                    objectName: "settingsRegionalLoader"
                                    visible: window.uiOpened && window.section === -17
                                    Layout.fillWidth: true
                                    sourceComponent: SettingsRegional {}
                                }
                                SettingsPageLoader {
                                    id: helpPage
                                    visible: window.uiOpened && window.section === -18
                                    Layout.fillWidth: true
                                    sourceComponent: SettingsHelp { onNavigate: section => window.section = section; onGuideFinished: window.firstRunPending = false }
                                }
                                SettingsPageLoader {
                                    id: behaviorPage
                                    objectName: "settingsBehaviorLoader"
                                    visible: window.uiOpened && window.section === -19
                                    Layout.fillWidth: true
                                    sourceComponent: SettingsBehavior {}
                                }
                                SettingsPageLoader {
                                    id: clipboardPage
                                    visible: window.uiOpened && window.section === -20
                                    Layout.fillWidth: true
                                    sourceComponent: SettingsClipboard { settings: window.draft.clipboard; runtimeError: window.clipboardError; onEdited: (key, value) => window.updateClipboard(key, value) }
                                }
                                SettingsPageLoader {
                                    id: peripheralsPage
                                    visible: window.uiOpened && window.section === -21
                                    Layout.fillWidth: true
                                    sourceComponent: SettingsPeripherals {}
                                }
                                SettingsPageLoader {
                                    id: setupBackupPage
                                    objectName: "settingsSetupBackupLoader"
                                    visible: window.uiOpened && window.section === -23
                                    Layout.fillWidth: true
                                    sourceComponent: SettingsConfigurationRecovery {
                                        ready: !window.dirty && !window.manualDirty && !window.saving && window.success && window.store.loaded
                                        onRestored: settings => {
                                            window.editingSession = false;
                                            window.initial = Model.copy(settings);
                                            window.draft = Model.copy(settings);
                                            window.store.config = Model.copy(settings);
                                            window.store.reload();
                                            window.editingSession = true;
                                        }
                                    }
                                }
                                SettingsRecovery {
                                    id: recoveryPage
                                    visible: window.uiOpened && window.section === -14
                                    Layout.fillWidth: true
                                    ready: !window.dirty && !window.saving && window.success && window.store.loaded
                                    onRestored: settings => {
                                        window.editingSession = false;
                                        window.initial = Model.copy(settings);
                                        window.draft = Model.copy(settings);
                                        window.store.config = Model.copy(settings);
                                        window.store.reload();
                                        window.editingSession = true;
                                    }
                                }
                                SettingsDisplays {
                                    id: displayPage
                                    visible: window.section === -7
                                    Layout.fillWidth: true
                                }
                                SettingsKeybindings {
                                    id: keybindingsPage
                                    targetWindow: window
                                    visible: window.section === -6
                                    Layout.fillWidth: true
                                    onEditorRequested: if (editorScroll.contentItem) editorScroll.contentItem.contentY = 0
                                }
                                SettingsCleanup {
                                    id: cleanupPage
                                    visible: window.section === -4
                                    Layout.fillWidth: true
                                    resetReady: !window.dirty && !window.manualDirty && !window.saving && window.success && window.store.loaded
                                    onRestored: settings => {
                                        window.editingSession = false;
                                        window.initial = Model.copy(settings);
                                        window.draft = Model.copy(settings);
                                        window.store.config = Model.copy(settings);
                                        window.store.reload();
                                        window.editingSession = true;
                                    }
                                }
                                SettingsHyprskill {
                                    id: hyprskillPage
                                    visible: window.section === -5
                                    Layout.fillWidth: true
                                }
                                SettingsPower {
                                    id: powerPage
                                    visible: window.section === -10
                                    Layout.fillWidth: true
                                    settings: window.draft.power
                                    runtimeError: window.powerError
                                    batteryInfo: window.batteryInfo
                                    onEdited: (key, value) => window.updatePower(key, value)
                                }
                                SettingsNotifications {
                                    visible: window.section === -11
                                    Layout.fillWidth: true
                                    settings: window.draft.notifications
                                    applications: window.notificationApps
                                    onEdited: (key, value) => window.updateNotifications(key, value)
                                }
                                SoundTest {
                                    id: soundTester
                                    sink: window.audioServices ? window.audioServices.sink : null
                                    visible: window.uiOpened && window.section === -12
                                }
                                SettingsSound {
                                    id: soundPage
                                    visible: window.uiOpened && window.section === -12
                                    Layout.fillWidth: true
                                    services: window.audioServices
                                    testSound: soundTester
                                }
                                SettingsPageLoader {
                                    id: bluetoothPage
                                    visible: window.uiOpened && window.section === -25
                                    Layout.fillWidth: true
                                    sourceComponent: SettingsBluetooth {}
                                }
                                SettingsInput {
                                    visible: window.section === -9
                                    Layout.fillWidth: true
                                    settings: window.draft.hyprland
                                    onEdited: (key, value) => window.updateHypr(key, value)
                                }
                                Loader {
                                    objectName: "settingsAppearanceLoader"
                                    active: false
                                    onVisibleChanged: if (visible) active = true
                                    Component.onCompleted: if (visible) active = true
                                    visible: window.uiOpened && (window.section === -2)
                                    Layout.fillWidth: true
                                    sourceComponent: SettingsAppearance {
                                        settings: window.draft.hyprland
                                        onEdited: (key, value) => window.updateHypr(key, value)
                                    }
                                }
                            }
                        }
                        Rectangle { Layout.fillWidth: true; Layout.leftMargin: 18; Layout.rightMargin: 18; implicitHeight: 1; color: Style.SettingsTheme.divider }
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.leftMargin: 18
                            Layout.rightMargin: 18
                            Layout.topMargin: 8
                            Layout.bottomMargin: 10
                            spacing: 10
                            Rectangle {
                                Layout.alignment: Qt.AlignVCenter
                                implicitWidth: 7; implicitHeight: 7; radius: 3.5
                                color: !window.success ? Style.SettingsTheme.danger : (window.manualDirty || window.pageDirty) ? Style.SettingsTheme.warning : window.saving ? Style.SettingsTheme.accentText : Style.SettingsTheme.success
                            }
                            Label {
                                Layout.fillWidth: true
                                objectName: "settingsSaveNotice"
                                text: !window.success ? (window.message || window.store.error) : window.saving ? "Saving changes…" : window.savedNotice || (window.pageDirty ? "Unapplied edits kept while Settings is running · " : window.manualDirty ? "Another page has unapplied edits · " : "") + window.savingPolicy()
                                horizontalAlignment: Text.AlignLeft
                                wrapMode: Text.WordWrap
                                font.pixelSize: Style.SettingsTheme.captionSize
                                color: !window.success ? Style.SettingsTheme.danger : window.manualDirty ? Style.SettingsTheme.warning : Style.SettingsTheme.muted
                            }
                            Label {
                                visible: window.hostWidth >= 1120
                                text: "Ctrl F search  ·  Ctrl Tab next"
                                color: Style.SettingsTheme.muted
                                font.pixelSize: Style.SettingsTheme.captionSize
                            }
                        }
                    }
                }
            }
        }
    }
}
