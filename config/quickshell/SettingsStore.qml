import QtQuick
import Quickshell
import Quickshell.Io
import "SettingsModel.js" as Model

Item {
    id: store
    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config"
    readonly property string settingsPath: configHome + "/hyprshell/settings.json"
    readonly property var defaults: JSON.parse(defaultFile.text())
    property var config: Model.copy(defaults)
    // Transient geometry preview never replaces saved settings or the expected
    // revision used by the transaction writer.
    property var panelPreview: ({})
    readonly property var panelConfig: Object.keys(panelPreview).length
        ? Object.assign({}, config, {bar:Object.assign({}, config.bar, panelPreview)}) : config
    property string error: ""
    property bool loaded: false
    FileView {
        id: defaultFile
        path: decodeURIComponent(Qt.resolvedUrl("settings/defaults.json").toString().replace(/^file:\/\//, ""))
        blockLoading: true
    }
    FileView {
        id: savedFile
        path: store.settingsPath
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                store.config = Model.merge(store.defaults, JSON.parse(text()));
                store.error = "";
            } catch (e) {
                store.error = "Settings were not loaded: " + e.message;
            }
            store.loaded = true;
        }
        onLoadFailed: error => {
            if (error !== FileViewError.FileNotFound)
                store.error = "Cannot read " + store.settingsPath;
            store.loaded = true;
        }
    }
    function reload() {
        savedFile.reload();
    }
}
