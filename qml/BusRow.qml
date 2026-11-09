import QtQuick
import QtQuick.Layouts

// One output. A buses play on a device you pick; B buses are virtual mics other programs use.
Rectangle {
    id: row
    required property var app
    required property int index
    readonly property int busIndex: index
    readonly property var bus: app.cfg.buses[busIndex]
    readonly property var peaks: app.meters.buses && app.meters.buses[busIndex] ? app.meters.buses[busIndex] : [0, 0]

    readonly property real reduction: app.meters.limit ? (app.meters.limit[busIndex] || 0) : 0

    color: app.diamond ? "transparent" : app.panelFill
    radius: app.rCard
    border.color: app.diamond ? "transparent" : app.edge

    Glass { app: row.app; radius: row.app.rCard }
    CutFrame { visible: row.app.diamond; anchors.fill: parent; cut: row.app.cut; fill: row.app.panelFill; stroke: row.app.frameDim }

    function set(mutate) {
        app.change(c => mutate(c.buses[row.busIndex]));
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 8

        RowLayout {
            spacing: 8
            Text {
                Layout.fillWidth: true
                text: row.bus.label
                color: row.app.accent
                font.family: row.app.mono
                font.pixelSize: 15
                font.weight: Font.Bold
            }
            Chip {
                app: row.app
                text: row.app.isRecording(row.busIndex) ? "● Rec" : "Rec"
                checked: row.app.isRecording(row.busIndex)
                onColor: row.app.danger
                tip: checked ? "Stop and save the recording (Music/Vox Pro)" : "Record what this output carries to a WAV file in Music/Vox Pro"
                onToggled: row.app.recordBus(row.busIndex, !checked)
            }
            Chip {
                app: row.app
                text: row.bus.mute ? (row.app.t("Muted")) : (row.app.t("Mute"))
                checked: row.bus.mute
                onColor: row.app.danger
                onToggled: row.set(b => b.mute = !b.mute)
            }
        }
        DevicePicker {
            visible: !row.bus.virtual_output
            Layout.fillWidth: true
            app: row.app
            devices: row.app.devices.sinks
            current: row.bus.device
            onPicked: name => row.set(b => b.device = name)
        }
        LevelMeter {
            Layout.fillWidth: true
            Layout.preferredHeight: 10
            app: row.app
            vertical: false
            peaks: row.peaks
        }
        RowLayout {
            spacing: 8
            Fader {
                Layout.fillWidth: true
                app: row.app
                vertical: false
                value: row.bus.gain_db
                onMoved: v => row.set(b => b.gain_db = v)
            }
            Text {
                Layout.preferredWidth: 58
                horizontalAlignment: Text.AlignRight
                text: row.app.db(row.bus.gain_db)
                color: row.app.ink
                font.family: row.app.mono
                font.pixelSize: 12
            }
        }
        RowLayout {
            spacing: 8
            Chip {
                app: row.app
                text: row.app.t("Limiter")
                checked: !!row.bus.limiter_on
                tip: "Nothing leaves this output louder than the ceiling, so a sudden loud sound can't blast or clip"
                onToggled: row.set(b => b.limiter_on = !b.limiter_on)
            }
            ToneSlider {
                Layout.fillWidth: true
                app: row.app
                enabled: !!row.bus.limiter_on
                label: row.reduction > 0.1 ? "Limiting " + row.reduction.toFixed(1) + " dB" : "Ceiling"
                from: -24
                to: 0
                resetValue: -1
                value: row.bus.limiter_db
                onMoved: v => row.set(b => b.limiter_db = v)
            }
        }
        // A virtual mic also shows which programs are recording from it.
        StreamList {
            visible: row.bus.virtual_output
            Layout.fillWidth: true
            Layout.fillHeight: true
            app: row.app
            target: row.bus.label.toLowerCase()
            mutable: false
            emptyText: "Nobody is using this mic"
        }
    }
}
