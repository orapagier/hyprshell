import QtQuick
import QtTest
import ".."

Item {
    id: scene
    MediaActivity { id: activity }
    TestCase {
        name: "MediaActivity"
        when: windowShown
        function cleanup() {
            activity.hasPlayer = false;
            activity.hasStream = false;
            activity.peak = 0;
            activity.fullTitle = "Audio playing";
            findChild(activity, "mediaSilenceHold").stop();
        }
        function test_idleHasNoRepeatingWakeups() {
            let timer = findChild(activity, "mediaMarqueeTimer");
            compare(activity.playing, false);
            compare(timer.running, false);
            compare(activity.marquee, "");
            wait(1100);
            compare(timer.running, false);
        }
        function test_mprisDoesNotNeedAnAudiblePeak() {
            activity.hasPlayer = true;
            activity.fullTitle = "Quiet song";
            compare(activity.playing, true);
            compare(activity.marquee, "Quiet song");
            compare(findChild(activity, "mediaMarqueeTimer").running, false);
            wait(1000);
            compare(activity.playing, true);
            activity.hasPlayer = false;
            compare(activity.playing, false);
            compare(activity.marquee, "");
        }
        function test_nonMprisSteadyPeakAndSilenceGrace() {
            activity.hasStream = true;
            compare(activity.playing, false);
            activity.peak = 0.5;
            compare(activity.playing, true);
            wait(1100);
            compare(activity.playing, true);
            activity.peak = 0;
            wait(400);
            compare(activity.playing, true);
            // A new sound restarts the full grace period after it falls silent.
            activity.peak = 0.2;
            activity.peak = 0;
            wait(600);
            compare(activity.playing, true);
            tryCompare(activity, "playing", false, 500);
            compare(activity.marquee, "");
            compare(findChild(activity, "mediaSilenceHold").running, false);
        }
        function test_streamRemovalAndPlayerHandoff() {
            activity.hasStream = true;
            activity.peak = 0.4;
            activity.hasStream = false;
            compare(activity.playing, false);
            activity.hasStream = true;
            compare(activity.playing, true);
            activity.hasPlayer = true;
            activity.peak = 0;
            wait(1000);
            compare(activity.playing, true);
            activity.hasPlayer = false;
            compare(activity.playing, false);
        }
        function test_thresholdAndSinkLoss() {
            activity.hasStream = true;
            activity.peak = 0.00015;
            compare(activity.playing, false);
            activity.peak = 0.00016;
            compare(activity.playing, true);
            activity.peak = 0;
            activity.hasStream = false;
            compare(activity.playing, false);
            wait(1000);
            activity.hasStream = true;
            compare(activity.playing, false);
        }
        function test_unicodeScrollTimingAndTitleChanges() {
            let title = "🎵 Artist — A long track title with 🎸 emoji and details";
            let chars = Array.from(title);
            activity.hasPlayer = true;
            activity.fullTitle = title;
            let timer = findChild(activity, "mediaMarqueeTimer");
            compare(timer.running, true);
            // No 67 ms polling during the opening pause; each subsequent
            // wakeup is scheduled at the next visible character boundary.
            verify(timer.interval > 2000 && timer.interval <= 2300);
            compare(timer.repeat, false);
            compare(activity.marquee, chars.slice(0, 28).join(""));
            wait(400);
            compare(activity.marquee, chars.slice(0, 28).join(""));
            activity.marqueeStarted = Date.now() - 2600;
            activity.updateMarquee();
            compare(activity.marquee, chars.slice(2, 30).join(""));
            verify(timer.interval > 250 && timer.interval <= 300);
            activity.fullTitle = "Next title";
            compare(activity.marquee, "Next title");
            compare(timer.running, false);
            activity.fullTitle = title;
            compare(timer.running, true);
            compare(activity.marquee, chars.slice(0, 28).join(""));
            activity.hasPlayer = false;
            compare(timer.running, false);
            compare(activity.marquee, "");
        }
    }
}
