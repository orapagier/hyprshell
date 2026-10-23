pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "AdaptiveColors.js" as Colors
import "style" as Style

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
    readonly property var upcomingHours: {
        const hourly = snapshot.weather?.hourly || ({});
        if (!current.time) return [];
        return (hourly.time || []).map((time, index) => ({
            time: time, temperature: hourly.temperature_2m?.[index],
            rain: hourly.precipitation_probability?.[index]
        })).filter(hour => hour.time > current.time).slice(0, 3);
    }
    readonly property bool busy: worker.running
    property string operation: "weather"
    property bool reloadAfterSave: false
    readonly property bool choosingCity: editing || snapshot.needsLocation === true
    readonly property var locationParts: (snapshot.location?.name || "").split(",").map(part => part.trim())
    radius: 22
    gradient: Gradient {
        GradientStop { position: 0; color: Style.Theme.highContrast ? card.cardColor : Colors.mix(card.cardColor, card.accentColor, 0.045) }
        GradientStop { position: 1; color: card.cardColor }
    }
    border.width: 1; border.color: Colors.alpha(textColor, Style.Theme.highContrast ? 1 : 0.08)
    implicitWidth: 340
    implicitHeight: details.implicitHeight + 48
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
        anchors.fill: parent; anchors.margins: 24; spacing: 0
        RowLayout {
            Layout.fillWidth: true; spacing: 12
            Label {
                objectName: "weatherLocation"
                text: card.locationParts[0] || "Your local weather"
                Accessible.name: card.snapshot.location?.name || text
                font.pixelSize: 24; font.weight: Font.DemiBold
                Layout.fillWidth: true
                Accessible.description: "Weather by Open-Meteo. Location data by GeoNames."
                ToolTip.visible: sourceHover.containsMouse
                ToolTip.text: "Weather: Open-Meteo · Location: GeoNames"
                MouseArea {
                    id: sourceHover
                    anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                    onClicked: Qt.openUrlExternally("https://open-meteo.com/")
                }
            }
            Action {
                objectName: "weatherChangeCity"
                text: card.editing ? "\u{f00d}" : "\u{f040}"
                font.family: "GoMono Nerd Font"; font.pixelSize: 16
                implicitWidth: 34; leftPadding: 0; rightPadding: 0
                contentItem: Text { text: parent.text; font: parent.font; color: card.textColor; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                Accessible.name: card.editing ? "Cancel city edit" : "Change city"
                ToolTip.visible: hovered
                ToolTip.text: Accessible.name
                onClicked: { card.editing = !card.editing; if (card.editing) city.forceActiveFocus(); }
            }
        }
        Label {
            visible: card.locationParts.length > 1 || !card.snapshot.location
            text: card.locationParts.slice(1).join(" · ").replace(/^Province of /, "") || "Choose a city or municipality to get started"
            color: card.secondaryColor; font.pixelSize: 11; lineHeight: 1.3
            Layout.topMargin: 5; Layout.fillWidth: true
        }
        ColumnLayout {
            visible: card.choosingCity
            Layout.topMargin: 22; Layout.fillWidth: true; spacing: 12
            TextField {
                id: city
                objectName: "weatherCitySearch"
                Layout.fillWidth: true; implicitHeight: 42
                placeholderText: "Search city or municipality"
                color: card.textColor; placeholderTextColor: card.secondaryColor
                font.family: "DejaVu Sans"; font.pixelSize: 13
                leftPadding: 12; rightPadding: 12; maximumLength: 120
                selectionColor: card.accentColor; selectedTextColor: card.cardColor
                onAccepted: if (searchButton.enabled) searchButton.clicked()
                background: Rectangle { color: Colors.alpha(card.accentColor, 0.06); radius: 12; border.color: city.activeFocus ? card.accentColor : Colors.alpha(card.textColor, 0.12) }
            }
            RowLayout {
                Layout.fillWidth: true; spacing: 8
                Action { text: card.philippinesOnly ? "Philippines" : "Worldwide"; visible: !card.manual; onClicked: { card.philippinesOnly = !card.philippinesOnly; card.results = []; } }
                Action { text: card.manual ? "Name search" : "Coordinates"; Layout.fillWidth: true; onClicked: { card.manual = !card.manual; card.message = ""; card.results = []; } }
            }
            RowLayout {
                visible: card.manual; Layout.fillWidth: true; spacing: 8
                TextField {
                    id: latitude; objectName: "weatherLatitude"; Layout.fillWidth: true; Layout.minimumWidth: 0; implicitHeight: 42
                    placeholderText: "Latitude"; color: card.textColor; placeholderTextColor: card.secondaryColor
                    font.pixelSize: 12; leftPadding: 12
                    validator: DoubleValidator { bottom: -90; top: 90; locale: "C" }
                    background: Rectangle { color: Colors.alpha(card.accentColor, 0.06); radius: 12; border.color: latitude.activeFocus ? card.accentColor : Colors.alpha(card.textColor, 0.12) }
                }
                TextField {
                    id: longitude; objectName: "weatherLongitude"; Layout.fillWidth: true; Layout.minimumWidth: 0; implicitHeight: 42
                    placeholderText: "Longitude"; color: card.textColor; placeholderTextColor: card.secondaryColor
                    font.pixelSize: 12; leftPadding: 12
                    validator: DoubleValidator { bottom: -180; top: 180; locale: "C" }
                    background: Rectangle { color: Colors.alpha(card.accentColor, 0.06); radius: 12; border.color: longitude.activeFocus ? card.accentColor : Colors.alpha(card.textColor, 0.12) }
                }
            }
            Action {
                id: searchButton
                objectName: "weatherSearchButton"
                text: card.busy ? "Please wait…" : card.manual ? "Use this location" : "Find location"
                fillColor: Colors.alpha(card.accentColor, 0.16)
                Layout.fillWidth: true
                enabled: !card.busy && city.text.trim().length >= 2 && (!card.manual || (latitude.acceptableInput && longitude.acceptableInput && latitude.text.length > 0 && longitude.text.length > 0))
                onClicked: card.manual ? card.selectLocation({name: city.text, latitude: Number(latitude.text), longitude: Number(longitude.text)}) : card.search()
            }
            Label { text: card.message; visible: text.length > 0; color: card.secondaryColor; font.pixelSize: 12; Layout.fillWidth: true }
            ScrollView {
                visible: card.results.length > 0
                Layout.fillWidth: true; Layout.preferredHeight: Math.min(180, choices.implicitHeight)
                clip: true; contentWidth: availableWidth
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                ColumnLayout {
                    id: choices; width: parent.width; spacing: 6
                    Repeater {
                        model: card.results
                        delegate: Action {
                            id: choice
                            required property var modelData
                            required property int index
                            objectName: "weatherResult-" + index
                            text: modelData.name; Layout.fillWidth: true
                            contentItem: Text { text: choice.text; color: choice.enabled ? card.textColor : card.secondaryColor; font.family: "DejaVu Sans"; font.pixelSize: 12; wrapMode: Text.Wrap; lineHeight: 1.3 }
                            implicitHeight: contentItem.implicitHeight + 24
                            enabled: !card.busy
                            onClicked: card.selectLocation(modelData)
                        }
                    }
                }
            }
        }
        Rectangle {
            objectName: "weatherCurrentConditions"
            visible: !card.choosingCity
            Layout.topMargin: 22; Layout.fillWidth: true
            implicitHeight: currentDetails.implicitHeight + 32
            color: Colors.alpha(card.accentColor, Style.Theme.highContrast ? 0 : 0.04); radius: 16
            border.width: Style.Theme.highContrast ? 1 : 0; border.color: card.textColor
            ColumnLayout {
                id: currentDetails
                anchors.fill: parent; anchors.margins: 16; spacing: 0
                ColumnLayout {
                    visible: card.snapshot.weather === undefined
                    Layout.fillWidth: true; spacing: 12
                    WeatherGlyph { code: 3; cloudColor: card.textColor; accentColor: card.accentColor; opacity: 0.45; Layout.preferredWidth: 76; Layout.preferredHeight: 68 }
                    Label { text: card.busy ? "Getting the forecast…" : "Weather unavailable"; font.pixelSize: 18; font.weight: Font.Medium; Layout.fillWidth: true }
                    Label { text: card.snapshot.error || "Your weather will appear here."; color: card.secondaryColor; font.pixelSize: 12; Layout.fillWidth: true }
                }
                RowLayout {
                    visible: card.snapshot.weather !== undefined && !card.choosingCity
                    Layout.fillWidth: true; spacing: 8
                    ColumnLayout {
                        Layout.fillWidth: true; spacing: 0
                        RowLayout {
                            spacing: 2
                            Label {
                                objectName: "weatherTemperature"
                                text: card.number(card.current.temperature_2m, "")
                                font.pixelSize: card.width < 320 ? 60 : 72; font.weight: Font.Light; font.letterSpacing: -3
                            }
                            Label { text: "°C"; font.pixelSize: 22; color: card.secondaryColor; Layout.alignment: Qt.AlignTop; Layout.topMargin: 14 }
                        }
                        Label { text: card.condition(card.current.weather_code); font.pixelSize: 16; font.weight: Font.Medium; Layout.fillWidth: true }
                    }
                    WeatherGlyph {
                        code: card.current.weather_code === undefined ? 3 : card.current.weather_code
                        daylight: !card.current.time || !card.daily.sunrise?.[0] || (card.current.time >= card.daily.sunrise[0] && card.current.time < card.daily.sunset[0])
                        cloudColor: card.textColor; accentColor: card.accentColor
                        Layout.preferredWidth: card.width < 320 ? 76 : 112
                        Layout.preferredHeight: card.width < 320 ? 76 : 100
                    }
                }
                RowLayout {
                    visible: card.snapshot.weather !== undefined && !card.choosingCity
                    Layout.topMargin: 12; Layout.fillWidth: true; spacing: 8
                    Label { text: "Feels like " + card.number(card.current.apparent_temperature, "°"); color: card.secondaryColor; font.pixelSize: 12; Layout.fillWidth: true }
                    Label { text: "High " + card.number(card.daily.temperature_2m_max?.[0], "°") + "  Low " + card.number(card.daily.temperature_2m_min?.[0], "°"); font.pixelSize: 11; color: card.secondaryColor }
                }
            }
        }
        Rectangle {
            objectName: "weatherMetrics"
            visible: card.snapshot.weather !== undefined && !card.choosingCity
            Layout.topMargin: 14; Layout.fillWidth: true
            implicitHeight: metrics.implicitHeight + 32
            color: Colors.alpha(card.accentColor, Style.Theme.highContrast ? 0 : 0.04); radius: 16
            border.width: Style.Theme.highContrast ? 1 : 0; border.color: card.textColor
            GridLayout {
                id: metrics
                anchors.fill: parent; anchors.margins: 16
                columns: 2; columnSpacing: 16; rowSpacing: 22
                Metric { title: "Rain chance"; value: card.number(card.daily.precipitation_probability_max?.[0], "%"); detail: card.number(card.current.precipitation, " mm", 1) + " / " + Math.round((card.current.interval || 900) / 60) + " min" }
                Metric { title: "Humidity"; value: card.number(card.current.relative_humidity_2m, "%") }
                Metric { title: "Wind"; value: card.number(card.current.wind_speed_10m, " km/h"); detail: "Gusts " + card.number(card.current.wind_gusts_10m, " km/h") }
                Metric { title: "Sunrise"; value: card.sun(card.daily.sunrise?.[0]); detail: "Sunset " + card.sun(card.daily.sunset?.[0]) + " · local" }
            }
        }
        Rectangle {
            objectName: "weatherHourlyForecast"
            visible: card.upcomingHours.length > 0 && !card.choosingCity
            Layout.topMargin: 14; Layout.fillWidth: true
            implicitHeight: hourlyDetails.implicitHeight + 32
            color: Colors.alpha(card.accentColor, Style.Theme.highContrast ? 0 : 0.04); radius: 16
            border.width: Style.Theme.highContrast ? 1 : 0; border.color: card.textColor
            ColumnLayout {
                id: hourlyDetails
                anchors.fill: parent; anchors.margins: 16; spacing: 10
                RowLayout {
                    Layout.fillWidth: true
                    Label { text: card.snapshot.stale ? "SAVED FORECAST" : "NEXT 3 HOURS"; color: card.secondaryColor; font.pixelSize: 10; font.letterSpacing: 1.2; Layout.fillWidth: true }
                    Label { text: "Temp · Rain"; color: card.secondaryColor; font.pixelSize: 10 }
                }
                RowLayout {
                    Layout.fillWidth: true; spacing: 12
                    Repeater {
                        model: card.upcomingHours
                        delegate: ColumnLayout {
                            id: hour
                            required property var modelData
                            required property int index
                            objectName: "weatherHour-" + index
                            Layout.fillWidth: true; Layout.minimumWidth: 0; spacing: 5
                            Label { text: card.sun(hour.modelData.time); color: card.secondaryColor; font.pixelSize: 11; Layout.fillWidth: true }
                            Label {
                                text: card.number(hour.modelData.temperature, "°") + " · " + card.number(hour.modelData.rain, "%")
                                font.pixelSize: card.width < 320 ? 12 : 14; font.weight: Font.Medium; Layout.fillWidth: true
                                Accessible.name: card.sun(hour.modelData.time) + ", " + card.number(hour.modelData.temperature, " degrees Celsius") + ", rain chance " + card.number(hour.modelData.rain, "%")
                            }
                        }
                    }
                }
            }
        }
        Label { text: card.snapshot.error || card.snapshot.warning || (card.busy && card.operation === "weather" ? "Updating weather…" : ""); visible: text.length > 0 && card.snapshot.weather !== undefined; color: card.secondaryColor; font.pixelSize: 11; Layout.fillWidth: true; Layout.topMargin: visible ? 8 : 0 }
        Item { Layout.fillHeight: true }
    }
    component Label: MenuLabel { color: card.textColor }
    component Metric: ColumnLayout {
        id: metric
        property string title
        property string value
        property string detail: ""
        Layout.fillWidth: true; Layout.minimumWidth: 0; Layout.alignment: Qt.AlignTop
        spacing: 5
        Label { text: metric.title; color: card.secondaryColor; font.pixelSize: 11; Layout.fillWidth: true }
        Label { text: metric.value; font.pixelSize: 20; font.weight: Font.Medium; Layout.fillWidth: true }
        Label { text: metric.detail; visible: text.length > 0; color: card.secondaryColor; font.pixelSize: 10; Layout.fillWidth: true }
    }
    component Action: MenuButton {
        id: action
        accent: card.textColor; font.pixelSize: 11
        fillColor: Colors.alpha(card.accentColor, 0.07); hoverColor: Colors.alpha(card.accentColor, 0.16)
        pressedColor: Colors.alpha(card.accentColor, 0.22)
        outlineColor: Style.Theme.highContrast ? card.textColor : "transparent"; focusColor: card.accentColor
        implicitHeight: 34; leftPadding: 12; rightPadding: 12; topPadding: 8; bottomPadding: 8
        background: Rectangle {
            radius: 12
            color: action.down ? action.pressedColor : action.hovered || action.activeFocus ? action.hoverColor : action.fillColor
            border.width: 1; border.color: action.activeFocus ? card.accentColor : action.outlineColor
            Behavior on color { ColorAnimation { duration: Style.Theme.duration(card, 140) } }
        }
    }
}
