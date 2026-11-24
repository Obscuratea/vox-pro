import QtQuick
import QtQuick.Layouts

// One channel as a row, for a narrow window: name, level and mute on one line, the fader under it.
Card {
    id: row
    property string kind: "strip"
    property int slot: 0

    readonly property bool isBus: kind === "bus"
    readonly property var ch: (isBus ? app.cfg.buses[slot] : app.cfg.strips[slot]) || app.blank
    readonly property var peaks: { const m = isBus ? app.meters.buses : app.meters.strips; return m && m[slot] ? m[slot] : [0, 0]; }

    implicitHeight: 84
    corner: app.soft ? 14 : 0
    selected: app.inspShown && app.sel.kind === kind && app.sel.index === slot

    function set(mutate) {
        app.change(c => mutate(row.isBus ? c.buses[row.slot] : c.strips[row.slot]));
    }

    MouseArea {
        anchors.fill: parent
        onClicked: row.app.selectChannel(row.kind, row.slot, true)
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 5

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Tag { app: row.app; text: row.app.tagOf(row.kind, row.slot) }
            Text {
                Layout.fillWidth: true
                text: row.app.nameOf(row.kind, row.slot)
                color: row.app.ink
                font.family: row.app.display
                font.pixelSize: 14
                font.weight: Font.Bold
                elide: Text.ElideRight
                MouseArea {
                    anchors.fill: parent
                    anchors.leftMargin: -60
                    anchors.margins: -6
                    cursorShape: Qt.PointingHandCursor
                    onClicked: row.app.selectChannel(row.kind, row.slot, true)
                }
            }
            Text {
                text: row.app.db(row.ch.gain_db || 0)
                color: row.ch.mute ? row.app.dim : row.app.ink
                font.family: row.app.mono
                font.pixelSize: 12
            }
            Chip {
                visible: row.isBus
                implicitWidth: 40; implicitHeight: 26
                app: row.app
                text: "EQ"
                checked: !!row.ch.eq_on
                onToggled: row.app.openEq("bus", row.slot)
            }
            Chip {
                implicitWidth: 34; implicitHeight: 26
                app: row.app
                text: "M"
                checked: !!row.ch.mute
                onColor: row.app.danger
                onToggled: row.set(s => s.mute = !s.mute)
            }
        }
        Fader {
            Layout.fillWidth: true
            Layout.preferredHeight: 22
            app: row.app
            vertical: false
            value: row.ch.gain_db || 0
            onMoved: v => row.set(s => s.gain_db = v)
        }
        LevelMeter {
            Layout.fillWidth: true
            Layout.preferredHeight: 6
            app: row.app
            vertical: false
            peaks: row.peaks
        }
    }
}
