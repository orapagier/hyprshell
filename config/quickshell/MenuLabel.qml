import QtQuick
import "AdaptiveColors.js" as Colors

Text {
    id: label
    color: Colors.menuColorsFor(label).text
    font.family: "DejaVu Sans"
    font.pixelSize: 13
    wrapMode: Text.Wrap
    textFormat: Text.PlainText
}
