import QtQuick
import QtQuick.Layouts

// A row of tabs in one box; the current one wears the accent gradient. Each tab is as wide as its label needs,
// and what is left over is shared out evenly.
Rectangle {
    id: tabs
    required property var app
    property var model: []
    property int current: 0
    signal picked(int index)

    implicitHeight: 30
    radius: app.soft ? height / 2 : app.diamond ? 0 : 4
    color: app.diamond || app.outlined ? "transparent" : app.tonal
    border.color: app.diamond ? app.frameDim : app.soft && !app.outlined ? "transparent" : app.outlined ? app.controlEdge : app.line

    RowLayout {
        anchors.fill: parent
        anchors.margins: 3
        spacing: 2
        Repeater {
            model: tabs.model
            Rectangle {
                id: tab
                required property int index
                required property string modelData
                readonly property bool on: tabs.current === index
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: label.implicitWidth + 12
                radius: tabs.app.soft ? height / 2 : 0
                color: on || !mouse.containsMouse ? "transparent" : tabs.app.hover
                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    visible: tab.on
                    opacity: tabs.app.diamond ? 0.45 : 1
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: tabs.app.accent }
                        GradientStop { position: 1; color: tabs.app.accentEnd }
                    }
                }
                Text {
                    id: label
                    anchors.centerIn: parent
                    text: tabs.app.t(tab.modelData)
                    color: tab.on && !tabs.app.diamond ? tabs.app.accentInk : tabs.app.ink
                    font.family: tabs.app.mono
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                }
                MouseArea {
                    id: mouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: tabs.picked(tab.index)
                }
            }
        }
    }
}
