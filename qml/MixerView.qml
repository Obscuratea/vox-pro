import QtQuick
import QtQuick.Controls.Basic

// The mixer: every channel in one row of strips (inputs, virtual inputs, then the slim outputs). Strips share the
// width that is there; when it runs short they slim down to fader, meter and mute, and after that the row scrolls.
// In a narrow window each channel is a row instead.
Item {
    id: view
    required property var app

    readonly property int nHw: app.showInputs ? app.hwIdx.length : 0
    readonly property int nVirt: app.showVirtual ? app.virtIdx.length : 0
    readonly property int nA: app.showOutputs ? app.aIdx.length : 0
    readonly property int nB: app.showOutputs ? app.bIdx.length : 0
    readonly property int nIn: nHw + nVirt
    readonly property int nOut: nA + nB
    readonly property int nSections: (nHw > 0) + (nVirt > 0) + (nA > 0) + (nB > 0)
    readonly property real pad: 16
    readonly property real stripHeight: height - 2 * pad - 26
    // Full strips need room for the quick switches and the routing buttons, across and down.
    // Settings > Fit detail to window size off: a narrow window keeps full strips and the row scrolls instead
    // (a short one still slims them, since full strips don't fit its height).
    readonly property bool condensed: app.compact || stripHeight < 410 || app.prefs.fit_detail !== false && (
        nIn * 150 + nOut * 88 > width - 2 * pad - Math.max(0, nIn + nOut - nSections) * 10 - Math.max(0, nSections - 1) * 20)
    readonly property real gap: condensed ? 8 : 10
    readonly property real sectionGap: condensed ? 14 : 20
    readonly property real gaps: Math.max(0, nIn + nOut - nSections) * gap + Math.max(0, nSections - 1) * sectionGap
    readonly property real room: width - 2 * pad - gaps
    readonly property real minIn: condensed ? 84 : 150
    readonly property real minOut: condensed ? 66 : 88
    // The strips always share out the whole width (closing the inspector widens them), inputs and outputs
    // keeping their proportions.
    readonly property real stretch: Math.max(1, room / Math.max(1, nIn * minIn + nOut * minOut))
    readonly property real inWidth: Math.floor(minIn * stretch)
    readonly property real outWidth: Math.floor(minOut * stretch)
    readonly property real contentWidth: nIn * inWidth + nOut * outWidth + gaps + 2 * pad

    // The + in a section header adds a channel to the group (removing one is in the inspector).
    component StepButton: Rectangle {
        id: step
        property var app
        property string icon
        property string tip
        signal clicked()
        width: 20; height: 20
        radius: app.soft ? 6 : 0
        color: stepMouse.containsMouse && enabled ? app.hover : "transparent"
        border.color: app.line
        opacity: enabled ? 1 : 0.35
        Icon { anchors.centerIn: parent; name: step.icon; color: stepMouse.containsMouse && step.enabled ? step.app.ink : step.app.dim; width: 12; height: 12 }
        MouseArea { id: stepMouse; anchors.fill: parent; hoverEnabled: true; enabled: step.enabled; cursorShape: Qt.PointingHandCursor; onClicked: step.clicked() }
        ToolTip.visible: stepMouse.containsMouse
        ToolTip.delay: 400
        ToolTip.text: tip
    }

    component Header: Item {
        id: header
        property var app
        property string title
        property string icon
        property string sub
        property string group
        height: 20
        readonly property int count: app.countOf(group)
        readonly property string one: ({ hw: "input", virt: "virtual input", a: "listen output", b: "send output" })[group]
        Row {
            anchors.left: parent.left
            anchors.right: steps.left
            anchors.rightMargin: 6
            anchors.verticalCenter: parent.verticalCenter
            spacing: 7
            clip: true
            Icon { anchors.verticalCenter: parent.verticalCenter; name: header.icon; color: header.app.dim; width: 14; height: 14; visible: header.width > 120 }
            Text {
                id: titleText
                anchors.verticalCenter: parent.verticalCenter
                text: header.title.toUpperCase()
                color: header.app.dim
                font.family: header.app.mono
                font.pixelSize: 11
                font.weight: Font.DemiBold
                font.letterSpacing: header.width > 120 ? 1.5 : 0.6
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                // Only when it fits whole; a cut-off note reads worse than none.
                visible: header.width - 28 >= 21 + titleText.implicitWidth + 7 + implicitWidth
                text: header.sub
                color: Qt.alpha(header.app.ink, 0.35)
                font.pixelSize: 11
            }
        }
        Row {
            id: steps
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            StepButton {
                app: header.app
                icon: "plus"
                enabled: header.count < header.app.limits[header.group]
                tip: enabled ? "Add a " + header.one : "That is the most there can be"
                onClicked: header.app.addChannel(header.group)
            }
        }
    }

    component Section: Column {
        id: sec
        property var host
        property string title
        property string icon
        property string sub
        property string kind: "strip"
        property var slots: []
        property bool slim: false
        property bool shown: true
        property string group
        visible: shown && slots.length > 0
        spacing: 9
        Header { app: sec.host.app; width: Math.max(strips.width, 66); title: sec.title; icon: sec.icon; sub: sec.sub; group: sec.group }
        Row {
            id: strips
            spacing: sec.host.gap
            height: sec.height - 26
            Repeater {
                model: sec.slots
                ChannelStrip {
                    required property int modelData
                    app: sec.host.app
                    kind: sec.kind
                    slot: modelData
                    condensed: sec.host.condensed
                    width: sec.slim ? sec.host.outWidth : sec.host.inWidth
                    height: strips.height
                }
            }
        }
    }

    component MiniSection: Column {
        id: sec
        property var host
        property string title
        property string icon
        property string sub
        property string kind: "strip"
        property var slots: []
        property bool shown: true
        property string group
        visible: shown && slots.length > 0
        spacing: 8
        Header { app: sec.host.app; width: sec.width; title: sec.title; icon: sec.icon; sub: sec.sub; group: sec.group }
        Repeater {
            model: sec.slots
            ChannelRow {
                required property int modelData
                app: sec.host.app
                kind: sec.kind
                slot: modelData
                width: sec.width
            }
        }
        Item { width: 1; height: 4 }
    }

    Text {
        visible: view.nIn + view.nOut === 0
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 320)
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        text: "Everything is hidden. Switch a group back on in the top bar."
        color: view.app.dim
        font.pixelSize: 13
    }

    Loader {
        anchors.fill: parent
        active: !view.app.mini
        sourceComponent: wide
    }
    Loader {
        anchors.fill: parent
        active: view.app.mini
        sourceComponent: narrow
    }

    Component {
    id: wide
    Flickable {
        contentWidth: Math.max(width, view.contentWidth)
        contentHeight: height
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.HorizontalFlick
        ScrollBar.horizontal: ScrollBar { height: 6; policy: ScrollBar.AsNeeded }

        Row {
            x: view.pad
            y: view.pad
            height: view.height - 2 * view.pad
            spacing: view.sectionGap
            Section { host: view; height: parent.height; title: "Inputs"; icon: "mic"; sub: view.condensed ? "" : "hardware"; group: "hw"; slots: view.app.hwIdx; shown: view.app.showInputs }
            Section { host: view; height: parent.height; title: view.condensed && view.app.virtIdx.length < 2 ? "Virtual" : "Virtual inputs"; icon: "app"; sub: view.condensed ? "" : "programs play here"; group: "virt"; slots: view.app.virtIdx; shown: view.app.showVirtual }
            Section { host: view; height: parent.height; title: "Listen"; icon: "out"; sub: view.app.aIdx.length > 1 ? "A outputs" : ""; kind: "bus"; slim: true; group: "a"; slots: view.app.aIdx; shown: view.app.showOutputs }
            Section { host: view; height: parent.height; title: "Send"; icon: "send"; sub: view.app.bIdx.length > 1 ? "B virtual mics" : ""; kind: "bus"; slim: true; group: "b"; slots: view.app.bIdx; shown: view.app.showOutputs }
        }
    }

    }
    Component {
    id: narrow
    Flickable {
        contentWidth: width
        contentHeight: rows.implicitHeight + 24
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollBar { width: 5; policy: ScrollBar.AsNeeded }

        Column {
            id: rows
            x: 12
            y: 12
            width: view.width - 24
            spacing: 8
            MiniSection { host: view; width: parent.width; title: "Inputs"; icon: "mic"; group: "hw"; slots: view.app.hwIdx; shown: view.app.showInputs }
            MiniSection { host: view; width: parent.width; title: "Virtual inputs"; icon: "app"; group: "virt"; slots: view.app.virtIdx; shown: view.app.showVirtual }
            MiniSection { host: view; width: parent.width; title: "Listen"; icon: "out"; sub: "A outputs"; kind: "bus"; group: "a"; slots: view.app.aIdx; shown: view.app.showOutputs }
            MiniSection { host: view; width: parent.width; title: "Send"; icon: "send"; sub: "B virtual mics"; kind: "bus"; group: "b"; slots: view.app.bIdx; shown: view.app.showOutputs }
        }
    }
    }
}
