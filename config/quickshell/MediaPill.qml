pragma ComponentBehavior: Bound
import QtQuick

Pill {
    id: media
    property var levels: []
    verticalLineLimit: vertical ? 12 : 0
    readonly property real spectrumScale: (settings.iconSize || 16) / 16
    readonly property int spectrumWidth: settings.hideIcon ? 0 : Math.ceil(58 * spectrumScale)
    implicitHeight: vertical ? Math.max(28, (settings.hideIcon ? 0 : 16 * spectrumScale + 4) + (shownText.length ? content.implicitHeight : 0) + 8) : Math.max(28, settings.hideIcon ? 0 : (settings.iconSize || 16) + 8, shownText.length ? content.implicitHeight + 8 : 0)
    foreground: "#cba6f7"
    tint: "#2ef5c2e7"
    outline: "#42f5c2e7"
    family: "DejaVu Sans Mono"
    pixelSize: 11
    bold: false
    leftPadding: 9 + spectrumWidth + 8
    rightPadding: vertical ? 4 : 9
    effectiveLeftPadding: Math.max(0, (vertical ? 4 : 9) + (settings.paddingLeft || 0)) + (vertical ? 0 : spectrumWidth + 8)
    interactive: false
    clip: true
    content.y: vertical ? (settings.hideIcon ? 4 : 16 * spectrumScale + 8) : (height - content.height) / 2
    content.horizontalAlignment: vertical ? Text.AlignHCenter : Text.AlignLeft
    AudioSpectrumBars {
        objectName: "mediaSpectrum"
        visible: !media.settings.hideIcon
        x: media.vertical ? (parent.width - width) / 2 : Math.max(0, 9 + (media.settings.paddingLeft || 0))
        width: media.vertical ? Math.min(parent.width - 8, 58 * media.spectrumScale) : 58 * media.spectrumScale
        height: 16 * media.spectrumScale
        y: media.vertical ? 4 : (parent.height - height) / 2
        spacing: 2 * media.spectrumScale
        minimumHeight: 2 * media.spectrumScale
        levels: media.levels
        color: media.settings.iconColor || ((media.colorSampler || media.settings.vibrantColor) ? media.effectiveForeground : "#94e2d5")
        variableOpacity: !media.colorSampler
        contrastEdge: media.glyphHalo
        edgeColor: media.iconEdge
    }
}
