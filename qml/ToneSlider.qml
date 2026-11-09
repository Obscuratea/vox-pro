import QtQuick

// A labelled horizontal slider for the voice tools. Drag or scroll; double-click resets.
// Ranges that cross zero fill outward from the middle, so boost and cut read at a glance.
Item {
    id: tone
    required property var app
    property string label
    property real value: 0
    property real from: -12
    property real to: 12
    property real resetValue: 0
    property var format: value => app.db(value)
    signal moved(real value)

    readonly property bool centered: from < 0 && to > 0
    readonly property real handle: app.soft ? 14 : 10

    implicitWidth: 180
    implicitHeight: 34
    opacity: enabled ? 1 : 0.4

    function posOf(v) {
        return (v - from) / (to - from);
    }
    function clamped(v) {
        return Math.round(Math.max(from, Math.min(to, v)) * 2) / 2;
    }

    Text {
        anchors.left: parent.left
        anchors.top: parent.top
        text: tone.label
        color: tone.app.dim
        font.pixelSize: 11
    }
    Text {
        anchors.right: parent.right
        anchors.top: parent.top
        text: tone.format(tone.value)
        color: tone.app.ink
        font.family: tone.app.mono
        font.pixelSize: 11
    }

    Item {
        id: rail
        x: tone.handle / 2
        y: 22
        width: tone.width - tone.handle
        height: 10

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: 2
            radius: 1
            color: tone.app.line
        }
        Rectangle {
            readonly property real start: tone.centered ? tone.posOf(0) : 0
            readonly property real end: tone.posOf(tone.value)
            anchors.verticalCenter: parent.verticalCenter
            x: Math.min(start, end) * rail.width
            width: Math.abs(end - start) * rail.width
            height: 2
            radius: 1
            color: tone.app.accent
        }
        Rectangle {
            x: tone.posOf(tone.value) * rail.width - width / 2
            anchors.verticalCenter: parent.verticalCenter
            width: tone.handle
            height: tone.handle
            radius: tone.app.soft ? width / 2 : 0
            color: area.pressed || area.containsMouse ? tone.app.accent : tone.app.ink
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        anchors.topMargin: 14
        hoverEnabled: true
        cursorShape: Qt.SizeHorCursor
        property real startX
        property real startValue

        onPressed: mouse => {
            startX = mouse.x;
            startValue = tone.value;
        }
        onPositionChanged: mouse => {
            if (pressed)
                tone.moved(tone.clamped(startValue + (mouse.x - startX) / rail.width * (tone.to - tone.from)));
        }
        onDoubleClicked: tone.moved(tone.resetValue)
        onWheel: wheel => tone.moved(tone.clamped(tone.value + (wheel.angleDelta.y > 0 ? 0.5 : -0.5)))
    }
}
