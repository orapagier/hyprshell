pragma ComponentBehavior: Bound
import QtQuick
import "TaskbarModel.js" as Tasks

Bar {
    id: status
    required property var config
    property string edge: 'bottom'
    property string component: 'hyprbar'
    statusIconsOnly: component === 'hyprbar'
    compactItemPadding: component === 'hyprbar' && config.panels?.hyprbar?.spacingRight != null
    mediaMaximumWidth: Math.max(80, Math.min(300, screenWidth * 0.24))
    settings: Tasks.statusConfig(config, edge, component)
    readonly property real contentLength: groupLength('right')
}
