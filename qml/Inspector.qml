import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic

// Everything about the selected channel that doesn't fit on its strip: its name, device, voice tools, the programs
// using it, its EQ and where it goes. Docked on the right in a wide window, a sheet over the mixer in a small one.
Rectangle {
    id: insp
    required property var app
    // Docked beside the mixer it is part of the window (no fill of its own); over the mixer it needs one.
    property bool docked: true
    readonly property string kind: app.sel.kind
    readonly property int slot: app.sel.index
    readonly property bool isBus: kind === "bus"
    readonly property var ch: (isBus ? app.cfg.buses[slot] : app.cfg.strips[slot]) || app.blank
    readonly property bool virtualIn: !isBus && !!ch.virtual_input
    readonly property bool hardwareIn: !isBus && !ch.virtual_input
    readonly property bool hardwareOut: isBus && !ch.virtual_output
    readonly property bool virtualOut: isBus && !!ch.virtual_output
    readonly property string streamName: app.slug(ch.label)
    readonly property string group: app.groupOf(kind, slot)
    readonly property string kindName: ({ hw: "input", virt: "virtual input", a: "listen output", b: "send output" })[group]
    readonly property bool lastOne: app.countOf(group) <= 1
    readonly property string me: kind + ":" + slot + ":" + (ch.label || "")
    readonly property string node: app.nodePrefix + streamName
    readonly property var playing: app.streams.filter(s => s.target === streamName)
    readonly property var elsewhere: app.streams.filter(s => s.target === "other")
    // How far the compressor (inputs) or limiter (outputs) is turning this channel down right now, in dB.
    readonly property real reduction: { const m = isBus ? app.meters.limit : app.meters.comp; return m ? (m[slot] || 0) : 0; }
    readonly property var plugins: ch.plugins || []

    function set(mutate) {
        app.change(c => mutate(insp.isBus ? c.buses[insp.slot] : c.strips[insp.slot]));
    }

    color: docked ? "transparent" : app.glassy || app.bgOn ? Qt.alpha(app.bg, 0.94) : Qt.tint(app.bg, Qt.alpha(app.ink, 0.035))
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onWheel: wheel => wheel.accepted = true }   // nothing reaches the mixer underneath

    // A titled box, with a switch in its header when the thing it holds can be turned off.
    component Block: Card {
        id: block
        property string title
        property string note
        property bool switchable: false
        property bool on: true
        signal toggled()
        default property alias body: bodyColumn.data
        Layout.fillWidth: true
        corner: app.soft ? 14 : 0
        implicitHeight: 12 + head.height + (bodyColumn.implicitHeight > 0 ? 10 + bodyColumn.implicitHeight : 0) + 12

        Item {
            id: head
            x: 12; y: 12
            width: parent.width - 24
            height: Math.max(20, titles.implicitHeight)
            Column {
                id: titles
                width: parent.width - (block.switchable ? 44 : 0)
                spacing: 2
                Text { width: parent.width; text: block.title; color: block.app.ink; font.pixelSize: 13; font.weight: Font.DemiBold; elide: Text.ElideRight }
                Text { visible: block.note !== ""; width: parent.width; text: block.note; color: block.app.dim; font.pixelSize: 11; wrapMode: Text.WordWrap }
            }
            Toggle {
                visible: block.switchable
                anchors.right: parent.right
                app: block.app
                checked: block.on
                onToggled: block.toggled()
            }
        }
        ColumnLayout {
            id: bodyColumn
            x: 12
            y: head.y + head.height + 10
            width: parent.width - 24
            spacing: 8
            opacity: block.on ? 1 : 0.45
        }
    }

    // A live "turned down by" bar under the compressor and the limiter.
    component ReductionBar: Item {
        id: bar
        property var app
        property string label
        property real amount: 0
        Layout.fillWidth: true
        Layout.preferredHeight: 30
        Text { anchors.left: parent.left; text: bar.label; color: bar.app.dim; font.pixelSize: 11 }
        Text {
            anchors.right: parent.right
            text: bar.amount.toFixed(1) + " dB"
            color: bar.amount > 0.5 ? bar.app.accent : bar.app.dim
            font.family: bar.app.mono
            font.pixelSize: 11
        }
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 6
            radius: bar.app.soft ? 3 : 0
            color: bar.app.well
            Rectangle {
                anchors.right: parent.right
                height: parent.height
                radius: parent.radius
                width: parent.width * Math.min(1, bar.amount / 20)
                color: bar.app.accent
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 14
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 36
                radius: insp.app.soft ? 11 : 0
                color: insp.app.soft ? insp.app.tonal : "transparent"
                border.color: nameInput.activeFocus ? insp.app.accent : insp.app.soft ? insp.app.controlEdge : insp.app.line
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 8
                    anchors.rightMargin: 10
                    spacing: 8
                    Tag { app: insp.app; text: insp.app.tagOf(insp.kind, insp.slot) }
                    TextInput {
                        id: nameInput
                        Layout.fillWidth: true
                        text: insp.ch.name || ""
                        color: insp.app.ink
                        font.family: insp.app.display
                        font.pixelSize: 14
                        font.weight: Font.Bold
                        clip: true
                        maximumLength: 18
                        selectByMouse: true
                        selectionColor: insp.app.select
                        selectedTextColor: insp.app.accentInk
                        onEditingFinished: {
                            const name = text.trim();
                            if (name !== (insp.ch.name || "")) insp.set(c => c.name = name);
                            text = Qt.binding(() => insp.ch.name || "");
                            focus = false;
                        }
                        Text {
                            visible: nameInput.text === ""
                            text: insp.app.defaultName(insp.kind, insp.slot)
                            color: nameInput.activeFocus ? insp.app.dim : insp.app.ink
                            font: nameInput.font
                            width: parent.width
                            elide: Text.ElideRight
                        }
                    }
                    Icon { name: "pen"; color: insp.app.dim; width: 14; height: 14 }
                }
            }
            IconButton { app: insp.app; icon: "x"; tip: "Close"; onClicked: insp.app.closeInspector() }
        }

        Flickable {
            id: scroller
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: body.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar { width: 5; policy: ScrollBar.AsNeeded }
            // A "remove this?" question sits at the bottom: bring it into view.
            function showEnd() { contentY = Math.max(0, contentHeight - height); }
            Connections {
                target: insp.app
                function onRemoveAskChanged() { if (insp.app.removeAsk === insp.me) Qt.callLater(scroller.showEnd); }
            }
            Component.onCompleted: if (insp.app.removeAsk === insp.me) Qt.callLater(scroller.showEnd)
            onContentHeightChanged: if (insp.app.removeAsk === insp.me) showEnd()

            ColumnLayout {
                id: body
                width: scroller.width - 8
                spacing: 10

                // ---- Device ----
                DevicePicker {
                    visible: insp.hardwareIn
                    Layout.fillWidth: true
                    implicitHeight: 34
                    app: insp.app
                    devices: insp.app.devices.sources
                    current: insp.ch.source || ""
                    onPicked: name => insp.set(s => s.source = name)
                }
                DevicePicker {
                    visible: insp.hardwareOut
                    Layout.fillWidth: true
                    implicitHeight: 34
                    app: insp.app
                    devices: insp.app.devices.sinks
                    current: insp.ch.device || ""
                    onPicked: name => insp.set(b => b.device = name)
                }

                // ---- Hardware input: voice tools ----
                Block {
                    visible: insp.hardwareIn
                    app: insp.app
                    title: "Noise gate"
                    switchable: true
                    on: !!insp.ch.gate_on
                    onToggled: insp.set(s => s.gate_on = !s.gate_on)
                    ToneSlider {
                        Layout.fillWidth: true
                        app: insp.app
                        label: "Opens above"
                        from: -80; to: 0; resetValue: -45
                        value: insp.ch.gate_threshold_db || 0
                        onMoved: v => insp.set(s => s.gate_threshold_db = v)
                    }
                }
                Block {
                    visible: insp.hardwareIn
                    app: insp.app
                    title: "Tone"
                    ToneSlider {
                        Layout.fillWidth: true
                        app: insp.app
                        label: "Bass"
                        value: insp.ch.bass_db || 0
                        onMoved: v => insp.set(s => s.bass_db = v)
                    }
                    ToneSlider {
                        Layout.fillWidth: true
                        app: insp.app
                        label: "Brightness"
                        value: insp.ch.brightness_db || 0
                        onMoved: v => insp.set(s => s.brightness_db = v)
                    }
                    ToneSlider {
                        Layout.fillWidth: true
                        app: insp.app
                        label: "Pitch"
                        format: insp.app.semitones
                        value: insp.ch.pitch_semitones || 0
                        onMoved: v => insp.set(s => s.pitch_semitones = v)
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        enabled: !!insp.ch.pitch_semitones
                        opacity: enabled ? 1 : 0.45
                        Text { Layout.fillWidth: true; text: "Hear my natural voice"; color: insp.app.ink; font.pixelSize: 12; elide: Text.ElideRight }
                        Toggle {
                            app: insp.app
                            checked: !!insp.ch.a_hears_dry
                            tip: "The A outputs play your voice without the pitch (and its delay). The B mics still carry the pitched voice."
                            onToggled: insp.set(s => s.a_hears_dry = !s.a_hears_dry)
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: !!insp.ch.pitch_semitones
                        text: insp.ch.a_hears_dry ? "You hear yourself with no delay. The B mics get the pitched voice, about 80 ms behind." : "Pitch adds about 80 ms of delay while it is on."
                        color: insp.app.warning
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }
                }
                Block {
                    visible: insp.hardwareIn
                    app: insp.app
                    title: "Auto-duck"
                    switchable: true
                    on: !!insp.ch.duck_on
                    onToggled: insp.set(s => s.duck_on = !s.duck_on)
                    ToneSlider {
                        Layout.fillWidth: true
                        app: insp.app
                        label: "When louder than"
                        from: -80; to: -6; resetValue: -40
                        value: insp.ch.duck_threshold_db || 0
                        onMoved: v => insp.set(s => s.duck_threshold_db = v)
                    }
                    ToneSlider {
                        Layout.fillWidth: true
                        app: insp.app
                        label: "Lower by"
                        from: -30; to: 0; resetValue: -10
                        value: insp.ch.duck_db || 0
                        onMoved: v => insp.set(s => s.duck_db = v)
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6
                        Chip {
                            Layout.fillWidth: true
                            app: insp.app
                            text: insp.app.t("On B mics")
                            checked: insp.ch.duck_b !== false
                            tip: "Duck what the B mics carry (what others hear)"
                            onToggled: insp.set(s => s.duck_b = !(s.duck_b !== false))
                        }
                        Chip {
                            Layout.fillWidth: true
                            app: insp.app
                            text: insp.app.t("On A")
                            checked: !!insp.ch.duck_a
                            tip: "Duck what you hear on the A outputs too"
                            onToggled: insp.set(s => s.duck_a = !s.duck_a)
                        }
                    }
                }

                // ---- Virtual input: the programs playing into it ----
                Block {
                    visible: insp.virtualIn
                    app: insp.app
                    title: "Playing here"
                    StreamList {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.max(1, Math.min(6, insp.playing.length)) * 40 - 6
                        app: insp.app
                        target: insp.virtualIn ? insp.streamName : "-"
                        emptyText: "Nothing playing"
                    }
                }
                Block {
                    visible: insp.virtualIn && insp.elsewhere.length > 0
                    app: insp.app
                    title: "Playing elsewhere"
                    StreamList {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.max(1, Math.min(4, insp.elsewhere.length)) * 40 - 6
                        app: insp.app
                        target: "other"
                    }
                }

                // ---- Virtual mic: who is recording it ----
                Block {
                    visible: insp.virtualOut
                    app: insp.app
                    title: "Listening now"
                    StreamList {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Math.max(1, Math.min(6, insp.playing.length)) * 40 - 6
                        app: insp.app
                        target: insp.virtualOut ? insp.streamName : "-"
                        mutable: false
                        emptyText: "Nobody is using this mic"
                    }
                }

                // ---- Parametric EQ ----
                Block {
                    visible: true
                    app: insp.app
                    title: "Parametric EQ"
                    switchable: true
                    on: !!insp.ch.eq_on
                    onToggled: insp.set(b => b.eq_on = !b.eq_on)
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 64
                        radius: insp.app.soft ? 10 : 0
                        color: Qt.alpha(insp.app.ink, 0.05)
                        clip: true
                        PeqCurve {
                            anchors.fill: parent
                            app: insp.app
                            cells: insp.ch.eq || []
                            on: !!insp.ch.eq_on
                            gain: insp.ch.eq_gain_db || 0
                        }
                    }
                    ToneSlider {
                        Layout.fillWidth: true
                        app: insp.app
                        label: "Output"
                        from: -12; to: 12; step: 0.1; wheelStep: 0.5
                        value: insp.ch.eq_gain_db || 0
                        onMoved: v => insp.set(b => { b.eq_gain_db = Math.round(v * 10) / 10; b.eq_on = true; })
                    }
                    TextButton {
                        Layout.fillWidth: true
                        app: insp.app
                        text: "Open the editor"
                        onClicked: insp.app.openEq(insp.kind, insp.slot)
                    }
                }

                // ---- Compressor on an input ----
                Block {
                    visible: !insp.isBus
                    app: insp.app
                    title: "Compressor"
                    switchable: true
                    on: !!insp.ch.comp_on
                    onToggled: insp.set(s => s.comp_on = !s.comp_on)
                    ToneSlider {
                        Layout.fillWidth: true
                        app: insp.app
                        label: "Threshold"
                        from: -60; to: 0; resetValue: -18
                        value: insp.ch.comp_threshold_db || 0
                        onMoved: v => insp.set(s => s.comp_threshold_db = v)
                    }
                    ToneSlider {
                        Layout.fillWidth: true
                        app: insp.app
                        label: "Ratio"
                        from: 1; to: 20; resetValue: 3
                        format: v => v.toFixed(1) + " : 1"
                        value: insp.ch.comp_ratio || 1
                        onMoved: v => insp.set(s => s.comp_ratio = v)
                    }
                    ToneSlider {
                        Layout.fillWidth: true
                        app: insp.app
                        label: "Attack"
                        from: 0.5; to: 200; step: 0.5; resetValue: 10
                        format: v => v.toFixed(1) + " ms"
                        value: insp.ch.comp_attack_ms || 10
                        onMoved: v => insp.set(s => s.comp_attack_ms = v)
                    }
                    ToneSlider {
                        Layout.fillWidth: true
                        app: insp.app
                        label: "Release"
                        from: 10; to: 1000; step: 5; resetValue: 120
                        format: v => Math.round(v) + " ms"
                        value: insp.ch.comp_release_ms || 120
                        onMoved: v => insp.set(s => s.comp_release_ms = v)
                    }
                    ToneSlider {
                        Layout.fillWidth: true
                        app: insp.app
                        label: "Make-up gain"
                        from: 0; to: 24; resetValue: 0
                        value: insp.ch.comp_makeup_db || 0
                        onMoved: v => insp.set(s => s.comp_makeup_db = v)
                    }
                    ReductionBar { app: insp.app; label: "Turning down"; amount: insp.reduction }
                }

                // ---- Limiter on an output ----
                Block {
                    visible: insp.isBus
                    app: insp.app
                    title: "Limiter"
                    switchable: true
                    on: !!insp.ch.limiter_on
                    onToggled: insp.set(b => b.limiter_on = !b.limiter_on)
                    ToneSlider {
                        Layout.fillWidth: true
                        app: insp.app
                        label: "Ceiling"
                        from: -24; to: 0; resetValue: -1
                        value: insp.ch.limiter_db || 0
                        onMoved: v => insp.set(b => b.limiter_db = v)
                    }
                    ReductionBar { app: insp.app; label: "Limiting"; amount: insp.reduction }
                }

                // ---- Vox Pro: plugins ----
                Block {
                    visible: insp.app.pro
                    app: insp.app
                    title: "Plugins"
                    switchable: insp.plugins.length > 0
                    on: insp.plugins.length === 0 || insp.ch.fx_on !== false
                    onToggled: insp.set(c => c.fx_on = c.fx_on === false)
                    Repeater {
                        model: insp.plugins.length
                        RowLayout {
                            id: plug
                            required property int index
                            readonly property var item: insp.plugins[index] || {}
                            Layout.fillWidth: true
                            spacing: 8
                            Text {
                                Layout.fillWidth: true
                                text: (plug.index + 1) + "  " + (plug.item.name || "")
                                color: insp.app.ink
                                opacity: plug.item.on ? 1 : 0.5
                                font.pixelSize: 12
                                elide: Text.ElideRight
                            }
                            Toggle {
                                app: insp.app
                                checked: !!plug.item.on
                                onToggled: insp.set(c => c.plugins[plug.index].on = !c.plugins[plug.index].on)
                            }
                        }
                    }
                    TextButton {
                        Layout.fillWidth: true
                        app: insp.app
                        text: insp.plugins.length === 0 ? "Add a plugin" : "Open the rack"
                        onClicked: insp.app.openRack(insp.kind, insp.slot)
                    }
                }

                // ---- Mono and Dim on a listening output ----
                RowLayout {
                    visible: insp.isBus && !insp.ch.virtual_output
                    Layout.fillWidth: true
                    spacing: 8
                    Block {
                        Layout.preferredWidth: 1
                        Layout.fillHeight: true
                        app: insp.app
                        title: "Mono"
                        switchable: true
                        on: !!insp.ch.mono
                        onToggled: insp.set(b => b.mono = !b.mono)
                    }
                    Block {
                        Layout.preferredWidth: 1
                        Layout.fillHeight: true
                        app: insp.app
                        title: "Dim"
                        note: "−20 dB"
                        switchable: true
                        on: !!insp.ch.dim
                        onToggled: insp.set(b => b.dim = !b.dim)
                    }
                }

                // ---- Record an output ----
                Block {
                    visible: insp.isBus
                    readonly property bool rec: insp.app.isRecording(insp.slot)
                    app: insp.app
                    title: "Record"
                    note: rec ? "Recording " + insp.app.elapsed(insp.app.clock - (insp.app.recordingSince[insp.ch.label] || insp.app.clock))
                              : insp.app.recordFolder + " · " + (insp.app.cfg.record_format || "flac").toUpperCase()
                    switchable: true
                    on: rec
                    onToggled: insp.app.recordBus(insp.slot, !rec)
                }

                // ---- Input: where it goes ----
                Block {
                    visible: !insp.isBus
                    app: insp.app
                    title: "Routing"
                    GridLayout {
                        Layout.fillWidth: true
                        columns: Math.min(5, Math.max(1, insp.app.aIdx.length + insp.app.bIdx.length))
                        columnSpacing: 6
                        rowSpacing: 6
                        Repeater {
                            model: insp.app.aIdx.concat(insp.app.bIdx)
                            Chip {
                                required property int modelData
                                Layout.fillWidth: true; Layout.preferredWidth: 20
                                app: insp.app
                                text: insp.app.tagOf("bus", modelData)
                                checked: !insp.isBus && !!(insp.ch.routes || [])[modelData]
                                tip: insp.app.busTip(modelData)
                                onToggled: insp.set(s => s.routes[modelData] = !s.routes[modelData])
                            }
                        }
                    }
                }

                // ---- System default ----
                TextButton {
                    visible: insp.virtualIn
                    Layout.fillWidth: true
                    app: insp.app
                    text: "Use as the system output"
                    tip: "Programs that play on the default output land on this strip"
                    onClicked: insp.app.makeDefault(insp.node, "System output is now " + insp.app.nameOf(insp.kind, insp.slot) + ".")
                }
                TextButton {
                    visible: insp.virtualOut
                    Layout.fillWidth: true
                    app: insp.app
                    text: "Use as the system microphone"
                    tip: "Programs that use the default microphone hear this mic"
                    onClicked: insp.app.makeDefault(insp.node, "System microphone is now " + insp.app.tagOf(insp.kind, insp.slot) + ".")
                }
                // ---- Remove ----
                Item { Layout.preferredHeight: 4 }
                Rectangle {
                    visible: insp.app.removeAsk !== insp.me
                    Layout.fillWidth: true
                    implicitHeight: 34
                    radius: insp.app.soft ? 11 : 0
                    color: removeMouse.containsMouse && !insp.lastOne ? Qt.alpha(insp.app.danger, 0.1) : "transparent"
                    border.color: Qt.alpha(insp.app.danger, insp.lastOne ? 0.25 : 0.5)
                    opacity: insp.lastOne ? 0.5 : 1
                    Row {
                        anchors.centerIn: parent
                        spacing: 7
                        Icon { anchors.verticalCenter: parent.verticalCenter; name: "minus"; color: insp.app.danger; width: 14; height: 14 }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "Remove this " + insp.kindName; color: insp.app.danger; font.pixelSize: 12; font.weight: Font.DemiBold }
                    }
                    MouseArea {
                        id: removeMouse
                        anchors.fill: parent
                        enabled: !insp.lastOne
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: insp.app.askRemove(insp.kind, insp.slot, insp.me)
                    }
                }
                Text {
                    visible: insp.lastOne
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: "The last " + insp.kindName + " always stays."
                    color: insp.app.dim
                    font.pixelSize: 11
                }
                Rectangle {
                    visible: insp.app.removeAsk === insp.me
                    Layout.fillWidth: true
                    implicitHeight: askRow.implicitHeight + 18
                    radius: insp.app.soft ? 11 : 0
                    color: Qt.alpha(insp.app.danger, 0.09)
                    border.color: Qt.alpha(insp.app.danger, 0.5)
                    ColumnLayout {
                        id: askRow
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 9
                        Text {
                            Layout.fillWidth: true
                            text: "Remove <b>" + insp.app.tagOf(insp.kind, insp.slot) + " · " + insp.app.nameOf(insp.kind, insp.slot) + "</b>? Its settings go with it."
                                + (insp.virtualIn || insp.virtualOut ? " Programs using it lose it." : "")
                            textFormat: Text.StyledText
                            color: insp.app.ink
                            font.pixelSize: 12
                            wrapMode: Text.WordWrap
                        }
                        RowLayout {
                        Layout.alignment: Qt.AlignRight
                        spacing: 8
                        TextButton { app: insp.app; text: "Keep"; onClicked: insp.app.removeAsk = "" }
                        Rectangle {
                            implicitWidth: yes.implicitWidth + 24
                            implicitHeight: 32
                            radius: insp.app.soft ? 16 : 0
                            color: yesMouse.containsMouse ? Qt.lighter(insp.app.danger, 1.1) : insp.app.danger
                            Text { id: yes; anchors.centerIn: parent; text: "Remove"; color: "#ffffff"; font.pixelSize: 12; font.weight: Font.DemiBold }
                            MouseArea {
                                id: yesMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { insp.app.removeAsk = ""; insp.app.removeChannel(insp.kind, insp.slot); }
                            }
                        }
                        }
                    }
                }
                Item { Layout.preferredHeight: 2 }
            }
        }
    }
}
