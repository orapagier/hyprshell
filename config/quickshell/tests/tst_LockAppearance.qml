import QtQuick
import QtTest
import ".."

TestCase {
    id: test
    name: "LockAppearance"
    width: 800; height: 1000
    visible: true
    when: windowShown
    Component {
        id: pageComponent
        SettingsLocking {
            width: 760
            settings: ({command: "hyprlock", backgroundTransparency: 85,
                enabled: false, idleMinutes: 5, beforeSleep: true})
        }
    }
    SignalSpy { id: edits; signalName: "edited" }
    function test_blur_controls_save_and_preserve_strength_when_disabled() {
        let page = createTemporaryObject(pageComponent, test);
        edits.target = page;
        edits.clear();
        let passes = findChild(page, "lockBlurPasses");
        let strength = findChild(page, "lockBlurSize");
        compare(passes.settingValue, 2);
        compare(strength.settingValue, 8);
        passes.commitDisplayValue(0);
        compare(edits.signalArguments[0][0], "blurPasses");
        compare(edits.signalArguments[0][1], 0);
        page.settings = Object.assign({}, page.settings, {blurPasses: 0, blurSize: 12});
        verify(!strength.enabled);
        compare(strength.settingValue, 12);
        page.settings = Object.assign({}, page.settings, {blurPasses: 1});
        verify(strength.enabled);
        strength.commitDisplayValue(15);
        compare(edits.signalArguments[1][0], "blurSize");
        compare(edits.signalArguments[1][1], 15);
        page.settings = Object.assign({}, page.settings, {command: "hyprlock --config /custom.conf"});
        verify(!passes.enabled);
        verify(!strength.enabled);
        edits.clear();
    }
    function test_slider_saves_transparency_and_preserves_command() {
        let page = createTemporaryObject(pageComponent, test);
        edits.target = page;
        let slider = findChild(page, "lockBackgroundTransparency");
        verify(slider !== null);
        compare(slider.settingValue, 85);
        slider.commitDisplayValue(92);
        compare(edits.count, 1);
        compare(edits.signalArguments[0][0], "backgroundTransparency");
        compare(edits.signalArguments[0][1], 92);
        compare(page.settings.command, "hyprlock");
        page.settings = {command:"hyprlock --config /custom.conf", backgroundTransparency:85,
            enabled:false, idleMinutes:5, beforeSleep:true};
        compare(slider.enabled, false);
        edits.clear();
    }
}
