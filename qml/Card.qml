import QtQuick

// The box every strip and panel sits in: the theme's fill, edge and corner style.
// The fill and edge are their own layer above the frosted glass: as the box's own colour they ended up under the
// glass on the GPU renderer (the glass is an opaque shader there), so boxes and their outlines vanished.
Item {
    id: card
    required property var app
    property bool selected: false
    property real corner: app.rCard
    readonly property real radius: corner

    Raised { app: card.app; radius: card.corner }
    Glass { app: card.app; radius: card.corner }
    Rectangle {
        anchors.fill: parent
        z: -1
        visible: !card.app.diamond
        color: card.app.panelFill
        radius: card.corner
        border.width: card.selected ? 2 : 1
        border.color: card.selected ? card.app.accent : card.app.edge
    }
    CutFrame { visible: card.app.diamond; anchors.fill: parent; z: -1; cut: card.app.cut; fill: card.app.panelFill; stroke: card.selected ? card.app.accent : card.app.frameDim }
}
