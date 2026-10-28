import QtQuick
import "style" as Style
import QtQuick.Controls.Basic
import QtQuick.Layouts

ColumnLayout {
    id: root
    required property string label
    property string description: ""
    property var settingValue: undefined
    property real defaultValue: 0
    property real from: 0
    property real to: 100
    property real stepSize: 1
    property string suffix: ""
    property bool inverted: false
    property bool allowReset: true
    property string inheritedText: "Use config"
    property string resetDescription: "Use your existing configuration"
    readonly property bool inherited: settingValue === undefined
    readonly property real displayValue: inherited ? defaultValue : inverted ? (1 - settingValue) * 100 : settingValue
    // Geometry sliders coalesce pointer motion while keeping the thumb live.
    property int editInterval: 0
    property var pendingDisplayValue: undefined
    signal edited(var value)
    function flushPendingEdit() {
        editTimer.stop();
        if (pendingDisplayValue === undefined) return;
        let value = pendingDisplayValue;
        pendingDisplayValue = undefined;
        commitDisplayValue(value);
    }
    Timer { id: editTimer; interval: root.editInterval; onTriggered: root.flushPendingEdit() }
    function commitDisplayValue(value) {
        let bounded = Math.max(from, Math.min(to, value));
        let rounded = Math.max(from, Math.min(to, Math.round(bounded / stepSize) * stepSize));
        let next = inverted ? Number((1 - rounded / 100).toFixed(6)) : Number(rounded.toFixed(6));
        if (settingValue !== next) edited(next);
    }
    function adjust(direction) {
        commitDisplayValue(slider.value + direction * stepSize);
    }
    spacing: 8
    opacity: enabled ? 1 : 0.45
    RowLayout {
        Layout.fillWidth: true
        Label {
            text: root.label
            color: Style.SettingsTheme.text
            font.pixelSize: Style.SettingsTheme.bodySize
            Layout.fillWidth: true
        }
        Label {
            objectName: "sliderValue"
            text: root.inherited && !slider.pressed ? root.inheritedText : Number((slider.pressed ? slider.value : root.displayValue).toFixed(2)) + root.suffix
            color: root.inherited ? Style.SettingsTheme.muted : Style.SettingsTheme.accentText
            font.pixelSize: Style.SettingsTheme.bodySize
        }
        ToolButton {
            objectName: "sliderReset"
            visible: root.allowReset
            text: "↺"
            enabled: !root.inherited
            implicitWidth: 28
            implicitHeight: 28
            hoverEnabled: true
            Accessible.name: "Reset " + root.label
            onClicked: root.edited("")
            contentItem: Text { text: parent.text; color: root.inherited ? Style.SettingsTheme.disabled : Style.SettingsTheme.muted; font.pixelSize: 18; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
            background: Rectangle { radius: 7; color: parent.hovered || parent.activeFocus ? Style.SettingsTheme.controlBorder : "transparent"; border.color: parent.activeFocus ? Style.SettingsTheme.accentText : "transparent" }
            Accessible.description: root.resetDescription
        }
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        SettingsButton {
            objectName: "sliderDecrease"
            text: "−"
            implicitWidth: 30; implicitHeight: 30
            Layout.preferredWidth: 30
            leftPadding: 0; rightPadding: 0
            enabled: slider.value > root.from
            Accessible.name: "Decrease " + root.label
            onClicked: root.adjust(-1)
        }
        Slider {
            id: slider
            objectName: "effectSlider"
            Layout.fillWidth: true
            implicitHeight: 28
            from: root.from
            to: root.to
            stepSize: root.stepSize
            value: root.displayValue
            live: true
            hoverEnabled: true
            Accessible.name: root.label
            onMoved: {
                if (root.editInterval > 0 && pressed) {
                    root.pendingDisplayValue = value;
                    if (!editTimer.running) editTimer.start();
                } else root.commitDisplayValue(value);
            }
            onPressedChanged: if (!pressed) root.flushPendingEdit()
            background: Rectangle {
                x: slider.leftPadding
                y: slider.topPadding + (slider.availableHeight - height) / 2
                width: slider.availableWidth
                height: 5
                radius: 3
                color: Style.SettingsTheme.controlBorder
                Rectangle {
                    width: slider.visualPosition * parent.width
                    height: parent.height
                    radius: 3
                    color: root.inherited ? Style.SettingsTheme.muted : Style.SettingsTheme.accentText
                }
            }
            handle: Rectangle {
                x: slider.leftPadding + slider.visualPosition * (slider.availableWidth - width)
                y: slider.topPadding + (slider.availableHeight - height) / 2
                implicitWidth: 18
                implicitHeight: 18
                radius: 9
                color: slider.pressed ? Style.SettingsTheme.accentForeground : Style.SettingsTheme.text
                border.width: slider.activeFocus || slider.hovered ? 3 : 2
                border.color: slider.activeFocus || slider.hovered ? Style.SettingsTheme.accentText : Style.SettingsTheme.accentForeground
                scale: slider.pressed ? 1.18 : 1
                Behavior on scale { NumberAnimation { duration: Style.SettingsTheme.duration(root, 220); easing.type: Easing.OutBack; easing.overshoot: 0.5 } }
            }
        }
        SettingsButton {
            objectName: "sliderIncrease"
            text: "+"
            implicitWidth: 30; implicitHeight: 30
            Layout.preferredWidth: 30
            leftPadding: 0; rightPadding: 0
            enabled: slider.value < root.to
            Accessible.name: "Increase " + root.label
            onClicked: root.adjust(1)
        }
    }
    Label {
        visible: root.description !== ""
        Layout.fillWidth: true
        text: root.description
        color: Style.SettingsTheme.muted
        font.pixelSize: Style.SettingsTheme.captionSize
        wrapMode: Text.WordWrap
    }
}
