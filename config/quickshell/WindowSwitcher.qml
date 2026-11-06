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
    function closeSelected() {
        if (!selectedRow || !applicationService || !applicationService.windowAction) return;
        if (applicationService.windowAction("close", selectedRow.address)) {
            // Keep the filmstrip open so another window can be selected after
            // Hyprland publishes the close event.
            selectedAddress = "";
            Hyprland.refreshToplevels();
        }
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
            text: switcher.hasRows ? "← ↑ previous   ·   ↓ → next   ·   Enter focus   ·   Super + Q close window   ·   Esc close"
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
        readonly property real cardHeight: Math.min(218, Math.max(124, usableHeight * 0.50))
        readonly property real cardWidth: Math.round(cardHeight * 1.58)
        readonly property real frameGap: Math.max(8, Math.min(14, usableWidth * 0.012))
        readonly property real frameInset: 24
        readonly property real previewInset: 3
        readonly property int visibleFrames: Math.min(3, count)
        readonly property real filmWidth: count > 0 ? Math.min(usableWidth,
            visibleFrames * cardWidth + Math.max(0, visibleFrames - 1) * frameGap + frameInset * 2) : 0

        Item {
            id: film
            anchors.fill: parent
            readonly property real railX: Math.max(0, (width - stage.filmWidth) / 2)
            readonly property real railY: Math.round((height - stage.cardHeight - 32) / 2)

                Rectangle {
                    id: filmRail
                    visible: switcher.hasRows
                    x: film.railX
                    y: film.railY
                    width: stage.filmWidth
                    height: stage.cardHeight + 32
                    radius: 10
                    color: Qt.rgba(0.015, 0.018, 0.022, 0.90)
                    border.width: 1
                    border.color: Qt.rgba(switcher.menuColors.text.r, switcher.menuColors.text.g, switcher.menuColors.text.b, 0.28)
                }
                Repeater {
                    model: stage.visibleFrames * 4
                    delegate: Rectangle {
                        required property int index
                        readonly property int frame: index % stage.visibleFrames
                        readonly property int railSlot: Math.floor(index / stage.visibleFrames)
                        readonly property bool lowerRail: railSlot >= 2
                        x: filmRail.x + 10 + frame * (stage.cardWidth + stage.frameGap)
                           + ((railSlot % 2) ? stage.cardWidth - 20 : 0)
                        y: lowerRail ? filmRail.y + filmRail.height - 10 : filmRail.y + 4
                        width: 10
                        height: 6
                        radius: 2
                        color: Qt.rgba(switcher.menuColors.background.r, switcher.menuColors.background.g, switcher.menuColors.background.b, 0.76)
                    }
                }

                Item {
                    id: frames
                    x: filmRail.x
                    y: Math.round((film.height - stage.cardHeight) / 2)
                    width: filmRail.width
                    height: stage.cardHeight
                    clip: true

                    Repeater {
                        model: switcher.workspaceRows
                        delegate: Item {
                            id: card
                            required property var modelData
                            required property int index
                            readonly property bool selected: switcher.selectedAddress === modelData.address
                            readonly property int carouselIndex: stage.count > 0
                                ? (index - switcher.selectedIndex + stage.count) % stage.count : index
                            readonly property real slotOffset: carouselIndex === 0 ? 0
                                : (carouselIndex % 2 ? 1 : -1) * Math.ceil(carouselIndex / 2)
                            objectName: "windowSwitcherCard-" + modelData.address
                            x: Math.round((frames.width - width) / 2
                                + slotOffset * (width + stage.frameGap))
                            width: stage.cardWidth
                            height: stage.cardHeight
                            z: selected ? stage.count + 2 : index + 1
                            Behavior on x { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: -4
                                radius: 8
                                color: "#52000000"
                                z: -1
                            }
                            Rectangle {
                                id: cardSurface
                                anchors.fill: parent
                                radius: 5
                                clip: true
                                color: switcher.menuColors.background
                                border.width: card.selected ? 2 : 1
                                border.color: card.selected ? switcher.menuColors.accent
                                                              : Qt.rgba(switcher.menuColors.text.r, switcher.menuColors.text.g, switcher.menuColors.text.b, 0.24)
                                Behavior on border.color { ColorAnimation { duration: 120 } }
                                PreviewCapture {
                                    id: capture
                                    anchors.fill: parent
                                    anchors.margins: cardSurface.border.width + stage.previewInset
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
                                    width: Math.max(0, parent.width - 32)
                                    visible: !capture.hasContent
                                    text: "Preview unavailable"
                                    color: switcher.menuColors.secondary
                                    horizontalAlignment: Text.AlignHCenter
                                    font.family: "Noto Sans"
                                    font.pixelSize: 12
                                }
                                Rectangle {
                                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                                    height: 42
                                    color: Qt.rgba(switcher.menuColors.background.r, switcher.menuColors.background.g, switcher.menuColors.background.b, 0.90)
                                }
                                Text {
                                    id: title
                                    anchors { left: parent.left; right: numberBadge.left; bottom: parent.bottom
                                        leftMargin: 11; rightMargin: 7; bottomMargin: 21 }
                                    text: card.modelData.title || "Untitled window"
                                    color: switcher.menuColors.text
                                    elide: Text.ElideRight
                                    font.family: "Noto Sans"
                                    font.pixelSize: 12
                                    font.weight: Font.Medium
                                }
                                Text {
                                    anchors { left: title.left; right: title.right; bottom: parent.bottom; bottomMargin: 6 }
                                    text: card.modelData.identity || card.modelData.appId || "Window"
                                    color: switcher.menuColors.secondary
                                    elide: Text.ElideRight
                                    font.family: "Noto Sans"
                                    font.pixelSize: 10
                                }
                                Rectangle {
                                    id: numberBadge
                                    anchors { right: parent.right; bottom: parent.bottom; rightMargin: 8; bottomMargin: 10 }
                                    width: 22; height: 22; radius: 5
                                    color: card.selected ? switcher.menuColors.accent
                                                         : Qt.rgba(switcher.menuColors.text.r, switcher.menuColors.text.g, switcher.menuColors.text.b, 0.12)
                                    Text {
                                        anchors.centerIn: parent
                                        text: String(card.index + 1)
                                        color: card.selected ? switcher.menuColors.background : switcher.menuColors.text
                                        font.family: "Noto Sans"
                                        font.pixelSize: 10
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
            else if (event.key === Qt.Key_Q && (event.modifiers & Qt.MetaModifier)) switcher.closeSelected();
            else if (event.key === Qt.Key_Tab && (event.modifiers & Qt.MetaModifier))
                switcher.moveSelection((event.modifiers & Qt.ShiftModifier) ? -1 : 1);
            else return;
            event.accepted = true;
        }
    }
}
