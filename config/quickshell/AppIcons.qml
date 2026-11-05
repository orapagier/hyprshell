pragma ComponentBehavior: Bound
import QtQuick
import QtCore
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io

Item {
    id: icons
    property var catalog: ({})
    // The catalog is only a fallback for icons the theme lookup cannot resolve.
    property bool catalogRequested: false
    // Keep the original directory models for a helper that fails before its
    // first catalog. A post-ready failure retains the last catalog and retries.
    property bool helperReady: false
    property bool useFolderModels: false
    readonly property string helperPath: decodeURIComponent(
        Qt.resolvedUrl("helpers/icon-catalog.py").toString().replace(/^file:\/\//, ""))
    readonly property var folders: {
        let result = [];
        for (let root of StandardPaths.standardLocations(StandardPaths.GenericDataLocation)) {
            for (let size of ["32x32", "24x24", "48x48", "64x64", "128x128", "256x256", "scalable", "symbolic"])
                result.push(root + "/icons/hicolor/" + size + "/apps");
            result.push(root + "/pixmaps");
        }
        // Include distribution themes when the platform has no category lookup.
        for (let theme of ["Pop", "Adwaita"])
            for (let size of ["32x32", "scalable", "symbolic"])
                for (let category of ["apps", "devices", "places", "status", "mimetypes"])
                    result.push("file:///usr/share/icons/" + theme + "/" + size + "/" + category);
        return result;
    }
    function source(name) {
        if (!name) return "";
        if (name.startsWith("/")) return "file://" + name.split("/").map(encodeURIComponent).join("/");
        let themed = Quickshell.iconPath(name, true);
        if (themed) return themed;
        // Scan icon directories lazily, on the first unresolved lookup. The
        // catalog binding re-evaluates as directories report their contents.
        if (!catalogRequested) catalogRequested = true;
        return catalog[name.replace(/\.(svg|png|xpm)$/i, "")] || "";
    }
    function rebuild() {
        let next = {};
        for (let i = 0; i < directories.count; ++i) {
            let folder = directories.objectAt(i);
            if (!folder) continue;
            for (let j = 0; j < folder.count; ++j) {
                let name = folder.get(j, "fileName").replace(/\.(svg|png|xpm)$/i, "");
                if (!next[name]) next[name] = folder.get(j, "fileUrl");
            }
        }
        catalog = next;
    }
    function startCatalog() {
        if (catalogRequested && !useFolderModels && !catalogProcess.running)
            catalogProcess.running = true;
    }
    onCatalogRequestedChanged: if (catalogRequested) startCatalog()
    Process {
        id: catalogProcess
        command: ["python3", icons.helperPath, "--folders-json", JSON.stringify(icons.folders)]
        stdout: SplitParser {
            onRead: line => {
                let message;
                try { message = JSON.parse(line); } catch (error) { return; }
                if (!message || message.version !== 1 || !message.catalog
                        || typeof message.catalog !== "object") return;
                icons.catalog = message.catalog;
                icons.helperReady = true;
                catalogStartup.stop();
                catalogRestart.stop();
            }
        }
        stderr: StdioCollector {}
        onRunningChanged: if (running) catalogStartup.restart()
        onExited: (code, status) => {
            catalogStartup.stop();
            if (!icons.helperReady) icons.useFolderModels = true;
            else if (icons.catalogRequested && !icons.useFolderModels) catalogRestart.restart();
        }
    }
    Timer {
        id: catalogStartup
        interval: 5000
        onTriggered: {
            if (icons.helperReady) return;
            icons.useFolderModels = true;
            catalogProcess.running = false;
        }
    }
    Timer {
        id: catalogRestart
        interval: 30000
        onTriggered: if (icons.catalogRequested && !icons.useFolderModels) catalogProcess.running = true
    }
    Instantiator {
        id: directories
        active: icons.catalogRequested && icons.useFolderModels
        model: icons.catalogRequested && icons.useFolderModels ? icons.folders : []
        delegate: FolderListModel {
            required property string modelData
            folder: modelData
            nameFilters: ["*.svg", "*.png", "*.xpm"]
            showDirs: false
            onStatusChanged: if (status === FolderListModel.Ready) Qt.callLater(icons.rebuild)
            onCountChanged: Qt.callLater(icons.rebuild)
        }
        onObjectAdded: Qt.callLater(icons.rebuild)
    }
}
