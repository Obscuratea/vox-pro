import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic

// The whole routing at once: a row per input, a column per output, a button where they meet.
Flickable {
    id: view
    required property var app
    readonly property var ins: app.hwIdx.concat(app.virtIdx)
    readonly property var outs: app.aIdx.concat(app.bIdx)
    readonly property real nameWidth: Math.max(96, Math.min(220, width * 0.26))
    readonly property real cell: Math.max(40, Math.min(120, (width - 32 - nameWidth - (outs.length - 1) * 8) / Math.max(1, outs.length)))

    contentWidth: Math.max(width, grid.width + 32)
    contentHeight: Math.max(height, grid.height + 32)
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar { width: 5; policy: ScrollBar.AsNeeded }
    ScrollBar.horizontal: ScrollBar { height: 5; policy: ScrollBar.AsNeeded }

    Column {
        id: grid
        x: 16
        y: 16
        spacing: 8

        Row {
            spacing: 8
            Item { width: view.nameWidth; height: 1 }
            Repeater {
                model: view.outs
                Column {
                    required property int modelData
                    width: view.cell
                    spacing: 4
                    Tag { anchors.horizontalCenter: parent.horizontalCenter; app: view.app; text: view.app.tagOf("bus", modelData) }
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: view.app.nameOf("bus", modelData)
                        color: view.app.dim
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                }
            }
        }
        Repeater {
            model: view.ins
            Card {
                id: line
                required property int modelData
                readonly property var strip: view.app.cfg.strips[modelData] || view.app.blank
                app: view.app
                corner: view.app.soft ? 14 : 0
                width: view.nameWidth + view.outs.length * (view.cell + 8) + 8
                height: 46
                Row {
                    x: 0
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8
                    Item {
                        width: view.nameWidth
                        height: 30
                        Tag { id: tag; x: 10; anchors.verticalCenter: parent.verticalCenter; app: view.app; text: view.app.tagOf("strip", line.modelData) }
                        Text {
                            x: tag.x + tag.width + 8
                            width: parent.width - x
                            anchors.verticalCenter: parent.verticalCenter
                            text: view.app.nameOf("strip", line.modelData)
                            color: line.strip.mute ? view.app.dim : view.app.ink
                            font.family: view.app.display
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                    }
                    Repeater {
                        model: view.outs
                        Chip {
                            required property int modelData
                            width: view.cell
                            height: 30
                            app: view.app
                            text: checked ? "●" : ""
                            checked: !!(line.strip.routes || [])[modelData]
                            tip: view.app.nameOf("strip", line.modelData) + " → " + view.app.tagOf("bus", modelData)
                            onToggled: view.app.change(c => c.strips[line.modelData].routes[modelData] = !c.strips[line.modelData].routes[modelData])
                        }
                    }
                }
            }
        }
    }
}
