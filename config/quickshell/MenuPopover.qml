pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Controls.Basic

Item {
    id: popover
    property url wallpaperSource: ""
    property real translucency: 0.06
    GlassSurface {
        id: glass
        wallpaperSource: popover.wallpaperSource
        screenWidth: popover.width; screenHeight: popover.height
        region: Qt.rect(popover.bodyX, popover.bodyY, popover.bodyWidth, popover.bodyHeight)
        accent: popover.accent; translucency: popover.translucency
    }
    property rect triggerRect: Qt.rect(12, 4, 32, 20)
    property string alignment: "center"
    property string edge: "top"
    readonly property bool vertical: edge === "left" || edge === "right"
    property color accent: "#b4befe"
    property string title: ""
    property string symbol: ""
    property Component page: null
    property Component persistentPage: null
    property bool persistentSelected: false
    property bool instant: false
    readonly property var pageItem: persistentSelected ? persistentLoader.item : pageLoader.item
    property bool opened: false
    property bool cardClickable: false
    property bool connected: true
    readonly property bool rendering: opened || surface.opacity > 0
    signal hoverChanged(bool inside)
    signal cardClicked()
    readonly property real bodyWidth: Math.max(0, Math.min(300, connected && vertical
        ? (edge === "left" ? width - triggerRect.x - triggerRect.width - 45 : triggerRect.x - 45)
        : width - 24))
    function clamp(value, low, high) { return Math.max(low, Math.min(Math.max(low, high), value)); }
    readonly property real bodyX: !connected || !vertical
        ? (alignment === "left" ? 12 : alignment === "right" ? width - bodyWidth - 12 : (width - bodyWidth) / 2)
        : edge === "left" ? clamp(triggerRect.x + triggerRect.width + 33, 12, width - bodyWidth - 12)
        : clamp(triggerRect.x - 33 - bodyWidth, 12, width - bodyWidth - 12)
    readonly property real availableHeight: !connected ? height - 64 : vertical ? height - 24
        : edge === "bottom" ? triggerRect.y - 49 : height - triggerRect.y - triggerRect.height - 49
    readonly property real bodyHeight: Math.max(0, Math.min(availableHeight, contents.implicitHeight + 36))
    readonly property real bodyY: !connected ? Math.max(48, triggerRect.y + triggerRect.height + 12)
        : edge === "top" ? triggerRect.y + triggerRect.height + 33
        : edge === "bottom" ? triggerRect.y - 33 - bodyHeight
        : clamp(triggerRect.y + triggerRect.height / 2 - bodyHeight / 2, 12, height - bodyHeight - 12)
    readonly property real bodyRight: bodyX + bodyWidth
    readonly property real bodyBottom: bodyY + bodyHeight
    // Draw the existing funnel in coordinates that always point inward, while
    // the card contents stay upright on every edge.
    readonly property real shapeX: vertical ? bodyY : bodyX
    readonly property real shapeY: edge === "bottom" ? height - bodyBottom : edge === "right" ? width - bodyRight : vertical ? bodyX : bodyY
    readonly property real shapeWidth: vertical ? bodyHeight : bodyWidth
    readonly property real shapeHeight: vertical ? bodyWidth : bodyHeight
    readonly property real neckY: edge === "bottom" ? height - triggerRect.y - 1
        : edge === "right" ? width - triggerRect.x - 1
        : edge === "left" ? triggerRect.x + triggerRect.width - 1 : triggerRect.y + triggerRect.height - 1
    readonly property real tipX: vertical ? triggerRect.y + triggerRect.height / 2 : triggerRect.x + triggerRect.width / 2
    readonly property real neckHalfWidth: 0.75
    readonly property real attachmentHalfWidth: 8
    readonly property real waistY: neckY + 7
    readonly property real shoulder: clamp(tipX, shapeX + 52, shapeX + shapeWidth - 52)
    readonly property bool pointerInside: opened && tracking.hovered && containsPointer(tracking.point.position)

    function containsPointer(point) {
        if (point.y >= bodyY && point.y <= bodyBottom && point.x >= bodyX && point.x <= bodyRight)
            return true;
        if (!connected) return false;
        // Keep a forgiving bridge between the trigger and the inward card.
        if (vertical) {
            let triggerEdge = edge === "left" ? triggerRect.x + triggerRect.width : triggerRect.x;
            let cardEdge = edge === "left" ? bodyX : bodyRight;
            return point.x >= Math.min(triggerEdge, cardEdge) - 4 && point.x <= Math.max(triggerEdge, cardEdge) + 4
                && point.y >= Math.min(triggerRect.y - 12, bodyY) && point.y <= Math.max(triggerRect.y + triggerRect.height + 12, bodyBottom);
        }
        let triggerEdge = edge === "bottom" ? triggerRect.y : triggerRect.y + triggerRect.height;
        let cardEdge = edge === "bottom" ? bodyBottom : bodyY;
        return point.y >= Math.min(triggerEdge, cardEdge) - 4 && point.y <= Math.max(triggerEdge, cardEdge) + 4
            && point.x >= Math.min(triggerRect.x - 12, bodyX) && point.x <= Math.max(triggerRect.x + triggerRect.width + 12, bodyRight);
    }
    onPointerInsideChanged: hoverChanged(pointerInside)
    HoverHandler { id: tracking }

    Item {
        id: surface
        anchors.fill: parent
        opacity: 0
        transform: Translate { id: arrival; y: -8 }
        states: State {
            name: "open"; when: popover.opened
            PropertyChanges { surface.opacity: 1; arrival.y: 0 }
        }
        transitions: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; duration: popover.instant ? 0 : 140; easing.type: Easing.OutCubic }
                NumberAnimation { property: "y"; duration: popover.instant ? 0 : 220; easing.type: Easing.OutCubic }
            }
        }
        Rectangle {
            x: popover.bodyX + 3; y: popover.bodyY + 7
            width: popover.bodyWidth; height: popover.bodyHeight
            radius: 20; color: "#28000000"
        }
        Shape {
            visible: popover.connected
            objectName: "menuFunnel"
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            transform: Matrix4x4 {
                matrix: popover.edge === "bottom" ? Qt.matrix4x4(1,0,0,0, 0,-1,0,popover.height, 0,0,1,0, 0,0,0,1)
                    : popover.edge === "left" ? Qt.matrix4x4(0,1,0,0, 1,0,0,0, 0,0,1,0, 0,0,0,1)
                    : popover.edge === "right" ? Qt.matrix4x4(0,-1,0,popover.width, 1,0,0,0, 0,0,1,0, 0,0,0,1)
                    : Qt.matrix4x4(1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1)
            }
            ShapePath {
                strokeWidth: 1
                strokeColor: glass.rimColor
                fillGradient: LinearGradient {
                    x1: 0; y1: popover.neckY; x2: 0; y2: (popover.shapeY + popover.shapeHeight)
                    GradientStop { position: 0; color: glass.rimColor }
                    GradientStop { position: 0.23; color: glass.topColor }
                    GradientStop { position: 1; color: glass.bottomColor }
                }
                startX: popover.tipX - popover.attachmentHalfWidth; startY: popover.neckY
                PathLine { x: popover.tipX + popover.attachmentHalfWidth; y: popover.neckY }
                PathCubic {
                    control1X: popover.tipX + popover.neckHalfWidth; control1Y: popover.neckY + 1
                    control2X: popover.tipX + popover.neckHalfWidth; control2Y: popover.waistY - 3
                    x: popover.tipX + popover.neckHalfWidth; y: popover.waistY
                }
                PathCubic {
                    control1X: popover.tipX + popover.neckHalfWidth; control1Y: popover.waistY + 12
                    control2X: popover.shoulder + 12; control2Y: popover.shapeY
                    x: popover.shoulder + 36; y: popover.shapeY
                }
                PathLine { x: (popover.shapeX + popover.shapeWidth) - 18; y: popover.shapeY }
                PathQuad { controlX: (popover.shapeX + popover.shapeWidth); controlY: popover.shapeY; x: (popover.shapeX + popover.shapeWidth); y: popover.shapeY + 18 }
                PathLine { x: (popover.shapeX + popover.shapeWidth); y: (popover.shapeY + popover.shapeHeight) - 18 }
                PathQuad { controlX: (popover.shapeX + popover.shapeWidth); controlY: (popover.shapeY + popover.shapeHeight); x: (popover.shapeX + popover.shapeWidth) - 18; y: (popover.shapeY + popover.shapeHeight) }
                PathLine { x: popover.shapeX + 18; y: (popover.shapeY + popover.shapeHeight) }
                PathQuad { controlX: popover.shapeX; controlY: (popover.shapeY + popover.shapeHeight); x: popover.shapeX; y: (popover.shapeY + popover.shapeHeight) - 18 }
                PathLine { x: popover.shapeX; y: popover.shapeY + 18 }
                PathQuad { controlX: popover.shapeX; controlY: popover.shapeY; x: popover.shapeX + 18; y: popover.shapeY }
                PathLine { x: popover.shoulder - 36; y: popover.shapeY }
                PathCubic {
                    control1X: popover.shoulder - 12; control1Y: popover.shapeY
                    control2X: popover.tipX - popover.neckHalfWidth; control2Y: popover.waistY + 12
                    x: popover.tipX - popover.neckHalfWidth; y: popover.waistY
                }
                PathCubic {
                    control1X: popover.tipX - popover.neckHalfWidth; control1Y: popover.waistY - 3
                    control2X: popover.tipX - popover.neckHalfWidth; control2Y: popover.neckY + 1
                    x: popover.tipX - popover.attachmentHalfWidth; y: popover.neckY
                }
            }
        }
        Rectangle {
            visible: !popover.connected
            objectName: "detachedMenuCard"
            x: popover.bodyX; y: popover.bodyY
            width: popover.bodyWidth; height: popover.bodyHeight
            radius: 20
            border.width: 1
            border.color: glass.rimColor
            gradient: Gradient {
                GradientStop { position: 0; color: glass.topColor }
                GradientStop { position: 1; color: glass.bottomColor }
            }
            Rectangle {
                x: 20; y: 1; width: parent.width - 40; height: 1
                color: Qt.rgba(popover.accent.r, popover.accent.g, popover.accent.b, 0.28)
            }
        }
        MouseArea {
            x: popover.bodyX; y: popover.bodyY
            width: popover.bodyWidth; height: popover.bodyHeight
            enabled: popover.opened
            cursorShape: popover.cardClickable ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (popover.cardClickable) popover.cardClicked()
        }
        Flickable {
            id: bodyScroll
            objectName: "menuBodyScroll"
            x: popover.bodyX + 18; y: popover.bodyY + 18
            width: Math.max(0, popover.bodyWidth - 36)
            height: Math.max(0, popover.bodyHeight - 36)
            contentWidth: width
            contentHeight: contents.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick
            interactive: contentHeight > height
            acceptedButtons: popover.cardClickable ? Qt.NoButton : Qt.LeftButton
            activeFocusOnTab: interactive
            Keys.onDownPressed: contentY = Math.min(contentHeight - height, contentY + 32)
            Keys.onUpPressed: contentY = Math.max(0, contentY - 32)
            ScrollBar.vertical: ScrollBar {}
            Connections {
                target: popover.Window.window
                function onActiveFocusItemChanged() {
                    let focused = popover.Window.window.activeFocusItem;
                    let ancestor = focused;
                    while (ancestor && ancestor !== contents) ancestor = ancestor.parent;
                    if (!ancestor) return;
                    let point = focused.mapToItem(contents, 0, 0);
                    if (point.y < bodyScroll.contentY) bodyScroll.contentY = Math.max(0, point.y);
                    else if (point.y + focused.height > bodyScroll.contentY + bodyScroll.height)
                        bodyScroll.contentY = Math.max(0, Math.min(bodyScroll.contentHeight - bodyScroll.height, point.y + focused.height - bodyScroll.height));
                }
            }
        ColumnLayout {
            id: contents
            width: bodyScroll.width
            spacing: 12
            RowLayout {
                spacing: 10
                Rectangle {
                    width: 30; height: 30; radius: 10
                    color: Qt.rgba(popover.accent.r, popover.accent.g, popover.accent.b, 0.14)
                    border.color: Qt.rgba(popover.accent.r, popover.accent.g, popover.accent.b, 0.25)
                    Text { anchors.centerIn: parent; text: popover.symbol; color: popover.accent; font.family: "GoMono Nerd Font"; font.pixelSize: 17 }
                }
                MenuLabel { text: popover.title; color: popover.accent; font.bold: true; font.pixelSize: 15; Layout.fillWidth: true }
                Rectangle { width: 5; height: 5; radius: 3; color: popover.accent; opacity: 0.7 }
            }
            Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Qt.rgba(popover.accent.r, popover.accent.g, popover.accent.b, 0.15) }
            Loader {
                id: persistentLoader
                Layout.fillWidth: true
                visible: popover.persistentSelected
                sourceComponent: popover.persistentPage
            }
            // An inactive Loader retains its last height. Hide it so the layout
            // does not count that stale size below the persistent launcher.
            Loader { id: pageLoader; Layout.fillWidth: true; visible: active; active: popover.rendering && !popover.persistentSelected; sourceComponent: popover.page }
        }
        }
    }
}
