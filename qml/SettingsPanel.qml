import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import QtQuick.Dialogs

// Settings, as in the mock-up: cards of option rows (title, a quiet note, the control on the right), laid out
// in as many columns as fit, each card dropping into the shortest column. Everything applies straight away.
Flickable {
    id: scroller
    required property var app
    clip: true
    contentWidth: width
    contentHeight: page.implicitHeight + 32
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded; width: 6 }
    // Dev aid for screenshots: --scroll <pixels>
    Component.onCompleted: { const i = Qt.application.arguments.indexOf("--scroll"); if (i >= 0) contentY = parseInt(Qt.application.arguments[i + 1]); }

    // ---- The pieces ----

    // A card with a small uppercase heading.
    component SetCard: Card {
        id: setCard
        property string title
        property string icon
        default property alias content: body.data
        implicitHeight: body.implicitHeight + 14
        ColumnLayout {
            id: body
            x: 16
            y: 6
            width: setCard.width - 32
            spacing: 0
            Row {
                Layout.topMargin: 12
                Layout.bottomMargin: 6
                spacing: 8
                Icon { anchors.verticalCenter: parent.verticalCenter; name: setCard.icon; width: 14; height: 14; color: setCard.app.dim }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: setCard.title.toUpperCase()
                    color: setCard.app.dim
                    font.pixelSize: 11
                    font.weight: Font.DemiBold
                    font.letterSpacing: 1.5
                }
            }
        }
    }

    // One option: a line above, the title and note on the left, whatever is put inside on the right.
    component Opt: Item {
        id: opt
        property var app: scroller.app
        property string title
        property string note
        property color noteColor: app.faint
        default property alias control: row.data
        Layout.fillWidth: true
        implicitHeight: row.implicitHeight + 20
        Rectangle { width: parent.width; height: 1; color: opt.app.line }
        RowLayout {
            id: row
            y: 10
            width: parent.width
            spacing: 14
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text { Layout.fillWidth: true; text: opt.title; color: opt.app.ink; font.pixelSize: 13; font.weight: Font.Medium; wrapMode: Text.WordWrap }
                Text { Layout.fillWidth: true; visible: opt.note !== ""; text: opt.note; color: opt.noteColor; font.pixelSize: 12; wrapMode: Text.WordWrap; lineHeight: 1.1 }
            }
        }
    }

    // An option that is one on/off preference (settings.rs Prefs), on unless set off when `fallback` is true.
    component PrefOpt: Opt {
        id: prefOpt
        property string key
        property bool fallback: false
        property bool usable: true
        signal switched(bool on)
        readonly property bool on: { const v = app.prefs[key]; return v === undefined ? fallback : !!v; }
        Toggle {
            app: prefOpt.app
            enabled: prefOpt.usable
            opacity: enabled ? 1 : 0.45
            checked: prefOpt.on
            onToggled: { const k = prefOpt.key, now = !prefOpt.on; prefOpt.app.setPref(p => p[k] = now); prefOpt.switched(now); }
        }
    }

    // Choose one of a few: a sunken bar with the chosen one raised.
    component Seg: Rectangle {
        id: seg
        property var app: scroller.app
        property var options: []
        property int current: 0
        signal picked(int index)
        implicitWidth: segRow.implicitWidth + 8
        implicitHeight: 34
        radius: app.soft ? 10 : 0
        color: app.well
        border.color: app.line
        Row {
            id: segRow
            anchors.centerIn: parent
            spacing: 2
            Repeater {
                model: seg.options
                Rectangle {
                    id: segButton
                    required property string modelData
                    required property int index
                    readonly property bool on: seg.current === index
                    width: segText.implicitWidth + 20
                    height: 26
                    radius: seg.app.soft ? 7 : 0
                    color: on ? seg.app.card2 : "transparent"
                    border.color: on ? seg.app.line2 : "transparent"
                    Text {
                        id: segText
                        anchors.centerIn: parent
                        text: segButton.modelData
                        color: segButton.on || segMouse.containsMouse ? seg.app.ink : seg.app.dim
                        font.pixelSize: 12
                        font.weight: Font.Medium
                    }
                    MouseArea { id: segMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: seg.picked(segButton.index) }
                }
            }
        }
    }

    // − count +
    component Step: Rectangle {
        id: step
        property var app: scroller.app
        property int value
        property bool canAdd: true
        property bool canRemove: true
        property string addTip
        property string removeTip
        signal add()
        signal remove()
        implicitWidth: 28 + 26 + 28
        implicitHeight: 30
        radius: app.soft ? 10 : 0
        color: app.well
        border.color: app.line
        Row {
            anchors.centerIn: parent
            Repeater {
                model: 3
                Item {
                    id: cell
                    required property int index
                    readonly property bool middle: index === 1
                    readonly property bool usable: index === 0 ? step.canRemove : index === 2 ? step.canAdd : false
                    width: middle ? 26 : 28
                    height: 28
                    Text {
                        visible: cell.middle
                        anchors.centerIn: parent
                        text: step.value
                        color: step.app.ink
                        font.family: step.app.mono
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                    }
                    Icon {
                        visible: !cell.middle
                        anchors.centerIn: parent
                        width: 13; height: 13
                        name: cell.index === 0 ? "minus" : "plus"
                        color: !cell.usable ? Qt.alpha(step.app.faint, 0.5) : stepMouse.containsMouse ? step.app.ink : step.app.dim
                    }
                    MouseArea {
                        id: stepMouse
                        visible: !cell.middle
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: cell.usable ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: if (cell.usable) { if (cell.index === 0) step.remove(); else step.add(); }
                    }
                    ToolTip.visible: !cell.middle && stepMouse.containsMouse
                    ToolTip.delay: 400
                    ToolTip.text: cell.index === 0 ? step.removeTip : step.addTip
                }
            }
        }
    }

    // A quiet text link in the accent colour, with a chevron.
    component Lnk: Item {
        id: lnk
        property var app: scroller.app
        property string text
        property string tip
        signal clicked()
        implicitWidth: lnkRow.implicitWidth
        implicitHeight: 26
        Row {
            id: lnkRow
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3
            Text { anchors.verticalCenter: parent.verticalCenter; text: lnk.text; color: lnkMouse.containsMouse ? lnk.app.ink : lnk.app.accent; font.pixelSize: 12; font.weight: Font.DemiBold }
            Icon { anchors.verticalCenter: parent.verticalCenter; name: "chev"; width: 12; height: 12; color: lnkMouse.containsMouse ? lnk.app.ink : lnk.app.accent }
        }
        MouseArea { id: lnkMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: lnk.clicked() }
        ToolTip.visible: lnkMouse.containsMouse && tip !== ""
        ToolTip.delay: 400
        ToolTip.text: tip
    }

    // A small framed value, like a key cap (read-only facts such as the sample rate).
    component Cap: Rectangle {
        id: capBox
        property var app: scroller.app
        property string text
        implicitWidth: capText.implicitWidth + 16
        implicitHeight: 24
        radius: app.soft ? 7 : 0
        color: app.well
        border.color: app.line2
        Text { id: capText; anchors.centerIn: parent; text: capBox.text; color: capBox.app.ink; font.family: capBox.app.mono; font.pixelSize: 11; font.weight: Font.DemiBold }
    }

    // "Remove X? Its settings go with it."  Keep / Remove
    component Confirm: Rectangle {
        id: confirm
        property var app: scroller.app
        property string text
        signal keep()
        signal remove()
        Layout.fillWidth: true
        Layout.bottomMargin: 10
        implicitHeight: confirmCol.implicitHeight + 18
        radius: app.soft ? 10 : 0
        color: Qt.alpha(app.danger, 0.09)
        border.color: Qt.alpha(app.danger, 0.45)
        ColumnLayout {
            id: confirmCol
            x: 10; y: 9
            width: parent.width - 20
            spacing: 8
            Text { Layout.fillWidth: true; text: confirm.text; textFormat: Text.StyledText; color: confirm.app.ink; font.pixelSize: 12; wrapMode: Text.WordWrap }
            Row {
                Layout.alignment: Qt.AlignRight
                spacing: 6
                TextButton { app: confirm.app; text: "Keep"; implicitHeight: 28; onClicked: confirm.keep() }
                Rectangle {
                    width: removeText.implicitWidth + 24; height: 28
                    radius: confirm.app.soft ? 8 : 0
                    color: removeMouse.containsMouse ? Qt.lighter(confirm.app.danger, 1.1) : confirm.app.danger
                    Text { id: removeText; anchors.centerIn: parent; text: "Remove"; color: "#ffffff"; font.pixelSize: 12; font.weight: Font.DemiBold }
                    MouseArea { id: removeMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: confirm.remove() }
                }
            }
        }
    }

    // ---- The page ----
    Item {
        id: page
        x: 16
        y: 16
        width: scroller.width - 32
        implicitHeight: heading.height + 14 + grid.height

        Row {
            id: heading
            spacing: 10
            Text { text: "Settings"; color: scroller.app.ink; font.pixelSize: 18; font.weight: Font.DemiBold }
        }

        // Masonry: each card goes to the shortest column, in order.
        Item {
            id: grid
            y: heading.height + 14
            width: page.width
            readonly property real gap: 12
            readonly property int cols: Math.max(1, Math.floor((width + gap) / (300 + gap)))
            readonly property real colWidth: (width - (cols - 1) * gap) / cols
            function relayout() {
                const tops = new Array(cols).fill(0);
                for (const card of children) {
                    if (!card.visible) continue;
                    let c = 0;
                    for (let i = 1; i < cols; i++) if (tops[i] < tops[c] - 0.5) c = i;
                    card.width = colWidth;
                    card.x = c * (colWidth + gap);
                    card.y = tops[c];
                    tops[c] += card.height + gap;
                }
                height = Math.max(0, Math.max(...tops) - gap);
            }
            onColsChanged: Qt.callLater(relayout)
            onWidthChanged: Qt.callLater(relayout)
            Component.onCompleted: Qt.callLater(relayout)

            // ---- Layout ----
            SetCard {
                id: layoutCard
                app: scroller.app
                title: "Layout"
                icon: "mixer"
                height: implicitHeight
                onHeightChanged: Qt.callLater(grid.relayout)

                // Which group's last channel is waiting on "Remove?", or "".
                property string asking: ""
                function lastOf(group) {
                    const list = { hw: app.hwIdx, virt: app.virtIdx, a: app.aIdx, b: app.bIdx }[group];
                    return list[list.length - 1];
                }
                function kindOf(group) { return group === "a" || group === "b" ? "bus" : "strip"; }

                Repeater {
                    model: [
                        { group: "hw", title: "Hardware inputs", one: "input" },
                        { group: "virt", title: "Virtual inputs", one: "virtual input" },
                        { group: "a", title: "Listen outputs", one: "listen output" },
                        { group: "b", title: "Virtual mics", one: "virtual mic" }
                    ]
                    ColumnLayout {
                        id: groupRow
                        required property var modelData
                        readonly property string group: modelData.group
                        readonly property int count: layoutCard.app.countOf(group)
                        readonly property int last: layoutCard.lastOf(group)
                        readonly property string kind: layoutCard.kindOf(group)
                        Layout.fillWidth: true
                        spacing: 0
                        Opt {
                            title: groupRow.modelData.title
                            Step {
                                value: groupRow.count
                                canAdd: groupRow.count < layoutCard.app.limits[groupRow.group]
                                canRemove: groupRow.count > 1
                                addTip: canAdd ? "Add a " + groupRow.modelData.one : "That is the most there can be"
                                removeTip: canRemove ? "Remove " + layoutCard.app.tagOf(groupRow.kind, groupRow.last) + " · " + layoutCard.app.nameOf(groupRow.kind, groupRow.last)
                                                     : "The last one always stays"
                                onAdd: { layoutCard.asking = ""; layoutCard.app.addChannel(groupRow.group); }
                                onRemove: {
                                    if (layoutCard.app.prefs.confirm_remove === false) layoutCard.app.removeChannel(groupRow.kind, groupRow.last);
                                    else layoutCard.asking = groupRow.group;
                                }
                            }
                        }
                        Confirm {
                            visible: layoutCard.asking === groupRow.group
                            text: "Remove <b>" + layoutCard.app.tagOf(groupRow.kind, groupRow.last) + " · " + layoutCard.app.nameOf(groupRow.kind, groupRow.last)
                                  + "</b>? Its settings go with it."
                            onKeep: layoutCard.asking = ""
                            onRemove: { layoutCard.asking = ""; layoutCard.app.removeChannel(groupRow.kind, groupRow.last); }
                        }
                    }
                }
                Opt {
                    title: "Strip detail"
                    Seg {
                        options: ["Comfortable", "Compact"]
                        current: scroller.app.compact ? 1 : 0
                        onPicked: i => scroller.app.setUi(u => u.compact = i === 1)
                    }
                }
                Repeater {
                    model: [{ key: "show_inputs", title: "Show hardware inputs" }, { key: "show_virtual", title: "Show virtual inputs" }, { key: "show_outputs", title: "Show outputs" }]
                    Opt {
                        id: showOpt
                        required property var modelData
                        title: modelData.title
                        Toggle {
                            app: scroller.app
                            checked: scroller.app.ui[showOpt.modelData.key] !== false
                            onToggled: { const k = showOpt.modelData.key, on = checked; scroller.app.setUi(u => u[k] = !on); }
                        }
                    }
                }
                PrefOpt { key: "fit_detail"; fallback: true; title: "Fit detail to window size" }
                PrefOpt { key: "inspector_on_select"; fallback: true; title: "Open the inspector on select" }
            }

            // ---- Appearance ----
            SetCard {
                app: scroller.app
                title: "Appearance"
                icon: "look"
                height: implicitHeight
                onHeightChanged: Qt.callLater(grid.relayout)

                Opt {
                    title: "Theme"
                    note: scroller.app.theme.name + " · " + scroller.app.theme.note
                    Row {
                        spacing: 8
                        Repeater {
                            model: scroller.app.themeList
                            Item {
                                id: swatch
                                required property var modelData
                                readonly property bool on: scroller.app.theme.id === modelData.id
                                width: 30; height: 30
                                // A diagonal split: the theme's two accents, then its window colour.
                                Canvas {
                                    anchors.fill: parent
                                    onPaint: {
                                        const c = getContext("2d");
                                        c.reset();
                                        const g = c.createLinearGradient(0, 0, width, height);
                                        g.addColorStop(0, swatch.modelData.accent);
                                        g.addColorStop(0.55, swatch.modelData.accentEnd);
                                        g.addColorStop(0.56, swatch.modelData.window);
                                        g.addColorStop(1, swatch.modelData.window);
                                        c.fillStyle = g;
                                        c.beginPath();
                                        c.roundedRect(0, 0, width, height, 10, 10);
                                        c.fill();
                                    }
                                }
                                Rectangle {
                                    anchors.fill: parent
                                    radius: 10
                                    color: "transparent"
                                    border.width: swatch.on ? 2 : 1
                                    border.color: swatch.on ? scroller.app.ink : scroller.app.line2
                                }
                                MouseArea { id: swatchMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: scroller.app.change(c => c.theme = swatch.modelData.id) }
                                ToolTip.visible: swatchMouse.containsMouse
                                ToolTip.delay: 300
                                ToolTip.text: swatch.modelData.name
                            }
                        }
                    }
                }

                // Optional picture behind everything. The theme underneath stays: switch it off and it is back.
                FileDialog {
                    id: picker
                    title: "Choose a background picture"
                    nameFilters: ["Pictures (*.png *.jpg *.jpeg *.webp *.bmp *.gif)", "All files (*)"]
                    onAccepted: scroller.app.change(c => { c.bg_image = selectedFile.toString(); c.bg_enabled = true; })
                }
                Opt {
                    readonly property string path: decodeURIComponent((scroller.app.cfg.bg_image || "").toString())
                    title: "Picture background"
                    note: path === "" ? "None chosen" : path.substring(path.lastIndexOf("/") + 1)
                    Toggle {
                        app: scroller.app
                        checked: !!scroller.app.cfg.bg_enabled && !!scroller.app.cfg.bg_image
                        tip: "Turn the picture background on or off"
                        onToggled: {
                            if (!scroller.app.cfg.bg_image) picker.open();
                            else scroller.app.change(c => c.bg_enabled = !c.bg_enabled);
                        }
                    }
                }
                // The picture itself, cropped like the window shows it, with the button to change it.
                RowLayout {
                    Layout.fillWidth: true
                    Layout.bottomMargin: 10
                    spacing: 12
                    Rectangle {
                        Layout.preferredWidth: 96
                        Layout.preferredHeight: 54
                        radius: scroller.app.soft ? 8 : 0
                        color: scroller.app.well
                        border.color: scroller.app.line
                        clip: true
                        Image {
                            anchors.fill: parent
                            anchors.margins: 1
                            source: scroller.app.cfg.bg_image || ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            sourceSize.width: 240
                            visible: status === Image.Ready
                        }
                        Text { anchors.centerIn: parent; visible: !scroller.app.cfg.bg_image; text: "none"; color: scroller.app.faint; font.pixelSize: 11 }
                    }
                    Item { Layout.fillWidth: true }
                    Lnk { text: scroller.app.cfg.bg_image ? "Change" : "Choose"; tip: "Pick a picture"; onClicked: picker.open() }
                }
                PrefOpt {
                    key: "blur"; fallback: true
                    title: "Blur what is behind the window"
                    usable: scroller.app.glassy
                }
                PrefOpt { key: "system_accent"; title: "Follow the system accent colour" }
                Opt {
                    title: "Meters"
                    Seg {
                        options: ["Gradient", "Segments", "Solid"]
                        current: Math.max(0, ["gradient", "segments", "solid"].indexOf(scroller.app.prefs.meter_style || "gradient"))
                        onPicked: i => scroller.app.setPref(p => p.meter_style = ["gradient", "segments", "solid"][i])
                    }
                }
                PrefOpt { key: "peak_hold"; fallback: true; title: "Peak hold" }
                PrefOpt { key: "animations"; fallback: true; title: "Animations" }
            }

            // ---- Scenes ----
            SetCard {
                app: scroller.app
                title: "Scenes"
                icon: "rows"
                height: implicitHeight
                onHeightChanged: Qt.callLater(grid.relayout)

                Repeater {
                    model: scroller.app.scenes
                    Opt {
                        id: sceneOpt
                        required property var modelData
                        required property int index
                        readonly property bool on: scroller.app.sceneActive(index)
                        title: modelData.name
                        note: on ? "Active" : ""
                        noteColor: scroller.app.accent
                        Lnk { visible: !sceneOpt.on; text: "Load"; tip: "Switch the mixer to this scene"; onClicked: scroller.app.applyScene(sceneOpt.index) }
                        TextButton { app: scroller.app; implicitHeight: 28; text: "Update"; tip: "Replace this scene with the mixer as it is now"; onClicked: scroller.app.saveScene(sceneOpt.modelData.name) }
                        TextButton { app: scroller.app; implicitHeight: 28; implicitWidth: 32; text: "✕"; tip: "Delete this scene"; onClicked: scroller.app.deleteScene(sceneOpt.index) }
                    }
                }
                Opt {
                    title: scroller.app.scenes.length === 0 ? "No scenes yet" : "New scene"
                }
                RowLayout {
                    Layout.fillWidth: true
                    Layout.bottomMargin: 10
                    spacing: 8
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 32
                        radius: scroller.app.soft ? 9 : 0
                        color: scroller.app.well
                        border.color: sceneName.activeFocus ? scroller.app.accent : scroller.app.line
                        TextInput {
                            id: sceneName
                            anchors.fill: parent
                            anchors.leftMargin: 10; anchors.rightMargin: 10
                            verticalAlignment: TextInput.AlignVCenter
                            maximumLength: 24
                            color: scroller.app.ink
                            selectionColor: scroller.app.accent
                            font.pixelSize: 13
                            clip: true
                            onAccepted: saveScene.clicked()
                            Text { visible: !parent.text; anchors.verticalCenter: parent.verticalCenter; text: "Name, e.g. Stream"; color: scroller.app.faint; font.pixelSize: 13 }
                        }
                    }
                    TextButton {
                        id: saveScene
                        app: scroller.app
                        enabled: sceneName.text.trim() !== "" && scroller.app.scenes.length < 12
                        opacity: enabled ? 1 : 0.5
                        text: "Save"
                        onClicked: { scroller.app.saveScene(sceneName.text); sceneName.text = ""; }
                    }
                }
            }

            // ---- Shortcuts ----
            SetCard {
                app: scroller.app
                title: "Shortcuts"
                icon: "key"
                height: implicitHeight
                onHeightChanged: Qt.callLater(grid.relayout)

                Opt {
                    visible: !scroller.app.shortcutsOk
                    title: "Global shortcuts"
                    note: "Need KDE Plasma"
                    noteColor: scroller.app.warning
                }
                Opt {
                    visible: scroller.app.shortcutsOk
                    title: "Push to talk"
                    Toggle {
                        app: scroller.app
                        checked: !!scroller.app.cfg.ptt_enabled
                        tip: "Turn push to talk on or off"
                        onToggled: {
                            if (!scroller.app.cfg.ptt_enabled && scroller.app.pttKey === 0) {
                                scroller.app.flash("Pick a key first, then turn it on.");
                                return;
                            }
                            scroller.app.change(c => c.ptt_enabled = !c.ptt_enabled);
                        }
                    }
                }
                RowLayout {
                    visible: scroller.app.shortcutsOk
                    Layout.fillWidth: true
                    Layout.bottomMargin: 10
                    spacing: 6
                    Text { Layout.fillWidth: true; text: "Key"; color: scroller.app.dim; font.pixelSize: 12 }
                    KeyCapture { app: scroller.app; key: scroller.app.pttKey; onCaptured: k => scroller.app.setShortcut("ptt", k) }
                    TextButton {
                        visible: scroller.app.pttKey !== 0
                        app: scroller.app; implicitHeight: 28; implicitWidth: 32; text: "✕"
                        tip: "Clear the key (and turn push to talk off)"
                        onClicked: { scroller.app.setShortcut("ptt", 0); if (scroller.app.cfg.ptt_enabled) scroller.app.change(c => c.ptt_enabled = false); }
                    }
                }
                Opt {
                    visible: scroller.app.shortcutsOk
                    title: "Mute all mics"
                    KeyCapture { app: scroller.app; key: scroller.app.muteKey; onCaptured: k => scroller.app.setShortcut("mute-mics", k) }
                    TextButton {
                        visible: scroller.app.muteKey !== 0
                        app: scroller.app; implicitHeight: 28; implicitWidth: 32; text: "✕"
                        tip: "Clear the key"
                        onClicked: scroller.app.setShortcut("mute-mics", 0)
                    }
                }
                Opt {
                    visible: scroller.app.shortcutsOk
                    title: "Next scene"
                                        KeyCapture { app: scroller.app; key: scroller.app.sceneKey; onCaptured: k => scroller.app.setShortcut("next-scene", k) }
                    TextButton {
                        visible: scroller.app.sceneKey !== 0
                        app: scroller.app; implicitHeight: 28; implicitWidth: 32; text: "✕"
                        tip: "Clear the key"
                        onClicked: scroller.app.setShortcut("next-scene", 0)
                    }
                }
                Opt {
                    visible: scroller.app.shortcutsOk
                    title: "Show or hide " + (scroller.app.pro ? "Vox Pro" : "Vox")
                    KeyCapture { app: scroller.app; key: scroller.app.windowKey; onCaptured: k => scroller.app.setShortcut("show-hide", k) }
                    TextButton {
                        visible: scroller.app.windowKey !== 0
                        app: scroller.app; implicitHeight: 28; implicitWidth: 32; text: "✕"
                        tip: "Clear the key"
                        onClicked: scroller.app.setShortcut("show-hide", 0)
                    }
                }
            }

            // ---- Behaviour ----
            SetCard {
                app: scroller.app
                title: "Behaviour"
                icon: "bolt"
                height: implicitHeight
                onHeightChanged: Qt.callLater(grid.relayout)

                PrefOpt { key: "autostart"; title: "Start with the computer" }
                Opt {
                    title: "Keep running in the tray"
                    note: scroller.app.trayOn ? "" : "No system tray found"
                    Toggle {
                        app: scroller.app
                        enabled: scroller.app.trayOn
                        checked: !!scroller.app.cfg.close_to_tray
                        onToggled: scroller.app.change(c => c.close_to_tray = !c.close_to_tray)
                    }
                }
                PrefOpt {
                    key: "start_hidden"
                    title: "Start hidden"
                    note: scroller.app.trayOn ? "" : "No system tray found"
                    usable: scroller.app.trayOn
                }
                PrefOpt { key: "restore_scene"; title: "Restore the last scene" }
                Opt {
                    title: "Check for updates"
                    note: "Once at launch"
                    Toggle {
                        app: scroller.app
                        checked: scroller.app.cfg.check_updates !== false
                        onToggled: scroller.app.change(c => c.check_updates = !(c.check_updates !== false))
                    }
                }
                PrefOpt { key: "confirm_remove"; fallback: true; title: "Confirm before removing a channel" }
            }

            // ---- Audio ----
            SetCard {
                id: audioCard
                app: scroller.app
                title: "Audio"
                icon: "wave"
                height: implicitHeight
                onHeightChanged: Qt.callLater(grid.relayout)
                readonly property var rates: [44100, 48000, 96000]
                readonly property var latencies: ["low", "balanced", "safe"]
                readonly property int rate: scroller.app.prefs.sample_rate || 48000
                readonly property string latency: scroller.app.prefs.latency || "balanced"
                // Both only take effect at the next start: the engine is built for them.
                readonly property bool rateWaits: rate !== scroller.app.bootPrefs.rate
                readonly property bool latencyWaits: latency !== scroller.app.bootPrefs.latency
                readonly property var outs: scroller.app.aIdx.concat(scroller.app.bIdx)
                readonly property bool allLimited: outs.length > 0 && outs.every(i => !!(scroller.app.cfg.buses[i] || {}).limiter_on)
                readonly property string firstMic: scroller.app.bIdx.length > 0 ? scroller.app.tagOf("bus", scroller.app.bIdx[0]) : "B1"
                readonly property string firstVirt: scroller.app.virtIdx.length > 0 ? scroller.app.nameOf("strip", scroller.app.virtIdx[0]) : "Apps"

                Opt {
                    title: "Sample rate"
                    note: audioCard.rateWaits ? "Used from the next start" : ""
                    noteColor: audioCard.rateWaits ? scroller.app.warning : scroller.app.faint
                    Seg {
                        options: ["44.1k", "48k", "96k"]
                        current: Math.max(0, audioCard.rates.indexOf(audioCard.rate))
                        onPicked: i => scroller.app.setPref(p => p.sample_rate = [44100, 48000, 96000][i])
                    }
                }
                Opt {
                    title: "Latency"
                    note: audioCard.latencyWaits ? "Used from the next start" : ""
                    noteColor: audioCard.latencyWaits ? scroller.app.warning : scroller.app.faint
                    Seg {
                        options: ["Low", "Balanced", "Safe"]
                        current: Math.max(0, audioCard.latencies.indexOf(audioCard.latency))
                        onPicked: i => scroller.app.setPref(p => p.latency = ["low", "balanced", "safe"][i])
                    }
                }
                PrefOpt {
                    key: "default_mic"
                    title: "Use " + audioCard.firstMic + " as the system microphone"
                    onSwitched: on => { if (on) scroller.app.claimDefaults(false); }
                }
                PrefOpt {
                    key: "default_output"
                    title: "Use " + audioCard.firstVirt + " as the system output"
                    onSwitched: on => { if (on) scroller.app.claimDefaults(false); }
                }
                Opt {
                    title: "Limiter on every output"
                    Toggle {
                        app: scroller.app
                        checked: audioCard.allLimited
                        onToggled: { const on = !audioCard.allLimited; scroller.app.change(c => { for (const b of c.buses) b.limiter_on = on; }); }
                    }
                }
                PrefOpt { key: "lock_mute"; title: "Mute mics when the screen locks" }
            }

            // ---- Recording ----
            SetCard {
                id: recCard
                app: scroller.app
                title: "Recording"
                icon: "rec"
                height: implicitHeight
                onHeightChanged: Qt.callLater(grid.relayout)
                readonly property var formats: [
                    { id: "flac", name: "FLAC", note: "24-bit, lossless · about 0.5 GB an hour" },
                    { id: "wav", name: "WAV", note: "32-bit float, lossless · about 1.4 GB an hour" },
                    { id: "opus", name: "Opus", note: "128 kbps, smallest · about 55 MB an hour" }
                ]
                readonly property int current: Math.max(0, formats.findIndex(f => f.id === (scroller.app.cfg.record_format || "flac")))

                Opt {
                    title: "Format"
                    note: recCard.formats[recCard.current].note
                    Seg {
                        options: ["FLAC", "WAV", "Opus"]
                        current: recCard.current
                        onPicked: i => scroller.app.change(c => c.record_format = ["flac", "wav", "opus"][i])
                    }
                }
                FolderDialog {
                    id: folderPicker
                    title: "Where recordings go"
                    onAccepted: scroller.app.setPref(p => p.record_dir = decodeURIComponent(selectedFolder.toString().replace("file://", "")))
                }
                Opt {
                    title: "Folder"
                    note: scroller.app.recordFolder
                    Lnk { text: "Open"; tip: "Open the folder"; onClicked: scroller.app.openRecordings() }
                    Lnk { text: "Change"; onClicked: folderPicker.open() }
                }
                Opt {
                    visible: !!scroller.app.prefs.record_dir
                    title: "Back to the default folder"
                    note: "Music/" + scroller.app.appName
                    Lnk { text: "Reset"; onClicked: scroller.app.setPref(p => p.record_dir = "") }
                }
                PrefOpt { key: "tray_rec_dot"; fallback: true; title: "Show a red dot in the tray" }
            }

            // ---- Vox Pro: plugins ----
            SetCard {
                visible: scroller.app.pro
                app: scroller.app
                title: "Plugins"
                icon: "plug"
                height: implicitHeight
                onHeightChanged: Qt.callLater(grid.relayout)
                Component.onCompleted: if (scroller.app.pro) scroller.app.loadPlugins()

                Opt {
                    title: "Installed"
                    note: scroller.app.pro && scroller.app.pluginsScanned ? "" : "Looking…"
                    Cap { text: scroller.app.pro ? String(scroller.app.pluginList.length) : "" }
                    Lnk { text: "Rescan"; tip: "Look for newly installed plugins"; onClicked: scroller.app.rescanPlugins() }
                }
                Opt {
                    visible: scroller.app.pro && scroller.app.pluginsSafe
                    title: "Plugins are off"
                    note: "Switched off after a crash"
                    noteColor: scroller.app.warning
                    Lnk { text: "Turn back on"; onClicked: scroller.app.resumePlugins() }
                }
            }

            // ---- About and updates ----
            SetCard {
                id: about
                app: scroller.app
                title: "About"
                icon: "logo"
                height: implicitHeight
                onHeightChanged: Qt.callLater(grid.relayout)
                readonly property var u: app.update
                readonly property bool busy: u.state === "checking" || u.state === "downloading" || u.state === "installing"

                Opt {
                    title: scroller.app.appName + " " + scroller.app.version
                    note: "Made by Obscuratea"
                    Lnk { text: "Ko-fi"; tip: "ko-fi.com/obscuratea"; onClicked: Qt.openUrlExternally("https://ko-fi.com/obscuratea") }
                    Lnk { text: "Patreon"; tip: "patreon.com/Obscuratea"; onClicked: Qt.openUrlExternally("https://patreon.com/Obscuratea") }
                }
                Opt {
                    title: ({ idle: "Updates", checking: "Checking for updates…", uptodate: "Up to date",
                              available: "Version " + about.u.latest + " is available", downloading: "Downloading " + about.u.latest + "…",
                              installing: "Installing…", installed: "Updated to " + about.u.latest, error: "Couldn't update" })[about.u.state] || "Updates"
                    note: about.u.state === "error" ? about.u.message : about.u.state === "available" ? about.u.notes : ""
                    noteColor: about.u.state === "error" ? scroller.app.danger : scroller.app.faint
                    Lnk {
                        visible: !about.busy && about.u.state !== "available" && about.u.state !== "installed"
                        text: about.u.state === "error" ? "Try again" : "Check"
                        onClicked: scroller.app.checkForUpdate()
                    }
                    Lnk {
                        visible: about.u.state === "available"
                        text: "Update"
                        tip: "Downloads the new version, checks it and installs it. Your settings are not touched."
                        onClicked: scroller.app.installUpdate()
                    }
                    Lnk { visible: about.u.state === "installed"; text: "Restart now"; onClicked: scroller.app.restartAfterUpdate() }
                }
                Rectangle {
                    visible: about.u.state === "downloading"
                    Layout.fillWidth: true
                    Layout.bottomMargin: 10
                    Layout.preferredHeight: 6
                    radius: 3
                    color: scroller.app.well
                    Rectangle { width: parent.width * about.u.progress / 100; height: parent.height; radius: 3; color: scroller.app.accent }
                }
                Opt {
                    title: "Credits and licences"
                    Lnk { text: "Show"; onClicked: licencePopup.open() }
                }
            }
        }
    }

    Popup {
        id: licencePopup
        parent: Overlay.overlay
        anchors.centerIn: parent
        width: Math.min(parent.width - 32, 640)
        height: Math.min(parent.height - 32, 600)
        modal: true
        focus: true
        padding: 16
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        Component.onCompleted: if (Qt.application.arguments.indexOf("--licences") >= 0) Qt.callLater(open)   // dev aid for screenshots
        Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.55) }
        background: Rectangle {
            radius: scroller.app.rBox
            color: scroller.app.bg
            border.color: scroller.app.line2
        }
        contentItem: ColumnLayout {
            spacing: 10
            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: "Credits and licences"
                    color: scroller.app.ink
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                }
                TextButton { app: scroller.app; text: "Close"; onClicked: licencePopup.close() }
            }
            Flickable {
                id: licenceView
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                contentWidth: width
                contentHeight: licenceText.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded; width: 6 }
                Text {
                    id: licenceText
                    width: licenceView.width - 12
                    text: licencePopup.visible ? scroller.app.licensesText() : ""
                    color: scroller.app.ink
                    font.family: "monospace"
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                    textFormat: Text.PlainText
                }
            }
        }
    }
}
