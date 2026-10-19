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
