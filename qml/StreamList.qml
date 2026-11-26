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
    // Streams in one of our strips can be sent back to where they would play by themselves (a sound card's
    // channel outputs to the card, a program to the default device): the button, or dragging out of the list.
    readonly property bool canSendBack: mutable && target !== "other"
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
            width: slot.width
            height: slot.height
            radius: list.app.diamond ? 0 : height / 2
            color: list.app.soft ? list.app.tonal : list.app.hover
            border.color: list.app.edge
            opacity: modelData.muted ? 0.6 : (dragArea.drag.active ? 0.35 : 1)

            // Drag a playing program onto the Apps or Media strip to send it there. The pill itself stays put;
            // what moves is a picture of it on the window overlay, so it isn't clipped by the list and has
            // nothing to put back afterwards.
            Item {
                id: ghost
                parent: pill.Overlay.overlay
                property var stream: slot.modelData     // what a DropArea reads from the dragged item
                width: pill.width
                height: pill.height
                visible: dragArea.drag.active
                Drag.active: dragArea.drag.active
                Drag.keys: ["vox-stream"]
                ShaderEffectSource {
                    anchors.fill: parent
                    sourceItem: ghost.visible ? pill : null
                    hideSource: false
                }
            }
            MouseArea {
                id: dragArea
                anchors.fill: parent
                enabled: list.mutable
                cursorShape: list.mutable ? (drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor) : Qt.ArrowCursor
                drag.target: ghost
                // Start the picture exactly over the pill; the drag moves it from there. It drops where the
                // pointer is (the spot it was grabbed by), not at its middle, which can be far off on a wide pill.
                onPressed: mouse => {
                    const p = pill.mapToItem(ghost.parent, 0, 0);
                    ghost.x = p.x;
                    ghost.y = p.y;
                    ghost.Drag.hotSpot = Qt.point(mouse.x, mouse.y);
                }
                onReleased: mouse => {
                    if (!drag.active) return;
                    // Over a strip? (Drag.target is the DropArea under the pointer; the strips take the drop
                    // without accepting it, so drop()'s result can't tell.)
                    const accepted = ghost.Drag.target !== null;
                    ghost.Drag.drop();
                    // Let go outside the list and not on a strip: send it back.
                    const p = dragArea.mapToItem(list, mouse.x, mouse.y);
                    const outside = p.x < 0 || p.y < 0 || p.x > list.width || p.y > list.height;
                    if (!accepted && outside && list.canSendBack)
                        list.app.sendBack(pill.modelData.id, pill.modelData.name);
                }
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
                    color: pill.modelData.icon !== "" && !pill.modelData.device ? "transparent" : Qt.alpha(list.app.accent, 0.25)
                    Icon {
                        visible: !!pill.modelData.device
                        anchors.centerIn: parent
                        width: 14; height: 14
                        name: "speaker"
                        color: list.app.ink
                    }
                    Text {
                        visible: pill.modelData.icon === "" && !pill.modelData.device
                        anchors.centerIn: parent
                        text: pill.modelData.name.charAt(0).toUpperCase()
                        color: list.app.ink
                        font.pixelSize: 11
                        font.weight: Font.Bold
                    }
                    Image {
                        visible: !pill.modelData.device
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
                IconButton {
                    visible: list.canSendBack
                    app: list.app
                    icon: "back"
                    quiet: true
                    implicitWidth: 24
                    implicitHeight: 24
                    radius: 12
                    tip: pill.modelData.device ? "Send " + pill.modelData.name + " back to its sound card"
                                               : "Send " + pill.modelData.name + " back to the default output"
                    onClicked: list.app.sendBack(pill.modelData.id, pill.modelData.name)
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
