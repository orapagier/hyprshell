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
    }
}
