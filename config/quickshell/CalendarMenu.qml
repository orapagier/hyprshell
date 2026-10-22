pragma ComponentBehavior: Bound
import QtQuick
import "AdaptiveColors.js" as Colors
import "style" as Style
import QtQuick.Controls
import QtQuick.Layouts
import "Calendar.js" as Calendar

ColumnLayout {
    id: page
    readonly property var menuColors: Colors.menuColorsFor(page)
    property bool adaptivePalette: true
    property color textColor: menuColors.text
    property color secondaryColor: menuColors.secondary
    property color accentColor: menuColors.accent
    property color surfaceColor: menuColors.background
    property date now: new Date()
    property date today: now
    property int year: today.getFullYear()
    property int month: today.getMonth()
    property date selected: today
    readonly property var holidays: Calendar.holidays(year)
    readonly property int offset: new Date(year, month, 1).getDay()
    readonly property int days: new Date(year, month + 1, 0).getDate()
    readonly property var holiday: holidays[(selected.getMonth()+1) + "-" + selected.getDate()]
    spacing: 8
    component CalendarButton: MenuButton {
        accent: page.textColor
        hoverColor: page.adaptivePalette ? Qt.rgba(page.accentColor.r, page.accentColor.g, page.accentColor.b, 0.16) : "#38cba6f7"
        pressedColor: page.adaptivePalette ? Qt.rgba(page.accentColor.r, page.accentColor.g, page.accentColor.b, 0.22) : "#55cba6f7"
        focusColor: page.adaptivePalette ? page.accentColor : "#88cba6f7"
    }
    function shift(amount) { let date = new Date(year, month + amount, 1); year = date.getFullYear(); month = date.getMonth(); selected = date; }
    Timer {
        interval: 1000
        running: page.visible
        repeat: true
        onTriggered: page.now = new Date()
    }
    ColumnLayout {
        Layout.fillWidth: true
        Layout.topMargin: 2
        Layout.bottomMargin: 6
        spacing: 2
        MenuLabel {
            objectName: "calendarTime"
            text: Qt.formatTime(page.now, "hh:mm AP")
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: 28
            font.bold: true
            color: page.textColor
        }
        MenuLabel {
            text: Qt.formatDate(page.now, "dddd, MMMM d")
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: 11
            color: page.secondaryColor
        }
    }
    RowLayout {
        Layout.fillWidth: true
        CalendarButton { text: "‹"; onClicked: page.shift(-1) }
        CalendarButton { text: Qt.formatDate(new Date(page.year,page.month,1), "MMMM yyyy"); Layout.fillWidth: true; accent: page.accentColor; onClicked: picker.visible = !picker.visible }
        CalendarButton { text: "›"; onClicked: page.shift(1) }
    }
    RowLayout {
        id: picker
        visible: false; Layout.fillWidth: true
        ComboBox {
            id: months
            model: ["January","February","March","April","May","June","July","August","September","October","November","December"]
            currentIndex: page.month; Layout.fillWidth: true
            onActivated: page.month = currentIndex
            palette.text: page.textColor; palette.buttonText: page.textColor; palette.button: (page.adaptivePalette ? Qt.lighter(page.surfaceColor, 1.3) : "#38384d"); palette.base: page.surfaceColor; palette.highlight: page.adaptivePalette ? Qt.rgba(page.accentColor.r, page.accentColor.g, page.accentColor.b, 0.20) : "#66517e"; palette.highlightedText: page.textColor
        }
        SpinBox {
            from: 1900; to: 9999; value: page.year; editable: true
            onValueModified: page.year = value
            palette.text: page.textColor; palette.buttonText: page.textColor; palette.button: (page.adaptivePalette ? Qt.lighter(page.surfaceColor, 1.3) : "#38384d"); palette.base: page.surfaceColor
        }
    }
    GridLayout {
        columns: 7; columnSpacing: 2; rowSpacing: 2; Layout.fillWidth: true
        Repeater {
            model: ["S","M","T","W","T","F","S"]
            delegate: MenuLabel { objectName: "calendarWeekday"; required property string modelData; text: modelData; horizontalAlignment: Text.AlignHCenter; color: page.secondaryColor; Layout.fillWidth: true }
        }
        Repeater {
            model: 42
            delegate: CalendarButton {
                id: day
                required property int index
                readonly property int number: index - page.offset + 1
                readonly property var holiday: page.holidays[(page.month+1) + "-" + number]
                readonly property bool selected: page.selected.getFullYear() === page.year && page.selected.getMonth() === page.month && page.selected.getDate() === number
                text: number > 0 && number <= page.days ? String(number) : ""
                enabled: text.length > 0
                implicitHeight: 28; implicitWidth: 28
                leftPadding: 2; rightPadding: 2; topPadding: 3; bottomPadding: 3
                Layout.fillWidth: true
                accent: holiday ? holiday[1] === "regular" ? "#f38ba8" : "#f9e2af" : page.textColor
                contentItem: Text { text: day.text; font: day.font; color: day.accent; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                background: Rectangle {
                    Behavior on color { ColorAnimation { duration: Style.Theme.duration(day, Style.Theme.hoverDuration); easing.type: Easing.BezierSpline; easing.bezierCurve: Style.Theme.effectsCurve } }
                    radius: 8
                    color: day.selected || day.hovered ? (page.adaptivePalette ? Qt.rgba(page.accentColor.r, page.accentColor.g, page.accentColor.b, 0.16) : "#38cba6f7") : day.holiday ? day.holiday[1] === "regular" ? "#1ff38ba8" : "#1ff9e2af" : "transparent"
                    border.width: page.today.getFullYear() === page.year && page.today.getMonth() === page.month && page.today.getDate() === day.number ? 1 : 0
                    border.color: page.accentColor
                }
                onClicked: page.selected = new Date(page.year,page.month,number)
            }
        }
    }
    MenuLabel { text: page.holiday ? page.holiday[0] + "\n" + ({regular: "Regular Holiday", special: "Special Non-Working Day", working: "Special Working Day"})[page.holiday[1]] : ""; visible: text.length > 0; Layout.fillWidth: true; color: "#f9e2af" }
    CalendarButton { text: "Today"; Layout.fillWidth: true; onClicked: { page.year = page.today.getFullYear(); page.month = page.today.getMonth(); page.selected = page.today; } }
}
