import QtQuick
import QtQuick.Layouts

MenuButton {
    id: control
    property url iconSource: ""
    contentItem: RowLayout {
        spacing: 10
        Item {
            Layout.preferredWidth: 22; Layout.preferredHeight: 22
            Image {
                id: artwork
                objectName: "applicationIcon"
                anchors.fill: parent
                source: control.iconSource
                sourceSize.width: 22; sourceSize.height: 22
                fillMode: Image.PreserveAspectFit
                visible: status === Image.Ready
            }
            Text {
                anchors.centerIn: parent
                visible: artwork.status !== Image.Ready
                text: "󰘳"
                color: control.accent
                font.family: "GoMono Nerd Font"; font.pixelSize: 20
            }
        }
        Text {
            Layout.fillWidth: true
            text: control.text
            textFormat: Text.PlainText
            font: control.font
            color: control.enabled ? control.accent : "#585b70"
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter
        }
    }
}
