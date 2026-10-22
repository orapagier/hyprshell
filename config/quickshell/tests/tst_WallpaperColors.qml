import QtQuick
import QtTest
import ".."
import "../AdaptiveColors.js" as Colors
import "../WallpaperQuery.js" as Query

Item {
    id: scene
    width: 800; height: 100
    WallpaperColors {
        id: sampler
        source: Qt.resolvedUrl("fixtures/wallpaper-regions.svg")
        screenWidth: 800; screenHeight: 400
        offsetX: 0; offsetY: 8
    }
    Item {
        id: movingRow
        x: 20; y: 8
        Pill { id: pill; width: 100; text: "Sample"; colorSampler: sampler; colorRoot: scene }
    }
    Bar {
        id: bar
        y: 50; width: 800
        wallpaperSource: sampler.source
        screenWidth: 800; screenHeight: 400
    }
    MenuPopover {
        id: menu
        width: 800; height: 400
        wallpaperSource: sampler.source
        instant: true; opened: true
        page: Component {
            Item {
                implicitHeight: 40
                MenuLabel { objectName: "adaptiveMenuLabel"; text: "Readable label" }
                MenuButton { objectName: "adaptiveMenuButton"; y: 20; text: "Action" }
            }
        }
    }
    TestCase {
        name: "WallpaperColors"
        when: windowShown
        function init() {
            sampler.source = Qt.resolvedUrl("fixtures/wallpaper-regions.svg");
            sampler.screenWidth = 800; sampler.screenHeight = 400;
            sampler.bandWidth = Qt.binding(() => sampler.screenWidth); sampler.bandHeight = 32;
            sampler.regionOffsetX = 0; sampler.offsetY = 8;
            movingRow.x = 20;
            tryCompare(sampler, "ready", true);
        }
        function sample(x) { return sampler.sampleRect(Qt.rect(x, 10, 30, 18)); }
        function test_pixelsUseExactByteStorage() {
            verify(sampler.pixels instanceof Uint8Array);
            compare(sampler.pixels.byteLength, sampler.pixels.length);
            for (let channel of sampler.pixels)
                verify(Number.isInteger(channel) && channel >= 0 && channel <= 255);
        }
        function benchmark_repeatedRegionSampling() {
            sampler.sampleRect(Qt.rect(20, 10, 300, 18), true);
        }
        function test_cachedSamplesInvalidateWithPixelChanges() {
            let rect = Qt.rect(185, 10, 30, 18);
            let original = sampler.pixels;
            let first = sampler.sampleRect(rect, true);
            verify(sampler.sampleRect(rect, true) === first);
            fuzzyCompare(sampler.sampleRect(rect), first.average, 0.001);
            try {
                sampler.pixels = original.map((value, index) => index % 4 === 3 ? 255 : 0);
                let next = sampler.sampleRect(rect, true);
                verify(next !== first);
                fuzzyCompare(next.average, Qt.rgba(0,0,0,1), 0.001);
                fuzzyCompare(next.minimum, Qt.rgba(0,0,0,1), 0.001);
                fuzzyCompare(next.maximum, Qt.rgba(0,0,0,1), 0.001);
            } finally {
                sampler.pixels = original;
            }
        }
        function test_sampleCacheStaysBoundedDuringMovement() {
            for (let x = 0; x < 300; ++x) sampler.sampleRect(Qt.rect(x, 10, 30, 18), true);
            verify(sampler.sampleCache.keys.length <= 128);
            verify(Object.keys(sampler.sampleCache.entries).length <= 128);
            fuzzyCompare(sample(20), Qt.rgba(0,0,0,1), 0.01);
            fuzzyCompare(sample(250), Qt.rgba(1,1,1,1), 0.01);
        }
        function test_samplesEachLocalRegionAtBarHeight() {
            fuzzyCompare(sample(20), Qt.rgba(0,0,0,1), 0.01);
            fuzzyCompare(sample(250), Qt.rgba(1,1,1,1), 0.01);
            fuzzyCompare(sample(450), Qt.rgba(1,0,0,1), 0.01);
            fuzzyCompare(sample(650), Qt.rgba(0,0,1,1), 0.01);
        }
        function test_detectsAwwwOutputsAndEscapesPaths() {
            let sources = Query.sources(": eDP-1: 1920x1080, scale: 1, currently displaying: image: /tmp/My wallpaper #1.png\nother: DP-1: 2560x1440, scale: 1.5, currently displaying: image: /tmp/other.jpg\n");
            compare(sources["eDP-1"], "file:///tmp/My%20wallpaper%20%231.png");
            compare(sources["DP-1"], "file:///tmp/other.jpg");
            sources = Query.sources("eDP-1: 1920x1080, scale: 1, currently displaying: image: /tmp/plain.jpg\n");
            compare(sources["eDP-1"], "file:///tmp/plain.jpg");
        }
        function test_centerCropMatchesWallpaper() {
            sampler.screenWidth = 400;
            tryCompare(sampler, "ready", true);
            fuzzyCompare(sample(20), Qt.rgba(1,1,1,1), 0.01);
            fuzzyCompare(sample(250), Qt.rgba(1,0,0,1), 0.01);
            sampler.screenWidth = 800; sampler.screenHeight = 200;
            tryCompare(sampler, "ready", true);
            fuzzyCompare(sample(20), Qt.rgba(0,1,0,1), 0.01);
        }
        function test_followsItemAndAncestorMovement() {
            let initial = Colors.luminance(pill.effectiveForeground);
            movingRow.x = 240;
            tryVerify(() => Colors.luminance(pill.effectiveForeground) < initial);
            movingRow.x = 440;
            tryVerify(() => Colors.luminance(pill.effectiveForeground) < 0.1);
        }
        function test_missingWallpaperKeepsReadableFallback() {
            sampler.source = "";
            compare(sampler.ready, false);
            verify(Colors.luminance(pill.effectiveForeground) > 0.15);
        }
        function test_emptyBandWaitsForLayoutAndRecovers() {
            sampler.bandWidth = 0;
            wait(60);
            compare(sampler.ready, false);
            sampler.bandWidth = 800;
            tryCompare(sampler, "ready", true);
            sampler.bandHeight = 0;
            wait(60);
            compare(sampler.ready, false);
            sampler.bandHeight = 32;
            tryCompare(sampler, "ready", true);
        }
        function test_transientOutsideRegionSamplesNearestEdge() {
            sampler.regionOffsetX = 1000; sampler.offsetY = 1000;
            tryCompare(sampler, "ready", true);
            let color = sampler.sampleRect(Qt.rect(1000, 1000, 10, 10));
            verify(isFinite(color.r) && isFinite(color.g) && isFinite(color.b));
            compare(color.a, 1);
        }
        function test_contrastForEveryStateAndUnderlyingExtreme() {
            let samples = [Qt.rgba(0,0,0,1), Qt.rgba(1,1,1,1), Qt.rgba(1,0,0,1), Qt.rgba(0,1,0,1), Qt.rgba(0,0,1,1), Qt.rgba(0.6,0.6,0.6,1)];
            let accents = [Qt.rgba(0.09,0.58,0.82,1), Qt.rgba(0.34,0.35,0.44,1), Qt.rgba(0.95,0.55,0.66,1)];
            for (let sample of samples) for (let accent of accents) for (let style of ["normal", "muted", "emphasized"]) {
                let palette = Colors.palette(sample, accent, Qt.rgba(0,0,0,1), Qt.rgba(1,1,1,1), style);
                for (let fill of [palette.tint, palette.hover, palette.selected]) {
                    for (let under of samples) {
                        let composite = Colors.mix(under, fill, fill.a);
                        for (let highlight of [0, 0.08]) {
                            let rendered = Colors.mix(composite, Qt.rgba(1,1,1,1), highlight);
                            verify(Colors.contrast(palette.foreground, rendered) >= 4.5,
                                   "Text contrast fell below 4.5:1");
                        }
                    }
                }
            }
        }
        function test_uniformWallpapersKeepTransparentGlass() {
            let samples = [Qt.rgba(0,0,0,1), Qt.rgba(1,1,1,1), Qt.rgba(1,0,0,1), Qt.rgba(0,1,0,1), Qt.rgba(0,0,1,1), Qt.rgba(0.6,0.6,0.6,1)];
            for (let sample of samples) {
                let palette = Colors.palette(sample, Qt.rgba(0.54,0.70,0.98,1));
                verify(palette.tint.a <= 0.40, "Uniform wallpaper should show through the glass");
                for (let fill of [palette.tint, palette.hover, palette.selected]) {
                    let composite = Colors.mix(sample, fill, fill.a);
                    for (let highlight of [0, 0.08])
                        verify(Colors.contrast(palette.foreground, Colors.mix(composite, Qt.rgba(1,1,1,1), highlight)) >= 4.5);
                }
            }
        }
        function test_mixedRegionsProvideContrastBounds() {
            let region = sampler.sampleRect(Qt.rect(185, 10, 30, 18), true);
            fuzzyCompare(region.minimum, Qt.rgba(0,0,0,1), 0.01);
            fuzzyCompare(region.maximum, Qt.rgba(1,1,1,1), 0.01);
            let palette = Colors.palette(region.average, Qt.rgba(0.54,0.70,0.98,1), region.minimum, region.maximum);
            verify(palette.tint.a > 0.22, "Mixed black and white areas need stronger tinting");
        }
        function test_barContentsUseLocalPalette() {
            tryCompare(bar.wallpaperColors, "ready", true);
            let launcher = findChild(bar, "launcherTrigger");
            let bell = findChild(bar, "notificationBell");
            verify(launcher.adaptivePalette !== null);
            verify(bell.adaptivePalette !== null);
            bar.mediaData = {playing: true, title: "Track", levels: [0.5]};
            let media = findChild(bar, "mediaSlot");
            tryCompare(media, "active", true);
            verify(media.item.adaptivePalette !== null);
            grabImage(bar).save("/tmp/quickshell-wallpaper-regions.png");
        }
        function test_lightGlyphsKeepTheirHueAndContrast() {
            let samples = [Qt.color("#000000"), Qt.color("#ffffff"), Qt.color("#808080"), Qt.color("#ff0000"), Qt.color("#0000ff")];
            let accents = [Qt.color("#ff6575"), Qt.color("#54e3da"), Qt.color("#86a6ff"), Qt.color("#343650")];
            for (let sample of samples) for (let accent of accents) {
                for (let style of ["light", "light-normal", "light-emphasized", "light-muted"]) {
                    let palette = Colors.palette(sample, accent, Qt.color("#000000"), Qt.color("#ffffff"), style);
                    verify(palette.foreground.hslLightness >= 0.69);
                    for (let fill of [palette.tint, palette.hover, palette.selected]) for (let under of samples) {
                        let composite = Colors.mix(under, fill, fill.a);
                        verify(Colors.contrast(palette.foreground, Colors.mix(composite, Qt.color("#ffffff"), 0.08)) >= 4.5);
                    }
                }
                let bare = Colors.palette(sample, accent, sample, sample, "light-bare");
                verify(bare.foreground.hslLightness >= 0.639, "Hyprpane items must stay light on every wallpaper");
                let darkest = Qt.hsla(accent.hslHue, accent.hslSaturation, 0.64, 1);
                let achievable = Math.min(4.5, Math.max(Colors.contrast(darkest, sample), Colors.contrast(Qt.color("#ffffff"), sample)) * 0.98);
                verify(Colors.contrast(bare.foreground, sample) >= achievable, "Use the strongest available contrast without darkening the item");
                fuzzyCompare(bare.foreground.hslHue, accent.hslHue, 0.01);
                fuzzyCompare(bare.foreground.hslSaturation, accent.hslSaturation, 0.01);
                compare(bare.glyphHalo, false);
                let textured = Colors.palette(sample, accent, Qt.color("#000000"), Qt.color("#ffffff"), "light-bare");
                compare(textured.glyphHalo, false);
                verify(textured.foreground.hslLightness >= 0.639);
                verify(Colors.contrast(textured.foreground, sample) >= achievable);
            }
        }
        function test_popdownPaletteFollowsWallpaperAndReachesControls() {
            let red = Colors.wallpaperPalette(Qt.color("#ee2233"), false);
            let blue = Colors.wallpaperPalette(Qt.color("#2244ee"), false);
            verify(red.background.r > red.background.b);
            verify(blue.background.b > blue.background.r);
            verify(red.accent.r > red.accent.b);
            verify(blue.accent.b > blue.accent.r);
            for (let palette of [red, blue, Colors.wallpaperPalette(Qt.color("#ffffff"), false)])
                for (let foreground of [palette.text, palette.secondary, palette.accent])
                    verify(Colors.contrast(foreground, palette.background) >= 4.5);
            let accessible = Colors.wallpaperPalette(Qt.color("#ff3344"), true);
            compare(accessible.background, Qt.color("#000000"));
            compare(accessible.text, Qt.color("#ffffff"));
            compare(accessible.accent, Qt.color("#ffffff"));
            let label = findChild(menu, "adaptiveMenuLabel"), button = findChild(menu, "adaptiveMenuButton");
            verify(label !== null && button !== null);
            fuzzyCompare(label.color, menu.menuColors.text, 0.001);
            fuzzyCompare(button.accent, menu.menuColors.text, 0.001);
            fuzzyCompare(button.hoverColor, menu.menuColors.hover, 0.001);
        }
        function test_paneGlyphsUseColorContrastWithoutOutlines() {
            let launcher = findChild(bar, "launcherTrigger");
            try {
                bar.settings = {bar:{background:"off", adaptiveColors:true}};
                compare(launcher.glyphHalo, false);
                compare(launcher.content.style, Text.Normal);
                compare(findChild(bar, "distroGlassLogo").contrastEdge, false);
                compare(findChild(bar, "settingsGlassCog").contrastEdge, false);
                for (let sample of [Qt.color("#000000"), Qt.color("#ffffff"), Qt.color("#808080")]) {
                    let ink = Colors.readableForeground(sample, Qt.color("#86a6ff"), sample, sample, 3.2);
                    verify(Colors.contrast(ink, sample) >= 3.1);
                }
                bar.mediaData = {playing:true,title:"Track",levels:[0.5]};
                let media = findChild(bar, "mediaSlot");
                tryCompare(media, "active", true);
                compare(findChild(media.item, "mediaSpectrum").contrastEdge, false);
                compare(findChild(bar, "notificationBadge").style, Text.Normal);
                bar.settings = {bar:{background:"off", adaptiveColors:true}, items:[{id:"launcher",iconColor:"#ff8800",textColor:"#00ddff"}]};
                compare(launcher.iconColor, Qt.color("#ff8800"));
                compare(launcher.textColor, Qt.color("#00ddff"));
                bar.settings = {bar:{adaptiveColors:false}};
                compare(launcher.adaptivePalette, null);
            } finally { bar.settings = {}; }
        }
    }
}
