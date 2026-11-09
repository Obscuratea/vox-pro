import QtQuick
import QtQuick.Layouts

// One input: where the sound comes from, how loud it is, where it goes, and voice shaping.
Rectangle {
    id: card
    required property var app
    required property int index
    readonly property var strip: app.cfg.strips[index]
    readonly property var peaks: app.meters.strips && app.meters.strips[index] ? app.meters.strips[index] : [0, 0]
    readonly property bool sendsToMic: strip.routes[5] || strip.routes[6] || strip.routes[7]
    readonly property bool isApps: strip.virtual_input && strip.label === "Apps"
    // Voice effects live on the back of mic strips. The front only shows whether any of them is on.
    readonly property bool effectsOn: !strip.virtual_input
        && (strip.gate_on || strip.duck_on || strip.bass_db !== 0 || strip.brightness_db !== 0 || strip.pitch_semitones !== 0)
    // Virtual strips (Apps, Media) flip to the list of programs using them; the dot says someone is.
    readonly property var playing: strip.virtual_input ? app.streams.filter(s => s.target === strip.label.toLowerCase()) : []
    readonly property bool dotOn: strip.virtual_input ? playing.length > 0 : effectsOn
    property real turn: Qt.application.arguments.indexOf("--flip") >= 0 ? 180 : 0   // degrees; --flip is a dev aid for screenshots
    readonly property bool showingBack: turn >= 90
    readonly property int flipBelow: 70   // room under the flip/Done button, for the hint text on the front
    Behavior on turn { NumberAnimation { duration: 380; easing.type: Easing.InOutCubic } }
    transform: Rotation {
        origin.x: card.width / 2
        origin.y: card.height / 2
        axis { x: 0; y: 1; z: 0 }
        angle: card.turn < 90 ? card.turn : card.turn - 180
    }

    color: app.diamond ? "transparent" : app.panelFill
    radius: app.rCard
    border.color: app.diamond ? "transparent" : app.edge

    Glass { app: card.app; radius: card.app.rCard }
    CutFrame { visible: card.app.diamond; anchors.fill: parent; cut: card.app.cut; fill: card.app.panelFill; stroke: card.app.frameDim }

    function set(mutate) {
        app.change(c => mutate(c.strips[card.index]));
    }

    ColumnLayout {
        id: front
        visible: !card.showingBack
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10

        RowLayout {
            spacing: 8
            Rectangle {
                Layout.preferredWidth: 26
                Layout.preferredHeight: 18
                radius: card.app.diamond ? 0 : 9
                color: card.app.soft ? card.app.tonal : "transparent"
                border.color: card.app.edge
                Text {
                    anchors.centerIn: parent
                    text: "0" + (card.index + 1)
                    color: card.app.dim
                    font.family: card.app.mono
                    font.pixelSize: 11
                }
            }
            Text {
                Layout.fillWidth: true
                text: card.app.t(card.strip.label)
                color: card.app.ink
                font.family: card.app.display
                font.pixelSize: 14
                font.weight: Font.Bold
                font.letterSpacing: card.app.soft || card.app.diamond ? 0.5 : 2
                elide: Text.ElideRight
            }
        }

        DevicePicker {
            visible: !card.strip.virtual_input
            Layout.fillWidth: true
            app: card.app
            devices: card.app.devices.sources
            current: card.strip.source
            onPicked: name => card.set(s => s.source = name)
        }
        Item {
            visible: card.strip.virtual_input
            Layout.fillWidth: true
            Layout.preferredHeight: 30
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10
            Item { Layout.fillWidth: true }
            Fader {
                app: card.app
                Layout.fillHeight: true
                value: card.strip.gain_db
                onMoved: v => card.set(s => s.gain_db = v)
            }
            LevelMeter {
                app: card.app
                Layout.fillHeight: true
                peaks: card.peaks
            }
            Item { Layout.fillWidth: true }
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: card.app.db(card.strip.gain_db)
            color: card.app.ink
            font.family: card.app.mono
            font.pixelSize: 12
        }

        Text {
            text: card.app.t("Listen on")
            color: card.app.dim
            font.family: card.app.mono
            font.pixelSize: 10
            font.letterSpacing: 1
        }
        GridLayout {
            Layout.fillWidth: true
            columns: 3
            columnSpacing: 5
            rowSpacing: 5
            Repeater {
                model: 5
                Chip {
                    required property int index
                    Layout.fillWidth: true
                    app: card.app
                    text: "A" + (index + 1)
                    checked: card.strip.routes[index]
                    tip: card.app.busTip(index)
                    onToggled: card.set(s => s.routes[index] = !s.routes[index])
                }
            }
        }

        Text {
            text: card.app.t("Send to mic")
            color: card.app.dim
            font.family: card.app.mono
            font.pixelSize: 10
            font.letterSpacing: 1
        }
        GridLayout {
            Layout.fillWidth: true
            columns: 3
            columnSpacing: 5
            Repeater {
                model: 3
                Chip {
                    required property int index
                    readonly property int bus: index + 5
                    Layout.fillWidth: true
                    app: card.app
                    text: "B" + (index + 1)
                    checked: card.strip.routes[bus]
                    tip: card.app.busTip(bus)
                    onToggled: card.set(s => s.routes[bus] = !s.routes[bus])
                }
            }
        }

        RowLayout {
            spacing: 6
            Chip {
                Layout.fillWidth: true
                app: card.app
                text: card.strip.mute ? (card.app.t("Muted")) : (card.app.t("Mute"))
                checked: card.strip.mute
                onColor: card.app.danger
                onToggled: card.set(s => s.mute = !s.mute)
            }
            Chip {
                Layout.preferredWidth: 56
                app: card.app
                text: card.app.t("Solo")
                checked: !!card.strip.solo
                onColor: card.app.warning
                tip: "Listen to just this strip on A1-A5. The mics (B1-B3) are not affected."
                onToggled: card.set(s => s.solo = !s.solo)
            }
        }

        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: card.app.soft ? "transparent" : card.app.line }

        // Fixed height so every strip's fader lines up, with or without voice tools.
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 170

            // One button to the back of the strip (voice tools, or the programs using it), with a dot when
            // something is on / playing.
            ColumnLayout {
                anchors.bottom: parent.bottom
                width: parent.width
                height: card.flipBelow
                spacing: 8
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    text: card.strip.virtual_input ? (card.isApps ? "Programs on the system output" : "Programs you sent here") : "Gate · Bass · Brightness · Pitch · EQ"
                    color: card.app.dim
                    font.pixelSize: 11
                }
                Text {
                    // Apps carries everything, voice chat included, so warn before it goes to a mic.
                    visible: card.strip.virtual_input && card.isApps && card.sendsToMic
                    Layout.fillWidth: true
                    Layout.topMargin: 6
                    horizontalAlignment: Text.AlignHCenter
                    text: "Voice chat playing here also goes into the mic, so people may hear themselves."
                    color: card.app.warning
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

    Rectangle {
        // One button for both faces, pinned to the same spot so flipping back is a double-click away.
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 14 + card.flipBelow
        width: 130
        height: 36
        radius: card.app.soft ? height / 2 : 0
        CutFrame { visible: card.app.diamond; anchors.fill: parent; cut: card.app.cut
            fill: flipMouse.pressed ? card.app.select : (flipMouse.containsMouse ? Qt.alpha(card.app.accent, 0.14) : "transparent")
            stroke: flipMouse.containsMouse ? card.app.accent : card.app.frameDim }
        color: card.app.diamond ? "transparent" : flipMouse.pressed ? card.app.onFill : flipMouse.containsMouse ? (card.app.soft ? Qt.tint(card.app.tonal, Qt.alpha(card.app.accent, 0.18)) : card.app.hover) : card.app.soft ? card.app.tonal : "transparent"
        border.color: card.app.diamond ? "transparent" : card.app.soft ? (flipMouse.containsMouse ? card.app.accent : card.app.controlEdge) : flipMouse.containsMouse ? card.app.accent : card.app.line
        Rectangle {
            visible: card.dotOn && !card.showingBack
            x: 14
            anchors.verticalCenter: parent.verticalCenter
            width: 8
            height: 8
            radius: 4
            color: card.app.accent
        }
        Text {
            id: flipLabel
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: card.dotOn && !card.showingBack ? 6 : 0
            text: card.showingBack ? "Done  ⟲" : (card.strip.virtual_input ? "Programs" : "Voice") + "  ⟲"
            color: card.app.ink
            font.pixelSize: 13
            font.weight: Font.DemiBold
        }
        MouseArea {
            id: flipMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: card.turn = card.showingBack ? 0 : 180
        }
    }

    // Back face of mic strips: the voice tools.
    ColumnLayout {
        id: back
        visible: card.showingBack && !card.strip.virtual_input
        anchors.fill: parent
        anchors.margins: 14
        anchors.bottomMargin: 14 + card.flipBelow + 36 + 12
        spacing: 12

        RowLayout {
            spacing: 8
            Text {
                Layout.fillWidth: true
                text: card.app.t(card.strip.label + " · voice")
                color: card.app.ink
                font.family: card.app.display
                font.pixelSize: 14
                font.weight: Font.Bold
                font.letterSpacing: card.app.soft || card.app.diamond ? 0.3 : 2
                elide: Text.ElideRight
            }
        }

        Chip {
            Layout.fillWidth: true
            app: card.app
            text: card.app.t("Gate")
            checked: card.strip.gate_on
            tip: "Silences the mic between words"
            onToggled: card.set(s => s.gate_on = !s.gate_on)
        }
        ToneSlider {
            Layout.fillWidth: true
            app: card.app
            label: "Gate threshold"
            enabled: card.strip.gate_on
            from: -80
            to: 0
            resetValue: -45
            value: card.strip.gate_threshold_db
            onMoved: v => card.set(s => s.gate_threshold_db = v)
        }
        ToneSlider {
            Layout.fillWidth: true
            app: card.app
            label: "Bass"
            value: card.strip.bass_db
            onMoved: v => card.set(s => s.bass_db = v)
        }
        ToneSlider {
            Layout.fillWidth: true
            app: card.app
            label: "Brightness"
            value: card.strip.brightness_db
            onMoved: v => card.set(s => s.brightness_db = v)
        }
        ToneSlider {
            Layout.fillWidth: true
            app: card.app
            label: "Pitch"
            format: card.app.semitones
            value: card.strip.pitch_semitones
            onMoved: v => card.set(s => s.pitch_semitones = v)
        }
        Chip {
            Layout.fillWidth: true
            app: card.app
            text: card.app.t("Hear my natural voice")
            checked: !!card.strip.a_hears_dry
            enabled: card.strip.pitch_semitones !== 0
            opacity: enabled ? 1 : 0.5
            tip: "A1-A3 play your voice without the pitch (and its delay). B1/B2 still carry the pitched voice."
            onToggled: card.set(s => s.a_hears_dry = !s.a_hears_dry)
        }
        Text {
            Layout.fillWidth: true
            visible: card.strip.pitch_semitones !== 0
            text: card.strip.a_hears_dry ? "You hear yourself with no delay. B1/B2 get the pitched voice, about 80 ms behind." : "Pitch adds about 80 ms of delay while it is on."
            color: card.app.warning
            font.pixelSize: 11
            wrapMode: Text.WordWrap
        }
        Chip {
            Layout.fillWidth: true
            app: card.app
            text: card.app.t("Duck programs")
            checked: !!card.strip.duck_on
            tip: "While you are talking, the program strips dip so people hear you over them"
            onToggled: card.set(s => s.duck_on = !s.duck_on)
        }
        ToneSlider {
            Layout.fillWidth: true
            visible: !!card.strip.duck_on
            app: card.app
            label: "Duck when louder than"
            from: -80
            to: -6
            resetValue: -40
            value: card.strip.duck_threshold_db
            onMoved: v => card.set(s => s.duck_threshold_db = v)
        }
        ToneSlider {
            Layout.fillWidth: true
            visible: !!card.strip.duck_on
            app: card.app
            label: "Duck by"
            from: -30
            to: 0
            resetValue: -10
            value: card.strip.duck_db
            onMoved: v => card.set(s => s.duck_db = v)
        }
        RowLayout {
            visible: !!card.strip.duck_on
            spacing: 6
            Chip {
                Layout.fillWidth: true
                app: card.app
                text: card.app.t("On B mics")
                checked: card.strip.duck_b !== false
                tip: "Duck what the B1/B2 mics carry (what others hear)"
                onToggled: card.set(s => s.duck_b = !(s.duck_b !== false))
            }
            Chip {
                Layout.fillWidth: true
                app: card.app
                text: card.app.t("On A")
                checked: !!card.strip.duck_a
                tip: "Duck what you hear on A1-A3 too"
                onToggled: card.set(s => s.duck_a = !s.duck_a)
            }
        }
        Item { Layout.fillHeight: true }
        Text {
            Layout.fillWidth: true
            text: "Double-click a slider to reset it."
            wrapMode: Text.WordWrap
            color: card.app.dim
            font.pixelSize: 11
        }
    }

    // Back face of Apps / Media: the programs using the strip, each with its own mute.
    ColumnLayout {
        id: appsBack
        visible: card.showingBack && card.strip.virtual_input
        anchors.fill: parent
        anchors.margins: 14
        anchors.bottomMargin: 14 + card.flipBelow + 36 + 12
        spacing: 12

        RowLayout {
            spacing: 8
            Text {
                Layout.fillWidth: true
                text: card.app.t(card.strip.label)
                color: card.app.ink
                font.family: card.app.display
                font.pixelSize: 14
                font.weight: Font.Bold
                font.letterSpacing: card.app.soft || card.app.diamond ? 0.3 : 2
                elide: Text.ElideRight
            }
        }
        StreamList {
            Layout.fillWidth: true
            Layout.fillHeight: true
            app: card.app
            target: card.strip.label.toLowerCase()
            emptyText: card.isApps ? "Nothing playing. Programs that use the system output show up here." : "Nothing playing. Drag a program here, or send one from Plasma's volume menu."
        }
        Text {
            visible: otherList.items.length > 0
            text: card.app.t("Playing elsewhere")
            color: card.app.dim
            font.family: card.app.mono
            font.pixelSize: 10
            font.letterSpacing: 1
        }
        StreamList {
            id: otherList
            visible: items.length > 0
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(items.length * 40, 140)
            app: card.app
            target: "other"
        }
        Text {
            Layout.fillWidth: true
            text: "Drag a program onto a program strip to send it there."
            color: card.app.dim
            font.pixelSize: 11
            wrapMode: Text.WordWrap
        }
    }

    // Drop a program here (dragged from a program list on an Apps or Media back) to send it to this strip.
    DropArea {
        id: drops
        anchors.fill: parent
        enabled: card.strip.virtual_input
        keys: ["vox-stream"]
        readonly property string name: card.strip.label.toLowerCase()
        onDropped: drop => {
            const s = drop.source.stream;
            if (s && s.target !== drops.name)
                card.app.moveStream(s.id, drops.name, card.strip.label);
        }
    }
    Rectangle {
        visible: drops.enabled && drops.containsDrag
        anchors.fill: parent
        radius: card.radius
        color: Qt.alpha(card.app.accent, 0.12)
        border.width: 2
        border.color: card.app.accent
    }
}
