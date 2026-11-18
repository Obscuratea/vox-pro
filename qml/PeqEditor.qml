import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic

// The parametric EQ of one output or strip, over the whole window: the response curve with a dot per cell to drag
// (left-right frequency, up-down gain, wheel for width), and the six cells underneath for exact values.
Rectangle {
    id: editor
    required property var app
    /// "bus" or "strip", and which one.
    property string kind: "bus"
    property int index: 0
    signal done()

    readonly property var target: kind === "bus" ? app.cfg.buses[index] : app.cfg.strips[index]
    readonly property var cells: target && target.eq ? target.eq : []
    readonly property bool on: !!(target && target.eq_on)
    property int selected: 0

    readonly property var kinds: [
        { id: "peak", name: "Bell" }, { id: "lowshelf", name: "Low shelf" }, { id: "highshelf", name: "High shelf" },
        { id: "highpass", name: "High pass" }, { id: "lowpass", name: "Low pass" }, { id: "notch", name: "Notch" }
    ]
    readonly property var fresh: [
        { on: true, kind: "lowshelf", hz: 80, db: 0, q: 0.71 }, { on: true, kind: "peak", hz: 200, db: 0, q: 1 },
        { on: true, kind: "peak", hz: 600, db: 0, q: 1 }, { on: true, kind: "peak", hz: 2000, db: 0, q: 1 },
        { on: true, kind: "peak", hz: 5000, db: 0, q: 1 }, { on: true, kind: "highshelf", hz: 10000, db: 0, q: 0.71 }
    ]
    function kindName(id) { for (const k of kinds) if (k.id === id) return k.name; return "Bell"; }
    function hzText(hz) { return hz >= 1000 ? (hz / 1000).toFixed(hz >= 10000 ? 1 : 2) + " kHz" : Math.round(hz) + " Hz"; }

    function set(mutate) {
        app.change(c => mutate(editor.kind === "bus" ? c.buses[editor.index] : c.strips[editor.index]));
    }
    // Editing a cell switches the EQ on: a curve you are shaping should be heard.
    function setCell(i, mutate) {
        set(t => { mutate(t.eq[i]); t.eq_on = true; });
    }

    color: app.bg
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons; onWheel: wheel => wheel.accepted = true }   // nothing reaches the mixer underneath

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 14

        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Text {
                text: editor.target ? editor.target.label : ""
                color: editor.app.accent
                font.family: editor.app.mono
                font.pixelSize: 20
                font.weight: Font.Bold
            }
            Text {
                Layout.fillWidth: true
                text: editor.app.t("Parametric EQ")
                color: editor.app.dim
                font.family: editor.app.mono
                font.pixelSize: 13
                font.letterSpacing: editor.app.soft || editor.app.diamond ? 0.3 : 2
            }
            Chip {
                app: editor.app
                text: editor.on ? editor.app.t("On") : editor.app.t("Off")
                checked: editor.on
                tip: "Switch this EQ on or off without losing its curve"
                onToggled: editor.set(t => t.eq_on = !t.eq_on)
            }
            TextButton {
                app: editor.app
                text: editor.app.diamond ? "flat" : "Flat"
                tip: "Put every cell back to flat"
                onClicked: editor.set(t => { t.eq = JSON.parse(JSON.stringify(editor.fresh)); })
            }
            TextButton {
                app: editor.app
                text: "Done  ⟲"
                onClicked: editor.done()
            }
        }

        // ---- The curve ----
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: editor.app.rCard
            color: editor.app.diamond ? "transparent" : editor.app.panelFill
            border.color: editor.app.diamond ? editor.app.frameDim : editor.app.edge
            clip: true

            PeqCurve {
                id: curve
                anchors.fill: parent
                anchors.margins: 1
                app: editor.app
                cells: editor.cells
                on: editor.on
                grid: true
                selected: editor.selected
            }

            MouseArea {
                id: pad
                anchors.fill: curve
                hoverEnabled: true
                property int grabbed: -1
                property int hovered: -1
                function nodeY(cell) { return curve.yOf(curve.gained(cell) ? cell.db : 0); }
                function nearest(x, y) {
                    let best = -1, bestD = 22 * 22;
                    for (let i = 0; i < editor.cells.length; i++) {
                        const c = editor.cells[i];
                        const dx = curve.xOf(c.hz) - x, dy = nodeY(c) - y;
                        if (dx * dx + dy * dy < bestD) { bestD = dx * dx + dy * dy; best = i; }
                    }
                    return best;
                }
                cursorShape: grabbed >= 0 ? Qt.ClosedHandCursor : hovered >= 0 ? Qt.OpenHandCursor : Qt.ArrowCursor
                onPressed: mouse => {
                    grabbed = nearest(mouse.x, mouse.y);
                    if (grabbed >= 0) editor.selected = grabbed;
                }
                onReleased: grabbed = -1
                onPositionChanged: mouse => {
                    if (grabbed < 0) { hovered = nearest(mouse.x, mouse.y); return; }
                    const hz = Math.round(Math.max(20, Math.min(20000, curve.hzAt(mouse.x))));
                    const db = Math.round(Math.max(-18, Math.min(18, curve.dbAt(mouse.y))) * 10) / 10;
                    editor.setCell(grabbed, c => { c.hz = hz; if (curve.gained(c)) c.db = db; c.on = true; });
                }
                onExited: hovered = -1
                onDoubleClicked: mouse => {
                    const i = nearest(mouse.x, mouse.y);
                    if (i >= 0) editor.setCell(i, c => { if (curve.gained(c)) c.db = 0; else c.on = !c.on; });
                }
                onWheel: wheel => {
                    const i = hovered >= 0 ? hovered : editor.selected;
                    if (i < 0 || i >= editor.cells.length) return;
                    const q = editor.cells[i].q * (wheel.angleDelta.y > 0 ? 1.12 : 1 / 1.12);
                    editor.selected = i;
                    editor.setCell(i, c => c.q = Math.round(Math.max(0.3, Math.min(12, q)) * 100) / 100);
                }
            }

            Repeater {
                model: editor.cells.length
                Rectangle {
                    id: node
                    required property int index
                    readonly property var cell: editor.cells[index]
                    readonly property bool current: editor.selected === index
                    x: curve.x + curve.xOf(cell.hz) - width / 2
                    y: curve.y + pad.nodeY(cell) - height / 2
                    width: current || pad.hovered === index ? 26 : 22
                    height: width
                    radius: editor.app.soft ? width / 2 : editor.app.diamond ? 0 : 4
                    opacity: cell.on && editor.on ? 1 : 0.4
                    color: current ? editor.app.accent : editor.app.bg
                    border.width: 2
                    border.color: editor.app.accent
                    Behavior on width { NumberAnimation { duration: 90 } }
                    Text {
                        anchors.centerIn: parent
                        text: node.index + 1
                        color: node.current ? editor.app.accentInk : editor.app.ink
                        font.family: editor.app.mono
                        font.pixelSize: 11
                        font.weight: Font.Bold
                    }
                }
            }

            Text {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 12
                text: "Drag a dot  ·  scroll for width  ·  double-click to flatten"
                color: editor.app.dim
                font.pixelSize: 11
            }
        }

        // ---- The six cells ----
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            Repeater {
                model: editor.cells.length
                Rectangle {
                    id: box
                    required property int index
                    readonly property var cell: editor.cells[index]
                    readonly property bool current: editor.selected === index
                    Layout.fillWidth: true
                    Layout.preferredWidth: 200
                    Layout.preferredHeight: column.implicitHeight + 24
                    radius: editor.app.rBox
                    color: editor.app.diamond ? "transparent" : editor.app.panelFill
                    border.color: current ? editor.app.accent : editor.app.diamond ? editor.app.frameDim : editor.app.edge

                    TapHandler { onTapped: editor.selected = box.index }

                    ColumnLayout {
                        id: column
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 12
                        spacing: 8
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 8
                            Text {
                                text: box.index + 1
                                color: editor.app.accent
                                font.family: editor.app.mono
                                font.pixelSize: 15
                                font.weight: Font.Bold
                            }
                            TextButton {
                                id: kindButton
                                Layout.fillWidth: true
                                app: editor.app
                                implicitHeight: 28
                                text: editor.kindName(box.cell.kind) + "  ▾"
                                onClicked: { editor.selected = box.index; kindMenu.open(); }
                                Popup {
                                    id: kindMenu
                                    y: kindButton.height + 4
                                    width: Math.max(kindButton.width, 130)
                                    padding: 6
                                    background: Rectangle {
                                        radius: editor.app.rBox
                                        color: editor.app.outlined ? editor.app.bg : Qt.tint(editor.app.bg, Qt.alpha(editor.app.ink, 0.08))
                                        border.color: editor.app.soft && !editor.app.outlined ? Qt.alpha(editor.app.ink, 0.12) : editor.app.line
                                    }
                                    contentItem: ColumnLayout {
                                        spacing: 2
                                        Repeater {
                                            model: editor.kinds
                                            Rectangle {
                                                id: option
                                                required property var modelData
                                                Layout.fillWidth: true
                                                implicitHeight: 28
                                                radius: editor.app.rChip
                                                color: optionMouse.containsMouse ? editor.app.hover : "transparent"
                                                Text {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    x: 10
                                                    text: option.modelData.name
                                                    color: box.cell.kind === option.modelData.id ? editor.app.accent : editor.app.ink
                                                    font.pixelSize: 12
                                                    font.weight: box.cell.kind === option.modelData.id ? Font.DemiBold : Font.Normal
                                                }
                                                MouseArea {
                                                    id: optionMouse
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        const id = option.modelData.id;
                                                        editor.setCell(box.index, c => { c.kind = id; c.on = true; });
                                                        kindMenu.close();
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            Chip {
                                app: editor.app
                                text: box.cell.on ? editor.app.t("On") : editor.app.t("Off")
                                checked: box.cell.on
                                onToggled: editor.set(t => t.eq[box.index].on = !t.eq[box.index].on)
                            }
                        }
                        ToneSlider {
                            Layout.fillWidth: true
                            app: editor.app
                            label: "Frequency"
                            // The slider runs on log10(Hz), so each octave gets the same travel.
                            from: Math.log(20) / Math.LN10
                            to: Math.log(20000) / Math.LN10
                            step: 0.005
                            wheelStep: 0.02
                            resetValue: Math.log(editor.fresh[box.index].hz) / Math.LN10
                            format: v => editor.hzText(Math.pow(10, v))
                            value: Math.log(box.cell.hz) / Math.LN10
                            onMoved: v => { editor.selected = box.index; editor.setCell(box.index, c => c.hz = Math.round(Math.pow(10, v))); }
                        }
                        ToneSlider {
                            Layout.fillWidth: true
                            app: editor.app
                            enabled: curve.gained(box.cell)
                            label: "Gain"
                            from: -18
                            to: 18
                            step: 0.1
                            value: box.cell.db
                            onMoved: v => { editor.selected = box.index; editor.setCell(box.index, c => c.db = Math.round(v * 10) / 10); }
                        }
                        ToneSlider {
                            Layout.fillWidth: true
                            app: editor.app
                            label: "Width (Q)"
                            // Also logarithmic: 0.3 (wide) to 12 (narrow).
                            from: Math.log(0.3) / Math.LN10
                            to: Math.log(12) / Math.LN10
                            step: 0.005
                            wheelStep: 0.03
                            resetValue: Math.log(editor.fresh[box.index].q) / Math.LN10
                            format: v => Math.pow(10, v).toFixed(2)
                            value: Math.log(box.cell.q) / Math.LN10
                            onMoved: v => { editor.selected = box.index; editor.setCell(box.index, c => c.q = Math.round(Math.pow(10, v) * 100) / 100); }
                        }
                    }
                }
            }
        }
    }
}
