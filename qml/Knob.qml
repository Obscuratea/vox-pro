import QtQuick
import QtQuick.Effects

// Glass knob for the Glass themes: a round frosted bead that sits raised on its track,
// lit from the top left (white glow up there, soft shadow below right).
Item {
    id: knob
    required property var app
    property bool hot: false
    implicitWidth: 24
    implicitHeight: 24

    Rectangle {
        id: shapeDark
        anchors.fill: parent
        radius: width / 2
        color: "black"
        visible: false
    }
    MultiEffect {
        anchors.fill: shapeDark
        source: shapeDark
        autoPaddingEnabled: true
        shadowEnabled: true
        shadowColor: knob.app.dark ? "#000000" : "#4a4f9a"
        shadowOpacity: knob.app.dark ? 0.55 : 0.38
        shadowBlur: 0.7
        shadowHorizontalOffset: 2
        shadowVerticalOffset: 3
        opacity: 0.999
    }
    MultiEffect {
        anchors.fill: shapeDark
        source: shapeDark
        autoPaddingEnabled: true
        shadowEnabled: true
        shadowColor: "#ffffff"
        shadowOpacity: knob.app.dark ? 0.10 : 0.95
        shadowBlur: 0.5
        shadowHorizontalOffset: -2
        shadowVerticalOffset: -2
        opacity: 0.999
    }
    Rectangle {
        anchors.fill: parent
        radius: width / 2
        border.width: 1.5
        border.color: knob.hot ? knob.app.accent : Qt.rgba(1, 1, 1, knob.app.dark ? 0.35 : 0.95)
        gradient: Gradient {
            GradientStop { position: 0; color: knob.app.dark ? Qt.rgba(1, 1, 1, 0.70) : Qt.rgba(1, 1, 1, 0.97) }
            GradientStop { position: 1; color: knob.app.dark ? Qt.rgba(0.8, 0.8, 1, 0.34) : Qt.rgba(0.88, 0.90, 1, 0.80) }
        }
        // the frosted core: a small gradient bead in the middle
        Rectangle {
            anchors.centerIn: parent
            width: parent.width * 0.34; height: width; radius: width / 2
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: knob.app.accent }
                GradientStop { position: 1; color: knob.app.accentEnd }
            }
            opacity: knob.hot ? 1 : 0.75
        }
    }
}
