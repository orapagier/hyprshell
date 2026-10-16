import QtQuick

Item {
    id: state
    property string mode: 'always'
    property bool eligible: true
    property bool fullscreen: false
    property string fullscreenPolicy: 'hide'
    property bool overlapped: false
    property bool hovered: false
    property bool interacting: false
    property bool revealed: false
    readonly property bool suppressed: !eligible || (fullscreen && fullscreenPolicy === 'hide')
    readonly property bool requested: !suppressed && (mode === 'always' || hovered || interacting || (mode === 'dodge' && !overlapped))
    readonly property bool shown: !suppressed && revealed
    readonly property bool reserve: !suppressed && mode === 'always'
    onRequestedChanged: update()
    onSuppressedChanged: update()
    Component.onCompleted: update()
    function update() {
        if (suppressed) { delay.stop(); revealed = false; }
        else if (requested) { delay.stop(); revealed = true; }
        else if (revealed) delay.restart();
    }
    Timer { id: delay; interval: 500; onTriggered: if (!state.requested) state.revealed = false }
}
