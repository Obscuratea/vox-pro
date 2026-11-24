import QtQuick

// The fixed badge of a channel: IN1, V2, A1, B1. A buses and B mics take the two accent colours.
Rectangle {
    id: tag
    required property var app
    property string text
    readonly property bool isA: text[0] === "A"
    readonly property bool isB: text[0] === "B"
    readonly property color tint: isA ? app.accentEnd : isB ? app.accent : app.dim

    implicitWidth: label.implicitWidth + 12
    implicitHeight: 20
    radius: app.soft ? 6 : 0
    color: isA || isB ? Qt.alpha(tint, 0.16) : app.soft ? app.tonal : "transparent"
    border.color: isA || isB ? Qt.alpha(tint, 0.55) : app.soft ? app.controlEdge : app.line
    Text {
        id: label
        anchors.centerIn: parent
        text: tag.text
        color: tag.isA || tag.isB ? Qt.tint(tag.app.ink, Qt.alpha(tag.tint, 0.55)) : tag.app.dim
        font.family: tag.app.mono
        font.pixelSize: 11
        font.weight: Font.DemiBold
    }
}
