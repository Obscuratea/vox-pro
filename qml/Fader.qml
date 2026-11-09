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

    readonly property real handleLength: 14
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
        width: fader.vertical ? 4 : fader.span
        height: fader.vertical ? fader.span : 4
        radius: fader.app.soft ? 2 : 0
        color: fader.app.line

        Rectangle {
            x: 0
            y: fader.vertical ? parent.height - height : 0
            width: fader.vertical ? parent.width : parent.width * fader.posOf(fader.value)
            height: fader.vertical ? parent.height * fader.posOf(fader.value) : parent.height
            radius: fader.app.soft ? 2 : 0
            gradient: Gradient {
                orientation: fader.vertical ? Gradient.Vertical : Gradient.Horizontal
                GradientStop { position: 0; color: fader.vertical ? fader.app.accentEnd : fader.app.accent }
                GradientStop { position: 1; color: fader.vertical ? fader.app.accent : fader.app.accentEnd }
            }
        }
    }

    // 0 dB mark
    Rectangle {
        readonly property real at: fader.posOf(0) * fader.span + fader.handleLength / 2
        x: fader.vertical ? 4 : at
        y: fader.vertical ? fader.height - at : 3
        width: fader.vertical ? fader.width - 8 : 1
        height: fader.vertical ? 1 : fader.height - 6
        color: fader.app.dim
    }

    Rectangle {
        readonly property real along: fader.posOf(fader.value) * fader.span
        x: fader.vertical ? 0 : along
        y: fader.vertical ? fader.span - along : 0
        width: fader.vertical ? fader.width : fader.handleLength
        height: fader.vertical ? fader.handleLength : fader.height
        radius: fader.app.soft ? (fader.vertical ? height / 2 : width / 2) : 0
        color: drag.pressed || drag.containsMouse ? fader.app.accent : fader.app.ink

        Rectangle {
            anchors.centerIn: parent
            width: fader.vertical ? parent.width - 12 : 2
            height: fader.vertical ? 2 : parent.height - 10
            radius: 1
            color: fader.app.bg
        }
    }

    MouseArea {
        id: drag
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.SizeVerCursor
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
