import QtQuick
import "AdaptiveColors.js" as Colors

Item {
    id: sampler
    property url source: ""
    property real screenWidth: 1366
    property real screenHeight: 768
    property real offsetX: 10
    property real offsetY: 5
    property real bandHeight: 32
    property real bandWidth: screenWidth
    property real regionOffsetX: 0
    property var pixels: []
    readonly property var linearChannels: Array.from({length: 256}, (_, value) => {
        let channel = value / 255;
        return channel <= 0.04045 ? channel / 12.92 : Math.pow((channel + 0.055) / 1.055, 2.4);
    })
    readonly property bool ready: pixels.length > 0
    width: 1; height: 1
    // Keep the Canvas attached to the scene so requestPaint works, without
    // displaying the sampled strip or intercepting pointer events.
    opacity: 0

    function invalidate() { pixels = []; strip.requestPaint(); }
    onSourceChanged: invalidate()
    onScreenWidthChanged: invalidate()
    onScreenHeightChanged: invalidate()
    onOffsetYChanged: invalidate()
    onBandHeightChanged: invalidate()
    onBandWidthChanged: invalidate()
    onRegionOffsetXChanged: invalidate()

    function sampleRect(rect, includeBounds) {
        if (!ready) {
            let fallback = Qt.rgba(0.08, 0.09, 0.13, 1);
            return includeBounds ? {average: fallback, minimum: fallback, maximum: fallback} : fallback;
        }
        let x0 = Math.max(0, Math.min(strip.width - 1, Math.floor((rect.x - regionOffsetX) / bandWidth * strip.width)));
        let x1 = Math.max(x0 + 1, Math.min(strip.width, Math.ceil((rect.x + rect.width - regionOffsetX) / bandWidth * strip.width)));
        let y0 = Math.max(0, Math.min(strip.height - 1, Math.floor((rect.y - offsetY) / bandHeight * strip.height)));
        let y1 = Math.max(y0 + 1, Math.min(strip.height, Math.ceil((rect.y + rect.height - offsetY) / bandHeight * strip.height)));
        let r = 0, g = 0, b = 0, count = 0;
        let low = Infinity, high = -Infinity, lowIndex = 0, highIndex = 0;
        for (let y = y0; y < y1; ++y) for (let x = x0; x < x1; ++x) {
            let i = (y * strip.width + x) * 4;
            r += pixels[i]; g += pixels[i + 1]; b += pixels[i + 2]; ++count;
            if (includeBounds) {
                // Use actual darkest/lightest pixels. Independent RGB extrema
                // invented black/white bounds on colorful wallpaper regions.
                let value = 0.2126 * linearChannels[pixels[i]] + 0.7152 * linearChannels[pixels[i + 1]] + 0.0722 * linearChannels[pixels[i + 2]];
                if (value < low) { low = value; lowIndex = i; }
                if (value > high) { high = value; highIndex = i; }
            }
        }
        let average = Qt.rgba(r / count / 255, g / count / 255, b / count / 255, 1);
        return includeBounds ? {average: average,
            minimum: Qt.rgba(pixels[lowIndex]/255, pixels[lowIndex+1]/255, pixels[lowIndex+2]/255, 1),
            maximum: Qt.rgba(pixels[highIndex]/255, pixels[highIndex+1]/255, pixels[highIndex+2]/255, 1)} : average;
    }
    function paletteFor(item, root, accent, style) {
        let x = offsetX, y = offsetY;
        // Explicitly read ancestor coordinates so bindings follow Row movement,
        // monitor resizing, newly visible controls, and media title changes.
        for (let node = item; node && node !== root; node = node.parent) {
            x += node.x; y += node.y;
        }
        let region = sampleRect(Qt.rect(x, y, item.width, item.height), true);
        return Colors.palette(region.average, accent, region.minimum, region.maximum, style);
    }

    Image {
        id: wallpaper
        source: sampler.source
        asynchronous: true
        visible: false
        onStatusChanged: {
            sampler.pixels = [];
            if (status === Image.Ready) strip.requestPaint();
        }
    }
    Canvas {
        id: strip
        // Preserve small bright/dark details instead of averaging them away
        // before bare-glyph contrast is measured.
        width: Math.min(4096, Math.max(1, Math.ceil(sampler.bandWidth)))
        height: Math.min(sampler.bandWidth < sampler.screenWidth ? 4096 : 160, Math.max(1, Math.ceil(sampler.bandHeight)))
        onAvailableChanged: if (available) requestPaint()
        onWidthChanged: sampler.invalidate()
        onHeightChanged: sampler.invalidate()
        onPaint: {
            if (wallpaper.status !== Image.Ready || sampler.screenWidth <= 0 || sampler.screenHeight <= 0
                    || sampler.bandWidth <= 0 || sampler.bandHeight <= 0) return;
            let iw = wallpaper.implicitWidth, ih = wallpaper.implicitHeight;
            if (!iw || !ih) return;
            // Match awww's default center-cropped, aspect-preserving wallpaper.
            let scale = Math.max(sampler.screenWidth / iw, sampler.screenHeight / ih);
            let sx = (iw - sampler.screenWidth / scale) / 2 + sampler.regionOffsetX / scale;
            let sy = (ih - sampler.screenHeight / scale) / 2 + sampler.offsetY / scale;
            // Layout/reload can briefly place the strip outside the wallpaper.
            // Sample its nearest edge until the final geometry is available.
            sx = Math.max(0, Math.min(iw - 1, sx));
            sy = Math.max(0, Math.min(ih - 1, sy));
            let sw = Math.min(iw - sx, sampler.bandWidth / scale);
            let sh = Math.min(ih - sy, sampler.bandHeight / scale);
            let ctx = getContext("2d");
            ctx.clearRect(0, 0, width, height);
            ctx.drawImage(wallpaper, sx, sy, sw, sh, 0, 0, width, height);
            let data = ctx.getImageData(0, 0, width, height).data;
            let copy = [];
            for (let i = 0; i < data.length; ++i) copy.push(data[i]);
            sampler.pixels = copy;
        }
    }
}
