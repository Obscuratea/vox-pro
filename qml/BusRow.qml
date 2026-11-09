import QtQuick
import QtQuick.Layouts

// One output. A buses play on a device you pick; B buses are virtual mics other programs use.
Rectangle {
    id: row
    required property var app
    required property int index
    property int offset: 0
    readonly property int busIndex: index + offset
    readonly property var bus: app.cfg.buses[busIndex]
    readonly property var peaks: app.meters.buses && app.meters.buses[busIndex] ? app.meters.buses[busIndex] : [0, 0]

    // Virtual mics have no device to pick, so they fit on one thin line.
    readonly property bool compact: bus.virtual_output

    implicitHeight: compact ? 48 : 88
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
        anchors.margins: row.compact ? 8 : 12
        spacing: 10

        RowLayout {
            spacing: 10
            Text {
                Layout.preferredWidth: 30
                text: row.bus.label
                color: row.app.accent
                font.family: row.app.mono
                font.pixelSize: 15
                font.weight: Font.Bold
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
                visible: row.compact
                Layout.fillWidth: true
                Layout.preferredHeight: 10
                app: row.app
                vertical: false
                peaks: row.peaks
            }
            Fader {
                visible: row.compact
                Layout.preferredWidth: 110
                app: row.app
                vertical: false
                value: row.bus.gain_db
                onMoved: v => row.set(b => b.gain_db = v)
            }
            Text {
                visible: row.compact
                Layout.preferredWidth: 56
                horizontalAlignment: Text.AlignRight
                text: row.app.db(row.bus.gain_db)
                color: row.app.ink
                font.family: row.app.mono
                font.pixelSize: 12
            }
            Chip {
                app: row.app
                text: row.bus.mute ? (row.app.t("Muted")) : (row.app.t("Mute"))
                checked: row.bus.mute
                onColor: row.app.danger
                onToggled: row.set(b => b.mute = !b.mute)
            }
        }

        RowLayout {
            visible: !row.compact
            spacing: 12
            Item { Layout.preferredWidth: 30 }
            LevelMeter {
                Layout.fillWidth: true
                Layout.preferredHeight: 10
                app: row.app
                vertical: false
                peaks: row.peaks
            }
            Fader {
                Layout.preferredWidth: 150
                app: row.app
                vertical: false
                value: row.bus.gain_db
                onMoved: v => row.set(b => b.gain_db = v)
            }
            Text {
                Layout.preferredWidth: 64
                horizontalAlignment: Text.AlignRight
                text: row.app.db(row.bus.gain_db)
                color: row.app.ink
                font.family: row.app.mono
                font.pixelSize: 12
            }
        }
    }
}
