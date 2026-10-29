pragma ComponentBehavior: Bound
import QtQuick
import "AdaptiveColors.js" as Colors
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "ApplicationModel.js" as Apps

ColumnLayout {
    id: page
    property bool fitContent: false
    readonly property var menuColors: Colors.menuColorsFor(page)
    signal launched()
    property url wallpaperSource: ""
    property real translucency: 0.06
    property var applicationService: null
    readonly property bool interacting: false
    property bool active: true
    function prepare() {
        search.clear();
        applications.currentIndex = entries.length ? 0 : -1;
        Qt.callLater(() => { if (page.active) search.forceActiveFocus(); });
    }
    onActiveChanged: if (active) prepare()
    Component.onCompleted: if (active) prepare()
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
    spacing: 12
    Loader { id: fallbackIcons; active: !page.applicationService; visible: false; sourceComponent: AppIcons {} }
    TextField {
        id: search
        objectName: "launcherSearch"
        Layout.fillWidth: true
        implicitHeight: 46
        leftPadding: 15; rightPadding: 15
        placeholderText: "Search applications"; color: page.menuColors.text; placeholderTextColor: page.menuColors.secondary
        font.family: "Noto Sans"; font.pixelSize: 13
        selectionColor: page.menuColors.accent
        selectedTextColor: page.menuColors.background
        background: Rectangle {
            radius: 12
            color: Qt.rgba(page.menuColors.background.r, page.menuColors.background.g, page.menuColors.background.b, 0.65)
            border.color: Qt.rgba(page.menuColors.text.r, page.menuColors.text.g, page.menuColors.text.b, 0.12)
            Behavior on border.color { ColorAnimation { duration: 140 } }
        }
        Component.onCompleted: if (page.active) page.prepare()
        onAccepted: { if (page.entries.length) page.launch(page.entries[Math.max(0, applications.currentIndex)]); }
        Keys.onDownPressed: page.moveSelection(1)
        Keys.onUpPressed: page.moveSelection(-1)
    }
    ListView {
        id: applications
        objectName: "applicationsList"
        Layout.fillWidth: true; Layout.fillHeight: true
        Layout.preferredHeight: page.fitContent ? Math.max(120, Math.min(520, applications.contentHeight)) : 300; Layout.minimumHeight: 120
        model: page.entries
        clip: true; spacing: 6
        keyNavigationEnabled: true
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
        Keys.onReturnPressed: { if (currentIndex >= 0 && page.entries[currentIndex]) { page.launch(page.entries[currentIndex]); } }
        delegate: AppListButton {
            id: appRow
            required property var modelData
            required property int index
            readonly property bool rowHighlighted: hovered || ((applications.activeFocus || search.activeFocus) && applications.currentIndex === index)
            width: applications.width
            implicitHeight: 54
            leftPadding: 14; rightPadding: 14
            font.family: "Noto Sans"; font.pixelSize: 13; font.weight: Font.Medium
            text: modelData.name
            iconSource: page.applicationService ? page.applicationService.iconSource(modelData.icon) : fallbackIcons.item ? (fallbackIcons.item.source(modelData.icon) || fallbackIcons.item.source("application-x-executable")) : ""
            accent: page.menuColors.text
            background: Rectangle {
                radius: 12
                color: appRow.down ? page.menuColors.pressed : appRow.rowHighlighted
                    ? Qt.rgba(page.menuColors.accent.r, page.menuColors.accent.g, page.menuColors.accent.b, 0.12)
                    : Qt.rgba(page.menuColors.text.r, page.menuColors.text.g, page.menuColors.text.b, 0.035)
                border.color: appRow.rowHighlighted
                    ? Qt.rgba(page.menuColors.accent.r, page.menuColors.accent.g, page.menuColors.accent.b, 0.24) : "transparent"
                Behavior on color { ColorAnimation { duration: 120 } }
            }
            onClicked: { page.launch(modelData); }
        }
        Column {
            anchors.centerIn: parent; width: parent.width; spacing: 8
            visible: !page.entries.length
            Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: "No applications found"; color: page.menuColors.text; font.family: "Noto Sans"; font.pixelSize: 14; font.weight: Font.Medium }
            Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: "Try a different name"; color: page.menuColors.secondary; font.family: "Noto Sans"; font.pixelSize: 12 }
        }
    }
    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Qt.rgba(page.menuColors.text.r, page.menuColors.text.g, page.menuColors.text.b, 0.08) }
    RowLayout {
        Layout.fillWidth: true
        Text { text: page.entries.length + " of " + page.sortedEntries.length + " apps"; color: page.menuColors.secondary; font.family: "Noto Sans"; font.pixelSize: 11; Layout.fillWidth: true }
        Text { text: "↑ ↓  Browse   ·   Enter  Open"; color: page.menuColors.secondary; font.family: "Noto Sans"; font.pixelSize: 11 }
    }
}
