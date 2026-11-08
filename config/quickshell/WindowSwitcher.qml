pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import "style" as Style
import "WindowSwitcherModel.js" as Switcher

// An overlay for windows that overlap on an auto-floating workspace. Window
// captures run only while it is open, then PreviewCapture releases them again.
PanelWindow {
    id: switcher
    property var applicationService: null
    property var windowRows: applicationService ? applicationService.windowRows : []
    property url wallpaperSource: ""
    property bool opened: false
    property real reveal: 0
    property int workspaceId: 0
    property string selectedAddress: ""
    // Unbounded card index under the fixed highlight slot. Rotating the cards
    // right decrements it, so the previous card slides into the highlight.
    property int rotationAnchor: 0
    readonly property var workspaceRows: Switcher.workspaceRows(windowRows, workspaceId)
    readonly property int selectedIndex: Switcher.indexForAddress(workspaceRows, selectedAddress)
    readonly property var selectedRow: selectedIndex >= 0 ? workspaceRows[selectedIndex] : null
    Behavior on reveal {
        enabled: !Style.Theme.reducedMotion
        SpringAnimation { spring: 4.0; damping: 0.38; epsilon: 0.001 }
    }
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
    function normalizedAnchorIndex() {
        return Switcher.wrapIndex(workspaceRows.length, rotationAnchor);
    }
    function syncSelectionFromAnchor() {
        let index = normalizedAnchorIndex();
        if (index < 0) return;
        let next = workspaceRows[index].address;
        if (next !== selectedAddress) selectedAddress = next;
    }
    function ensureSelection() {
        if (!opened) return;
        let next = Switcher.preferredAddress(workspaceRows, selectedAddress, Hyprland.activeToplevel?.address || "");
        let index = Switcher.indexForAddress(workspaceRows, next);
        if (next !== selectedAddress) {
            if (index >= 0)
                rotationAnchor = Switcher.nearestAnchor(workspaceRows.length, rotationAnchor, index);
            selectedAddress = next;
        } else if (index >= 0 && normalizedAnchorIndex() !== index) {
            rotationAnchor = Switcher.nearestAnchor(workspaceRows.length, rotationAnchor, index);
        }
    }
    function open(output) {
        let target = output || focusedOutput();
        if (target) screen = target;
        workspaceId = workspaceFor(target);
        let rows = Switcher.workspaceRows(windowRows, workspaceId);
        let next = Switcher.preferredAddress(rows, "", Hyprland.activeToplevel?.address || "");
        let index = Switcher.indexForAddress(rows, next);
        rotationAnchor = index >= 0 ? index : 0;
        selectedAddress = next;
        opened = true;
    }
    // Repeating Super+Tab advances while the switcher owns keyboard focus.
    function cycle(step) {
        if (!opened) { open(); return; }
        moveSelection(Number(step) < 0 ? -1 : 1);
    }
    function moveSelection(step) {
        if (workspaceRows.length <= 1) return;
        rotationAnchor = Switcher.anchorAfterStep(rotationAnchor, step);
        syncSelectionFromAnchor();
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
    onSelectedAddressChanged: {
        if (!opened) return;
        let index = Switcher.indexForAddress(workspaceRows, selectedAddress);
        if (index < 0 || normalizedAnchorIndex() === index) return;
        // Hover or an external selection change: rotate the shortest way to
        // bring that card under the fixed highlight.
        rotationAnchor = Switcher.nearestAnchor(workspaceRows.length, rotationAnchor, index);
    }
    onOpenedChanged: {
        if (!opened) { selectedAddress = ""; reveal = 0; return; }
        reveal = 1;
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
                : "No open windows on this workspace — press Super+Tab to try another"
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
            text: switcher.hasRows ? "← ↑ rotate left   ·   ↓ → rotate right   ·   Enter focus   ·   Super + Q close window   ·   Esc close"
                                  : "Esc close · Super + Tab cycle workspaces"
            color: switcher.menuColors.secondary
            font.family: "Noto Sans"
            font.pixelSize: 12
        }
    }

    Item {
        id: stage
        z: 1
        opacity: Math.min(1, switcher.reveal * 1.6)
        anchors { top: header.bottom; bottom: footer.top; left: parent.left; right: parent.right
            topMargin: 4; bottomMargin: 4; leftMargin: Math.max(18, switcher.width * 0.045); rightMargin: Math.max(18, switcher.width * 0.045) }
        transform: Scale { origin.x: width / 2; origin.y: height / 2; xScale: 0.965 + 0.035 * switcher.reveal; yScale: 0.965 + 0.035 * switcher.reveal }
        readonly property int count: switcher.workspaceRows.length
        readonly property int maxVisibleCards: 5
        readonly property real usableWidth: Math.max(1, width)
        readonly property real usableHeight: Math.max(1, height)
        readonly property real cardHeight: Math.min(218, Math.max(124, usableHeight * 0.50))
        readonly property real cardWidth: Math.round(cardHeight * 1.58)
        readonly property real frameGap: Math.max(8, Math.min(14, usableWidth * 0.012))
        readonly property real frameInset: 24
        readonly property real previewInset: 3
        readonly property real cardClipMarginX: 14
        readonly property real cardClipMarginY: 24
        readonly property bool motionEnabled: !Style.Theme.reducedMotion
        readonly property real focusScale: 1.07
        readonly property real idleScale: 0.955
        readonly property real liquidStretch: 0.05
        readonly property int visibleCount: Math.min(count, maxVisibleCards)
        // Frame grows to fit exactly the visible cards with margins on both sides
        readonly property real filmWidth: visibleCount * cardWidth + Math.max(0, visibleCount - 1) * frameGap + frameInset * 2
        // Highlight position: even counts -> right of center (index = count/2), odd -> center (index = floor(count/2))
        readonly property int highlightIndex: Math.floor(visibleCount / 2)

        Item {
            id: film
            anchors.fill: parent
            readonly property real railX: Math.max(0, (width - stage.filmWidth) / 2)
            readonly property real railY: Math.round((height - stage.cardHeight - 32) / 2)

                Rectangle {
                    id: filmRail
                    visible: true
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
                    model: stage.visibleCount * 4
                    delegate: Rectangle {
                        required property int index
                        readonly property int frame: index % stage.visibleCount
                        readonly property int railSlot: Math.floor(index / stage.visibleCount)
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
                    id: cardViewport
                    x: filmRail.x + stage.frameInset - stage.cardClipMarginX
                    y: Math.round((film.height - stage.cardHeight) / 2) - stage.cardClipMarginY
                    width: stage.visibleCount * stage.cardWidth + Math.max(0, stage.visibleCount - 1) * stage.frameGap + stage.cardClipMarginX * 2
                    height: stage.cardHeight + stage.cardClipMarginY * 2
                    clip: true

                    Item {
                        id: frames
                        x: stage.cardClipMarginX
                        y: stage.cardClipMarginY
                        width: stage.visibleCount * stage.cardWidth + Math.max(0, stage.visibleCount - 1) * stage.frameGap
                        height: stage.cardHeight

                        Repeater {
                            // Three duplicate copies of every card. carouselSlot()
                            // keeps them inside a fixed window, so a copy only jumps
                            // between the edges while it is offscreen and an
                            // unbounded anchor can spin without ever running out.
                            model: stage.count * 3
                            delegate: Item {
                                id: card
                                required property int index
                                readonly property int rowIndex: index % Math.max(1, stage.count)
                                readonly property int copy: Math.floor(index / Math.max(1, stage.count))
                                readonly property var rowData: rowIndex < switcher.workspaceRows.length ? switcher.workspaceRows[rowIndex] : null
                                readonly property int slotPosition: Switcher.carouselSlot(stage.count, stage.visibleCount, switcher.rotationAnchor, rowIndex, copy)
                                readonly property bool activeSlot: slotPosition >= -1 && slotPosition <= stage.visibleCount
                                readonly property bool shown: slotPosition >= 0 && slotPosition < stage.visibleCount
                                readonly property bool selected: rowData && shown && switcher.selectedAddress === rowData.address
                                property int knownSlot: 0
                                property bool snapping: false
                                property real visualSlot: 0
                                property bool initialized: false
                                property real zoom: selected ? stage.focusScale : stage.idleScale
                                property real travel: 0
                                objectName: rowData ? "windowSwitcherCard-" + rowData.address + "-copy" + copy : "windowSwitcherCard-empty"
                                x: (initialized ? visualSlot : slotPosition) * (stage.cardWidth + stage.frameGap)
                                width: stage.cardWidth
                                height: stage.cardHeight
                                scale: zoom
                                z: selected ? stage.count * 3 + 2 : (shown ? slotPosition + 2 : 1)
                                visible: activeSlot
                                opacity: shown ? 1.0 : 0.0
                                transform: Scale {
                                    origin.x: card.width / 2
                                    origin.y: card.height / 2
                                    xScale: 1 + stage.liquidStretch * Math.abs(card.travel)
                                    yScale: 1 - stage.liquidStretch * 0.6 * Math.abs(card.travel)
                                }
                                // scale property gets a matching liquid overshoot.
                                Behavior on scale {
                                    enabled: stage.motionEnabled && !card.snapping
                                    NumberAnimation { duration: Style.Theme.duration(card, 300); easing.type: Easing.OutBack; easing.overshoot: 0.45 }
                                }
                                Behavior on visualSlot {
                                    enabled: !card.snapping
                                    NumberAnimation { duration: 260; easing.type: Easing.OutCubic }
                                }
                                Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                                NumberAnimation {
                                    id: travelAnimation
                                    target: card
                                    property: "travel"
                                    duration: Style.Theme.duration(card, 320)
                                    easing.type: Easing.OutCubic
                                }
                                onSlotPositionChanged: {
                                    let delta = Math.abs(slotPosition - knownSlot);
                                    if (delta > stage.count * 1.5) {
                                        // Wrapped to the other edge: snap while the
                                        // copy is outside the visible strip.
                                        card.snapping = true;
                                        knownSlot = slotPosition;
                                        card.visualSlot = slotPosition;
                                        card.travel = 0
                                        Qt.callLater(() => { card.snapping = false; });
                                    } else if (delta > 0) {
                                        knownSlot = slotPosition;
                                        card.visualSlot = slotPosition;
                                        if (stage.motionEnabled) {
                                            card.travel = 1
                                            travelAnimation.from = 1
                                            travelAnimation.to = 0
                                            travelAnimation.restart()
                                        }
                                    } else {
                                        knownSlot = slotPosition;
                                    }
                                }
                                Component.onCompleted: {
                                    knownSlot = slotPosition;
                                    visualSlot = slotPosition;
                                    initialized = true;
                                }

                            Rectangle {
                                id: cardShadow
                                x: -7
                                y: card.selected ? -1 : 2
                                width: parent.width + 14
                                height: parent.height + (card.selected ? 18 : 10)
                                radius: 10
                                color: "#52000000"
                                z: -2
                                opacity: card.selected ? 0.95 : 0.55
                                Behavior on y { enabled: stage.motionEnabled; NumberAnimation { duration: Style.Theme.duration(parent, 260); easing.type: Easing.OutCubic } }
                                Behavior on height { enabled: stage.motionEnabled; NumberAnimation { duration: Style.Theme.duration(parent, 260); easing.type: Easing.OutCubic } }
                                Behavior on opacity { enabled: stage.motionEnabled; NumberAnimation { duration: Style.Theme.duration(parent, 200); easing.type: Easing.OutCubic } }
                            }
                            Rectangle {
                                id: accentRim
                                anchors.fill: parent
                                anchors.margins: -3
                                radius: 7
                                color: "transparent"
                                border.width: card.selected ? 3 : 0
                                border.color: switcher.menuColors.accent
                                opacity: card.selected ? 0.75 : 0.0
                                z: -1
                                Behavior on opacity { enabled: stage.motionEnabled; NumberAnimation { duration: Style.Theme.duration(parent, 220); easing.type: Easing.OutCubic } }
                                Behavior on border.width { enabled: stage.motionEnabled; NumberAnimation { duration: Style.Theme.duration(parent, 180); easing.type: Easing.OutCubic } }
                            }
                            Rectangle {
                                id: cardSurface
                                anchors.fill: parent
                                radius: 5
                                clip: true
                                color: switcher.menuColors.background
                                border.width: selected ? 2 : 1
                                border.color: selected ? switcher.menuColors.accent
                                                           : Qt.rgba(switcher.menuColors.text.r, switcher.menuColors.text.g, switcher.menuColors.text.b, 0.24)
                                Behavior on border.color { ColorAnimation { duration: 120 } }
                                PreviewCapture {
                                    id: capture
                                    anchors.fill: parent
                                    anchors.margins: cardSurface.border.width + stage.previewInset
                                    source: rowData.handle?.wayland || null
                                    active: switcher.opened && rowData && activeSlot
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
                                    anchors.fill: parent
                                    color: Qt.rgba(switcher.menuColors.accent.r, switcher.menuColors.accent.g,
                                                 switcher.menuColors.accent.b, 0.10)
                                    opacity: card.selected ? 1.0 : 0.0
                                    Behavior on opacity { enabled: stage.motionEnabled; NumberAnimation { duration: Style.Theme.duration(parent, 180); easing.type: Easing.OutCubic } }
                                    visible: opacity > 0
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
                                    text: rowData ? (rowData.title || "Untitled window") : ""
                                    color: switcher.menuColors.text
                                    elide: Text.ElideRight
                                    font.family: "Noto Sans"
                                    font.pixelSize: 12
                                    font.weight: Font.Medium
                                }
                                Text {
                                    anchors { left: title.left; right: title.right; bottom: parent.bottom; bottomMargin: 6 }
                                    text: rowData ? (rowData.identity || rowData.appId || "Window") : ""
                                    color: switcher.menuColors.secondary
                                    elide: Text.ElideRight
                                    font.family: "Noto Sans"
                                    font.pixelSize: 10
                                }
                                Rectangle {
                                    id: numberBadge
                                    anchors { right: parent.right; bottom: parent.bottom; rightMargin: 8; bottomMargin: 10 }
                                    width: 22; height: 22; radius: 5
                                    color: selected ? switcher.menuColors.accent
                                                             : Qt.rgba(switcher.menuColors.text.r, switcher.menuColors.text.g, switcher.menuColors.text.b, 0.12)
                                    Text {
                                        anchors.centerIn: parent
                                        text: rowData ? String(rowIndex + 1) : ""
                                        color: selected ? switcher.menuColors.background : switcher.menuColors.text
                                        font.family: "Noto Sans"
                                        font.pixelSize: 10
                                        font.weight: Font.DemiBold
                                    }
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                enabled: shown
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: {
                                    if (rowData) switcher.selectedAddress = rowData.address;
                                }
                                onClicked: {
                                    if (rowData) switcher.activateAddress(rowData.address);
                                }
                            }
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