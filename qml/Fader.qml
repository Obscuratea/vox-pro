import QtQuick

// A level fader in dB. Drag to move (it moves from where it is, it doesn't jump),
// scroll for 1 dB steps, double-click to go back to 0 dB.
Item {
    id: fader
    required property var app
    property real value: 0
    property real from: -60
    property real to: 12
    property bool vertical: true
    signal moved(real value)

    readonly property real handleLength: 16
    readonly property real span: Math.max(1, (vertical ? height : width) - handleLength)

    implicitWidth: vertical ? 34 : 160
    implicitHeight: vertical ? 160 : 24

    function posOf(v) {
        return (v - from) / (to - from);
    }
    function clamped(v) {
        return Math.round(Math.max(from, Math.min(to, v)) * 2) / 2;
    }

    Rectangle {
        id: track
        x: fader.vertical ? (fader.width - width) / 2 : fader.handleLength / 2
        y: fader.vertical ? fader.handleLength / 2 : (fader.height - height) / 2
        width: fader.vertical ? 6 : fader.span
        height: fader.vertical ? fader.span : 6
        radius: fader.app.soft ? 3 : 0
        color: fader.app.well
        border.width: 1
        border.color: fader.app.line

        Rectangle {
            x: 0
            y: fader.vertical ? parent.height - height : 0
            width: fader.vertical ? parent.width : parent.width * fader.posOf(fader.value)
            height: fader.vertical ? parent.height * fader.posOf(fader.value) : parent.height
            radius: fader.app.soft ? 3 : 0
            gradient: Gradient {
                orientation: fader.vertical ? Gradient.Vertical : Gradient.Horizontal
                GradientStop { position: 0; color: fader.vertical ? fader.app.accent : fader.app.accentEnd }
                GradientStop { position: 1; color: fader.vertical ? fader.app.accentEnd : fader.app.accent }
            }
        }
    }

    // 0 dB mark
    Rectangle {
        readonly property real at: fader.posOf(0) * fader.span + fader.handleLength / 2
        x: fader.vertical ? (fader.width - width) / 2 : at
        y: fader.vertical ? fader.height - at : (fader.height - height) / 2
        width: fader.vertical ? 14 : 1
        height: fader.vertical ? 1 : 14
        color: fader.app.line2
    }

    // The handle: a light cap with an accent line across it, a little bigger while held or hovered.
    Rectangle {
        readonly property real along: fader.posOf(fader.value) * fader.span
        x: fader.vertical ? (fader.width - width) / 2 : along
        y: fader.vertical ? fader.span - along : (fader.height - height) / 2
        width: fader.vertical ? 30 : fader.handleLength
        height: fader.vertical ? fader.handleLength : 30
        radius: fader.app.soft ? 6 : 0
        color: fader.app.ink
        border.color: Qt.alpha("#000000", 0.2)
        scale: drag.pressed || drag.containsMouse ? 1.12 : 1
        Behavior on scale { enabled: fader.app.anim !== false; NumberAnimation { duration: 120 } }
        Rectangle {
            anchors.centerIn: parent
            width: fader.vertical ? parent.width - 14 : 2
            height: fader.vertical ? 2 : parent.height - 14
            radius: 1
            color: fader.app.accent
        }
    }

    MouseArea {
        id: drag
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: fader.vertical ? Qt.SizeVerCursor : Qt.SizeHorCursor
        preventStealing: true
        property real startPos
        property real startValue

        function along(mouse) {
            return fader.vertical ? -mouse.y : mouse.x;
        }
        onPressed: mouse => {
            startPos = along(mouse);
            startValue = fader.value;
        }
        onPositionChanged: mouse => {
            if (pressed)
                fader.moved(fader.clamped(startValue + (along(mouse) - startPos) / fader.span * (fader.to - fader.from)));
        }
        onDoubleClicked: fader.moved(0)
        onWheel: wheel => fader.moved(fader.clamped(fader.value + (wheel.angleDelta.y > 0 ? 1 : -1)))
    }
}
