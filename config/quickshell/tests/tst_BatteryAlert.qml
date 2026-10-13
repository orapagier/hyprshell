import QtQuick
import QtTest
import ".."

Item {
    BatteryAlert { id: alert }
    SignalSpy { id: sound; target: alert; signalName: "triggered" }
    Pill { id: indicator; icon: "B"; text: "25%"; blink: alert.low }
    TestCase {
        name: "BatteryAlerts"
        when: windowShown
        function setBattery(percent, plugged) {
            alert.info = {present: true, percentage: percent, pluggedIn: plugged};
        }
        function init() {
            alert.info = {present: false};
            sound.clear();
        }
        function test_thresholdAndSoundOnce() {
            setBattery(26, false);
            compare(alert.low, false);
            compare(sound.count, 0);
            setBattery(25, false);
            compare(alert.low, true);
            compare(sound.count, 1);
            setBattery(24, false);
            setBattery(26, false);
            setBattery(25, false);
            compare(sound.count, 1);
            setBattery(31, false);
            setBattery(23, false);
            compare(sound.count, 2);
        }
        function test_pluggingInStopsBlinkAndRearms() {
            setBattery(25, false);
            tryVerify(() => indicator.content.opacity < 0.9);
            setBattery(25, true);
            compare(alert.low, false);
            tryCompare(indicator.content, "opacity", 1);
            compare(sound.count, 1);
            setBattery(24, false);
            compare(sound.count, 2);
        }
        function test_initialLowReadingAndMissingBattery() {
            setBattery(15, false);
            compare(sound.count, 1);
            alert.update();
            compare(sound.count, 1);
            alert.info = {present: false, percentage: 0, pluggedIn: false};
            compare(alert.low, false);
            alert.info = {present: true, percentage: NaN, pluggedIn: false};
            compare(alert.low, false);
            compare(sound.count, 1);
        }
    }
}
