import QtQuick

// A flat, matt gold metal knob for the Pro theme: an almost solid brushed-gold disc, a thin darker rim and a
// fine machined ring inside it. No gloss.
Rectangle {
    id: knob
    property bool lit: false
    width: 22
    height: 22
    radius: width / 2
    border.width: 1
    border.color: "#7d5f1c"
    gradient: Gradient {
        GradientStop { position: 0.0; color: knob.lit ? "#dcb862" : "#cfab55" }
        GradientStop { position: 1.0; color: knob.lit ? "#c29a40" : "#b78f3a" }
    }
    Rectangle {
        anchors.centerIn: parent
        width: parent.width * 0.58
        height: width
        radius: width / 2
        color: "transparent"
        border.width: 1
        border.color: "#8a6a24"
        opacity: 0.7
    }
}
