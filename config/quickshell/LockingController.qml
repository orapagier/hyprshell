import QtQuick
import Quickshell.Io

Item {
    id: controller
    required property var store
    property bool onBattery: false
    onOnBatteryChanged: sync()
    function effectivePower() {
        let power = Object.assign({}, store.config.power || {});
        if (onBattery && power.separateBatteryTimers)
            for (let key of ["dimMinutes", "offMinutes", "suspendMinutes", "dimPercent"]) power[key] = power["battery" + key[0].toUpperCase() + key.slice(1)];
        return power;
    }
    property string error: ""
    property string fingerprint: ""
    property bool restarting: false
    property bool stopping: false
    readonly property string backend: decodeURIComponent(Qt.resolvedUrl("settings/backend.py").toString().replace(/^file:\/\//, ""))
    function lockNow() {
        if (locker.running) return;
        error = "";
        locker.running = true;
    }
    function idleEnabled() {
        let power = effectivePower();
        return store.config.locking.enabled || power.dimMinutes > 0 || power.offMinutes > 0 || power.suspendMinutes > 0;
    }
    function sync() {
        if (!store.loaded) return;
        let power = effectivePower();
        let lock = store.config.locking;
        let next = JSON.stringify([lock.enabled, lock.command, lock.idleMinutes, lock.beforeSleep,
            power.dimMinutes || 0, power.offMinutes || 0, power.suspendMinutes || 0, power.dimPercent || 20]);
        if (next === fingerprint) return;
        fingerprint = next;
        error = "";
        restarting = true;
        if (daemon.running && !stopping) { stopping = true; daemon.running = false; }
        else if (!stopping) restart.restart();
    }
    Component.onCompleted: sync()
    Connections {
        target: controller.store
        function onConfigChanged() { controller.sync(); }
        function onLoadedChanged() { controller.sync(); }
    }
    Timer {
        id: restart
        interval: 100
        onTriggered: {
            controller.restarting = false;
            if (controller.idleEnabled()) daemon.running = true;
        }
    }
    Process {
        id: locker
        command: ["python3", controller.backend, "--lock"]
        stderr: StdioCollector { onStreamFinished: if (text) controller.error = text.trim() }
        onExited: (code, status) => {
            if (code !== 0 && !controller.error) controller.error = "Lock command failed. Check your locker configuration.";
        }
    }
    Process {
        id: daemon
        command: ["python3", controller.backend, "--idle"].concat(controller.onBattery && controller.store.config.power.separateBatteryTimers ? ["--battery"] : [])
        stderr: StdioCollector { onStreamFinished: if (text && !controller.restarting) controller.error = text.trim() }
        onExited: (code, status) => {
            controller.stopping = false;
            if (controller.restarting) restart.restart();
            else if (controller.idleEnabled() && !controller.error)
                controller.error = "Idle controls stopped. Check locking and power settings, then change a timer to retry.";
        }
    }
}
