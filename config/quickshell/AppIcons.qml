pragma ComponentBehavior: Bound
import QtQuick
import QtCore
import Qt.labs.folderlistmodel
import Quickshell

Item {
    id: icons
    property var catalog: ({})
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
        return themed || catalog[name.replace(/\.(svg|png|xpm)$/i, "")] || "";
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
    Instantiator {
        id: directories
        model: icons.folders
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
