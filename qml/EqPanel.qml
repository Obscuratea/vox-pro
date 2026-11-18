import QtQuick
import QtQuick.Layouts

// The strip's parametric EQ on the back of its card: the switch, the curve, and the way into the editor.
ColumnLayout {
    id: root
    required property var card
    Layout.fillWidth: true
    spacing: 12
    Chip {
        Layout.fillWidth: true
        app: card.app
        text: card.app.t("EQ")
        checked: !!card.strip.eq_on
        tip: "Six-cell parametric EQ, after Bass and Brightness"
        onToggled: card.set(s => s.eq_on = !s.eq_on)
    }
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 120
        radius: card.app.rBox
        color: card.app.diamond ? "transparent" : curveMouse.containsMouse ? card.app.hover : card.app.soft ? card.app.tonal : "transparent"
        border.color: curveMouse.containsMouse ? card.app.accent : card.app.soft ? card.app.controlEdge : card.app.line
        clip: true
        PeqCurve {
            anchors.fill: parent
            anchors.margins: 4
            app: card.app
            cells: card.strip.eq || []
            on: !!card.strip.eq_on
        }
        MouseArea {
            id: curveMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: card.app.openEq("strip", card.index)
        }
    }
    TextButton {
        Layout.fillWidth: true
        app: card.app
        text: card.app.diamond ? "edit curve" : "Edit curve"
        onClicked: card.app.openEq("strip", card.index)
    }
}
