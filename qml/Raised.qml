import QtQuick
import QtQuick.Effects

// Soft raised-plate shadow behind a card (neumorphism): light glow top left, gentle shadow bottom right.
// Put it inside the card; it paints outside the card's edge, under it.
Item {
    id: raised
    required property var app
    property real radius: 20
    anchors.fill: parent
    z: -2
    visible: app.glassy

    Rectangle { id: shape; anchors.fill: parent; radius: raised.radius; color: "black"; visible: false }
    MultiEffect {
        anchors.fill: shape; source: shape; autoPaddingEnabled: true
        shadowEnabled: true
        shadowColor: raised.app.dark ? "#000000" : "#5560b8"
        shadowOpacity: raised.app.dark ? 0.45 : 0.22
        shadowBlur: 1.0; shadowHorizontalOffset: 4; shadowVerticalOffset: 6
        opacity: 0.999
    }
    MultiEffect {
        anchors.fill: shape; source: shape; autoPaddingEnabled: true
        shadowEnabled: true
        shadowColor: "#ffffff"
        shadowOpacity: raised.app.dark ? 0.06 : 0.9
        shadowBlur: 1.0; shadowHorizontalOffset: -4; shadowVerticalOffset: -4
        opacity: 0.999
    }
}
