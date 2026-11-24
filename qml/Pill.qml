import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic

// The small switches on a strip, as in the mock-up:
//   "pill"  GATE / DUCK / EQ: sunken, an accent line along the bottom when on
//   "send"  A1, B1...: a hairline outline, filled with the A or B colour when on
//   "mute", "solo"  M and S: the bigger footer buttons, red or amber when on
//   "rec"   the record dot on an output: a red dot, the whole button red while recording
Rectangle {
    id: pill
    required property var app
    property string kind: "pill"
    property string text
    property bool checked
    property string tip
    signal toggled()

    readonly property bool send: kind === "send"
    readonly property bool footer: kind === "mute" || kind === "solo" || kind === "rec"
    readonly property color fillOn: kind === "mute" || kind === "rec" ? app.danger
                                  : kind === "solo" ? app.warning
                                  : send && text[0] === "A" ? app.accentEnd
                                  : send ? app.accent : app.card2
    readonly property color inkOn: kind === "solo" ? "#241500"
                                 : kind === "mute" || kind === "rec" || (send && text[0] === "A") ? "#ffffff"
                                 : send ? app.accentInk : app.ink

    implicitWidth: Math.max(footer ? 30 : 28, label.implicitWidth + 14)
    // In a row of pills the row's width wins: a narrow strip shrinks them (the label elides) instead of letting
    // them stick out of the strip.
    Layout.minimumWidth: 0
    implicitHeight: footer ? 30 : 24
    radius: app.soft ? (footer ? 9 : 8) : 0
    readonly property bool lit: checked && kind === "pill"
    color: lit ? app.card2 : checked ? fillOn : send ? "transparent" : app.well
    border.color: lit ? app.line2 : checked ? "transparent" : mouse.containsMouse ? app.line2 : app.line
    clip: false

    // An "on" pill gets an accent edge along its bottom that follows the rounded corners: a 2 px rounded outline
    // of the whole pill, with only its bottom curve showing.
    Item {
        visible: pill.lit
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Math.max(3, pill.radius)
        clip: true
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: pill.height
            radius: pill.radius
            color: "transparent"
            border.width: 2
            border.color: pill.app.accent
        }
    }

    Text {
        id: label
        anchors.centerIn: parent
        width: Math.min(implicitWidth, pill.width - 4)
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        text: pill.kind === "pill" ? pill.text.toUpperCase() : pill.text
        color: pill.checked ? pill.inkOn : pill.kind === "rec" ? pill.app.danger : mouse.containsMouse ? pill.app.ink : pill.footer ? pill.app.dim : pill.app.faint
        font.family: pill.send ? pill.app.mono : pill.app.display
        font.pixelSize: pill.footer ? 12 : pill.send ? 11 : 10
        font.weight: Font.DemiBold
        font.letterSpacing: pill.kind === "pill" ? 0.7 : 0
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: pill.toggled()
    }
    ToolTip.visible: mouse.containsMouse && tip !== ""
    ToolTip.text: tip
    ToolTip.delay: 400
}
