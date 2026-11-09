import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic

// The programs currently using one of our devices, each in a pill with its icon. Playing streams
// get a mute button; recording streams (who is listening to a B mic) are just listed.
Item {
    id: list
    required property var app
    required property string target
    property bool mutable: true
    property string emptyText: "Nothing playing"
    readonly property var items: app.streams.filter(s => s.target === target)

    Text {
        visible: list.items.length === 0
        anchors.fill: parent
        text: list.emptyText
        color: list.app.dim
        font.pixelSize: 11
        wrapMode: Text.WordWrap
    }

    ListView {
        anchors.fill: parent
        visible: list.items.length > 0
        clip: true
        spacing: 6
        model: list.items
        delegate: Item {
          id: slot
          required property var modelData
          width: ListView.view.width
          height: 34
          Rectangle {
            id: pill
            property var modelData: slot.modelData
            property var stream: slot.modelData     // what a DropArea reads from the dragged pill
            width: slot.width
            height: slot.height
            radius: list.app.diamond ? 0 : height / 2
            color: list.app.soft ? list.app.tonal : list.app.hover
            border.color: list.app.edge
            opacity: modelData.muted ? 0.6 : 1

            // Drag a playing program onto the Apps or Media strip to send it there. While dragging, the pill
            // moves to the window overlay so it isn't clipped by the list.
            Drag.active: dragArea.drag.active
            Drag.keys: ["vox-stream"]
            Drag.hotSpot.x: width / 2
            Drag.hotSpot.y: height / 2
            states: State {
                when: dragArea.drag.active
                ParentChange { target: pill; parent: Overlay.overlay }
            }
            MouseArea {
                id: dragArea
                anchors.fill: parent
                enabled: list.mutable
                cursorShape: list.mutable ? (drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor) : Qt.ArrowCursor
                drag.target: pill
                onReleased: pill.Drag.drop()
            }
            Connections {
                target: dragArea.drag
                function onActiveChanged() { if (!dragArea.drag.active) { pill.x = 0; pill.y = 0; } }
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 7
                anchors.rightMargin: 5
                spacing: 8

                // The first letter shows behind the icon, so a program with no icon still gets a badge.
                Rectangle {
                    Layout.preferredWidth: 22
                    Layout.preferredHeight: 22
                    radius: 11
                    color: pill.modelData.icon !== "" ? "transparent" : Qt.alpha(list.app.accent, 0.25)
                    Text {
                        visible: pill.modelData.icon === ""
                        anchors.centerIn: parent
                        text: pill.modelData.name.charAt(0).toUpperCase()
                        color: list.app.ink
                        font.pixelSize: 11
                        font.weight: Font.Bold
                    }
                    Image {
                        anchors.fill: parent
                        source: pill.modelData.icon
                        sourceSize: Qt.size(44, 44)
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: pill.modelData.name
                    color: list.app.ink
                    font.pixelSize: 12
                    elide: Text.ElideRight
                    font.strikeout: pill.modelData.muted
                }
                Chip {
                    visible: list.mutable
                    app: list.app
                    text: pill.modelData.muted ? (list.app.t("Muted")) : (list.app.t("Mute"))
                    checked: pill.modelData.muted
                    implicitHeight: 24
                    radius: 12
                    onColor: list.app.danger
                    tip: "Mute just " + pill.modelData.name
                    onToggled: list.app.muteStream(pill.modelData.id, !pill.modelData.muted)
                }
            }
          }
        }
    }
}
