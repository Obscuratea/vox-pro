import QtQuick
import QtQuick.Layouts

// Compressor for one strip, with a live gain-reduction meter.
ColumnLayout {
    id: root
    required property var card
    Layout.fillWidth: true
    spacing: 12
    Chip {
        Layout.fillWidth: true
        app: card.app
        text: card.app.t("Compressor")
        checked: !!card.strip.comp_on
        tip: "Turns loud parts down so your level stays even"
        onToggled: card.set(s => s.comp_on = !s.comp_on)
    }
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 12
        enabled: !!card.strip.comp_on
        opacity: enabled ? 1 : 0.5
        ToneSlider {
            Layout.fillWidth: true
            app: card.app
            label: "Threshold"
            from: -60
            to: 0
            resetValue: -18
            value: card.strip.comp_threshold_db
            onMoved: v => card.set(s => s.comp_threshold_db = v)
        }
        ToneSlider {
            Layout.fillWidth: true
            app: card.app
            label: "Ratio"
            from: 1
            to: 20
            resetValue: 3
            format: v => v.toFixed(1) + " : 1"
            value: card.strip.comp_ratio
            onMoved: v => card.set(s => s.comp_ratio = v)
        }
        ToneSlider {
            Layout.fillWidth: true
            app: card.app
            label: "Attack"
            from: 0.5
            to: 200
            step: 0.5
            resetValue: 10
            format: v => v.toFixed(1) + " ms"
            value: card.strip.comp_attack_ms
            onMoved: v => card.set(s => s.comp_attack_ms = v)
        }
        ToneSlider {
            Layout.fillWidth: true
            app: card.app
            label: "Release"
            from: 10
            to: 1000
            step: 5
            resetValue: 120
            format: v => Math.round(v) + " ms"
            value: card.strip.comp_release_ms
            onMoved: v => card.set(s => s.comp_release_ms = v)
        }
        ToneSlider {
            Layout.fillWidth: true
            app: card.app
            label: "Make-up gain"
            from: 0
            to: 24
            resetValue: 0
            value: card.strip.comp_makeup_db
            onMoved: v => card.set(s => s.comp_makeup_db = v)
        }
        // How far the compressor is turning you down right now.
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 34
            Text {
                anchors.left: parent.left
                anchors.top: parent.top
                text: card.app.t("Turning down")
                color: card.app.dim
                font.pixelSize: 11
            }
            Text {
                anchors.right: parent.right
                anchors.top: parent.top
                text: card.reduction.toFixed(1) + " dB"
                color: card.reduction > 0.5 ? card.app.accent : card.app.dim
                font.family: card.app.mono
                font.pixelSize: 11
            }
            Rectangle {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                height: 8
                radius: 4
                color: card.app.hover
                Rectangle {
                    anchors.right: parent.right
                    height: parent.height
                    radius: 4
                    width: parent.width * Math.min(1, card.reduction / 20)
                    color: card.app.accent
                }
            }
        }
    }
}
