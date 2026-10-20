pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "AdaptiveColors.js" as Colors

Rectangle {
    id: card
    objectName: "dashboardWeather"
    property bool active: false
    property color textColor: "#cdd6f4"
    property color secondaryColor: "#a6adc8"
    property color accentColor: "#b4befe"
    property color cardColor: "#11111b"
    property color outlineColor: "#45475a"
    property string helperProgram: decodeURIComponent(Qt.resolvedUrl("helpers/hyprweather").toString().replace(/^file:\/\//, ""))
    property var snapshot: ({})
    property var results: []
    property string message: ""
    property bool editing: false
    property bool manual: false
    property bool philippinesOnly: true
    readonly property var current: snapshot.weather?.current || ({})
    readonly property var daily: snapshot.weather?.daily || ({})
    readonly property bool busy: worker.running
    property string operation: "weather"
    property bool reloadAfterSave: false
    radius: 16
    color: cardColor
    border.width: 1; border.color: outlineColor
    implicitWidth: 250
    implicitHeight: details.implicitHeight + 32
    function refresh() {
        if (worker.running) return;
        operation = "weather";
        worker.command = [helperProgram, "weather"];
        worker.running = true;
    }
    function search() {
        if (busy) return;
        message = "Searching…"; results = [];
        operation = "search";
        worker.command = [helperProgram, "search", city.text, philippinesOnly ? "PH" : ""];
        worker.running = true;
    }
    function selectLocation(location) {
        if (busy) return;
        operation = "select";
        worker.command = [helperProgram, "select", JSON.stringify(location)];
        worker.running = true;
    }
    function number(value, unit, decimals) {
        return typeof value === "number" ? value.toFixed(decimals || 0) + unit : "—";
    }
    function sun(value) { return value ? value.substring(11, 16) : "—"; }
    function condition(code) {
        if (code === 0) return "Clear sky";
        if (code === 1) return "Mostly clear";
        if (code === 2) return "Partly cloudy";
        if (code === 3) return "Overcast";
        if ([45,48].includes(code)) return "Fog";
        if ([51,53,55,56,57].includes(code)) return "Drizzle";
        if ([61,63,65,66,67].includes(code)) return "Rain";
        if ([71,73,75,77,85,86].includes(code)) return "Snow";
        if ([80,81,82].includes(code)) return "Rain showers";
        if ([95,96,99].includes(code)) return "Thunderstorm";
        return "Conditions unavailable";
    }
    onActiveChanged: if (active) refresh()
    Component.onCompleted: if (active) refresh()
    Process {
        id: worker
        stdout: SplitParser {
            onRead: line => {
                try {
                    const data = JSON.parse(line);
                    if (card.operation === "search") {
                        card.results = data.results || [];
                        card.message = data.error || (card.results.length ? "Choose the matching place:" : "No matches. Try another spelling or coordinates.");
                    } else if (card.operation === "select") {
                        if (data.saved) {
                            card.snapshot = {location: data.location}; card.editing = false;
                            card.results = []; card.message = "";
                            card.reloadAfterSave = true;
                        } else card.message = data.error || "Could not save location";
                    } else card.snapshot = data;
                } catch (error) { card.message = "Could not read weather information"; }
            }
        }
        stderr: StdioCollector {}
        onExited: (exitCode, exitStatus) => {
            if (card.operation === "select" && card.reloadAfterSave) {
                card.reloadAfterSave = false;
                Qt.callLater(card.refresh);
            }
            else if (exitCode !== 0 && card.operation === "weather" && !card.snapshot.error)
                card.snapshot = {error: "Weather helper unavailable"};
        }
    }
    ColumnLayout {
        id: details
        anchors.fill: parent; anchors.margins: 16; spacing: 6
        RowLayout {
            Layout.fillWidth: true
            Label { text: "WEATHER"; color: card.secondaryColor; font.pixelSize: 12; font.letterSpacing: 2; Layout.fillWidth: true }
            Action { objectName: "weatherChangeCity"; text: card.editing ? "Done" : "City"; onClicked: card.editing = !card.editing }
        }
        Label {
            objectName: "weatherLocation"
            text: card.snapshot.location?.name || "Choose your city or municipality"
            font.weight: Font.DemiBold; Layout.fillWidth: true; wrapMode: Text.Wrap
        }
        ColumnLayout {
            visible: card.editing || card.snapshot.needsLocation === true
            Layout.fillWidth: true; spacing: 6
            TextField {
                id: city
                objectName: "weatherCitySearch"
                Layout.fillWidth: true
                placeholderText: "City / municipality name"
                color: card.textColor; placeholderTextColor: card.secondaryColor
                font.family: "DejaVu Sans"; font.pixelSize: 13
                maximumLength: 120
                onAccepted: if (searchButton.enabled) searchButton.clicked()
                background: Rectangle { color: Colors.alpha(card.accentColor, 0.06); radius: 8; border.color: card.outlineColor }
            }
            RowLayout {
                Layout.fillWidth: true
                Action { text: card.philippinesOnly ? "Philippines" : "Worldwide"; visible: !card.manual; onClicked: { card.philippinesOnly = !card.philippinesOnly; card.results = []; } }
                Action { text: card.manual ? "Name search" : "Coordinates"; Layout.fillWidth: true; onClicked: { card.manual = !card.manual; card.message = ""; card.results = []; } }
            }
            RowLayout {
                visible: card.manual; Layout.fillWidth: true
                TextField {
                    id: latitude; objectName: "weatherLatitude"; Layout.fillWidth: true
                    placeholderText: "Latitude"; color: card.textColor; placeholderTextColor: card.secondaryColor
                    validator: DoubleValidator { bottom: -90; top: 90; locale: "C" }
                    background: Rectangle { color: Colors.alpha(card.accentColor, 0.06); radius: 8; border.color: card.outlineColor }
                }
                TextField {
                    id: longitude; objectName: "weatherLongitude"; Layout.fillWidth: true
                    placeholderText: "Longitude"; color: card.textColor; placeholderTextColor: card.secondaryColor
                    validator: DoubleValidator { bottom: -180; top: 180; locale: "C" }
                    background: Rectangle { color: Colors.alpha(card.accentColor, 0.06); radius: 8; border.color: card.outlineColor }
                }
            }
            Action {
                id: searchButton
                objectName: "weatherSearchButton"
                text: card.busy ? "Please wait…" : card.manual ? "Use coordinates" : "Search"
                Layout.fillWidth: true
                enabled: !card.busy && city.text.trim().length >= 2 && (!card.manual || (latitude.acceptableInput && longitude.acceptableInput && latitude.text.length > 0 && longitude.text.length > 0))
                onClicked: card.manual ? card.selectLocation({name: city.text, latitude: Number(latitude.text), longitude: Number(longitude.text)}) : card.search()
            }
            Label { text: card.message; visible: text.length > 0; color: card.secondaryColor; Layout.fillWidth: true }
            ScrollView {
                visible: card.results.length > 0
                Layout.fillWidth: true; Layout.preferredHeight: Math.min(150, choices.implicitHeight)
                clip: true; contentWidth: availableWidth
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                ColumnLayout {
                    id: choices; width: parent.width; spacing: 4
                    Repeater {
                        model: card.results
                        delegate: Action {
                            required property var modelData
                            required property int index
                            objectName: "weatherResult-" + index
                            text: modelData.name; Layout.fillWidth: true
                            contentItem: Text { text: parent.text; color: card.textColor; font.pixelSize: 12; wrapMode: Text.Wrap }
                            implicitHeight: contentItem.implicitHeight + 12
                            enabled: !card.busy
                            onClicked: card.selectLocation(modelData)
                        }
                    }
                }
            }
        }
        Label {
            objectName: "weatherTemperature"
            visible: card.snapshot.weather !== undefined
            text: card.number(card.current.temperature_2m, "°C") + " · " + card.condition(card.current.weather_code)
            font.pixelSize: 22; font.weight: Font.DemiBold; Layout.fillWidth: true
        }
        Label { visible: card.snapshot.weather !== undefined; text: "Feels like " + card.number(card.current.apparent_temperature, "°C") + " · Humidity " + card.number(card.current.relative_humidity_2m, "%"); Layout.fillWidth: true }
        Label { visible: card.snapshot.weather !== undefined; text: "Today · High " + card.number(card.daily.temperature_2m_max?.[0], "°") + " / Low " + card.number(card.daily.temperature_2m_min?.[0], "°") + " · Rain chance " + card.number(card.daily.precipitation_probability_max?.[0], "%"); Layout.fillWidth: true }
        Label { visible: card.snapshot.weather !== undefined; text: "Rainfall " + card.number(card.current.precipitation, " mm", 1) + " (" + Math.round((card.current.interval || 900) / 60) + " min)"; Layout.fillWidth: true }
        Label { visible: card.snapshot.weather !== undefined; text: "Wind " + card.number(card.current.wind_speed_10m, " km/h") + " · Gusts " + card.number(card.current.wind_gusts_10m, " km/h"); Layout.fillWidth: true }
        Label { visible: card.snapshot.weather !== undefined; text: "Sunrise " + card.sun(card.daily.sunrise?.[0]) + " · Sunset " + card.sun(card.daily.sunset?.[0]) + " (local)"; Layout.fillWidth: true }
        Label {
            objectName: "weatherUpdated"
            visible: card.snapshot.fetchedAt !== undefined
            text: (card.snapshot.stale ? "Cached data · " : "Data · ") + (card.snapshot.weather?.current?.time || "").replace("T", " ") + " " + (card.snapshot.weather?.timezone_abbreviation || "")
            color: card.secondaryColor; font.pixelSize: 11; Layout.fillWidth: true
        }
        Label { text: card.snapshot.error || card.snapshot.warning || (card.busy && card.operation === "weather" ? "Updating weather…" : ""); visible: text.length > 0; color: card.secondaryColor; Layout.fillWidth: true }
        Label {
            text: "Open-Meteo · GeoNames"; font.pixelSize: 11; color: card.secondaryColor; Layout.fillWidth: true
            MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: Qt.openUrlExternally("https://open-meteo.com/") }
        }
    }
    component Label: MenuLabel { color: card.textColor }
    component Action: MenuButton {
        accent: card.accentColor
        fillColor: Colors.alpha(card.accentColor, 0.06); hoverColor: Colors.alpha(card.accentColor, 0.14)
        pressedColor: Colors.alpha(card.accentColor, 0.20); outlineColor: card.outlineColor; focusColor: card.accentColor
        implicitHeight: 30; topPadding: 5; bottomPadding: 5
    }
}
