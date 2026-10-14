pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

ColumnLayout {
    id: page
    signal launched()
    property bool active: true
    function prepare() {
        search.clear();
        applications.currentIndex = entries.length ? 0 : -1;
        Qt.callLater(() => { if (page.active) search.forceActiveFocus(); });
    }
    onActiveChanged: if (active) prepare()
    readonly property var sortedEntries: DesktopEntries.applications.values.slice().sort((a,b) => a.name.localeCompare(b.name))
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
        let desktopId = entry.id.endsWith(".desktop") ? entry.id : entry.id + ".desktop";
        // UWSM reads desktop metadata (including Terminal and working directory).
        // Services inherit the current manager environment after theme changes.
        // uwsM only accepts desktop IDs matching [A-Za-z0-9_][A-Za-z0-9_.-]*.desktop;
        // a file name with a space in it (My Download Manager.desktop, say) is
        // rejected before the entry is even looked up. Those are launched by
        // Quickshell itself instead, which parses Exec and working directory;
        // runInTerminal and %-field codes are ignored, which these rare names
        // lose nothing from in practice.
        if (/^[A-Za-z0-9_][A-Za-z0-9_.-]*\.desktop$/.test(desktopId)) {
            Quickshell.execDetached(["uwsm", "app", "-t", "service", "--", desktopId]);
        } else {
            entry.execute();
        }
        launched();
    }
    spacing: 8
    AppIcons { id: icons; visible: false }
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
            iconSource: icons.source(modelData.icon) || icons.source("application-x-executable")
            accent: (applications.activeFocus || search.activeFocus) && applications.currentIndex === index ? "#cba6f7" : "#cdd6f4"
            onClicked: { page.launch(modelData); }
        }
    }
}
