import QtQuick
import QtQuick.Controls.Basic

// An on/off switch.
Rectangle {
    id: sw
    required property var app
    property bool checked
    property string tip
    signal toggled()

    implicitWidth: 34
    implicitHeight: 20
    radius: app.soft ? height / 2 : app.diamond ? 0 : 4
    color: checked ? "transparent" : app.outlined ? "transparent" : Qt.alpha(app.ink, 0.14)
    border.color: checked ? "transparent" : app.outlined || !app.soft ? app.line : "transparent"
    opacity: enabled ? 1 : 0.45

    Rectangle {
        anchors.fill: parent
        radius: parent.radius
        visible: sw.checked
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: sw.app.accentEnd }
            GradientStop { position: 1; color: sw.app.accent }
        }
    }
    Rectangle {
        width: parent.height - 6
        height: width
        radius: sw.app.soft ? width / 2 : sw.app.diamond ? 0 : 2
        y: 3
        x: sw.checked ? parent.width - width - 3 : 3
        color: sw.checked ? "#ffffff" : sw.app.dim
        Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        anchors.margins: -4
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: sw.toggled()
    }
    ToolTip.visible: mouse.containsMouse && tip !== ""
    ToolTip.text: tip
    ToolTip.delay: 400
}
