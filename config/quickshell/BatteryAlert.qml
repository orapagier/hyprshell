import QtQuick

QtObject {
    id: alert
    property var info: ({})
    readonly property bool low: isLow(info)
    property bool notified: false
    signal triggered()

    function isLow(reading) {
        return reading.present === true && reading.pluggedIn === false
            && Number.isFinite(reading.percentage) && reading.percentage <= 25;
    }

    function update() {
        // Allow small percentage fluctuations without sounding repeatedly.
        if (!info.present || info.pluggedIn || info.percentage > 30)
            notified = false;
        if (isLow(info) && !notified) {
            notified = true;
            triggered();
        }
    }
    onInfoChanged: update()
    Component.onCompleted: update()
}
