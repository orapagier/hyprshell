pragma ComponentBehavior: Bound
import QtQuick
import "AdaptiveColors.js" as Colors
import QtQuick.Controls
import QtQuick.Controls.Basic as Basic
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import "ApplicationModel.js" as Apps

ColumnLayout {
    id: page
    readonly property var menuColors: Colors.menuColorsFor(page)
    signal launched()
    property url wallpaperSource: ""
    property real translucency: 0.06
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
    Basic.Menu {
        id: pinMenu
        objectName: "launcherPinMenu"
        palette.text: page.menuColors.text; palette.windowText: page.menuColors.text; palette.buttonText: page.menuColors.text
        palette.window: 'transparent'; palette.base: 'transparent'; palette.button: 'transparent'
        palette.highlight: Colors.alpha(page.menuColors.accent, 0.24); palette.highlightedText: page.menuColors.text
        property var entry: null
        padding: 8
        implicitWidth: 228
        popupType: Popup.Item
        background: Rectangle {
            objectName: 'launcherPinGlass'
            radius: 16
            border.color: pinGlass.rimColor
            gradient: Gradient {
                GradientStop { position: 0; color: pinGlass.topColor }
                GradientStop { position: 1; color: pinGlass.bottomColor }
            }
            GlassSurface {
                id: pinGlass
                anchors.fill: parent
                wallpaperSource: page.wallpaperSource
                translucency: page.translucency
                screenWidth: page.Window.window ? page.Window.window.width : page.width
                screenHeight: page.Window.window ? page.Window.window.height : page.height
                region: { let point = pinMenu.parent ? pinMenu.parent.mapToItem(null, pinMenu.x, pinMenu.y) : Qt.point(0, 0); return Qt.rect(point.x, point.y, width, height); }
            }
            Rectangle { x:16; y:1; width:parent.width-32; height:1; color:Colors.alpha(page.menuColors.accent, 0.28) }
        }
        component PinAction: Basic.MenuItem {
            id: pinAction
            implicitHeight: 38
            leftPadding: 12; rightPadding: 12
            contentItem: Text {
                text: pinAction.text; color:page.menuColors.text
                font.family:'DejaVu Sans'; font.pixelSize:13
                verticalAlignment:Text.AlignVCenter
                elide:Text.ElideRight
                opacity:pinAction.enabled ? 1 : 0.45
            }
            background: Rectangle {
                radius: 10
                color: pinAction.highlighted ? Colors.alpha(page.menuColors.accent, 0.19) : 'transparent'
                border.color: pinAction.activeFocus ? Colors.alpha(page.menuColors.accent, 0.40) : 'transparent'
            }
        }
        PinAction {
            text: 'Pin to Hyprdock'
            enabled: !!page.applicationService && !page.applicationService.busy
            onTriggered: page.applicationService.edit({action:'pin',component:'hyprdock',id:Apps.desktopId(pinMenu.entry)})
        }
        PinAction {
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
        placeholderText: "Search applications"; color: page.menuColors.text; placeholderTextColor: page.menuColors.secondary
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
            accent: (applications.activeFocus || search.activeFocus) && applications.currentIndex === index ? page.menuColors.accent : page.menuColors.text
            onClicked: { page.launch(modelData); }
            TapHandler {
                acceptedButtons: Qt.RightButton
                onTapped: page.pinEntry(modelData)
            }
        }
    }
}
