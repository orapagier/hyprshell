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
    property var wallpaperSources: ({})
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
    readonly property bool saving: writer.running
    readonly property bool idle: !writer.running && !autoSave.running && !displayPage.busy && !cleanupPage.busy && !hyprskillPage.busy && !githubSync.running && !githubUpdate.busy && !keybindingsPage.busy && !themePage.busy && !applicationsPage.busy && !recoveryPage.busy && !powerPage.busy && !soundPage.busy && !networkPage.busy && !firewallPage.busy && !regionalPage.busy && !helpPage.busy && !behaviorPage.busy && !clipboardPage.busy && !peripheralsPage.busy
    readonly property bool manualDirty: lockPage.dirty || themePage.dirty || displayPage.dirty || keybindingsPage.dirty || cleanupPage.dirty || regionalPage.dirty || firewallPage.dirty || behaviorPage.dirty || recoveryPage.dirty
    readonly property bool pageDirty: section === -3 ? lockPage.dirty : section === -8 ? themePage.dirty : section === -7 ? displayPage.dirty : section === -6 ? keybindingsPage.dirty : section === -4 ? cleanupPage.dirty : section === -17 ? regionalPage.dirty : section === -22 ? firewallPage.dirty : section === -19 ? behaviorPage.dirty : section === -14 ? recoveryPage.dirty : false
    function savingPolicy() {
        if (section === -3) return "Timers save automatically · Use Apply lock command to change the locker";
        if (section === -8) return "Colors save immediately · Apply font and cursor to save them";
        if (section === -7) return "Apply and confirm display changes before they are saved";
        if (section === -6) return "Use Save shortcut to apply your edits";
        if (section === -4) return "Use Save cleanup settings to apply your edits";
        if (section === -17) return "Use Save for next login to save language and region";
        if (section === -19) return "Use Apply changes to save workspaces and rules";
        if (section === -14) return "Backup plans require Save · Recovery and updates require an explicit action";
        if ([-5, -15, -18, -21, -22].indexOf(section) >= 0) return "Use this page’s action buttons";
        if (section === -12) return "Sound changes apply immediately and are remembered by the audio service";
        if (section === -10) return "Timers save automatically · Hardware controls apply immediately";
        if (section === -13) return "Choices save immediately · Startup changes take effect at next login";
        return "Changes save automatically";
    }
    onDraftChanged: { Style.Theme.preferences = draft.accessibility || {}; if (editingSession) autoSave.restart(); }
    Component.onCompleted: Style.Theme.preferences = draft.accessibility || {}
    onVisibleChanged: {
        if (visible) Qt.callLater(focusSearch);
        else if (editingSession && dirty) apply();
    }
    function focusSearch() {
        if (!visible) return;
        searchField.forceActiveFocus();
        searchField.selectAll();
    }
    property int section: -1
    property var scrollPositions: ({})
    property int previousSection: -1
    property string searchQuery: ""
    property int searchResultIndex: -1
    onSearchResultsChanged: {
        searchResultIndex = searchResults.length ? 0 : -1;
        if (searchQuery.trim()) Qt.callLater(() => moveSearchSelection(0));
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
    property bool barItemsExpanded: false
    readonly property var navigation: [
        {group: "Desktop", pages: [
            {section: -8, title: "Appearance", symbol: "󰔎", keywords: "theme colors font cursor"},
            {section: -20, title: "Clipboard history", symbol: "󰅍", keywords: "copy paste clips text images"},
            {section: -21, title: "Printing & scanning", symbol: "󰐪", keywords: "printer scanner cups paper documents"},
            {section: -19, title: "Workspaces & rules", symbol: "󰍹", keywords: "workspace rules tiling layout focus pointer"},
            {section: -2, title: "Windows", symbol: "󰖲", keywords: "hyprland transparency blur gaps animations"},
            {section: -1, title: "Bar & layout", symbol: "󰕮", keywords: "topbar hyprbar position screen edge top bottom left right spacing workspace workspaces"},
            {section: -13, title: "Applications", symbol: "󰀻", keywords: "default apps startup"},
            {section: -11, title: "Notifications", symbol: "󰂚", keywords: "delivery popups disturb"}
        ]},
        {group: "Devices", pages: [
            {section: -7, title: "Displays", symbol: "󰍹", keywords: "monitor resolution scale rotation"},
            {section: -15, title: "Network", symbol: "󰤨", keywords: "wifi wi-fi hidden enterprise vpn wireguard ethernet connections dns"},
            {section: -12, title: "Sound", symbol: "󰕾", keywords: "audio volume microphone speakers"},
            {section: -9, title: "Mouse & keyboard", symbol: "󰍽", keywords: "input touchpad scrolling typing layouts"},
            {section: -6, title: "Keyboard shortcuts", symbol: "󰌌", keywords: "keybindings hotkeys"}
        ]},
        {group: "System", pages: [
            {section: -22, title: "Firewall", symbol: "󰒃", keywords: "firewalld security rules ports services zones block incoming tcp udp"},
            {section: -16, title: "Accessibility", symbol: "󰋁", keywords: "large text size contrast reduced motion animations"},
            {section: -17, title: "Language & region", symbol: "󰗊", keywords: "locale timezone date time number formats"},
            {section: -10, title: "Power & battery", symbol: "󰁹", keywords: "brightness sleep lid profiles"},
            {section: -3, title: "Screen locking", symbol: "󰌾", keywords: "security idle lock"},
            {section: -4, title: "Cleanup", symbol: "󰃢", keywords: "storage files maintenance"},
            {section: -14, title: "Updates & recovery", symbol: "󰁯", keywords: "backup restore checkpoints"},
            {section: -18, title: "Help & diagnostics", symbol: "󰋖", keywords: "welcome guide health diagnostics support getting started"},
            {section: -5, title: "Hyprskill", symbol: "󰒓", keywords: "agents coding knowledge"}
        ]}
    ]
    readonly property var barNavigation: draft.items.map((item, index) => ({section: index, title: names[item.id] || item.id, symbol: symbols[item.id] || "󰒓", keywords: "bar item " + item.id, itemEnabled: item.enabled}))
    readonly property var searchResults: navigation.reduce((pages, group) => pages.concat(matchingPages(group.pages)), []).concat(matchingPages(barNavigation))
    function matchingPages(pages) {
        let query = searchQuery.trim().toLowerCase();
        return pages.filter(page => !query || (page.title + " " + page.keywords).toLowerCase().includes(query));
    }
    onSectionChanged: {
        if (editorScroll.contentItem) scrollPositions[previousSection] = editorScroll.contentItem.contentY;
        previousSection = section;
        if (section >= 0) barItemsExpanded = true;
        Qt.callLater(() => {
            if (editorScroll.contentItem) editorScroll.contentItem.contentY = scrollPositions[section] || 0;
        });
        pageFade.restart();
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
    color: Style.Theme.background
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
        if (visible) {
            focusRequested();
            Qt.callLater(focusSearch);
            return;
        }
        if (editingSession && (dirty || saving || manualDirty)) {
            visible = true;
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
        if (firstRunPending) section = -18;
        visible = true;
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
        if (JSON.stringify(before.bar) !== JSON.stringify(after.bar)) labels.push("Bar & layout");
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
        interval: 500
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
                        window.store.config = Model.copy(window.submitted);
                        window.store.reload();
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
        enabled: window.visible
        onActivated: { searchField.forceActiveFocus(); searchField.selectAll(); }
    }
    NumberAnimation {
        id: pageFade
        target: pageContent
        property: "opacity"
        from: 0.65
        to: 1
        duration: window.draft.hyprland.animations === false ? 0 : 140
        easing.type: Easing.OutCubic
    }
    SettingsGithubUpdate { id: githubUpdate; hostWidth: window.width; hostHeight: window.height }
    Popup {
        id: githubDialog
        objectName: "githubSyncDialog"
        anchors.centerIn: parent
        width: Math.min(480, window.width - 40)
        padding: 24
        modal: true
        closePolicy: githubSync.running ? Popup.NoAutoClose : Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle { color: Style.Theme.surface; radius: 14; border.color: Style.Theme.controlBorder }
        contentItem: ColumnLayout {
            spacing: 14
            Label { text: "Sync to GitHub"; color: Style.Theme.text; font.pixelSize: 20; font.bold: true }
            Label { Layout.fillWidth: true; text: "Sync saves your current desktop to a local commit, then pushes it to GitHub."; wrapMode: Text.WordWrap; color: Style.Theme.muted }
            Label { objectName: "githubRepositoryLabel"; text: window.syncRepository || "Sign in to find your repository"; color: Style.Theme.accentText }
            Label { Layout.fillWidth: true; text: window.syncMessage; wrapMode: Text.WordWrap; color: window.syncSuccess ? Style.Theme.muted : Style.Theme.danger }
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
        objectName: "settingsRoot"
        anchors.fill: parent
        padding: 0
        property bool settingsMotionEnabled: window.draft.hyprland.animations !== false && !window.draft.accessibility.reducedMotion
        palette.window: Style.Theme.background
        palette.windowText: Style.Theme.text
        palette.text: Style.Theme.text
        palette.base: Style.Theme.surface
        palette.button: Style.Theme.button
        palette.buttonText: Style.Theme.text
        palette.highlight: Style.Theme.accent
        palette.highlightedText: Style.Theme.accentForeground
        palette.brightText: Style.Theme.accentForeground
        palette.dark: Style.Theme.accentText
        palette.mid: Style.Theme.border
        font.family: "Noto Sans"
        font.pixelSize: Style.Theme.bodySize
        background: Rectangle { color: Style.Theme.background }
        contentItem: ColumnLayout {
            spacing: 0
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.preferredHeight: 64
                Layout.leftMargin: 22
                Layout.rightMargin: 22
                ColumnLayout {
                    spacing: 2
                    Label {
                        text: "Hyprshell"
                        font.pixelSize: 18
                        font.bold: true
                        color: Style.Theme.text
                    }
                    Label {
                        text: "Settings"
                        font.pixelSize: Style.Theme.captionSize
                        color: Style.Theme.muted
                    }
                }
                Item {
                    Layout.fillWidth: true
                }
                SettingsGithubButton {
                    objectName: "githubSyncButton"
                    text: githubSync.running ? "Syncing…" : "Sync to GitHub"
                    enabled: window.idle && !window.dirty && !window.manualDirty && window.success && window.store.loaded
                    ToolTip.visible: hovered
                    ToolTip.text: "Commit and push your desktop setup to your GitHub hyprshell repository"
                    onClicked: {
                        githubDialog.open();
                        githubSync.request("--status", []);
                    }
                }
                SettingsGithubButton {
                    objectName: "githubUpdateButton"
                    text: "Sync from GitHub"
                    enabled: window.idle && !window.dirty && !window.manualDirty && window.success && window.store.loaded
                    ToolTip.visible: hovered
                    ToolTip.text: "Review incoming changes and compatibility before updating Hyprshell"
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
            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Style.Theme.separator }
            RowLayout {
                enabled: !githubSync.running && !githubUpdate.busy && !recoveryPage.busy
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0
                ScrollView {
                    id: sidebar
                    objectName: "settingsSidebar"
                    Layout.preferredWidth: window.width < 900 ? 228 : 250
                    Layout.fillHeight: true
                    clip: true
                    padding: 12
                    contentWidth: availableWidth
                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                    background: Rectangle { color: Style.Theme.sidebar }
                    ColumnLayout {
                        width: sidebar.availableWidth
                        spacing: 4
                        TextField {
                            id: searchField
                            objectName: "settingsSearch"
                            Layout.fillWidth: true
                            Layout.bottomMargin: 10
                            implicitHeight: 38
                            placeholderText: "Search settings"
                            color: Style.Theme.text
                            placeholderTextColor: Style.Theme.muted
                            font.pixelSize: Style.Theme.bodySize
                            leftPadding: 12
                            rightPadding: searchClear.visible ? 38 : 12
                            selectByMouse: true
                            Accessible.name: "Search settings"
                            onTextChanged: window.searchQuery = text
                            onAccepted: if (window.searchResults.length) window.section = window.searchResults[Math.max(0, window.searchResultIndex)].section
                            Keys.onDownPressed: window.moveSearchSelection(1)
                            Keys.onUpPressed: window.moveSearchSelection(-1)
                            Keys.onEscapePressed: event => {
                                if (text.length) { clear(); event.accepted = true; }
                                else event.accepted = false;
                            }
                            background: Rectangle {
                                radius: Style.Theme.controlRadius
                                color: Style.Theme.field
                                border.width: 1
                                border.color: Style.Theme.border
                            }
                            ToolButton {
                                id: searchClear
                                objectName: "settingsSearchClear"
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                width: 34; height: 34
                                text: "×"
                                visible: searchField.text.length > 0
                                Accessible.name: "Clear search"
                                onClicked: { searchField.clear(); searchField.forceActiveFocus(); }
                                contentItem: Text { text: searchClear.text; color: Style.Theme.muted; font.pixelSize: 20; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                                background: Rectangle { radius: 6; color: searchClear.hovered ? Style.Theme.hover : "transparent"; border.color: searchClear.activeFocus ? Style.Theme.accentText : "transparent" }
                            }
                        }
                        Repeater {
                            id: navigationGroups
                            model: window.navigation
                            delegate: ColumnLayout {
                                id: navGroup
                                required property var modelData
                                readonly property var pages: window.matchingPages(modelData.pages)
                                property alias buttons: pageResults
                                visible: pages.length > 0
                                Layout.fillWidth: true
                                spacing: 3
                                Label {
                                    text: navGroup.modelData.group
                                    Layout.leftMargin: 12
                                    Layout.topMargin: 12
                                    Layout.bottomMargin: 5
                                    color: Style.Theme.muted
                                    font.pixelSize: Style.Theme.captionSize
                                    font.weight: Font.DemiBold
                                }
                                Repeater {
                                    id: pageResults
                                    model: navGroup.pages
                                    delegate: SettingsNavButton {
                                        required property var modelData
                                        objectName: "settingsNav" + modelData.section
                                        text: modelData.title
                                        symbol: modelData.symbol
                                        Layout.fillWidth: true
                                        keyboardSelected: searchField.activeFocus && window.searchResultIndex >= 0 && window.searchResults[window.searchResultIndex]?.section === modelData.section
                                        highlighted: window.section === modelData.section
                                        onClicked: window.section = modelData.section
                                    }
                                }
                            }
                        }
                        SettingsButton {
                            objectName: "settingsBarItemsToggle"
                            Layout.fillWidth: true
                            Layout.topMargin: 16
                            flat: true
                            text: "Bar items  " + (window.barItemsExpanded || window.searchQuery.trim() ? "⌃" : "⌄")
                            visible: window.matchingPages(window.barNavigation).length > 0
                            Accessible.description: window.barItemsExpanded ? "Expanded" : "Collapsed"
                            onClicked: window.barItemsExpanded = !window.barItemsExpanded
                        }
                        Repeater {
                            id: barResults
                            model: window.barItemsExpanded || window.searchQuery.trim() ? window.matchingPages(window.barNavigation) : []
                            delegate: SettingsNavButton {
                                required property var modelData
                                text: modelData.title
                                symbol: modelData.symbol
                                itemEnabled: modelData.itemEnabled
                                Layout.fillWidth: true
                                keyboardSelected: searchField.activeFocus && window.searchResultIndex >= 0 && window.searchResults[window.searchResultIndex]?.section === modelData.section
                                highlighted: window.section === modelData.section
                                onClicked: window.section = modelData.section
                            }
                        }
                        Label {
                            objectName: "settingsSearchEmpty"
                            visible: window.searchResults.length === 0
                            Layout.fillWidth: true
                            Layout.margins: 12
                            text: "No settings found. Try another search."
                            color: Style.Theme.muted
                            font.pixelSize: Style.Theme.bodySize
                            wrapMode: Text.WordWrap
                        }
                    }
                }
                Rectangle { Layout.fillHeight: true; implicitWidth: 1; color: Style.Theme.separator }
                ScrollView {
                    id: editorScroll
                    objectName: "settingsEditorScroll"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    contentWidth: availableWidth
                    padding: window.width < 900 ? 22 : 36
                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                    background: Rectangle { color: Style.Theme.background }
                    ColumnLayout {
                        id: pageContent
                        objectName: "settingsPageContent"
                        width: Math.min(840, editorScroll.availableWidth)
                        x: Math.max(0, (editorScroll.availableWidth - width) / 2)
                        spacing: 24
                        Label {
                            objectName: "settingsPageTitle"
                            text: window.section >= 0 ? window.names[window.selected.id] || "" : window.navigation.reduce((pages, group) => pages.concat(group.pages), []).find(page => page.section === window.section)?.title || "Settings"
                            font.pixelSize: Style.Theme.titleSize
                            font.bold: true
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                        }
                        Label {
                            Layout.fillWidth: true
                            Layout.topMargin: -14
                            font.pixelSize: Style.Theme.bodySize
                            text: window.section === -22 ? "Choose what other devices can access on this laptop." : window.section === -20 ? "Optional local clipboard history" : window.section === -21 ? "Printers and scanners when you need them" : window.section === -19 ? "Choose workspace layouts and rules for application windows." : window.section === -18 ? "Get started, check desktop services, and create a private diagnostic report." : window.section === -17 ? "Choose application language, timezone, and regional formats." : window.section === -16 ? "Make controls easier to read and reduce desktop motion." : window.section === -15 ? "Manage saved connections, hidden and enterprise Wi-Fi, and VPNs." : window.section === -14 ? "Keep your system updated, recover personal configuration, and back up personal files." : window.section === -13 ? "Choose which apps open files and which start when you log in." : window.section === -12 ? "Choose sound devices, check your microphone, and adjust application volumes." : window.section === -11 ? "Choose popups, Do Not Disturb, and preferences for each application." : window.section === -10 ? "Adjust brightness, inactivity timers, laptop lid behavior, and supported power profiles." : window.section === -9 ? "Adjust pointing, scrolling, typing, and keyboard layouts. Changes save and apply automatically." : window.section === -8 ? "Choose application colors, fonts, and cursors." : window.section === -7 ? "Set resolution, refresh rate, scale, rotation, and monitor positions. Confirm changes before they are saved." : window.section === -6 ? "Record a shortcut, choose its action, and save. Changes appear in Super + K." : window.section === -5 ? "Give your coding agents reusable knowledge of your machine." : window.section === -4 ? "Schedule cleanup and review files before removing them." : window.section === -3 ? "Choose your lock screen and when it activates." : window.section === -1 ? "Set the layout and default appearance for your desktop bar." : window.section === -2 ? "Fine-tune transparency, frosted glass, and window details. Changes save and apply automatically." : "Customize this item. Empty fields follow the original appearance."
                            wrapMode: Text.WordWrap
                            color: Style.Theme.muted
                        }
                        Rectangle {
                            objectName: "settingsBarPreview"
                            Layout.fillWidth: true
                            visible: window.section >= -1
                            Layout.preferredHeight: previewBar.y + previewBar.height * previewBar.scale + 16
                            radius: Style.Theme.radius
                            color: Style.Theme.surface
                            border.color: Style.Theme.border
                            Label {
                                id: previewLabel
                                x: 16
                                y: 12
                                width: parent.width - 32
                                wrapMode: Text.WordWrap
                                text: "Bar preview · drag to rearrange, click to customize"
                                color: Style.Theme.muted
                                font.pixelSize: Style.Theme.captionSize
                                font.letterSpacing: 0
                            }
                            Bar {
                                id: previewBar
                                x: 12
                                y: previewLabel.y + previewLabel.height + 12
                                width: vertical ? implicitWidth : Math.max(1000, parent.width - 24)
                                height: vertical ? Math.max(720, window.screen ? window.screen.height - 2 * (window.draft.bar.marginSide || 0) : 720) : implicitHeight
                                scale: vertical ? Math.min(1, 320 / height) : Math.min(1, (parent.width - 24) / width)
                                transformOrigin: Item.TopLeft
                                settings: window.draft
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
                        SettingsAccessibility {
                            visible: window.section === -16
                            Layout.fillWidth: true
                            settings: window.draft.accessibility
                            onEdited: (key, value) => window.updateAccessibility(key, value)
                            onNavigate: section => window.section = section
                        }
                        SettingsBarEditor {
                            visible: window.section === -1
                            Layout.fillWidth: true
                            settings: window.draft.bar
                            currentWorkspace: window.currentWorkspace
                            onVisibilityEdited: bar => window.updateBarSettings(bar)
                            onEdited: (key, value) => window.updateBar(key, value)
                        }
                        SettingsItemEditor {
                            visible: window.section >= 0
                            Layout.fillWidth: true
                            settings: window.selected
                            allItems: window.draft.items
                            barSettings: window.draft.bar
                            saving: window.saving
                            onEdited: (key, value) => window.updateItem(key, value)
                            onMoveRequested: direction => window.moveItem(direction)
                            onResetRequested: window.resetItem()
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
                            visible: window.visible && window.section === -22
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
                            visible: window.visible && window.section === -15
                            sourceComponent: SettingsNetwork {}
                        }
                        SettingsPageLoader {
                            id: regionalPage
                            objectName: "settingsRegionalLoader"
                            visible: window.visible && window.section === -17
                            Layout.fillWidth: true
                            sourceComponent: SettingsRegional {}
                        }
                        SettingsPageLoader {
                            id: helpPage
                            visible: window.visible && window.section === -18
                            Layout.fillWidth: true
                            sourceComponent: SettingsHelp { onNavigate: section => window.section = section; onGuideFinished: window.firstRunPending = false }
                        }
                        SettingsPageLoader {
                            id: behaviorPage
                            objectName: "settingsBehaviorLoader"
                            visible: window.visible && window.section === -19
                            Layout.fillWidth: true
                            sourceComponent: SettingsBehavior {}
                        }
                        SettingsPageLoader {
                            id: clipboardPage
                            visible: window.visible && window.section === -20
                            Layout.fillWidth: true
                            sourceComponent: SettingsClipboard { settings: window.draft.clipboard; runtimeError: window.clipboardError; onEdited: (key, value) => window.updateClipboard(key, value) }
                        }
                        SettingsPageLoader {
                            id: peripheralsPage
                            visible: window.visible && window.section === -21
                            Layout.fillWidth: true
                            sourceComponent: SettingsPeripherals {}
                        }
                        SettingsRecovery {
                            id: recoveryPage
                            visible: window.visible && window.section === -14
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
                            visible: window.visible && window.section === -12
                        }
                        SettingsSound {
                            id: soundPage
                            visible: window.visible && window.section === -12
                            Layout.fillWidth: true
                            services: window.audioServices
                            testSound: soundTester
                        }
                        SettingsInput {
                            visible: window.section === -9
                            Layout.fillWidth: true
                            settings: window.draft.hyprland
                            onEdited: (key, value) => window.updateHypr(key, value)
                        }
                        SettingsAppearance {
                            visible: window.section === -2
                            Layout.fillWidth: true
                            settings: window.draft.hyprland
                            onEdited: (key, value) => window.updateHypr(key, value)
                        }
                    }
                }
            }
            Label {
                Layout.fillWidth: true
                objectName: "settingsSaveNotice"
                Layout.minimumHeight: 30
                Layout.leftMargin: 16
                Layout.rightMargin: 16
                topPadding: 7
                bottomPadding: 7
                text: !window.success ? (window.message || window.store.error) : window.saving ? "Saving changes…" : window.savedNotice || (window.pageDirty ? "Unapplied edits kept while Settings is running · " : window.manualDirty ? "Another page has unapplied edits · " : "") + window.savingPolicy()
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                font.pixelSize: Style.Theme.captionSize
                color: !window.success ? Style.Theme.danger : window.manualDirty ? Style.Theme.warning : Style.Theme.muted
            }
        }
    }
}
