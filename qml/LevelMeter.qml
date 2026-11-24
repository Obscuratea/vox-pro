import QtQuick

// Stereo peak meter from -60 to 0 dB, lit with the accent gradient that turns amber, then red, near the top.
// Settings > Meters picks the look: that gradient, the same in segments, or one solid colour.
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
    readonly property string style: app.prefs ? app.prefs.meter_style || "gradient" : "gradient"
    readonly property bool solid: style === "solid"

    implicitWidth: vertical ? 13 : 120
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
            readonly property real thickness: ((meter.vertical ? meter.width : meter.height) - 3) / 2

            x: meter.vertical ? index * (thickness + 3) : 0
            y: meter.vertical ? 0 : index * (thickness + 3)
            width: meter.vertical ? thickness : meter.width
            height: meter.vertical ? meter.height : thickness
            radius: meter.app.soft ? thickness / 2 : 0
            color: meter.app.well
            clip: true

            // The lit part shows a slice of one gradient laid over the whole bar, so loud reads amber, then red.
            Item {
                x: 0
                y: meter.vertical ? parent.height * (1 - bar.level) : 0
                width: meter.vertical ? parent.width : parent.width * bar.level
                height: meter.vertical ? parent.height * bar.level : parent.height
                clip: true
                Rectangle {
                    visible: meter.style !== "segments"
                    x: 0
                    y: meter.vertical ? parent.height - height : 0
                    width: meter.vertical ? parent.width : bar.width
                    height: meter.vertical ? bar.height : parent.height
                    radius: meter.app.soft ? bar.thickness / 2 : 0
                    gradient: Gradient {
                        orientation: meter.vertical ? Gradient.Vertical : Gradient.Horizontal
                        GradientStop { position: meter.vertical ? 1 : 0; color: meter.solid ? meter.app.accent : meter.app.accentEnd }
                        GradientStop { position: meter.vertical ? 0.38 : 0.62; color: meter.app.accent }
                        GradientStop { position: meter.vertical ? 0.16 : 0.84; color: meter.solid ? meter.app.accent : meter.app.warning }
                        GradientStop { position: meter.vertical ? 0 : 1; color: meter.solid ? meter.app.accent : meter.app.danger }
                    }
                }
                // Segments: the same colours in 3 px steps with 1 px gaps, painted once for the whole bar and
                // uncovered by the level like the gradient.
                Canvas {
                    visible: meter.style === "segments"
                    x: 0
                    y: meter.vertical ? parent.height - height : 0
                    width: meter.vertical ? parent.width : bar.width
                    height: meter.vertical ? bar.height : parent.height
                    readonly property var colors: [meter.app.accentEnd, meter.app.accent, meter.app.warning, meter.app.danger]
                    onColorsChanged: requestPaint()
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()
                    onVisibleChanged: if (visible) requestPaint()
                    onPaint: {
                        const c = getContext("2d");
                        c.reset();
                        if (!visible) return;
                        const along = meter.vertical ? height : width;
                        const g = meter.vertical ? c.createLinearGradient(0, height, 0, 0) : c.createLinearGradient(0, 0, width, 0);
                        g.addColorStop(0, colors[0]); g.addColorStop(0.62, colors[1]); g.addColorStop(0.84, colors[2]); g.addColorStop(1, colors[3]);
                        c.fillStyle = g;
                        for (let at = 0; at < along; at += 4) {
                            if (meter.vertical) c.fillRect(0, height - at - 3, width, 3);
                            else c.fillRect(at, 0, 3, height);
                        }
                    }
                }
            }
            // The peak-hold tick.
            Rectangle {
                readonly property real held: bar.index === 0 ? meter.holdLeft : meter.holdRight
                visible: held > 0.02 && (!meter.app.prefs || meter.app.prefs.peak_hold !== false)
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
