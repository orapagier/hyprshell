pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Mpris

ColumnLayout {
    id: media
    objectName: "activityMedia"
    property var players: Mpris.players.values
    property var retainedPlayer: null
    readonly property var currentPlaying: players.find(p => p.isPlaying) || null
    readonly property var player: currentPlaying
        || (players.includes(retainedPlayer) ? retainedPlayer : null)
        || players.find(p => p.trackTitle) || players[0] || null
    property color textColor: "#cdd6f4"
    property color secondaryColor: "#a6adc8"
    property color accentColor: "#b4befe"
    visible: !!player
    spacing: 10
    // Keep the same target after Pause, while a newly playing app takes priority.
    onCurrentPlayingChanged: if (currentPlaying) retainedPlayer = currentPlaying
    RowLayout {
        Layout.fillWidth: true
        spacing: 12
        Image {
            source: media.player?.trackArtUrl || ""
            visible: status === Image.Ready
            Layout.preferredWidth: 64; Layout.preferredHeight: 64
            fillMode: Image.PreserveAspectFit
            asynchronous: true
        }
        ColumnLayout {
            Layout.fillWidth: true
            MenuLabel { text: "NOW PLAYING"; color: media.secondaryColor; font.pixelSize: 11; font.letterSpacing: 2 }
            MenuLabel {
                objectName: "activityTrackTitle"
                text: media.player?.trackTitle || media.player?.identity || ""
                color: media.textColor; font.bold: true
                Layout.fillWidth: true; wrapMode: Text.Wrap
            }
            MenuLabel {
                text: [media.player?.trackArtist, media.player?.identity].filter(Boolean).join(" · ")
                color: media.secondaryColor; font.pixelSize: 11
                Layout.fillWidth: true; elide: Text.ElideRight
            }
        }
    }
    RowLayout {
        Layout.fillWidth: true
        MenuButton {
            objectName: "activityPrevious"
            text: "Previous"; Layout.fillWidth: true; accent: media.accentColor
            enabled: !!media.player?.canGoPrevious
            onClicked: media.player.previous()
        }
        MenuButton {
            objectName: "activityPlayPause"
            text: media.player?.isPlaying ? "Pause" : "Play"
            Layout.fillWidth: true; accent: media.accentColor
            enabled: !!media.player && (media.player.isPlaying ? media.player.canPause : media.player.canPlay)
            onClicked: media.player.togglePlaying()
        }
        MenuButton {
            objectName: "activityNext"
            text: "Next"; Layout.fillWidth: true; accent: media.accentColor
            enabled: !!media.player?.canGoNext
            onClicked: media.player.next()
        }
    }
}
