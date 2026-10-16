pragma ComponentBehavior: Bound
import QtQuick
import "DockModel.js" as Model
import "SettingsModel.js" as Settings

Pill {
    id: surface
    required property var config
    required property var panel
    property url wallpaperSource: ''
    property real screenWidth: 1366
    property real screenHeight: 768
    property real screenOffsetX: 0
    property real screenOffsetY: 0
    readonly property var appearance: Model.pillStyle(config,panel,wallpaperSource.toString())
    settings:appearance.settings
    interactive:false
    foreground:({launcher:'#51a2da',settings:'#b4befe',calendar:'#b4befe'})[appearance.id] || '#cdd6f4'
    tint:Qt.rgba(foreground.r,foreground.g,foreground.b,0.20)
    outline:Qt.rgba(foreground.r,foreground.g,foreground.b,0.28)
    opacity:panel.backgroundOpacity ?? 1
    colorSampler:Settings.adaptive(config,appearance.id) ? sampler : null
    colorRoot:surface
    WallpaperColors {
        id:sampler
        source:surface.wallpaperSource
        screenWidth:surface.screenWidth; screenHeight:surface.screenHeight
        offsetX:surface.screenOffsetX; offsetY:surface.screenOffsetY
        bandHeight:surface.height; bandWidth:surface.width
        regionOffsetX:surface.screenOffsetX
    }
}
