import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic

// The parametric EQ page: pick an output (in Vox Pro, an input too) along the top, shape its curve underneath.
Item {
    id: view
    required property var app
    readonly property var picks: (app.pro ? app.hwIdx.concat(app.virtIdx).map(i => ({ kind: "strip", index: i })) : [])
        .concat(app.aIdx.concat(app.bIdx).map(i => ({ kind: "bus", index: i })))

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        Flickable {
            Layout.fillWidth: true
            Layout.preferredHeight: 28
            contentWidth: picks.width
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.HorizontalFlick
            Row {
                id: picks
                spacing: 6
                Repeater {
                    model: view.picks
                    Chip {
                        required property var modelData
                        readonly property string name: view.app.nameOf(modelData.kind, modelData.index)
                        app: view.app
                        text: view.app.tagOf(modelData.kind, modelData.index) + (view.width >= (view.app.pro ? 1300 : 700) ? "  " + name : "")
                        checked: view.app.eqKind === modelData.kind && view.app.eqIndex === modelData.index
                        tip: name
                        onToggled: view.app.openEq(modelData.kind, modelData.index)
                    }
                }
            }
        }
        Flickable {
            id: scroller
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: Math.max(height, editor.wantedHeight)
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { width: 5; policy: ScrollBar.AsNeeded }
            PeqEditor {
                id: editor
                width: scroller.width - (scroller.contentHeight > scroller.height ? 8 : 0)
                height: scroller.contentHeight
                app: view.app
                embedded: true
                kind: view.app.eqKind
                index: view.app.eqIndex
            }
        }
    }
}
