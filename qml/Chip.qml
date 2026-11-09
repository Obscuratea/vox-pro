import QtQuick
import QtQuick.Controls.Basic

// A toggle: routing buttons (A1, B1...), mute, and the gate switch.
Rectangle {
    id: chip
    required property var app
    property string text
    property bool checked
    property string tip
    property color onColor: app.onFill
    signal toggled()

    implicitWidth: Math.max(44, label.implicitWidth + 20)
    implicitHeight: 28
    radius: app.rChip
    readonly property bool danger: onColor !== app.onFill
    color: app.diamond ? "transparent" : checked ? onColor : mouse.containsMouse ? app.hover : app.soft ? app.tonal : "transparent"
    border.color: app.diamond ? "transparent" : checked ? onColor : app.soft ? app.controlEdge : app.line

    // Diamond: outlined, a checked chip gets the violet selection fill and an accent outline (danger: red)
    CutFrame {
        visible: chip.app.diamond
        anchors.fill: parent
        cut: chip.app.cut
        fill: chip.checked ? (chip.danger ? Qt.alpha(chip.onColor, 0.25) : chip.app.select) : (mouse.containsMouse ? chip.app.hover : "transparent")
        stroke: chip.checked ? chip.onColor : (mouse.containsMouse ? chip.app.accent : chip.app.frameDim)
    }

    // a checked chip takes on the accent gradient (the danger kind stays red)
    Rectangle {
        anchors.fill: parent
        anchors.margins: chip.app.diamond ? 2 : 0
        radius: chip.app.diamond ? 0 : chip.radius
        visible: chip.checked && !chip.danger
        opacity: chip.app.diamond ? 0.45 : 1
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: chip.app.accent }
            GradientStop { position: 1; color: chip.app.accentEnd }
        }
    }

    Text {
        id: label
        anchors.centerIn: parent
        text: chip.text
        color: chip.checked && !chip.app.diamond ? chip.app.accentInk : chip.app.ink
        font.family: chip.app.mono
        font.pixelSize: 12
        font.weight: Font.DemiBold
        font.letterSpacing: chip.app.soft ? 0.4 : 0
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: chip.toggled()
    }

    ToolTip.visible: mouse.containsMouse && tip !== ""
    ToolTip.text: tip
    ToolTip.delay: 400
}
