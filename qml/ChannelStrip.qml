import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic

// One channel as a vertical strip: an input (hardware or virtual) or an output (A or B).
// Full strips also carry the quick switches and the routing buttons; condensed strips and outputs keep to
// the fader, meter and mute, and the rest is in the inspector (click the name).
Card {
    id: strip
    property string kind: "strip"       // "strip" (an input) or "bus" (an output)
    property int slot: 0                // index into cfg.strips or cfg.buses
    property bool condensed: false

    readonly property bool isBus: kind === "bus"
    readonly property var ch: (isBus ? app.cfg.buses[slot] : app.cfg.strips[slot]) || app.blank
    readonly property bool virtualIn: !isBus && !!ch.virtual_input
    readonly property bool full: !condensed && !isBus
    readonly property bool stacked: !full
    readonly property bool tight: width < 84
    corner: Math.min(app.rCard, 16)
    readonly property var peaks: { const m = isBus ? app.meters.buses : app.meters.strips; return m && m[slot] ? m[slot] : [0, 0]; }
    readonly property string streamName: app.slug(ch.label)
    readonly property int playing: virtualIn ? app.streams.filter(s => s.target === streamName).length : 0
    readonly property bool echo: virtualIn && ch.label === "Apps" && app.bIdx.some(b => ch.routes[b])

    selected: app.inspShown && app.sel.kind === kind && app.sel.index === slot

    function set(mutate) {
        app.change(c => mutate(strip.isBus ? c.buses[strip.slot] : c.strips[strip.slot]));
    }

    // A click anywhere on the strip that isn't on one of its controls selects it.
    MouseArea {
        anchors.fill: parent
        onClicked: strip.app.selectChannel(strip.kind, strip.slot, true)
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: strip.tight ? 6 : strip.stacked ? 10 : 12
        spacing: 10

        // Tag and name: click to open the inspector on this channel.
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: strip.stacked ? 42 : 20
            Tag {
                id: tag
                app: strip.app
                text: strip.app.tagOf(strip.kind, strip.slot)
                x: strip.stacked ? (parent.width - width) / 2 : 0
            }
            Text {
                x: strip.stacked ? 0 : tag.width + 8
                y: strip.stacked ? 25 : 1
                width: parent.width - x - (warn.visible ? 18 : 0)
                horizontalAlignment: strip.stacked ? Text.AlignHCenter : Text.AlignLeft
                text: strip.app.nameOf(strip.kind, strip.slot)
                color: strip.app.ink
                font.family: strip.app.display
                font.pixelSize: strip.stacked ? 12 : 14
                font.weight: Font.Bold
                elide: Text.ElideRight
            }
            MouseArea {
                id: headMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: strip.app.selectChannel(strip.kind, strip.slot, true)
            }
            // Apps carries everything, voice chat included, so warn while it goes to a mic.
            Text {
                id: warn
                visible: strip.echo && !strip.stacked
                anchors.right: parent.right
                y: 1
                text: "⚠"
                color: strip.app.warning
                font.pixelSize: 13
                HoverHandler { id: echoHover }
                ToolTip.visible: echoHover.hovered
                ToolTip.text: "Voice chat playing through Apps also goes into this mic, so people may hear themselves"
            }
            ToolTip.visible: headMouse.containsMouse
            ToolTip.delay: 600
            ToolTip.text: strip.app.nameOf(strip.kind, strip.slot) + " · " + strip.app.subOf(strip.kind, strip.slot)
        }
        Text {
            visible: strip.full
            Layout.fillWidth: true
            Layout.topMargin: -5
            text: strip.app.subOf(strip.kind, strip.slot)
            color: strip.app.faint
            font.pixelSize: 11
            elide: Text.ElideRight
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 80
            spacing: strip.tight ? 4 : 10
            Item { Layout.fillWidth: true }
            Fader {
                app: strip.app
                Layout.fillHeight: true
                value: strip.ch.gain_db || 0
                onMoved: v => strip.set(s => s.gain_db = v)
            }
            LevelMeter {
                app: strip.app
                Layout.fillHeight: true
                peaks: strip.peaks
            }
            Item { Layout.fillWidth: true }
        }
        // The level as a number, with a quieter "dB".
        Row {
            Layout.alignment: Qt.AlignHCenter
            spacing: 4
            readonly property real v: strip.ch.gain_db || 0
            Text {
                text: (parent.v > 0 ? "+" : parent.v < 0 ? "−" : "") + Math.abs(parent.v).toFixed(1)
                color: strip.ch.mute ? strip.app.dim : strip.app.ink
                font.family: strip.app.mono
                font.pixelSize: 13
                font.weight: Font.DemiBold
            }
            Text {
                text: "dB"
                topPadding: 3
                color: strip.app.faint
                font.family: strip.app.mono
                font.pixelSize: 10
            }
        }

        // The switches: gate and duck on a hardware input, the EQ on an output. Vox Pro adds a row of
        // EQ / COMP / FX on every input, and LIM and FX under an output's EQ.
        RowLayout {
            visible: strip.full && !strip.virtualIn
            Layout.fillWidth: true
            spacing: 5
            Pill {
                Layout.fillWidth: true; Layout.preferredWidth: 20
                app: strip.app
                text: "Gate"
                checked: !!strip.ch.gate_on
                tip: "Noise gate: silences the mic between words"
                onToggled: strip.set(s => s.gate_on = !s.gate_on)
            }
            Pill {
                Layout.fillWidth: true; Layout.preferredWidth: 20
                app: strip.app
                text: "Duck"
                checked: !!strip.ch.duck_on
                tip: "While you are talking, the virtual inputs dip so people hear you over them"
                onToggled: strip.set(s => s.duck_on = !s.duck_on)
            }
        }
        RowLayout {
            visible: strip.full && strip.app.pro
            Layout.fillWidth: true
            spacing: 5
            Pill {
                Layout.fillWidth: true; Layout.preferredWidth: 20
                app: strip.app
                text: "EQ"
                checked: !!strip.ch.eq_on
                tip: "Parametric EQ on this input (opens the editor)"
                onToggled: strip.app.openEq("strip", strip.slot)
            }
            Pill {
                Layout.fillWidth: true; Layout.preferredWidth: 20
                app: strip.app
                text: "Comp"
                checked: !!strip.ch.comp_on
                tip: "Compressor: turns loud parts down so the level stays even"
                onToggled: strip.set(s => s.comp_on = !s.comp_on)
            }
            Pill {
                Layout.fillWidth: true; Layout.preferredWidth: 20
                app: strip.app
                text: "FX"
                readonly property int count: (strip.ch.plugins || []).length
                checked: count > 0 && strip.ch.fx_on !== false
                tip: count === 0 ? "Plugins: none yet (opens the rack)" : "Plugins: " + count + (strip.ch.fx_on !== false ? " in use" : ", all bypassed")
                onToggled: count === 0 ? strip.app.openRack("strip", strip.slot) : strip.set(s => s.fx_on = s.fx_on === false)
            }
        }
        Pill {
            visible: strip.isBus && !strip.condensed
            Layout.fillWidth: true
            app: strip.app
            text: "EQ"
            checked: !!strip.ch.eq_on
            tip: "Parametric EQ on this output (opens the editor)"
            onToggled: strip.app.openEq("bus", strip.slot)
        }
        Pill {
            visible: strip.isBus && !strip.condensed && strip.app.pro
            Layout.fillWidth: true
            Layout.topMargin: -5
            app: strip.app
            text: "Lim"
            checked: !!strip.ch.limiter_on
            tip: "Limiter: keeps this output from going over " + (strip.ch.limiter_db || 0).toFixed(1) + " dB"
            onToggled: strip.set(b => b.limiter_on = !b.limiter_on)
        }
        Pill {
            visible: strip.isBus && !strip.condensed && strip.app.pro
            Layout.fillWidth: true
            Layout.topMargin: -5
            app: strip.app
            text: "FX"
            readonly property int count: (strip.ch.plugins || []).length
            checked: count > 0 && strip.ch.fx_on !== false
            tip: count === 0 ? "Plugins: none yet (opens the rack)" : "Plugins: " + count + (strip.ch.fx_on !== false ? " in use" : ", all bypassed")
            onToggled: count === 0 ? strip.app.openRack("bus", strip.slot) : strip.set(b => b.fx_on = b.fx_on === false)
        }
        // A virtual input shows how many programs play into it.
        RowLayout {
            visible: strip.full && strip.virtualIn
            Layout.fillWidth: true
            Layout.preferredHeight: 24
            spacing: 7
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                width: 7; height: 7; radius: 4
                color: strip.playing > 0 ? strip.app.ok : strip.app.faint
            }
            Text {
                Layout.fillWidth: true
                text: strip.playing === 0 ? "Nothing playing" : strip.playing === 1 ? "1 program playing" : strip.playing + " programs playing"
                color: strip.app.dim
                font.pixelSize: 11
                elide: Text.ElideRight
            }
        }
        // Where a full input strip goes: the A outputs on one line, the B mics on the next.
        Repeater {
            model: strip.full ? [strip.app.aIdx, strip.app.bIdx] : []
            GridLayout {
                id: sends
                required property var modelData
                Layout.fillWidth: true
                columns: Math.max(3, strip.app.aIdx.length, strip.app.bIdx.length)
                columnSpacing: 5
                rowSpacing: 5
                Repeater {
                    model: sends.modelData
                    Pill {
                        required property int modelData
                        Layout.fillWidth: true; Layout.preferredWidth: 10
                        app: strip.app
                        kind: "send"
                        text: strip.app.tagOf("bus", modelData)
                        checked: !!strip.ch.routes[modelData]
                        tip: strip.app.busTip(modelData)
                        onToggled: strip.set(s => s.routes[modelData] = !s.routes[modelData])
                    }
                }
                // Empty cells keep the chips the same width on both lines.
                Repeater {
                    model: Math.max(0, sends.columns - sends.modelData.length)
                    Item { Layout.fillWidth: true; Layout.preferredWidth: 10; implicitHeight: 24 }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Pill {
                Layout.fillWidth: true; Layout.preferredWidth: 20
                app: strip.app
                kind: "mute"
                text: "M"
                checked: !!strip.ch.mute
                tip: strip.ch.mute ? "Muted" : "Mute"
                onToggled: strip.set(s => s.mute = !s.mute)
            }
            // Vox Pro: record what this output carries.
            Pill {
                visible: strip.isBus && strip.app.pro && !strip.tight
                Layout.fillWidth: true; Layout.preferredWidth: 20
                app: strip.app
                kind: "rec"
                text: "●"
                checked: strip.app.pro && strip.app.isRecording(strip.slot)
                tip: checked ? "Stop and save the recording" : "Record this output to a file (Music/" + strip.app.appName + ")"
                onToggled: strip.app.recordBus(strip.slot, !checked)
            }
            Pill {
                visible: !strip.isBus && !strip.tight
                Layout.fillWidth: true; Layout.preferredWidth: 20
                app: strip.app
                kind: "solo"
                text: "S"
                checked: !!strip.ch.solo
                tip: "Solo: listen to just this strip on the A outputs. The B mics are not affected."
                onToggled: strip.set(s => s.solo = !s.solo)
            }
        }
    }

    // Drop a program here (dragged from a program list in the inspector) to send it to this strip.
    DropArea {
        id: drops
        anchors.fill: parent
        enabled: strip.virtualIn
        keys: ["vox-stream"]
        onDropped: drop => {
            const s = drop.source.stream;
            if (s && s.target !== strip.streamName)
                strip.app.moveStream(s.id, strip.streamName, strip.app.nameOf("strip", strip.slot));
        }
    }
    Rectangle {
        visible: drops.enabled && drops.containsDrag
        anchors.fill: parent
        radius: strip.radius
        color: Qt.alpha(strip.app.accent, 0.12)
        border.width: 2
        border.color: strip.app.accent
    }
}
