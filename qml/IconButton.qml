import QtQuick
import QtQuick.Controls.Basic

// A square button with a line icon, and optionally a label beside it. `checked` gives it the accent.
Rectangle {
    id: button
    required property var app
    property string icon
    property string text
    property string tip
    property bool checked: false
    property color tint: app.accent
    property bool quiet: false          // no fill or edge until hovered
    signal clicked()

    implicitHeight: 34
    implicitWidth: text !== "" ? row.implicitWidth + 22 : 34
    radius: app.soft ? 10 : 0
    // Plain buttons as in the mock-up: an outline, a raised fill when on. A tinted one (`tint` set) glows in it.
    readonly property bool tinted: tint !== app.accent
    color: checked ? (tinted ? Qt.alpha(tint, 0.16) : app.card2) : mouse.containsMouse ? app.hover : "transparent"
    border.color: checked && tinted ? Qt.alpha(tint, 0.5) : quiet && !mouse.containsMouse ? "transparent" : mouse.containsMouse ? app.line2 : app.line
    opacity: enabled ? 1 : 0.35

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 7
        Icon {
            anchors.verticalCenter: parent.verticalCenter
            visible: button.icon !== ""
            name: button.icon
            color: button.checked && button.tinted ? button.tint : button.checked || mouse.containsMouse ? button.app.ink : button.app.dim
            width: 17; height: 17
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: button.text !== ""
            text: button.text
            color: button.checked && button.tinted ? button.tint : button.checked || mouse.containsMouse ? button.app.ink : button.app.dim
            font.pixelSize: 12
            font.weight: Font.DemiBold
        }
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        enabled: button.enabled
        cursorShape: Qt.PointingHandCursor
        onClicked: button.clicked()
    }
    ToolTip.visible: mouse.containsMouse && tip !== ""
    ToolTip.text: tip
    ToolTip.delay: 400
}
