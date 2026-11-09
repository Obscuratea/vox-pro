import QtQuick

// A round gold metal knob for the Pro theme: a bright top, a dark horizon band and a bright bottom edge
// (like polished metal), a thin dark rim and a small highlight.
Rectangle {
    id: knob
    property bool lit: false
    width: 22
    height: 22
    radius: width / 2
    border.width: 1
    border.color: "#6b4c10"
    gradient: Gradient {
        GradientStop { position: 0.0; color: knob.lit ? "#fff6d2" : "#fbe9aa" }
        GradientStop { position: 0.42; color: knob.lit ? "#f0c457" : "#dcaf45" }
        GradientStop { position: 0.52; color: "#8c6414" }
        GradientStop { position: 0.60; color: knob.lit ? "#e7bb55" : "#c9972f" }
        GradientStop { position: 1.0; color: knob.lit ? "#fff0b8" : "#f2d27a" }
    }
    Rectangle {
        x: parent.width * 0.22
        y: parent.height * 0.12
        width: parent.width * 0.34
        height: parent.height * 0.2
        radius: height / 2
        color: "#ffffff"
        opacity: 0.55
    }
}
