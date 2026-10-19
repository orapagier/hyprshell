import QtQml

// Keep identity stable: spectrum frames must not invalidate title, playback,
// layout and preview matching bindings throughout every panel.
QtObject {
    property bool playing: false
    property var levels: []
    property string title: ""
    property string tooltip: ""
    property string fullTitle: ""
    property string artUrl: ""
    property string trackTitle: ""
    property string artist: ""
    property string appId: ""
    property string appName: ""
    property int processId: 0
}
