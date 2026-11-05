import QtQuick
import QtQuick.Shapes
import "AdaptiveColors.js" as Colors
import "style" as Style

Item {
    id: liquidGlass
    property url wallpaperSource: ""
    property real screenWidth: 1366
    property real screenHeight: 768
    property rect region: Qt.rect(0, 0, 300, 300)
    property color accent: "#b4befe"
    property real translucency: 0.06
    property bool cacheFullWallpaper: false
    property bool enabled: true
    property real highlightIntensity: 0.15
    property real noiseOpacity: 0.03
    property real animationSpeed: 1.0

    readonly property color sample: sampler.sampleRect(region)
    readonly property var menuColors: Colors.wallpaperPalette(sample, Style.Theme.highContrast)
    readonly property color base: menuColors.background
    readonly property color topColor: Colors.alpha(Colors.mix(base, Qt.color("#ffffff"), Style.Theme.highContrast ? 0 : 0.13), 1 - translucency)
    readonly property color bottomColor: Colors.alpha(base, 1 - translucency)
    readonly property color middleColor: Colors.alpha(Colors.mix(base, menuColors.accent, Style.Theme.highContrast ? 0 : 0.04), 1 - translucency)
    readonly property color rimColor: Colors.alpha(Colors.mix(menuColors.accent, Qt.color("#ffffff"), 0.48), 0.64)

    WallpaperColors {
        id: sampler
        source: liquidGlass.wallpaperSource
        screenWidth: liquidGlass.screenWidth; screenHeight: liquidGlass.screenHeight
        offsetY: liquidGlass.cacheFullWallpaper ? 0 : liquidGlass.region.y
        bandHeight: liquidGlass.cacheFullWallpaper ? Math.max(1, liquidGlass.screenHeight) : Math.max(1, liquidGlass.region.height)
        sampleWidth: liquidGlass.cacheFullWallpaper ? 96 : 0
        sampleHeight: liquidGlass.cacheFullWallpaper ? 64 : 0
    }

    property real highlightX: region.width / 2
    property real highlightY: region.height / 2
    property real highlightPhase: 0

    NumberAnimation on highlightPhase {
        running: liquidGlass.enabled && !Style.Theme.reducedMotion
        loops: Animation.Infinite
        from: 0; to: Math.PI * 2
        duration: 8000 / liquidGlass.animationSpeed
    }

    Timer {
        id: noiseTimer
        interval: 100
        running: liquidGlass.enabled && !Style.Theme.reducedMotion
        repeat: true
        onTriggered: noiseSeed = Math.random()
    }
    property real noiseSeed: 0

    readonly property color highlightColor: Colors.alpha(Qt.color("#ffffff"), liquidGlass.highlightIntensity)
    readonly property color noiseColor: Colors.alpha(Qt.color("#ffffff"), liquidGlass.noiseOpacity)

    function updateHighlightPosition(x, y) {
        if (!liquidGlass.enabled) return
        liquidGlass.highlightX = Math.max(0, Math.min(region.width, x - region.x))
        liquidGlass.highlightY = Math.max(0, Math.min(region.height, y - region.y))
    }

    Item {
        id: visualLayer
        anchors.fill: parent
        visible: liquidGlass.enabled
        opacity: 1

        Rectangle {
            id: baseLayer
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0; color: liquidGlass.topColor }
                GradientStop { position: 0.35; color: liquidGlass.middleColor }
                GradientStop { position: 0.7; color: liquidGlass.bottomColor }
                GradientStop { position: 1; color: liquidGlass.bottomColor }
            }
        }

        Rectangle {
            id: highlightLayer
            anchors.fill: parent
            visible: liquidGlass.enabled && !Style.Theme.reducedMotion
            gradient: Gradient {
                GradientStop { position: 0; color: "transparent" }
                GradientStop {
                    position: 0.15
                    color: liquidGlass.highlightColor
                    property real dynamicPos: 0.15 + 0.1 * Math.sin(liquidGlass.highlightPhase)
                }
                GradientStop {
                    position: 0.35
                    color: "transparent"
                    property real dynamicPos: 0.35 + 0.1 * Math.cos(liquidGlass.highlightPhase * 0.7)
                }
                GradientStop { position: 1; color: "transparent" }
            }
            rotation: 15 + 10 * Math.sin(liquidGlass.highlightPhase * 0.5)
            transformOrigin: Item.Center
            Behavior on rotation { enabled: liquidGlass.enabled; NumberAnimation { duration: 4000 } }
        }

        ShaderEffect {
            id: noiseLayer
            anchors.fill: parent
            visible: liquidGlass.enabled && !Style.Theme.reducedMotion
            property variant source: baseLayer
            property real time: 0
            property real glassNoiseSeed: liquidGlass.noiseSeed
            property real glassNoiseOpacity: liquidGlass.noiseOpacity
            fragmentShader: "
                uniform lowp sampler2D source;
                uniform lowp float time;
                uniform lowp float glassNoiseSeed;
                uniform lowp float glassNoiseOpacity;
                varying highp vec2 qt_TexCoord0;
                float hash(vec2 p) {
                    return fract(sin(dot(p + glassNoiseSeed, vec2(127.1, 311.7))) * 43758.5453);
                }
                float noise(vec2 p) {
                    vec2 i = floor(p);
                    vec2 f = fract(p);
                    f = f * f * (3.0 - 2.0 * f);
                    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
                               mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
                }
                void main() {
                    vec2 uv = qt_TexCoord0 * vec2(100.0, 100.0) + time * 0.5;
                    float n = noise(uv) * 0.5 + 0.5;
                    vec4 base = texture2D(source, qt_TexCoord0);
                    gl_FragColor = vec4(base.rgb + (n - 0.5) * 0.02, base.a) * glassNoiseOpacity + base * (1.0 - glassNoiseOpacity);
                }
            "
            NumberAnimation on time {
                running: liquidGlass.enabled && !Style.Theme.reducedMotion
                loops: Animation.Infinite
                from: 0; to: 100
                duration: 20000
            }
        }

        Rectangle {
            id: rimLayer
            anchors.fill: parent
            visible: liquidGlass.enabled
            color: "transparent"
            border.color: liquidGlass.rimColor
            border.width: 1
            radius: Math.min(region.width, region.height) / 2
        }
    }

    MouseArea {
        id: mouseTracker
        anchors.fill: parent
        hoverEnabled: true
        onPositionChanged: liquidGlass.updateHighlightPosition(mouse.x, mouse.y)
        onEntered: liquidGlass.updateHighlightPosition(mouse.x, mouse.y)
    }

    Connections {
        target: Style.Theme
        function onReducedMotionChanged() {
            if (Style.Theme.reducedMotion) {
                highlightLayer.visible = false
                noiseLayer.visible = false
            } else if (liquidGlass.enabled) {
                highlightLayer.visible = true
                noiseLayer.visible = true
            }
        }
    }
}