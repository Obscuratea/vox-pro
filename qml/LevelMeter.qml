import QtQuick

// Stereo peak meter from -60 to 0 dB. Turns amber above -6 dB and red near clipping.
Item {
    id: meter
    required property var app
    property var peaks: [0, 0]
    property bool vertical: true
    property real leftLevel: 0
    property real rightLevel: 0
    // Peak hold: a thin tick stays at the loudest recent level for 1.5 s, then drifts down.
    property real holdLeft: 0
    property real holdRight: 0
    property int ageLeft: 0
    property int ageRight: 0
    // Clip light: lit when a sample reaches full scale, stays lit until the meter is clicked.
    property bool clipped: false

    implicitWidth: vertical ? 12 : 120
    implicitHeight: vertical ? 120 : 10

    function fraction(peak) {
        if (!(peak > 0.00001))
            return 0;
        return Math.max(0, Math.min(1, (20 * Math.log10(peak) + 60) / 60));
    }
    // Jump up instantly, fall back slowly so short peaks stay readable.
    onPeaksChanged: {
        const l = fraction(peaks[0]), r = fraction(peaks[1]);
        leftLevel = Math.max(l, leftLevel - 0.02);
        rightLevel = Math.max(r, rightLevel - 0.02);
        if (l >= holdLeft) { holdLeft = l; ageLeft = 0; } else if (++ageLeft > 45) holdLeft = Math.max(0, holdLeft - 0.01);
        if (r >= holdRight) { holdRight = r; ageRight = 0; } else if (++ageRight > 45) holdRight = Math.max(0, holdRight - 0.01);
        if (peaks[0] >= 0.995 || peaks[1] >= 0.995) clipped = true;
    }

    Repeater {
        model: 2
        Rectangle {
            id: bar
            required property int index
            readonly property real level: index === 0 ? meter.leftLevel : meter.rightLevel
            readonly property real thickness: ((meter.vertical ? meter.width : meter.height) - 2) / 2

            x: meter.vertical ? index * (thickness + 2) : 0
            y: meter.vertical ? 0 : index * (thickness + 2)
            width: meter.vertical ? thickness : meter.width
            height: meter.vertical ? meter.height : thickness
            radius: meter.app.soft ? thickness / 2 : 0
            color: meter.app.line
            clip: meter.app.soft

            Rectangle {
                x: 0
                y: meter.vertical ? parent.height * (1 - bar.level) : 0
                width: meter.vertical ? parent.width : parent.width * bar.level
                height: meter.vertical ? parent.height * bar.level : parent.height
                radius: meter.app.soft ? thickness / 2 : 0
                color: bar.level > 0.97 ? meter.app.danger : bar.level > 0.9 ? meter.app.warning : meter.app.accent
            }
            // The peak-hold tick.
            Rectangle {
                readonly property real held: bar.index === 0 ? meter.holdLeft : meter.holdRight
                visible: held > 0.02
                x: meter.vertical ? 0 : Math.min(parent.width - 2, parent.width * held)
                y: meter.vertical ? Math.min(parent.height - 2, parent.height * (1 - held)) : 0
                width: meter.vertical ? parent.width : 2
                height: meter.vertical ? 2 : parent.height
                color: held > 0.97 ? meter.app.danger : meter.app.ink
            }
        }
    }

    // The clip light sits at the loud end of the meter; clicking the meter puts it out.
    Rectangle {
        visible: meter.clipped
        x: meter.vertical ? 0 : meter.width - 4
        y: 0
        width: meter.vertical ? meter.width : 4
        height: meter.vertical ? 4 : meter.height
        radius: meter.app.soft ? 2 : 0
        color: meter.app.danger
    }
    MouseArea {
        anchors.fill: parent
        enabled: meter.clipped
        cursorShape: Qt.PointingHandCursor
        onClicked: meter.clipped = false
    }
}
