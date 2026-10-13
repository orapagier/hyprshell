pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

PanelWindow {
    id: dropdown
    property url wallpaperSource: ""
    property real translucency: 0.06
    property string section: ""
    property string displayedSection: section
    property rect triggerRect: Qt.rect(12, 4, 32, 20)
    property string alignment: "center"
    property color accent: "#b4befe"
    property bool connected: true
    property bool movePointerOnOpen: !connected
    property bool pinned: false
    property string barEdge: "top"
    property rect barRect: Qt.rect(0, 5, width, 32)
    readonly property real barBottom: barRect.y + barRect.height
    readonly property rect inputRect: !connected ? Qt.rect(0, 0, width, height)
        : barEdge === "bottom" ? Qt.rect(0, 0, width, barRect.y)
        : barEdge === "left" ? Qt.rect(barRect.x + barRect.width, 0, width - barRect.x - barRect.width, height)
        : barEdge === "right" ? Qt.rect(0, 0, barRect.x, height)
        : Qt.rect(0, barBottom, width, height - barBottom)
    readonly property bool opened: section.length > 0
    signal hoverChanged(bool inside)
    required property var services
    required property var inbox
    signal closeRequested()
    signal settingsRequested()
    // Keep one surface mapped. Remapping it during hover can synthesize
    // leave/enter events on the bar and repeatedly close and reopen menus.
    visible: true
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    // Keep the bar reachable while this overlay is open, so hovering a
    // neighboring icon can switch menus without closing the current one.
    mask: Region { x: dropdown.inputRect.x; y: dropdown.inputRect.y; width: Math.max(0, dropdown.inputRect.width); height: dropdown.opened ? Math.max(0, dropdown.inputRect.height) : 0 }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "hyprshell"
    WlrLayershell.keyboardFocus: !opened ? WlrKeyboardFocus.None : pinned ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.OnDemand
    MouseArea { anchors.fill: parent; onClicked: dropdown.closeRequested() }
    FocusScope {
        id: focusScope
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: dropdown.closeRequested()
        Keys.onPressed: event => powerShortcuts.handleKey(event)
        PowerShortcuts {
            id: powerShortcuts
            active: dropdown.section === "power" && dropdown.opened && dropdown.pinned
            onTriggered: key => {
                if (popover.pageItem) popover.pageItem.runShortcut(key);
            }
        }
        MenuPopover {
            id: popover
            anchors.fill: parent
            wallpaperSource: dropdown.wallpaperSource
            translucency: dropdown.translucency
            triggerRect: dropdown.triggerRect
            alignment: dropdown.alignment
            connected: dropdown.connected
            edge: dropdown.barEdge
            accent: dropdown.accent
            opened: dropdown.opened
            persistentPage: launcherPage
            persistentSelected: dropdown.displayedSection === "launcher"
            instant: persistentSelected
            cardClickable: dropdown.displayedSection === "settings"
            onCardClicked: {
                dropdown.closeRequested();
                dropdown.settingsRequested();
            }
            title: ({launcher:"Applications",settings:"Hyprshell",calendar:"Calendar",audio:"Audio",wifi:"Wi-Fi",bluetooth:"Bluetooth",notifications:"Notifications",battery:"Battery",power:"Power options"})[dropdown.displayedSection] || ""
            symbol: ({launcher:"",settings:"󰒓",calendar:"󰃭",audio:dropdown.services.audioIcon || "󰕾",wifi:"󰤨",bluetooth:"󰂯",notifications:"󰂚",battery:"󰁹",power:"󰐥"})[dropdown.displayedSection] || ""
            page: ({launcher: launcherPage, settings: settingsPage, calendar: calendarPage, audio: audioPage, wifi: wifiPage, bluetooth: bluetoothPage, notifications: inboxPage, battery: batteryPage, power: powerPage})[dropdown.displayedSection] || null
            onHoverChanged: inside => dropdown.hoverChanged(inside)
        }
    }
    // Delay the warp until the compositor has received the input region.
    Timer {
        id: headerPointer
        interval: 100
        onTriggered: {
            if (!dropdown.opened || !dropdown.movePointerOnOpen) return;
            let monitor = Hyprland.monitorFor(dropdown.screen);
            if (!monitor) return;
            let x = Math.round(monitor.x + popover.bodyX + popover.bodyWidth / 2);
            let y = Math.round(monitor.y + popover.bodyY + 33);
            Hyprland.dispatch("hl.dsp.cursor.move({ x = " + x + ", y = " + y + " })");
        }
    }
    onSectionChanged: {
        headerPointer.stop();
        if (section.length && movePointerOnOpen) headerPointer.restart();
    }
    onOpenedChanged: {
        headerPointer.stop();
        if (opened) {
            focusScope.forceActiveFocus();
            if (movePointerOnOpen) headerPointer.restart();
        }
    }
    onMovePointerOnOpenChanged: {
        headerPointer.stop();
        if (opened && movePointerOnOpen) headerPointer.restart();
    }
    onPinnedChanged: if (opened && pinned) focusScope.forceActiveFocus()
    Shortcut { sequence: "Escape"; enabled: dropdown.opened; onActivated: dropdown.closeRequested() }
    Component { id: launcherPage; LauncherMenu { active: dropdown.opened && dropdown.section === "launcher"; onLaunched: dropdown.closeRequested() } }
    Component { id: settingsPage; SettingsMenu { onOpenRequested: { dropdown.closeRequested(); dropdown.settingsRequested(); } } }
    Component { id: calendarPage; CalendarMenu {} }
    Component { id: audioPage; AudioMenu { services: dropdown.services } }
    Component { id: wifiPage; WifiMenu { services: dropdown.services } }
    Component { id: bluetoothPage; BluetoothMenu { services: dropdown.services } }
    Component { id: batteryPage; BatteryMenu { services: dropdown.services } }
    Component { id: inboxPage; InboxMenu { inbox: dropdown.inbox } }
    Component { id: powerPage; PowerMenu {} }
}
