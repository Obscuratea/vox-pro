import QtQuick

// A button that records a key combination. Click it, press the keys you want (Esc cancels).
// `key` is a Qt key code: the key plus its modifier flags, 0 for none (the format KDE's shortcut service takes).
Rectangle {
    id: cap
    required property var app
    property int key: 0
    property bool recording: false
    signal captured(int key)

    implicitWidth: 150
    implicitHeight: 32
    radius: app.soft ? height / 2 : 0
    color: recording ? Qt.alpha(app.accent, 0.18) : app.soft ? app.tonal : "transparent"
    border.color: recording || mouse.containsMouse ? app.accent : app.soft ? app.controlEdge : app.line
    activeFocusOnTab: true
    onActiveFocusChanged: if (!activeFocus) recording = false

    Text {
        anchors.centerIn: parent
        text: cap.recording ? "Press keys…  (Esc cancels)" : cap.key === 0 ? "Not set" : cap.app.keyText(cap.key)
        color: cap.recording || cap.key !== 0 ? cap.app.ink : cap.app.dim
        font.pixelSize: 12
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
