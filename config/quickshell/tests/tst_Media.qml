import QtQuick
import QtTest
import ".."
import "../PreviewModel.js" as PreviewModel

Item {
    id: scene
    width: 600; height: 70
    MediaPill { id: media; x: 10; y: 10; text: "Artist — Track title" }
    MediaState { id: state }
    Bar { id: stableBar; width: 600; mediaData: state }
    QtObject {
        id: observer
        property var data: stableBar.mediaData
        property var reads: ({playing: 0, title: 0, preview: 0})
        property bool playing: { reads.playing++; return data.playing; }
        property string title: { reads.title++; return data.title; }
        property var matchedWindow: {
            reads.preview++;
            return PreviewModel.mediaWindow([{lastIpcObject: {class: "player"}, title: "Track"}], data);
        }
    }
    TestCase {
        name: "MediaSpectrum"
        when: windowShown
        function cleanup() { media.levels = []; wait(60); }
        function test_spectrumFramesLeaveMetadataAndPreviewBindingsAlone() {
            state.playing = true; state.title = "Track";
            state.appId = "player"; state.trackTitle = "Track";
            tryVerify(() => observer.matchedWindow !== null);
            let slot = findChild(stableBar, "mediaSlot");
            tryCompare(slot, "active", true);
            observer.reads.playing = 0; observer.reads.title = 0; observer.reads.preview = 0;
            let identity = stableBar.mediaData;
            for (let frame = 0; frame < 63; ++frame)
                state.levels = Array(12).fill(frame / 63);
            compare(stableBar.mediaData, identity);
            compare(observer.reads.playing, 0);
            compare(observer.reads.title, 0);
            compare(observer.reads.preview, 0);
            compare(slot.item.levels[0], 62 / 63);
            state.title = "Next track";
            compare(observer.title, "Next track");
            verify(observer.reads.title > 0);
            state.appId = "other-player";
            compare(observer.matchedWindow, null);
            verify(observer.reads.preview > 0);
            state.playing = false;
            compare(slot.active, false);
        }
        function test_barsExpandAboveAndBelowTheirCenter() {
            let bar = findChild(media, "spectrumBar3");
            compare(bar.height, 2);
            let top = bar.y;
            let bottom = bar.y + bar.height;
            media.levels = [0,0,0,1];
            tryCompare(bar, "height", 16);
            verify(bar.y < top);
            verify(bar.y + bar.height > bottom);
            compare(bar.y + bar.height / 2, 8);
        }
        function test_frequencyBandsMoveIndependently() {
            media.levels = [0.05,0.1,0.25,0.5,0.75,1,0.8,0.6,0.4,0.2,0.1,0];
            wait(70);
            for (let index = 0; index < 12; ++index) {
                let bar = findChild(media, "spectrumBar" + index);
                fuzzyCompare(bar.height, 2 + media.levels[index] * 14, 0.01);
            }
        }
        function test_missingAndInvalidLevelsStayWithinThePill() {
            media.levels = [NaN, -2, 9, undefined];
            wait(70);
            for (let index = 0; index < 12; ++index) {
                let bar = findChild(media, "spectrumBar" + index);
                verify(bar.height >= 2 && bar.height <= 16);
                verify(bar.y >= 0 && bar.y + bar.height <= 16);
            }
        }
        function test_renderSpectrum() {
            media.levels = [0.2,0.4,0.7,0.95,0.6,0.3,0.5,0.8,0.65,0.4,0.15,0.3];
            wait(70);
            grabImage(media).save("/tmp/quickshell-media-spectrum.png");
        }
    }
}
