import QtQuick
import QtQuick.Controls.Basic

Rectangle {
    id: button
    required property var app
    property string text
    property string tip
    signal clicked()

    implicitHeight: 32
    implicitWidth: label.implicitWidth + 28
    radius: app.soft ? height / 2 : 0
    CutFrame {
        visible: button.app.diamond
        anchors.fill: parent
        cut: button.app.cut
        fill: mouse.pressed ? button.app.select : (mouse.containsMouse ? Qt.alpha(button.app.accent, 0.14) : "transparent")
        stroke: mouse.containsMouse ? button.app.accent : button.app.frameDim
    }
    color: button.app.diamond ? "transparent" : mouse.pressed ? app.onFill : app.soft ? (mouse.containsMouse ? Qt.tint(app.tonal, Qt.alpha(app.accent, 0.18)) : app.tonal)
                                                : mouse.containsMouse ? app.hover : "transparent"
    border.color: app.diamond ? "transparent" : app.soft ? (mouse.containsMouse ? app.accent : app.controlEdge) : mouse.containsMouse ? app.accent : app.line

    Text {
        id: label
        anchors.centerIn: parent
        text: button.text
        color: mouse.pressed && !button.app.diamond ? button.app.accentInk : button.app.ink
        font.family: button.app.diamond ? button.app.mono : Qt.application.font.family
        font.pixelSize: 12
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: button.clicked()
    }

    ToolTip.visible: mouse.containsMouse && tip !== ""
    ToolTip.text: tip
    ToolTip.delay: 400
}
