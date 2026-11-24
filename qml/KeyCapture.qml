import QtQuick

// A button that records a key combination. Click it, press the keys you want (Esc cancels).
// `key` is a Qt key code: the key plus its modifier flags, 0 for none (the format KDE's shortcut service takes).
Rectangle {
    id: cap
    required property var app
    property int key: 0
    property bool recording: false
    signal captured(int key)

    implicitWidth: Math.max(84, keyText.implicitWidth + 20)
    implicitHeight: 28
    radius: app.soft ? 7 : 0
    // Drawn like a key cap: sunken, with a thicker bottom edge.
    color: recording ? Qt.alpha(app.accent, 0.18) : app.well
    border.color: recording || mouse.containsMouse ? app.accent : app.line2
    activeFocusOnTab: true
    onActiveFocusChanged: if (!activeFocus) recording = false

    Rectangle {
        visible: !cap.recording && !mouse.containsMouse
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: cap.radius / 2
        anchors.rightMargin: cap.radius / 2
        height: 2
        color: cap.app.line2
    }
    Text {
        id: keyText
        anchors.centerIn: parent
        text: cap.recording ? "Press keys…  (Esc cancels)" : cap.key === 0 ? "Set a key" : cap.app.keyText(cap.key)
        color: cap.recording || cap.key !== 0 ? cap.app.ink : cap.app.accent
        font.family: cap.key !== 0 && !cap.recording ? cap.app.mono : Qt.application.font.family
        font.pixelSize: cap.key !== 0 && !cap.recording ? 11 : 12
        font.weight: Font.DemiBold
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: { cap.recording = true; cap.forceActiveFocus(); }
    }
    Keys.onPressed: event => {
        if (!recording)
            return;
        event.accepted = true;
        if (event.key === Qt.Key_Escape) { recording = false; return; }
        // A bare modifier press is just the start of a combination.
        if ([Qt.Key_Control, Qt.Key_Shift, Qt.Key_Alt, Qt.Key_AltGr, Qt.Key_Meta, Qt.Key_Super_L, Qt.Key_Super_R,
             Qt.Key_Hyper_L, Qt.Key_Hyper_R, Qt.Key_unknown].indexOf(event.key) >= 0)
            return;
        const mods = event.modifiers & (Qt.ShiftModifier | Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier);
        recording = false;
        captured(event.key | mods);
    }
}
