pragma ComponentBehavior: Bound
import QtQuick
import "PopdownGeometry.js" as FluidGeometry
import "style" as Style
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
    property bool alignToTrigger: false
    property string edge: "top"
    readonly property bool vertical: edge === "left" || edge === "right"
    property color accent: "#b4befe"
    property string title: ""
    property string symbol: ""
    property bool showHeader: true
    property real preferredBodyWidth: 300
    property real maximumBodyHeight: Infinity
    property Component page: null
    property Component persistentPage: null
    property bool persistentSelected: false
    property bool instant: false
    readonly property var pageItem: persistentSelected ? persistentLoader.item : pageLoader.item
    property bool opened: false
    property bool cardClickable: false
    property bool connected: true
    // Opt-in left-edge drawer; ordinary menus retain their funnel and motion.
    property bool edgeAttached: false
    readonly property bool attachedLeft: edgeAttached && connected && edge === "left"
    property bool bottomLeftAttached: false
    readonly property bool attachedCorner: attachedLeft && bottomLeftAttached
    readonly property real footRadius: Math.max(0, Math.min(28, bodyY, attachedCorner ? width - bodyRight : height - bodyBottom))
    property real edgeProgress: opened ? 1 : 0
    Behavior on edgeProgress {
        enabled: popover.attachedLeft && !popover.instant && Style.Theme.duration(popover, 1) > 0
        NumberAnimation {
            duration: popover.opened ? 520 : 380
            easing.type: Easing.BezierSpline
            easing.bezierCurve: popover.opened ? [0.22, 1.32, 0.36, 1, 1, 1] : [0.4, 0, 0.2, 1, 1, 1]
        }
    }
    readonly property bool fluidSurface: connected && !attachedLeft
    readonly property bool motionEnabled: !instant && Style.Theme.duration(popover, 1) > 0
    readonly property real connectorGap: 20
    readonly property alias fluidMotion: fluid
    property rect panelBounds: Qt.rect(0, 0, width, height)
    readonly property real safeLeft: panelBounds.x + 12
    readonly property real safeRight: panelBounds.x + panelBounds.width - 12
    readonly property real safeTop: panelBounds.y + (attachedLeft ? 28 : 12)
    readonly property real safeBottom: panelBounds.y + panelBounds.height - (attachedCorner ? 0 : attachedLeft ? 28 : 12)
    readonly property bool rendering: opened || surface.opacity > 0 || (attachedLeft && edgeProgress > 0)
    signal hoverChanged(bool inside)
    signal cardClicked()
    readonly property real bodyWidth: Math.max(0, Math.min(preferredBodyWidth, connected && vertical && !attachedLeft
        ? (edge === "left" ? width - triggerRect.x - triggerRect.width - connectorGap - 12 : triggerRect.x - connectorGap - 12)
        : panelBounds.width - (attachedCorner ? 28 : 24), panelBounds.width - (attachedCorner ? 28 : 24)))
    function clamp(value, low, high) { return Math.max(low, Math.min(Math.max(low, high), value)); }
    readonly property real bodyX: attachedLeft ? 0 : !connected || !vertical
        ? (alignToTrigger && connected ? clamp(triggerRect.x + triggerRect.width / 2 - bodyWidth / 2, safeLeft, safeRight - bodyWidth) : alignment === "left" ? safeLeft : alignment === "right" ? safeRight - bodyWidth : panelBounds.x + (panelBounds.width - bodyWidth) / 2)
        : edge === "left" ? clamp(triggerRect.x + triggerRect.width + connectorGap, safeLeft, safeRight - bodyWidth)
        : clamp(triggerRect.x - connectorGap - bodyWidth, safeLeft, safeRight - bodyWidth)
    readonly property real availableHeight: !connected ? Math.max(0, Math.min(panelBounds.height - 64, safeBottom - bodyY)) : vertical ? Math.max(0, safeBottom - safeTop)
        : edge === "bottom" ? triggerRect.y - connectorGap - safeTop - 4 : safeBottom - triggerRect.y - triggerRect.height - connectorGap - 4
    readonly property real bodyHeight: Math.max(0, Math.min(availableHeight, maximumBodyHeight, contents.implicitHeight + 36))
    readonly property real bodyY: attachedCorner ? safeBottom - bodyHeight : !connected ? Math.max(safeTop + 36, triggerRect.y + triggerRect.height + 12)
        : edge === "top" ? clamp(triggerRect.y + triggerRect.height + connectorGap, safeTop, safeBottom - bodyHeight)
        : edge === "bottom" ? clamp(triggerRect.y - connectorGap - bodyHeight, safeTop, safeBottom - bodyHeight)
        : clamp(triggerRect.y + triggerRect.height / 2 - bodyHeight / 2, safeTop, safeBottom - bodyHeight)
    readonly property real bodyRight: bodyX + bodyWidth
    readonly property real bodyBottom: bodyY + bodyHeight
    // Draw the continuous surface in coordinates that always point inward, while
    // the card contents stay upright on every edge.
    readonly property real shapeX: vertical ? bodyY : bodyX
    readonly property real shapeY: edge === "bottom" ? height - bodyBottom : edge === "right" ? width - bodyRight : vertical ? bodyX : bodyY
    readonly property real shapeWidth: vertical ? bodyHeight : bodyWidth
    readonly property real shapeHeight: vertical ? bodyWidth : bodyHeight
    readonly property real neckY: edge === "bottom" ? height - triggerRect.y
        : edge === "right" ? width - triggerRect.x
        : edge === "left" ? triggerRect.x + triggerRect.width : triggerRect.y + triggerRect.height
    readonly property real shoulder: clamp(tipX, shapeX + 40, shapeX + shapeWidth - 40)
    readonly property real tipX: vertical ? triggerRect.y + triggerRect.height / 2 : triggerRect.x + triggerRect.width / 2
    readonly property real attachmentHalfWidth: Math.max(0, (vertical ? triggerRect.height : triggerRect.width) / 2)
    // Keep the pill bounds as the anchor reference; the small connector starts
    // at its outer edge. Coordinates rotate with the edge.
    property real triggerRadius: Math.min(triggerRect.width, triggerRect.height) / 2
    readonly property real attachmentRadius: Math.max(0, Math.min(attachmentHalfWidth,
        (vertical ? triggerRect.width : triggerRect.height) / 2, triggerRadius))
    readonly property real attachmentY: neckY - attachmentRadius
    PopdownMotion {
        id: fluid
        animate: popover.motionEnabled && popover.fluidSurface
        active: popover.rendering && popover.fluidSurface
        opened: popover.opened
        targetX: popover.shapeX; targetY: popover.shapeY
        targetWidth: popover.shapeWidth; targetHeight: popover.shapeHeight
        minimumX: popover.vertical ? popover.safeTop : popover.safeLeft
        maximumX: popover.vertical ? popover.safeBottom : popover.safeRight
        minimumY: popover.edge === "bottom" ? popover.height - popover.safeBottom
            : popover.edge === "right" ? popover.width - popover.safeRight : popover.vertical ? popover.safeLeft : popover.safeTop
        maximumY: popover.edge === "bottom" ? popover.height - popover.safeTop
            : popover.edge === "right" ? popover.width - popover.safeLeft : popover.vertical ? popover.safeRight : popover.safeBottom
    }
    readonly property var fluidOutline: FluidGeometry.outline(fluid.displayX, fluid.displayY,
        fluid.displayWidth, fluid.displayHeight, tipX, neckY, attachmentHalfWidth, attachmentRadius, fluid.shear)
    // Keep layout and text wrapping at their final size. The background, content,
    // shadow and hit targets receive exactly the same body deformation.
    function cardPoint(x, y) {
        let point = FluidGeometry.toInward(edge, width, height, x, y);
        let sx = fluid.displayWidth / Math.max(1, shapeWidth);
        let sy = fluid.displayHeight / Math.max(1, shapeHeight);
        let normal = (point.y - shapeY) * sy;
        return FluidGeometry.fromInward(edge, width, height,
            fluid.displayX + (point.x - shapeX) * sx + fluid.shear * normal,
            fluid.displayY + normal);
    }
    function cardTransform(x, y) {
        if (!fluidSurface) return Qt.matrix4x4(1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1);
        let a = cardPoint(x, y), b = cardPoint(x + 1, y), c = cardPoint(x, y + 1);
        return Qt.matrix4x4(b.x-a.x,c.x-a.x,0,a.x-x, b.y-a.y,c.y-a.y,0,a.y-y, 0,0,1,0, 0,0,0,1);
    }
    readonly property bool pointerInside: opened && tracking.hovered && containsPointer(tracking.point.position)

    function containsPointer(point) {
        if (fluidSurface) {
            let p = FluidGeometry.toInward(edge, width, height, point.x, point.y);
            let localY = p.y - fluid.displayY;
            let localX = p.x - fluid.displayX - fluid.shear * localY;
            if (localX >= 0 && localX <= fluid.displayWidth && localY >= 0 && localY <= fluid.displayHeight)
                return true;
        }
        if (point.y >= bodyY && point.y <= bodyBottom && point.x >= bodyX && point.x <= bodyRight)
            return true;
        if (attachedLeft && point.x >= 0 && point.x <= footRadius
            && point.y >= bodyY - footRadius && point.y <= bodyBottom + footRadius) return true;
        if (attachedCorner && point.x >= bodyRight && point.x <= bodyRight + footRadius
            && point.y >= bodyBottom - footRadius && point.y <= bodyBottom) return true;
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
        visible: popover.rendering
        transform: [Scale {
            origin.x: 0
            origin.y: popover.attachedCorner ? popover.bodyBottom : popover.bodyY + popover.bodyHeight / 2
            xScale: popover.attachedLeft ? Math.max(0, popover.edgeProgress) : 1
            // A small squash/stretch follows the same continuous curve on reversal.
            yScale: popover.attachedCorner ? Math.max(0, popover.edgeProgress) * (1 + 0.06 * Math.sin(Math.PI * popover.edgeProgress))
                : popover.attachedLeft ? 1 + 0.035 * Math.sin(Math.PI * popover.edgeProgress) : 1
        }, Translate {
            id: arrival
            x: popover.opened || popover.connected ? 0 : popover.edge === "left" ? -12 : popover.edge === "right" ? 12 : 0
            y: popover.opened || (popover.connected && !popover.attachedLeft) ? 0 : popover.edge === "bottom" ? 12 : popover.vertical ? 0 : -12
            Behavior on x { NumberAnimation { duration: popover.instant ? 0 : Style.Theme.duration(popover, Style.Theme.spatialDuration); easing.type: Easing.BezierSpline; easing.bezierCurve: Style.Theme.spatialCurve } }
            Behavior on y { NumberAnimation { duration: popover.instant ? 0 : Style.Theme.duration(popover, Style.Theme.spatialDuration); easing.type: Easing.BezierSpline; easing.bezierCurve: Style.Theme.spatialCurve } }
        }]
        states: State {
            name: "open"; when: popover.opened
            PropertyChanges { surface.opacity: 1 }
        }
        transitions: Transition {
            ParallelAnimation {
                NumberAnimation { property: "opacity"; duration: popover.instant ? 0 : Style.Theme.duration(popover, popover.attachedLeft ? (popover.opened ? 160 : 380) : Style.Theme.hoverDuration); easing.type: Easing.BezierSpline; easing.bezierCurve: Style.Theme.effectsCurve }
            }
        }
        Rectangle {
            id: cardShadow
            visible: !popover.attachedLeft
            x: popover.bodyX + 3; y: popover.bodyY + 7
            width: popover.bodyWidth; height: popover.bodyHeight
            radius: popover.fluidSurface ? 24 : 20; color: "#28000000"
            transform: Matrix4x4 { matrix: popover.cardTransform(cardShadow.x, cardShadow.y) }
        }
        // Clip in screen coordinates so neither fill nor antialiased rim can
        // wrap over the trigger pill, including during the jelly animation.
        Item {
            id: connectorClip
            clip: true
            visible: popover.fluidSurface
            x: popover.edge === "left" ? popover.triggerRect.x + popover.triggerRect.width : 0
            y: popover.edge === "top" ? popover.triggerRect.y + popover.triggerRect.height : 0
            width: popover.edge === "right" ? popover.triggerRect.x : popover.width - x
            height: popover.edge === "bottom" ? popover.triggerRect.y : popover.height - y
            Shape {
                visible: popover.connected && !popover.attachedLeft
                objectName: "menuFunnel"
                anchors.fill: parent
                preferredRendererType: Shape.GeometryRenderer
                transform: Matrix4x4 {
                    matrix: popover.edge === "bottom" ? Qt.matrix4x4(1,0,0,-connectorClip.x, 0,-1,0,popover.height-connectorClip.y, 0,0,1,0, 0,0,0,1)
                        : popover.edge === "left" ? Qt.matrix4x4(0,1,0,-connectorClip.x, 1,0,0,-connectorClip.y, 0,0,1,0, 0,0,0,1)
                        : popover.edge === "right" ? Qt.matrix4x4(0,-1,0,popover.width-connectorClip.x, 1,0,0,-connectorClip.y, 0,0,1,0, 0,0,0,1)
                        : Qt.matrix4x4(1,0,0,-connectorClip.x, 0,1,0,-connectorClip.y, 0,0,1,0, 0,0,0,1)
                }
                ShapePath {
                    strokeWidth: 0.65
                    strokeColor: Qt.alpha(glass.rimColor, 0.55)
                    fillGradient: LinearGradient {
                        x1: 0; y1: popover.neckY; x2: 0; y2: (popover.shapeY + popover.shapeHeight)
                        GradientStop { position: 0; color: glass.topColor }
                        GradientStop { position: 1; color: glass.bottomColor }
                    }
                    PathSvg { path: popover.fluidOutline.path }
                }
            }
        }
        Shape {
            objectName: "edgeAttachedSurface"
            visible: popover.attachedLeft
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeWidth: 0
                fillGradient: LinearGradient {
                    x1: 0; y1: popover.bodyY; x2: 0; y2: popover.bodyBottom
                    GradientStop { position: 0; color: glass.topColor }
                    GradientStop { position: 1; color: glass.bottomColor }
                }
                // Corner drawers join the left edge above and the bottom edge at right.
                startX: 0; startY: popover.bodyY - popover.footRadius
                PathQuad { controlX: 0; controlY: popover.bodyY; x: popover.footRadius; y: popover.bodyY }
                PathLine { x: popover.bodyRight - 24; y: popover.bodyY }
                PathQuad { controlX: popover.bodyRight; controlY: popover.bodyY; x: popover.bodyRight; y: popover.bodyY + 24 }
                PathLine { x: popover.bodyRight; y: popover.bodyBottom - (popover.attachedCorner ? popover.footRadius : 24) }
                PathQuad {
                    controlX: popover.bodyRight; controlY: popover.bodyBottom
                    x: popover.bodyRight + (popover.attachedCorner ? popover.footRadius : -24); y: popover.bodyBottom
                }
                PathLine { x: popover.attachedCorner ? 0 : popover.footRadius; y: popover.bodyBottom }
                PathQuad { controlX: 0; controlY: popover.bodyBottom; x: 0; y: popover.bodyBottom + (popover.attachedCorner ? 0 : popover.footRadius) }
                PathLine { x: 0; y: popover.bodyY - popover.footRadius }
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
            id: cardClick
            transform: Matrix4x4 { matrix: popover.cardTransform(cardClick.x, cardClick.y) }
            x: popover.bodyX; y: popover.bodyY
            width: popover.bodyWidth; height: popover.bodyHeight
            enabled: popover.opened
            cursorShape: popover.cardClickable ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (popover.cardClickable) popover.cardClicked()
        }
        Flickable {
            id: bodyScroll
            objectName: "menuBodyScroll"
            transform: Matrix4x4 { matrix: popover.cardTransform(bodyScroll.x, bodyScroll.y) }
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
                visible: popover.showHeader
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
            Rectangle { visible: popover.showHeader; Layout.fillWidth: true; implicitHeight: 1; color: Qt.rgba(popover.accent.r, popover.accent.g, popover.accent.b, 0.15) }
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
