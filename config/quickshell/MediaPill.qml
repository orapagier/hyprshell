pragma ComponentBehavior: Bound
import QtQuick

Pill {
    id: media
    property var levels: []
    readonly property real spectrumScale: (settings.iconSize || 16) / 16
    readonly property real spectrumWidth: settings.hideIcon ? 0 : uniformItems ? (settings.iconSize || 16) * (vertical ? 1 : 2.9) : Math.ceil(58 * spectrumScale)
    glyphRect: settings.hideIcon ? textGlyphRect : Qt.rect(spectrum.x, spectrum.y, spectrum.width, spectrum.height)
    implicitHeight: settings.panelPillHeight || (uniformItems ? naturalHeight : vertical ? width : Math.max(28, settings.hideIcon ? 0 : (settings.iconSize || 16) + 8, shownText.length ? content.implicitHeight + 8 : 0))
    foreground: "#cba6f7"
    tint: "#2ef5c2e7"
    outline: "#42f5c2e7"
    leftPadding: 9 + spectrumWidth + 8
    rightPadding: vertical ? 4 : 9
    effectiveLeftPadding: uniformItems && !vertical ? (settings.panelItemPadding ?? 4) + spectrumWidth + (shownText.length ? 4 : 0) : Math.max(0, (settings.panelItemPadding ?? (vertical ? 4 : 9)) + (settings.paddingLeft || 0)) + (vertical ? 0 : spectrumWidth + 8)
    interactive: false
    clip: true
    content.y: uniformGlyphHeight > 0 && !vertical ? normalizedTextY : vertical ? (settings.hideIcon ? 4 : 16 * spectrumScale + 8) : (height - content.height) / 2
    content.horizontalAlignment: vertical ? Text.AlignHCenter : Text.AlignLeft
    AudioSpectrumBars {
        id: spectrum
        objectName: "mediaSpectrum"
        visible: !media.settings.hideIcon
        x: media.iconOnly ? (parent.width - width) / 2 : media.uniformItems ? (media.settings.panelItemPadding ?? 4) : Math.max(0, (media.settings.panelItemPadding ?? 9) + (media.settings.paddingLeft || 0))
        width: media.uniformItems ? media.spectrumWidth : media.vertical ? Math.min(parent.width * 0.8, 28 * media.spectrumScale) : 58 * media.spectrumScale
        height: media.uniformItems ? Math.min(Math.max(0, parent.height - (media.vertical ? 4 : 3)), (media.settings.uniformGlyphHeight || media.settings.iconSize || 16) * (media.vertical ? 1 : 1.25)) : media.vertical ? (media.settings.uniformGlyphHeight || Math.min(parent.height - 14, 16 * media.spectrumScale)) : 16 * media.spectrumScale
        y: (parent.height - height) / 2
        spacing: media.uniformItems ? (media.vertical ? 1 : 0.75) : media.vertical ? Math.max(1, media.spectrumScale) : 2 * media.spectrumScale
        minimumHeight: 2 * media.spectrumScale
        barCount: media.vertical ? 5 : 12
        levels: media.vertical ? Array.from({length:5}, (_, band) => {
            let start = Math.floor(band * media.levels.length / 5);
            let end = Math.max(start + 1, Math.floor((band + 1) * media.levels.length / 5));
            return Math.max(0, ...media.levels.slice(start, end));
        }) : media.levels
        color: media.settings.iconColor || ((media.colorSampler || media.settings.vibrantColor) ? media.effectiveForeground : "#94e2d5")
        variableOpacity: !media.colorSampler
        contrastEdge: media.glyphHalo
        edgeColor: media.iconEdge
    }
}
