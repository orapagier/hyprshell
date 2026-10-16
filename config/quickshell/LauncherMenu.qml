pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "ApplicationModel.js" as Apps

ColumnLayout {
    id: page
    signal launched()
    property var applicationService: null
    readonly property bool interacting: pinMenu.visible
    property bool active: true
    function prepare() {
        search.clear();
        applications.currentIndex = entries.length ? 0 : -1;
        Qt.callLater(() => { if (page.active) search.forceActiveFocus(); });
    }
    onActiveChanged: if (active) prepare()
    readonly property var sortedEntries: applicationService ? applicationService.entries : DesktopEntries.applications.values.slice().sort((a,b) => a.name.localeCompare(b.name))
    readonly property var entries: sortedEntries.filter(a => (a.name + " " + a.genericName).toLowerCase().includes(search.text.toLowerCase()))
    onEntriesChanged: {
        applications.currentIndex = entries.length ? 0 : -1;
        applications.positionViewAtBeginning();
    }
    function moveSelection(step) {
        if (!entries.length) return;
        applications.currentIndex = applications.currentIndex < 0 ? 0
            : Math.max(0, Math.min(entries.length - 1, applications.currentIndex + step));
        applications.positionViewAtIndex(applications.currentIndex, ListView.Contain);
    }
    function launch(entry) {
        if (!entry || !entry.id) return;
        if (applicationService) {
            if (!applicationService.launch(entry)) return;
        } else {
            let command = Apps.launchCommand(entry);
            if (command.length) Quickshell.execDetached(command);
            else entry.execute();
        }
        launched();
    }
    function pinEntry(entry) {
        if (!applicationService || !entry) return;
        pinMenu.entry = entry;
        pinMenu.popup();
    }
    Menu {
        id: pinMenu
        palette.text: '#cdd6f4'; palette.windowText: '#cdd6f4'; palette.buttonText: '#cdd6f4'
        palette.window: '#1e1e2e'; palette.base: '#1e1e2e'; palette.button: '#38384d'
        palette.highlight: '#66517e'; palette.highlightedText: '#cdd6f4'
        property var entry: null
        MenuItem {
            text: 'Pin to Hyprdock'
            enabled: !!page.applicationService && !page.applicationService.busy
            onTriggered: page.applicationService.edit({action:'pin',component:'hyprdock',id:Apps.desktopId(pinMenu.entry)})
        }
        MenuItem {
            text: 'Pin to Hyprbar'
            enabled: !!page.applicationService && !page.applicationService.busy
            onTriggered: page.applicationService.edit({action:'pin',component:'hyprbar',id:Apps.desktopId(pinMenu.entry)})
        }
    }
    Shortcut {
        sequence: 'Ctrl+P'
        enabled: page.active && !!page.applicationService && page.entries.length > 0
        onActivated: page.pinEntry(page.entries[Math.max(0,applications.currentIndex)])
    }
    spacing: 8
    Loader { id: fallbackIcons; active: !page.applicationService; visible: false; sourceComponent: AppIcons {} }
    TextField {
        id: search
        objectName: "launcherSearch"
        Layout.fillWidth: true
        placeholderText: "Search applications"; color: "#cdd6f4"; placeholderTextColor: "#a6adc8"
        font.family: "DejaVu Sans"; font.pixelSize: 13
        background: Rectangle { radius: 8; color: "#0bffffff"; border.color: "#1fffffff" }
        Component.onCompleted: if (page.active) page.prepare()
        onAccepted: { if (page.entries.length) page.launch(page.entries[Math.max(0, applications.currentIndex)]); }
        Keys.onDownPressed: page.moveSelection(1)
        Keys.onUpPressed: page.moveSelection(-1)
    }
    ListView {
        id: applications
        objectName: "applicationsList"
        Layout.fillWidth: true; Layout.preferredHeight: 300
        model: page.entries
        clip: true; spacing: 4
        keyNavigationEnabled: true
        Keys.onReturnPressed: { if (currentIndex >= 0 && page.entries[currentIndex]) { page.launch(page.entries[currentIndex]); } }
        delegate: AppListButton {
            required property var modelData
            required property int index
            width: applications.width
            text: modelData.name
            iconSource: page.applicationService ? page.applicationService.iconSource(modelData.icon) : fallbackIcons.item ? (fallbackIcons.item.source(modelData.icon) || fallbackIcons.item.source("application-x-executable")) : ""
            accent: (applications.activeFocus || search.activeFocus) && applications.currentIndex === index ? "#cba6f7" : "#cdd6f4"
            onClicked: { page.launch(modelData); }
            TapHandler {
                acceptedButtons: Qt.RightButton
                onTapped: page.pinEntry(modelData)
            }
        }
    }
}
