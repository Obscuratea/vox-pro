import QtQuick
import QtQuick.Layouts

// The strip's plugins on the back of its card: each one with its switch, and the way into the rack.
ColumnLayout {
    id: root
    required property var card
    readonly property var slots: card.strip.plugins || []
    Layout.fillWidth: true
    spacing: 8
    Repeater {
        model: root.slots.length
        RowLayout {
            id: row
            required property int index
            readonly property var slot: root.slots[index]
            Layout.fillWidth: true
            spacing: 6
            Text {
                Layout.fillWidth: true
                text: row.slot.name
                color: card.app.ink
                opacity: row.slot.on ? 1 : 0.5
                font.pixelSize: 12
                elide: Text.ElideRight
            }
            Chip {
                app: card.app
                implicitHeight: 24
                text: row.slot.on ? card.app.t("On") : card.app.t("Off")
                checked: row.slot.on
                onToggled: card.set(s => s.plugins[row.index].on = !s.plugins[row.index].on)
            }
        }
    }
    Text {
        visible: root.slots.length === 0
        Layout.fillWidth: true
        text: "No plugins yet"
        color: card.app.dim
        font.pixelSize: 12
    }
    TextButton {
        Layout.fillWidth: true
        Layout.topMargin: 4
        app: card.app
        text: root.slots.length === 0 ? (card.app.diamond ? "+ add plugin" : "+  Add plugin") : (card.app.diamond ? "open rack" : "Open rack")
        onClicked: card.app.openRack("strip", card.index)
    }
}
