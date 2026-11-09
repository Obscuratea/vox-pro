import QtQuick
import QtQuick.Layouts

// Three bell filters for one strip (on top of Bass and Brightness).
ColumnLayout {
    id: root
    required property var card
    Layout.fillWidth: true
    spacing: 12
    Chip {
        Layout.fillWidth: true
        app: card.app
        text: card.app.t("EQ")
        checked: !!card.strip.eq_on
        tip: "Three adjustable bands, after Bass and Brightness"
        onToggled: card.set(s => s.eq_on = !s.eq_on)
    }
    Repeater {
        model: [
            { name: "Low", from: 40, to: 800, step: 10 },
            { name: "Mid", from: 200, to: 5000, step: 50 },
            { name: "High", from: 1500, to: 12000, step: 100 }
        ]
        ColumnLayout {
            id: band
            required property int index
            required property var modelData
            Layout.fillWidth: true
            spacing: 6
            enabled: !!card.strip.eq_on
            opacity: enabled ? 1 : 0.5
            Text {
                text: card.app.t(band.modelData.name + " band")
                color: card.app.ink
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }
            ToneSlider {
                Layout.fillWidth: true
                app: card.app
                label: "Gain"
                value: card.strip.eq_db[band.index]
                onMoved: v => card.set(s => s.eq_db[band.index] = v)
            }
            ToneSlider {
                Layout.fillWidth: true
                app: card.app
                label: "Frequency"
                from: band.modelData.from
                to: band.modelData.to
                step: band.modelData.step
                resetValue: [250, 1000, 3500][band.index]
                format: card.hz
                value: card.strip.eq_hz[band.index]
                onMoved: v => card.set(s => s.eq_hz[band.index] = v)
            }
        }
    }
}

