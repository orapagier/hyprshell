import QtQuick
import "AdaptiveColors.js" as Colors
import "style" as Style

Item {
    id: glass
    property url wallpaperSource: ""
    property real screenWidth: 1366
    property real screenHeight: 768
    property rect region: Qt.rect(0, 0, 300, 300)
    property color accent: "#b4befe"
    property real translucency: 0.06
    property bool cacheFullWallpaper: false
    readonly property color sample: sampler.sampleRect(region)
    readonly property var menuColors: Colors.wallpaperPalette(sample, Style.Theme.highContrast)
    // A dark backing keeps menu labels readable on light and busy wallpapers.
    readonly property color base: menuColors.background
    readonly property color topColor: Colors.alpha(Colors.mix(base, Qt.color("#ffffff"), Style.Theme.highContrast ? 0 : 0.13), 1 - translucency)
    readonly property color bottomColor: Colors.alpha(base, 1 - translucency)
    // Static tonal layers suggest glass without another blur or render texture.
    readonly property color middleColor: Colors.alpha(Colors.mix(base, menuColors.accent, Style.Theme.highContrast ? 0 : 0.04), 1 - translucency)
    readonly property color rimColor: Colors.alpha(Colors.mix(menuColors.accent, Qt.color("#ffffff"), 0.48), 0.64)
    WallpaperColors {
        id: sampler
        source: glass.wallpaperSource
        screenWidth: glass.screenWidth; screenHeight: glass.screenHeight
        offsetY: glass.cacheFullWallpaper ? 0 : glass.region.y
        bandHeight: glass.cacheFullWallpaper ? Math.max(1, glass.screenHeight) : Math.max(1, glass.region.height)
        sampleWidth: glass.cacheFullWallpaper ? 96 : 0
        sampleHeight: glass.cacheFullWallpaper ? 64 : 0
    }
}
