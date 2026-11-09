import QtQuick
import QtQuick.Effects

// Frosted-glass backdrop for a box: shows the blurred background picture behind it. Put it inside the box
// (it paints under the box's own translucent fill). Does nothing when the picture background is off.
Item {
    id: glass
    required property var app
    property real radius: 0
    anchors.fill: parent
    z: -1
    visible: app.bgOn

    property rect src: Qt.rect(0, 0, 1, 1)
    function refresh() {
        if (!visible || width < 1 || height < 1)
            return;
        const p = glass.mapToItem(app.blurSource, 0, 0);
        src = Qt.rect(p.x, p.y, width, height);
    }
    onWidthChanged: refresh()
    onHeightChanged: refresh()
    onVisibleChanged: refresh()
    Component.onCompleted: refresh()
    // Boxes move when the window is resized or the layout settles; checking is cheap.
    Timer { running: glass.visible; interval: 250; repeat: true; onTriggered: glass.refresh() }

    ShaderEffectSource {
        id: snap
        anchors.fill: parent
        sourceItem: glass.app.blurSource
        sourceRect: glass.src
        visible: false
        live: true
    }
    Item {
        id: mask
        anchors.fill: parent
        visible: false
        layer.enabled: true
        Rectangle { anchors.fill: parent; radius: glass.radius; color: "black" }
    }
    MultiEffect {
        anchors.fill: parent
        source: snap
        maskEnabled: true
        maskSource: mask
    }
}
