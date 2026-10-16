import QtQuick
import QtTest
import ".."

Item {
    width: 320; height: 520
    CalendarMenu { id: calendar; width: parent.width }
    TestCase {
        name: "CalendarMenu"
        when: windowShown
        function test_sundayFirstMonthAlignment() {
            compare(findChild(calendar,'calendarWeekday').text,'S');
            // March starts on Sunday; June starts on Monday, August on Saturday.
            for (let entry of [{month:2,offset:0}, {month:5,offset:1}, {month:7,offset:6}]) {
                calendar.year = 2026;
                calendar.month = entry.month;
                compare(calendar.offset,entry.offset);
            }
        }
        function test_clockUpdatesWithoutChangingBrowsedMonthOrSelection() {
            calendar.year = 2025;
            calendar.month = 11;
            calendar.selected = new Date(2025,11,25);
            let clock = findChild(calendar,'calendarTime');
            calendar.now = new Date(2026,9,16,11,59);
            compare(clock.text,'11:59 AM');
            calendar.now = new Date(2026,9,16,12,0);
            compare(clock.text,'12:00 PM');
            compare(calendar.year,2025);
            compare(calendar.month,11);
            compare(calendar.selected.getDate(),25);
        }
    }
}
