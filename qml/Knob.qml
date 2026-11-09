import QtQuick

// A flat, matt knob for the Pro theme: a plain disc filled with the same accent gradient as the buttons
// (gold, or the wallpaper's colours when a picture is behind the mixer) and a thin darker rim.
Rectangle {
    id: knob
    required property var app
    property bool lit: false
    width: 22
    height: 22
    radius: width / 2
    border.width: 1
    border.color: Qt.darker(app.accentEnd, 1.9)
    gradient: Gradient {
        GradientStop { position: 0.0; color: knob.lit ? Qt.lighter(knob.app.accent, 1.15) : knob.app.accent }
        GradientStop { position: 1.0; color: knob.lit ? Qt.lighter(knob.app.accentEnd, 1.15) : knob.app.accentEnd }
    }
}
