pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import "WindowSwitcherModel.js" as Switcher

// An overlay for windows that overlap on an auto-floating workspace. Window
// captures run only while it is open, then PreviewCapture releases them again.
PanelWindow {
    id: switcher
    property var applicationService: null
    property var windowRows: applicationService ? applicationService.windowRows : []
    property url wallpaperSource: ""
    property bool opened: false
    property int workspaceId: 0
    property string selectedAddress: ""
    readonly property var workspaceRows: Switcher.workspaceRows(windowRows, workspaceId)
    readonly property int selectedIndex: Switcher.indexForAddress(workspaceRows, selectedAddress)
    readonly property var selectedRow: selectedIndex >= 0 ? workspaceRows[selectedIndex] : null
    readonly property bool hasRows: workspaceRows.length > 0
    signal windowActivated(string address)

    function focusedOutput() {
        let focused = Hyprland.focusedMonitor;
        return Quickshell.screens.find(output => focused && output.name === focused.name) || Quickshell.screens[0] || null;
    }
    function workspaceFor(output) {
        let monitor = output ? Hyprland.monitorFor(output) : Hyprland.focusedMonitor;
        return Number(monitor?.activeWorkspace?.id || 0);
    }
    function ensureSelection() {
        if (!opened) return;
        let next = Switcher.preferredAddress(workspaceRows, selectedAddress, Hyprland.activeToplevel?.address || "");
        if (next !== selectedAddress) selectedAddress = next;
    }
    function open(output) {
        let target = output || focusedOutput();
        if (target) screen = target;
        workspaceId = workspaceFor(target);
        selectedAddress = Switcher.preferredAddress(
            Switcher.workspaceRows(windowRows, workspaceId), "", Hyprland.activeToplevel?.address || "");
        opened = true;
    }
    // Repeating Super+Tab advances while the switcher owns keyboard focus.
    function cycle(step) {
        if (!opened) { open(); return; }
        moveSelection(Number(step) < 0 ? -1 : 1);
    }
    function moveSelection(step) {
        let index = Switcher.nextIndex(workspaceRows.length, selectedIndex, step);
        if (index >= 0) selectedAddress = workspaceRows[index].address;
    }
    function activateAddress(address) {
        let row = workspaceRows.find(candidate => candidate.address === address);
        if (!row) return;
        close();
        if (applicationService && applicationService.activateWindow)
            applicationService.activateWindow(row.address, true);
        else windowActivated(row.address);
    }
    function activateSelected() {
        if (selectedRow) activateAddress(selectedRow.address);
    }
    function close() { opened = false; }

    onWorkspaceRowsChanged: ensureSelection()
    onOpenedChanged: {
        if (!opened) { selectedAddress = ""; return; }
        Hyprland.refreshToplevels();
        Qt.callLater(() => keyCatcher.forceActiveFocus());
    }

    visible: opened
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    exclusiveZone: -1
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "hyprshell-window-switcher"
    WlrLayershell.keyboardFocus: opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    GlassSurface {
        id: glass
        wallpaperSource: switcher.wallpaperSource
        screenWidth: switcher.width
        screenHeight: switcher.height
        region: Qt.rect(stage.x, stage.y, stage.width, stage.height)
        cacheFullWallpaper: true
        translucency: 0.08
    }
    readonly property var menuColors: glass.menuColors

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(glass.base.r, glass.base.g, glass.base.b, 0.78)
    }
    Rectangle {
        anchors.fill: parent
        color: "#000000"
        opacity: 0.28
    }
    MouseArea {
        anchors.fill: parent
        enabled: switcher.opened
        onClicked: switcher.close()
    }

    Item {
        id: header
        z: 1
        anchors { top: parent.top; left: parent.left; right: parent.right; topMargin: 20 }
        height: 66
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: switcher.workspaceId > 0 ? "Windows · Workspace " + switcher.workspaceId : "Windows"
            color: switcher.menuColors.text
            font.family: "Noto Sans"
            font.pixelSize: 21
            font.weight: Font.DemiBold
        }
        Text {
            anchors { top: parent.top; topMargin: 32; horizontalCenter: parent.horizontalCenter }
            text: switcher.hasRows
                ? switcher.workspaceRows.length + (switcher.workspaceRows.length === 1 ? " window" : " windows") + " · choose one to bring it forward"
                : "No open windows on this workspace"
            color: switcher.menuColors.secondary
            font.family: "Noto Sans"
            font.pixelSize: 12
        }
    }

    Item {
        id: footer
        z: 1
        anchors { bottom: parent.bottom; left: parent.left; right: parent.right; bottomMargin: 18 }
        height: 30
        Text {
            anchors.centerIn: parent
            text: switcher.hasRows ? "← ↑ previous   ·   ↓ → next   ·   Enter focus   ·   Esc close"
                                  : "Esc close"
            color: switcher.menuColors.secondary
            font.family: "Noto Sans"
            font.pixelSize: 12
        }
    }

    Item {
        id: stage
        z: 1
        anchors { top: header.bottom; bottom: footer.top; left: parent.left; right: parent.right
            topMargin: 4; bottomMargin: 4; leftMargin: Math.max(18, switcher.width * 0.045); rightMargin: Math.max(18, switcher.width * 0.045) }
        readonly property int count: switcher.workspaceRows.length
        readonly property real usableWidth: Math.max(1, width)
        readonly property real usableHeight: Math.max(1, height)
        readonly property real minimumStepX: Math.min(26, Math.max(6, usableWidth * 0.032))
        readonly property real minimumStepY: Math.min(20, Math.max(5, usableHeight * 0.042))
        readonly property real desiredWidth: Math.min(900, usableWidth * 0.66,
            Math.max(140, usableWidth - minimumStepX * Math.max(0, count - 1)))
        readonly property real desiredHeight: Math.min(desiredWidth * 0.60,
            Math.max(100, usableHeight - minimumStepY * Math.max(0, count - 1)))
        readonly property real cardWidth: Math.min(desiredWidth, desiredHeight * 16 / 9)
        readonly property real cardHeight: Math.min(desiredHeight, cardWidth * 0.60)
        readonly property real stepX: count > 1 ? Math.min(Math.min(64, cardWidth * 0.10),
            Math.max(0, (usableWidth - cardWidth) / (count - 1))) : 0
        readonly property real stepY: count > 1 ? Math.min(Math.min(46, cardHeight * 0.13),
            Math.max(0, (usableHeight - cardHeight) / (count - 1))) : 0
        readonly property real stackWidth: cardWidth + Math.max(0, count - 1) * stepX
        readonly property real stackHeight: cardHeight + Math.max(0, count - 1) * stepY
        readonly property real originX: Math.max(0, (width - stackWidth) / 2)
        readonly property real originY: Math.max(0, (height - stackHeight) / 2)

        Repeater {
            model: switcher.workspaceRows
            delegate: Item {
                id: card
                required property var modelData
                required property int index
                readonly property bool selected: switcher.selectedAddress === modelData.address
                objectName: "windowSwitcherCard-" + modelData.address
                x: stage.originX + index * stage.stepX
                y: stage.originY + index * stage.stepY
                width: stage.cardWidth
                height: stage.cardHeight
                z: selected ? stage.count + 2 : index + 1
                scale: selected ? 1 : 0.975
                Behavior on scale { NumberAnimation { duration: 120 } }

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: -6
                    radius: 22
                    color: "#52000000"
                    z: -1
                }
                Rectangle {
                    id: cardSurface
                    anchors.fill: parent
                    radius: 17
                    clip: true
                    color: switcher.menuColors.background
                    border.width: card.selected ? 2 : 1
                    border.color: card.selected ? switcher.menuColors.accent
                                                  : Qt.rgba(switcher.menuColors.text.r, switcher.menuColors.text.g, switcher.menuColors.text.b, 0.24)
                    Behavior on border.color { ColorAnimation { duration: 120 } }
                    PreviewCapture {
                        id: capture
                        anchors.fill: parent
                        anchors.margins: cardSurface.border.width
                        source: card.modelData.handle?.wayland || null
                        active: switcher.opened
                    }
                    Rectangle {
                        anchors.fill: parent
                        color: Qt.rgba(switcher.menuColors.background.r, switcher.menuColors.background.g, switcher.menuColors.background.b, 0.72)
                        visible: !capture.hasContent
                    }
                    Text {
                        anchors.centerIn: parent
                        width: Math.max(0, parent.width - 48)
                        visible: !capture.hasContent
                        text: "Preview unavailable"
                        color: switcher.menuColors.secondary
                        horizontalAlignment: Text.AlignHCenter
                        font.family: "Noto Sans"
                        font.pixelSize: 13
                    }
                    Rectangle {
                        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                        height: 52
                        color: Qt.rgba(switcher.menuColors.background.r, switcher.menuColors.background.g, switcher.menuColors.background.b, 0.90)
                    }
                    Text {
                        id: title
                        anchors { left: parent.left; right: numberBadge.left; bottom: parent.bottom
                            leftMargin: 15; rightMargin: 10; bottomMargin: 25 }
                        text: card.modelData.title || "Untitled window"
                        color: switcher.menuColors.text
                        elide: Text.ElideRight
                        font.family: "Noto Sans"
                        font.pixelSize: 13
                        font.weight: Font.Medium
                    }
                    Text {
                        anchors { left: title.left; right: title.right; bottom: parent.bottom; bottomMargin: 8 }
                        text: card.modelData.identity || card.modelData.appId || "Window"
                        color: switcher.menuColors.secondary
                        elide: Text.ElideRight
                        font.family: "Noto Sans"
                        font.pixelSize: 11
                    }
                    Rectangle {
                        id: numberBadge
                        anchors { right: parent.right; bottom: parent.bottom; rightMargin: 12; bottomMargin: 14 }
                        width: 25; height: 25; radius: 8
                        color: card.selected ? switcher.menuColors.accent
                                             : Qt.rgba(switcher.menuColors.text.r, switcher.menuColors.text.g, switcher.menuColors.text.b, 0.12)
                        Text {
                            anchors.centerIn: parent
                            text: String(card.index + 1)
                            color: card.selected ? switcher.menuColors.background : switcher.menuColors.text
                            font.family: "Noto Sans"
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                        }
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: switcher.selectedAddress = card.modelData.address
                    onClicked: switcher.activateAddress(card.modelData.address)
                }
            }
        }
        Text {
            anchors.centerIn: parent
            visible: !switcher.hasRows
            text: "Open a window here, then press Super + Tab to select it."
            color: switcher.menuColors.text
            font.family: "Noto Sans"
            font.pixelSize: 14
        }
    }

    FocusScope {
        id: keyCatcher
        anchors.fill: parent
        focus: switcher.opened
        Keys.onPressed: event => {
            if (!switcher.opened) return;
            if (event.key === Qt.Key_Left || event.key === Qt.Key_Up) switcher.moveSelection(-1);
            else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down) switcher.moveSelection(1);
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) switcher.activateSelected();
            else if (event.key === Qt.Key_Escape) switcher.close();
            else if (event.key === Qt.Key_Tab && (event.modifiers & Qt.MetaModifier))
                switcher.moveSelection((event.modifiers & Qt.ShiftModifier) ? -1 : 1);
            else return;
            event.accepted = true;
        }
    }
}
