import QtQuick
import QtQuick.Controls.Basic
import QtTest
import ".."

Item {
    width: 820; height: 1600
    SettingsInput {
        id: page
        width: parent.width
        settings: ({})
        onEdited: (key, value) => {
            let next = Object.assign({}, settings);
            if (value === "") delete next[key]; else next[key] = value;
            settings = next;
        }
    }
    TestCase {
        name: "SettingsInput"
        when: windowShown
        function cleanup() { page.settings = {}; page.width = 820; }
        function test_openDoesNotCreateOverrides() {
            wait(20);
            compare(JSON.stringify(page.settings), "{}");
            compare(findChild(page, "keyboardLayoutsControl").currentIndex, 0);
            compare(findChild(page, "tapToClickControl").currentIndex, 0);
        }
        function test_pointerSpeedAndReset() {
            let control = findChild(page, "pointerSpeedControl");
            mouseClick(findChild(control, "sliderIncrease"));
            compare(page.settings.pointerSpeed, 0.05);
            mouseClick(findChild(control, "sliderReset"));
            compare(page.settings.pointerSpeed, undefined);
        }
        function test_customLayoutEditsReachDraftWithoutLosingFocus() {
            let field = findChild(page, "customLayouts");
            field.forceActiveFocus();
            for (let key of [Qt.Key_U, Qt.Key_S, Qt.Key_Comma, Qt.Key_G, Qt.Key_B]) keyClick(key);
            compare(page.settings.keyboardLayouts, "us,gb");
            verify(field.activeFocus);
        }
        function test_layoutsSwitchAndInheritance() {
            let layouts = findChild(page, "keyboardLayoutsControl");
            layouts.activated(6);
            compare(page.settings.keyboardLayouts, "us,ru");
            let switching = findChild(page, "layoutSwitchControl");
            switching.activated(1);
            compare(page.settings.layoutSwitch, "grp:alt_shift_toggle");
            layouts.activated(0);
            compare(page.settings.keyboardLayouts, undefined);
            switching.activated(0);
            compare(page.settings.layoutSwitch, undefined);
        }
        function test_booleanAndRepeatEditsPreserveOtherValues() {
            page.settings = {rounding: 12, repeatRate: 40, tapToClick: false};
            let tap = findChild(page, "tapToClickControl");
            compare(tap.currentIndex, 2);
            tap.activated(1);
            compare(page.settings.tapToClick, true);
            mouseClick(findChild(findChild(page, "repeatRateControl"), "sliderIncrease"));
            compare(page.settings.repeatRate, 41);
            compare(page.settings.rounding, 12);
        }
        function test_narrowLayoutFits() {
            page.width = 480; wait(30);
            for (let name of ["pointerSpeedControl", "keyboardLayoutsControl", "customLayouts", "repeatRateControl"]) {
                let control = findChild(page, name);
                let position = control.mapToItem(page, 0, 0);
                verify(position.x >= 0);
                verify(position.x + control.width <= page.width + 1);
            }
        }
    }
}
