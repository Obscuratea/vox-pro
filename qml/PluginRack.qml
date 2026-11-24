import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic

// The plugins of one strip or output, in place of the mixer page: the chain on the left (order, on/off, remove),
// and on the right either the installed plugins to pick from or the controls of the selected one.
Item {
    id: rack
    required property var app
    /// "bus" or "strip", and which one.
    property string kind: "strip"
    property int index: 0
    signal done()

    readonly property var target: kind === "bus" ? app.cfg.buses[index] : app.cfg.strips[index]
    readonly property var slots: target && target.plugins ? target.plugins : []
    readonly property int maxSlots: 6
    property int selected: 0
    property bool browsing: slots.length === 0
    readonly property var slot: !browsing && selected < slots.length ? slots[selected] : null
    readonly property var info: slot && app.pluginsScanned ? app.pluginInfo(slot.uri) : null

    property string addMessage: ""
    property bool addFailed: false
    property string search: ""
    property string category: ""
    readonly property var categories: {
        const seen = {};
        for (const p of app.pluginList) seen[p.category] = true;
        return Object.keys(seen).sort();
    }
    readonly property var found: {
        const words = search.toLowerCase().split(" ").filter(w => w !== "");
        return app.pluginList.filter(p => (category === "" || p.category === category)
            && words.every(w => (p.name + " " + p.author + " " + p.category).toLowerCase().indexOf(w) >= 0));
    }

    function set(mutate) {
        app.change(c => mutate(rack.kind === "bus" ? c.buses[rack.index] : c.strips[rack.index]));
    }
    function add(plugin) {
        if (slots.length >= maxSlots) return;
        const at = slots.length;
        set(t => { t.plugins = t.plugins || []; t.plugins.push({ uri: plugin.uri, name: plugin.name, on: true, params: {} }); });
        selected = at;
        browsing = false;
    }
    function remove(i) {
        set(t => t.plugins.splice(i, 1));
        selected = Math.max(0, Math.min(selected, slots.length - 1));
        if (slots.length === 0) browsing = true;
    }
    function move(i, by) {
        const to = i + by;
        if (to < 0 || to >= slots.length) return;
        set(t => { const s = t.plugins.splice(i, 1)[0]; t.plugins.splice(to, 0, s); });
        selected = to;
    }
    function setParam(symbol, value) {
        const i = selected;
        set(t => { t.plugins[i].params = t.plugins[i].params || {}; t.plugins[i].params[symbol] = value; });
    }
    function valueOf(p) {
        const v = rack.slot && rack.slot.params ? rack.slot.params[p.symbol] : undefined;
        return v === undefined ? p.def : v;
    }

    // ---- How one control is shown ----
    function isLog(p) { return p.max > 0 && p.max > p.min && (p.log || (p.min > 0 && p.max / p.min >= 1000)); }
    function low(p) { return p.min > 0 ? p.min : p.max * 1e-5; }
    function shown(p, v) {
        const tidy = x => Math.abs(x) >= 100 ? x.toFixed(0) : Math.abs(x) >= 10 ? x.toFixed(1) : x.toFixed(2);
        switch (p.unit) {
        case "db": return app.db(v);
        case "hz": return v >= 1000 ? tidy(v / 1000) + " kHz" : tidy(v) + " Hz";
        case "ms": return tidy(v) + " ms";
        case "s": return tidy(v) + " s";
        case "pc": return tidy(v) + " %";
        case "G": return v <= 1e-6 ? "−∞ dB" : app.db(20 * Math.log(v) / Math.LN10);   // a gain factor
        }
        return p.kind === "int" ? Math.round(v).toString() : tidy(v);
    }

    // Inside the app frame, over the mixer page: the top bar, rail and status bar stay.
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onWheel: wheel => wheel.accepted = true }   // nothing reaches the mixer underneath
    // Drop a .clap, .vst3 or .lv2 on the window to add it.
    DropArea {
        anchors.fill: parent
        keys: ["text/uri-list"]
        onDropped: drop => {
            let failed = "", added = 0;
            for (const url of drop.urls) {
                const err = rack.app.installPlugin(url);
                if (err === "") added++; else failed = err;
            }
            rack.addFailed = failed !== "";
            rack.addMessage = failed !== "" ? failed : added === 1 ? "Plugin added." : added + " plugins added.";
            if (added > 0) { rack.browsing = true; rack.app.rescanPlugins(); }
        }
        Rectangle {
            anchors.fill: parent
            visible: parent.containsDrag
            color: Qt.alpha(rack.app.accent, 0.12)
            border.color: rack.app.accent
            border.width: 2
            radius: rack.app.soft ? 14 : 0
            Text { anchors.centerIn: parent; text: "Drop to add the plugin"; color: rack.app.ink; font.pixelSize: 16; font.bold: true }
        }
    }

    Component.onCompleted: app.loadPlugins()
    Timer { interval: 250; repeat: true; running: !rack.app.pluginsScanned; onTriggered: rack.app.loadPlugins() }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            TextButton { app: rack.app; text: "←  Mixer"; onClicked: rack.done() }
            Tag { app: rack.app; text: rack.app.tagOf(rack.kind, rack.index) }
            Text {
                Layout.maximumWidth: 360
                text: rack.app.nameOf(rack.kind, rack.index)
                color: rack.app.ink
                font.pixelSize: 15
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            Text { text: "Plugins"; color: rack.app.dim; font.pixelSize: 13 }
            Item { Layout.fillWidth: true }
            Text { text: "FX"; color: rack.app.dim; font.pixelSize: 12; font.weight: Font.DemiBold }
            Toggle {
                app: rack.app
                checked: rack.target ? rack.target.fx_on !== false : false
                tip: "Bypass the whole chain"
                onToggled: rack.set(t => t.fx_on = t.fx_on === false)
            }
        }

        // Plugins are off after a crash: say so, and offer the way back.
        Rectangle {
            visible: rack.app.pluginsSafe
            Layout.fillWidth: true
            Layout.preferredHeight: 46
            radius: rack.app.soft ? 12 : 0
            color: Qt.alpha(rack.app.danger, 0.14)
            border.color: Qt.alpha(rack.app.danger, 0.6)
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 8
                spacing: 12
                Text {
                    Layout.fillWidth: true
                    text: "Plugins are switched off after a crash. Remove the one added last, then switch them back on."
                    color: rack.app.ink
                    font.pixelSize: 12
                    elide: Text.ElideRight
                }
                TextButton { app: rack.app; text: "Switch plugins on"; onClicked: rack.app.resumePlugins() }
            }
        }

        // Side by side; one above the other in a narrow window.
        GridLayout {
            readonly property bool narrow: rack.width < 640
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: narrow ? 1 : 2
            columnSpacing: 12
            rowSpacing: 12

            // ---- The chain ----
            Card {
                app: rack.app
                corner: rack.app.soft ? 14 : 0
                Layout.preferredWidth: Math.max(220, Math.min(300, rack.width * 0.28))
                Layout.fillWidth: parent.narrow
                Layout.fillHeight: !parent.narrow
                Layout.preferredHeight: chain.implicitHeight + 24

                ColumnLayout {
                    id: chain
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 8
                    Text {
                        text: "CHAIN"
                        color: rack.app.dim
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        font.letterSpacing: 1.2
                    }
                    Repeater {
                        model: rack.slots.length
                        Rectangle {
                            id: row
                            required property int index
                            readonly property var slot: rack.slots[index]
                            readonly property bool current: !rack.browsing && rack.selected === index
                            Layout.fillWidth: true
                            Layout.preferredHeight: 42
                            radius: rack.app.soft ? 10 : 0
                            color: row.current ? rack.app.card2 : rowMouse.containsMouse ? rack.app.hover : rack.app.well
                            border.color: row.current ? rack.app.accent : rowMouse.containsMouse ? rack.app.line2 : rack.app.line
                            MouseArea {
                                id: rowMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { rack.selected = row.index; rack.browsing = false; }
                            }
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 4
                                spacing: 8
                                Tag { app: rack.app; text: (row.index + 1).toString() }
                                Text {
                                    Layout.fillWidth: true
                                    text: row.slot.name
                                    color: rack.app.ink
                                    opacity: row.slot.on ? 1 : 0.5
                                    font.pixelSize: 13
                                    font.weight: Font.Medium
                                    elide: Text.ElideRight
                                }
                                Toggle {
                                    app: rack.app
                                    checked: !!row.slot.on
                                    onToggled: rack.set(t => t.plugins[row.index].on = !t.plugins[row.index].on)
                                }
                                Rectangle {
                                    id: more
                                    implicitWidth: 24
                                    implicitHeight: 28
                                    radius: rack.app.soft ? 6 : 0
                                    color: moreMouse.containsMouse || slotMenu.opened ? rack.app.hover : "transparent"
                                    Text { anchors.centerIn: parent; text: "⋮"; color: moreMouse.containsMouse ? rack.app.ink : rack.app.faint; font.pixelSize: 16; font.bold: true }
                                    MouseArea { id: moreMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: slotMenu.open() }
                                    Popup {
                                        id: slotMenu
                                        y: more.height + 4
                                        x: more.width - width
                                        width: 170
                                        padding: 6
                                        background: Rectangle { radius: rack.app.soft ? 12 : 0; color: Qt.tint(rack.app.bg, Qt.alpha(rack.app.ink, 0.06)); border.color: rack.app.line2 }
                                        contentItem: Column {
                                            spacing: 2
                                            Repeater {
                                                model: [
                                                    { label: "Move up", usable: row.index > 0, act: () => rack.move(row.index, -1) },
                                                    { label: "Move down", usable: row.index < rack.slots.length - 1, act: () => rack.move(row.index, 1) },
                                                    { label: "Remove", usable: true, danger: true, act: () => rack.remove(row.index) }
                                                ]
                                                Rectangle {
                                                    id: menuItem
                                                    required property var modelData
                                                    width: 158
                                                    height: 30
                                                    radius: rack.app.soft ? 8 : 0
                                                    opacity: modelData.usable ? 1 : 0.35
                                                    color: itemMouse.containsMouse && modelData.usable ? rack.app.hover : "transparent"
                                                    Text {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        x: 10
                                                        text: menuItem.modelData.label
                                                        color: menuItem.modelData.danger ? rack.app.danger : rack.app.ink
                                                        font.pixelSize: 12
                                                    }
                                                    MouseArea {
                                                        id: itemMouse
                                                        anchors.fill: parent
                                                        hoverEnabled: true
                                                        enabled: menuItem.modelData.usable
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: { slotMenu.close(); menuItem.modelData.act(); }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    TextButton {
                        Layout.fillWidth: true
                        visible: rack.slots.length < rack.maxSlots
                        app: rack.app
                        text: "+  Add plugin"
                        onClicked: rack.browsing = true
                    }
                    Item { Layout.fillHeight: true }
                }
            }

            // ---- The installed plugins, or the selected plugin's controls ----
            Card {
                app: rack.app
                corner: rack.app.soft ? 14 : 0
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                // Browser
                ColumnLayout {
                    visible: rack.browsing
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 10
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        TextField {
                            id: searchBox
                            Layout.fillWidth: true
                            Layout.preferredHeight: 32
                            placeholderText: "Search " + rack.app.pluginList.length + " plugins"
                            placeholderTextColor: rack.app.dim
                            color: rack.app.ink
                            font.pixelSize: 12
                            leftPadding: 14
                            selectByMouse: true
                            onTextChanged: rack.search = text
                            background: Rectangle {
                                radius: rack.app.soft ? 10 : 0
                                color: rack.app.well
                                border.color: searchBox.activeFocus ? rack.app.accent : rack.app.line
                            }
                        }
                        TextButton {
                            app: rack.app
                            text: "Rescan"
                            tip: "Look for plugins again. To add one, drop a .clap, .vst3 or .lv2 anywhere on this window, or install it from your package manager."
                            onClicked: { rack.addMessage = ""; rack.app.rescanPlugins(); }
                        }
                        TextButton {
                            visible: rack.slots.length > 0
                            app: rack.app
                            text: "Cancel"
                            onClicked: rack.browsing = false
                        }
                    }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 6
                        Chip {
                            app: rack.app
                            implicitHeight: 24
                            text: rack.app.t("All")
                            checked: rack.category === ""
                            onToggled: rack.category = ""
                        }
                        Repeater {
                            model: rack.categories
                            Chip {
                                required property string modelData
                                app: rack.app
                                implicitHeight: 24
                                text: rack.app.t(modelData)
                                checked: rack.category === modelData
                                onToggled: rack.category = checked ? "" : modelData
                            }
                        }
                    }
                    Text {
                        visible: !rack.app.pluginsScanned || rack.found.length === 0
                        Layout.fillWidth: true
                        Layout.topMargin: 20
                        horizontalAlignment: Text.AlignHCenter
                        text: !rack.app.pluginsScanned ? "Looking for plugins…"
                            : rack.app.pluginList.length === 0 ? "No plugins found. Install some (lsp-plugins, calf or x42-plugins from your package manager) or drop a .clap, .vst3 or .lv2 here."
                            : "Nothing matches."
                        color: rack.app.dim
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                    }
                    // Adding plugins: drop one on the window, or install it any way you like and press Rescan.
                    Text {
                        visible: rack.addMessage !== ""
                        Layout.fillWidth: true
                        text: rack.addMessage
                        color: rack.addFailed ? rack.app.danger : rack.app.dim
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }
                    ListView {
                        id: list
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: 4
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded; width: 6 }
                        model: rack.found
                        delegate: Rectangle {
                            id: entry
                            required property var modelData
                            width: list.width - 10
                            height: 40
                            radius: rack.app.soft ? 8 : 0
                            color: entryMouse.containsMouse ? rack.app.hover : "transparent"
                            border.color: entryMouse.containsMouse ? rack.app.accent : "transparent"
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 12
                                spacing: 12
                                Text {
                                    Layout.fillWidth: true
                                    text: entry.modelData.name
                                    color: rack.app.ink
                                    font.pixelSize: 13
                                    elide: Text.ElideRight
                                }
                                Text {
                                    text: entry.modelData.author
                                    color: rack.app.dim
                                    font.pixelSize: 11
                                    elide: Text.ElideRight
                                    Layout.maximumWidth: 260
                                }
                                Text {
                                    Layout.preferredWidth: 40
                                    text: entry.modelData.format
                                    color: rack.app.accent
                                    font.pixelSize: 10
                                    font.bold: true
                                }
                                Text {
                                    Layout.preferredWidth: 150
                                    horizontalAlignment: Text.AlignRight
                                    text: entry.modelData.category + (entry.modelData.stereo ? "" : "  ·  mono")
                                    color: rack.app.dim
                                    font.pixelSize: 11
                                }
                            }
                            MouseArea {
                                id: entryMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: rack.add(entry.modelData)
                            }
                        }
                    }
                }

                // Controls
                ColumnLayout {
                    visible: !rack.browsing && rack.slot !== null
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 12
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        Text {
                            Layout.fillWidth: true
                            text: rack.slot ? rack.slot.name : ""
                            color: rack.app.ink
                            font.pixelSize: 16
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        TextButton {
                            visible: rack.info !== null
                            app: rack.app
                            text: "Defaults"
                            tip: "Put every control back to the plugin's default"
                            onClicked: { const i = rack.selected; rack.set(t => t.plugins[i].params = {}); }
                        }
                    }
                    Text {
                        visible: rack.app.pluginsScanned && rack.info === null
                        Layout.fillWidth: true
                        text: "This plugin isn't installed any more. Its settings are kept in case it comes back."
                        color: rack.app.dim
                        font.pixelSize: 12
                        wrapMode: Text.WordWrap
                    }
                    Flickable {
                        id: controls
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        contentWidth: width
                        contentHeight: grid.implicitHeight
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded; width: 6 }
                        GridLayout {
                            id: grid
                            width: controls.width - 12
                            columns: Math.max(1, Math.floor(width / 300))
                            columnSpacing: 28
                            rowSpacing: 14
                            Repeater {
                                // Switches that only drive a plugin's own window (LSP's graphs and overlays) are left out.
                                model: rack.info ? rack.info.params.filter(p => !/visibility|overlay|graph analysis/i.test(p.name)) : []
                                Item {
                                    id: cell
                                    required property var modelData
                                    readonly property var p: modelData
                                    readonly property real value: rack.valueOf(p)
                                    Layout.fillWidth: true
                                    Layout.preferredWidth: 260
                                    Layout.preferredHeight: 36

                                    // A switch
                                    RowLayout {
                                        visible: cell.p.kind === "toggle"
                                        anchors.fill: parent
                                        spacing: 8
                                        Text {
                                            Layout.fillWidth: true
                                            text: cell.p.name
                                            color: rack.app.dim
                                            font.pixelSize: 11
                                            elide: Text.ElideRight
                                        }
                                        Toggle {
                                            app: rack.app
                                            checked: cell.value > (cell.p.min + cell.p.max) / 2
                                            onToggled: rack.setParam(cell.p.symbol, checked ? cell.p.min : cell.p.max)
                                        }
                                    }
                                    // A choice
                                    RowLayout {
                                        visible: cell.p.kind === "pick"
                                        anchors.fill: parent
                                        spacing: 8
                                        Text {
                                            Layout.fillWidth: true
                                            text: cell.p.name
                                            color: rack.app.dim
                                            font.pixelSize: 11
                                            elide: Text.ElideRight
                                        }
                                        TextButton {
                                            id: pickButton
                                            app: rack.app
                                            implicitHeight: 28
                                            Layout.maximumWidth: 170
                                            readonly property var chosen: {
                                                let best = null;
                                                for (const o of cell.p.options) if (best === null || Math.abs(o.value - cell.value) < Math.abs(best.value - cell.value)) best = o;
                                                return best;
                                            }
                                            text: (chosen ? chosen.label : "") + "  ▾"
                                            onClicked: pickMenu.open()
                                            Popup {
                                                id: pickMenu
                                                y: pickButton.height + 4
                                                x: pickButton.width - width
                                                width: 220
                                                height: Math.min(implicitHeight, 320)
                                                padding: 6
                                                background: Rectangle { radius: rack.app.soft ? 12 : 0; color: Qt.tint(rack.app.bg, Qt.alpha(rack.app.ink, 0.06)); border.color: rack.app.line2 }
                                                contentItem: ListView {
                                                    implicitHeight: contentHeight
                                                    clip: true
                                                    boundsBehavior: Flickable.StopAtBounds
                                                    model: cell.p.options
                                                    delegate: Rectangle {
                                                        id: option
                                                        required property var modelData
                                                        width: ListView.view.width
                                                        height: 28
                                                        radius: rack.app.soft ? 8 : 0
                                                        color: optionMouse.containsMouse ? rack.app.hover : "transparent"
                                                        Text {
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            x: 10
                                                            width: parent.width - 20
                                                            text: option.modelData.label
                                                            elide: Text.ElideRight
                                                            color: pickButton.chosen && pickButton.chosen.value === option.modelData.value ? rack.app.accent : rack.app.ink
                                                            font.pixelSize: 12
                                                        }
                                                        MouseArea {
                                                            id: optionMouse
                                                            anchors.fill: parent
                                                            hoverEnabled: true
                                                            cursorShape: Qt.PointingHandCursor
                                                            onClicked: { rack.setParam(cell.p.symbol, option.modelData.value); pickMenu.close(); }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                    // A range
                                    ToneSlider {
                                        visible: cell.p.kind === "int" || cell.p.kind === "float"
                                        anchors.fill: parent
                                        app: rack.app
                                        label: cell.p.name
                                        readonly property bool logScale: rack.isLog(cell.p)
                                        readonly property real lo: rack.low(cell.p)
                                        from: logScale ? Math.log(lo) / Math.LN10 : cell.p.min
                                        to: logScale ? Math.log(cell.p.max) / Math.LN10 : cell.p.max
                                        step: cell.p.kind === "int" && !logScale ? 1 : (to - from) / 400
                                        wheelStep: cell.p.kind === "int" && !logScale ? 1 : (to - from) / 100
                                        centered: !logScale && cell.p.min < 0 && cell.p.max > 0
                                        resetValue: logScale ? Math.log(Math.max(lo, cell.p.def)) / Math.LN10 : cell.p.def
                                        value: logScale ? Math.log(Math.max(lo, cell.value)) / Math.LN10 : cell.value
                                        format: v => rack.shown(cell.p, logScale ? (v <= from + 1e-6 && cell.p.min <= 0 ? cell.p.min : Math.pow(10, v)) : v)
                                        onMoved: v => {
                                            let out = logScale ? (v <= from + 1e-6 && cell.p.min <= 0 ? cell.p.min : Math.pow(10, v)) : v;
                                            if (cell.p.kind === "int") out = Math.round(out);
                                            rack.setParam(cell.p.symbol, Math.max(cell.p.min, Math.min(cell.p.max, out)));
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
