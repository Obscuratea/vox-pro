import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import QtQuick.Effects
import org.obscura.vox

ApplicationWindow {
    id: win
    width: 1840
    height: 960
    minimumWidth: 1300
    minimumHeight: 720
    visible: true
    title: "Vox Pro"
    color: bg

    // The theme picks the look. "Follow system" wears the default soft look (rounded, gradient fills) in the
    // Plasma colour scheme's colours (window, text, selection and the scheme's focus accent, re-read live).
    // The other themes bring their own colours and style. A --theme <id> argument overrides it for screenshots.
    SystemPalette { id: pal; colorGroup: SystemPalette.Active }
    Themes { id: themes }
    readonly property int themeArg: Qt.application.arguments.indexOf("--theme")
    readonly property string themeWanted: themeArg >= 0 ? Qt.application.arguments[themeArg + 1] : (cfg.theme || "default")
    readonly property var theme: themes.find(themeWanted) || themes.find("default")
    readonly property bool ownColors: theme.style !== "auto"
    // Follow system keeps the default (soft, gradient) look and only borrows the Plasma colours.
    readonly property string style: ownColors ? theme.style : "soft"
    readonly property bool soft: style === "soft"
    readonly property bool diamond: style === "diamond"
    // Follow system: the scheme's window colour with its tint removed, so a purple scheme doesn't paint Vox purple.
    readonly property color neutralWindow: Qt.hsla(0, 0, pal.window.hslLightness, 1)
    readonly property color baseWindow: ownColors ? theme.window : neutralWindow
    readonly property color baseText: ownColors ? theme.text : pal.windowText
    readonly property color baseHighlight: ownColors ? theme.highlight : pal.highlight
    readonly property color baseHighlightedText: ownColors ? theme.highlightedText : pal.highlightedText
    readonly property var themeList: themes.list
    readonly property color systemWindow: neutralWindow
    readonly property color systemText: pal.windowText
    readonly property color systemAccent: schemeAccent !== "" ? schemeAccent : pal.highlight
    readonly property color frame: "#8e7adf"
    readonly property color frameDim: "#3b2e63"
    readonly property color ember: "#feb963"
    readonly property int cut: 3
    // Label casing: sharp = UPPER, MatOS = as written, Diamond = lower.
    function t(s) { return soft ? s : diamond ? s.toLowerCase() : s.toUpperCase(); }
    readonly property color bg: baseWindow
    // Outlined themes (Pure Black) draw boxes and controls as thin outlines on the bare window instead of grey fills.
    readonly property bool outlined: ownColors && !!theme.outline
    readonly property color controlEdge: outlined ? Qt.alpha(baseText, 0.30) : "transparent"
    readonly property color panel: outlined ? "transparent" : Qt.tint(baseWindow, Qt.alpha(baseText, soft ? 0.055 : 0.035))
    // With a picture behind them the boxes turn translucent (and frosted, see Glass.qml).
    readonly property color panelFill: bgOn ? Qt.alpha(Qt.darker(baseWindow, 1.25), 0.52) : panel
    readonly property color tonal: outlined ? "transparent" : Qt.tint(baseWindow, Qt.alpha(baseText, 0.11))
    readonly property color edge: outlined ? Qt.alpha(baseText, 0.24) : bgOn ? Qt.alpha(baseText, 0.14) : soft ? "transparent" : line
    readonly property int rCard: soft ? 20 : 0
    readonly property int rBox: soft ? 14 : 0
    readonly property int rChip: soft ? 14 : diamond ? 0 : 4
    readonly property color ink: baseText
    readonly property color dim: Qt.alpha(baseText, 0.55)
    readonly property color line: diamond ? frameDim : Qt.alpha(baseText, 0.15)
    readonly property color hover: Qt.alpha(baseText, 0.06)
    // The accent is the scheme's focus colour (its selection colour is the deeper container tone).
    // Re-read while following the system, so a wallpaper-driven accent change shows up without a restart.
    property string schemeAccent: mixer.schemeAccent()
    Timer {
        interval: 1000; repeat: true; running: !win.ownColors
        onTriggered: { const a = mixer.schemeAccent(); if (a !== win.schemeAccent) win.schemeAccent = a; }
    }
    readonly property color accent: bgOn && imgReady ? imgA : ownColors ? theme.accent : systemAccent
    readonly property color accentEnd: bgOn && imgReady ? imgB : ownColors && theme.accentEnd ? theme.accentEnd : soft ? Qt.hsla(accent.hslHue + 0.045, accent.hslSaturation, accent.hslLightness, 1) : accent
    readonly property color onFill: soft ? baseHighlight : accent
    readonly property color select: diamond ? "#4b3a85" : baseHighlight
    readonly property color accentInk: baseHighlightedText
    readonly property color danger: "#e5484d"
    readonly property color warning: "#f5a524"
    readonly property string mono: soft ? "Roboto Flex" : "Geist Mono"
    readonly property string display: soft ? "Roboto Flex" : diamond ? "Geist Mono" : "Archivo"

    Mixer { id: mixer }

    // Picture background (Settings > Background). `--bg <file>` is a dev aid for screenshots.
    readonly property int bgArg: Qt.application.arguments.indexOf("--bg")
    readonly property string imgUrl: bgArg >= 0 ? "file://" + Qt.application.arguments[bgArg + 1] : (cfg.bg_image || "")
    readonly property bool bgOn: imgUrl !== "" && (bgArg >= 0 || !!cfg.bg_enabled)
    readonly property Item blurSource: blurLayer
    // The two colours the bars take from the picture.
    property color imgA: "#ff4fd8"
    property color imgB: "#8b5cff"
    property bool imgReady: false

    // Reads a 48x48 thumbnail of the picture (cropped like the background) and picks two vivid colours
    // of different hues: the most common vivid hue, then the most common one that is clearly another.
    function pickColors(data) {
        const BINS = 18;
        const w = new Array(BINS).fill(0), sum = new Array(BINS).fill(0);
        for (let i = 0; i < data.length; i += 4) {
            const r = data[i] / 255, g = data[i + 1] / 255, b = data[i + 2] / 255;
            const hi = Math.max(r, g, b), lo = Math.min(r, g, b), d = hi - lo;
            if (hi < 0.2 || d / hi < 0.18) continue;
            let h = d === 0 ? 0 : hi === r ? ((g - b) / d + 6) % 6 : hi === g ? (b - r) / d + 2 : (r - g) / d + 4;
            h /= 6;
            const weight = (d / hi) * hi;
            const bin = Math.min(BINS - 1, Math.floor(h * BINS));
            w[bin] += weight;
            sum[bin] += weight * h;
        }
        let a = 0;
        for (let i = 1; i < BINS; i++) if (w[i] > w[a]) a = i;
        if (w[a] <= 0) return false;          // a grey picture keeps the normal colours
        let b = -1;
        for (let i = 0; i < BINS; i++) {
            const dist = Math.min(Math.abs(i - a), BINS - Math.abs(i - a));
            if (dist >= 2 && w[i] >= w[a] * 0.2 && (b < 0 || w[i] > w[b])) b = i;
        }
        const hA = sum[a] / w[a];
        const hB = b >= 0 ? sum[b] / w[b] : (hA + 0.09) % 1;
        imgA = Qt.hsla(hA, 0.85, 0.64, 1);
        imgB = Qt.hsla(hB, 0.8, 0.58, 1);
        return true;
    }

    property var cfg: JSON.parse(mixer.settings())
    // Set while PipeWire can't be reached (see Mixer::engineStatus); shown in place of the status pill.
    property string engineError: ""
    // No point redrawing meters and program lists for a window nobody can see.
    readonly property bool awake: visibility !== Window.Minimized && visibility !== Window.Hidden
    property var devices: ({ sources: [], sinks: [] })
    property var meters: ({ strips: [], buses: [] })
    property string devicesJson: ""
    property var streams: []
    property string streamsJson: "[]"
    property string status: Qt.application.arguments.indexOf("--status") >= 0 ? "System output is now Vox Pro Apps." : ""

    // Every edit goes through here. It edits a copy and swaps it in: a binding that gets back the
    // same object it had before doesn't update, so editing in place left buttons and sliders stale.
    function change(mutate) {
        const next = JSON.parse(JSON.stringify(cfg));
        mutate(next);
        cfg = next;
        mixer.apply(JSON.stringify(next));
        saveTimer.restart();
    }

    function semitones(value) {
        const sign = value > 0 ? "+" : value < 0 ? "−" : "";
        return sign + Math.abs(value).toFixed(1) + " st";
    }

    function db(value) {
        const sign = value > 0 ? "+" : value < 0 ? "−" : "";
        return sign + Math.abs(value).toFixed(1) + " dB";
    }

    // "01   INPUTS" (sharp), "Inputs" (MatOS), "01 inputs" with an amber first letter (Diamond; rich text).
    function sectionLabel(num, name) {
        if (soft) return name;
        if (!diamond) return num + "   " + name.toUpperCase();
        const n = name.toLowerCase();
        return num + "  <font color=\"" + ember + "\">" + n[0] + "</font>" + n.slice(1);
    }

    function describe(list, name) {
        for (const device of list)
            if (device.name === name)
                return device.description;
        return name;
    }

    function busTip(index) {
        const bus = cfg.buses[index];
        if (bus.virtual_output)
            return "Virtual mic " + bus.label;
        return bus.device !== "" ? bus.label + " · " + describe(devices.sinks, bus.device) : bus.label + " has no device yet";
    }

    function muteStream(id, muted) {
        mixer.muteStream(id, muted);
    }
    function moveStream(id, target, label) {
        mixer.moveStream(id, target);
        flash("Sent to " + label);
    }

    // All three virtual mics at once, for a quick "nobody can hear me" button.
    readonly property bool micsMuted: cfg.buses[5].mute && cfg.buses[6].mute && cfg.buses[7].mute
    function muteMics(muted) {
        change(c => { for (const i of [5, 6, 7]) c.buses[i].mute = muted; });
    }

    // ---- Scenes: saved layouts of every strip and bus (not the look) ----
    readonly property var scenes: cfg.scenes || []
    function plain(x) { return JSON.parse(JSON.stringify(x)); }
    // The mixer as it is now, without the session-only solo flags.
    function snapshot() {
        const strips = plain(cfg.strips);
        for (const s of strips) delete s.solo;
        return { strips: strips, buses: plain(cfg.buses) };
    }
    function same(a, b) {
        if (a === b) return true;
        if (typeof a !== "object" || typeof b !== "object" || a === null || b === null) return false;
        const ka = Object.keys(a), kb = Object.keys(b);
        return ka.length === kb.length && ka.every(k => same(a[k], b[k]));
    }
    function sceneActive(i) {
        const scene = scenes[i], now = snapshot();
        return !!scene && same(scene.strips, now.strips) && same(scene.buses, now.buses);
    }
    function saveScene(name) {
        const clean = name.trim();
        if (clean === "") return;
        const snap = snapshot();
        change(c => {
            c.scenes = c.scenes || [];
            const at = c.scenes.findIndex(s => s.name === clean);
            const scene = { name: clean, strips: snap.strips, buses: snap.buses };
            if (at >= 0) c.scenes[at] = scene; else if (c.scenes.length < 12) c.scenes.push(scene);
        });
    }
    function deleteScene(i) { change(c => c.scenes.splice(i, 1)); }
    function applyScene(i) {
        const scene = scenes[i];
        if (!scene) return;
        change(c => { c.strips = plain(scene.strips); c.buses = plain(scene.buses); });
        flash("Scene: " + scene.name);
    }
    function flash(text) { status = text; statusTimer.restart(); }

    // ---- Global shortcuts (keys are kept by KDE's shortcut service) ----
    readonly property bool shortcutsOk: mixer.shortcutsAvailable()
    property int pttKey: mixer.shortcutKey("ptt")
    property int muteKey: mixer.shortcutKey("mute-mics")
    function setShortcut(action, key) {
        const got = mixer.setShortcutKey(action, key);
        if (got < 0) { flash("That key is already used by another shortcut."); return; }
        if (action === "ptt") pttKey = got; else muteKey = got;
    }
    // "Ctrl+Alt+F12" from a Qt key code.
    function keyText(code) {
        if (!code) return "";
        const names = { 0x20: "Space", 0x01000001: "Tab", 0x01000003: "Backspace", 0x01000004: "Return", 0x01000005: "Enter",
                        0x01000006: "Insert", 0x01000007: "Delete", 0x01000008: "Pause", 0x01000009: "Print", 0x01000010: "Home",
                        0x01000011: "End", 0x01000012: "Left", 0x01000013: "Up", 0x01000014: "Right", 0x01000015: "Down",
                        0x01000016: "PgUp", 0x01000017: "PgDown", 0x01000024: "CapsLock", 0x01000025: "NumLock", 0x01000026: "ScrollLock" };
        const parts = [];
        if (code & 0x10000000) parts.push("Meta");
        if (code & 0x04000000) parts.push("Ctrl");
        if (code & 0x08000000) parts.push("Alt");
        if (code & 0x02000000) parts.push("Shift");
        const k = code & 0x01ffffff;
        parts.push(names[k] || (k >= 0x01000030 && k <= 0x01000047 ? "F" + (k - 0x01000030 + 1)
                  : k >= 0x21 && k <= 0x7e ? String.fromCharCode(k).toUpperCase() : "Key " + k.toString(16)));
        return parts.join("+");
    }
    // Requests from the desktop (the mute shortcut), picked up a few times a second.
    Timer {
        interval: 100; running: true; repeat: true
        onTriggered: {
            for (const e of JSON.parse(mixer.takeEvents())) {
                if (e === "mute-mics") {
                    muteMics(!micsMuted);
                    flash(micsMuted ? "Microphones muted" : "Microphones live");
                }
            }
        }
    }

    // ---- Tray icon: show/hide, mute, scenes, quit ----
    readonly property bool trayOn: trayLoader.item ? trayLoader.item.available : false
    function quitApp() { mixer.persist(); Qt.quit(); }
    function toggleWindow() {
        if (visible) { hide(); return; }
        show(); raise(); requestActivate();
    }
    // Not made under the offscreen test platform, which has no native menus.
    Loader {
        id: trayLoader
        active: Qt.platform.pluginName !== "offscreen"
        sourceComponent: Component { Tray { app: win } }
    }

    function makeDefault(node, done) {
        status = mixer.makeDefault(node) ? done : "Couldn't change the system default.";
        statusTimer.restart();
    }

    Timer { id: saveTimer; interval: 600; onTriggered: mixer.persist() }
    Timer { id: statusTimer; interval: 4000; onTriggered: win.status = "" }
    Timer {
        interval: 33
        running: win.awake
        repeat: true
        onTriggered: win.meters = JSON.parse(mixer.meters())
    }
    Timer {
        // Only replace the device lists when they actually change, so open dropdowns stay open.
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            win.engineError = mixer.engineStatus();
            const json = mixer.devices();
            if (json !== win.devicesJson) {
                win.devicesJson = json;
                win.devices = JSON.parse(json);
            }
        }
    }
    Timer {
        // Programs come and go quickly (a mute button should show its state at once), so poll faster.
        interval: 300
        running: win.awake
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            const json = mixer.streams();
            if (json !== win.streamsJson) {
                win.streamsJson = json;
                win.streams = JSON.parse(json);
            }
        }
    }
    onClosing: close => {
        mixer.persist();
        if (cfg.close_to_tray && trayOn) { close.accepted = false; hide(); }
        else Qt.quit();
    }

    // Developer aid: `vox-pro --screenshot out.png` saves the window and quits.
    Timer {
        readonly property int flag: Qt.application.arguments.indexOf("--screenshot")
        interval: 2000
        running: flag >= 0
        onTriggered: page.grabToImage(result => {
            result.saveToFile(Qt.application.arguments[flag + 1]);
            Qt.quit();
        })
    }

    Rectangle {
        id: page
        anchors.fill: parent
        color: win.bg

        // The picture, cropped to fill (never squashed), a little darker so text stays readable. It is a bit
        // bigger than the window so the blurred copy has no faded edges where boxes sit near the border.
        Item {
            id: bgScene
            x: -80; y: -80
            width: page.width + 160
            height: page.height + 160
            visible: win.bgOn
            Image {
                id: bgImage
                anchors.fill: parent
                source: win.bgOn ? win.imgUrl : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                smooth: true
                autoTransform: true
                sourceSize.width: 2560
                onStatusChanged: if (status === Image.Ready) sampler.requestPaint()
            }
            Rectangle { anchors.fill: parent; color: Qt.alpha(win.bg, 0.30) }
        }
        // The blurred copy the boxes show through (not too strong). It sits under the sharp picture.
        MultiEffect {
            id: blurLayer
            x: bgScene.x; y: bgScene.y; width: bgScene.width; height: bgScene.height
            z: -1
            source: bgScene
            visible: win.bgOn
            autoPaddingEnabled: false
            blurEnabled: true
            blurMax: 48
            blur: 0.8
        }
        Canvas {
            id: sampler
            width: 48; height: 48
            visible: false
            renderTarget: Canvas.Image
            readonly property url src: win.bgOn ? win.imgUrl : ""
            onSrcChanged: { win.imgReady = false; if (src.toString() !== "") loadImage(src); }
            onImageLoaded: requestPaint()
            onPaint: {
                if (src.toString() === "" || !isImageLoaded(src)) return;
                const ctx = getContext("2d");
                ctx.clearRect(0, 0, 48, 48);
                ctx.drawImage(src, 0, 0, 48, 48);
                win.imgReady = win.pickColors(ctx.getImageData(0, 0, 48, 48).data);
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 24
            spacing: 18

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 24

                ColumnLayout {
                    Layout.fillHeight: true
                    spacing: 12

                    // The chips are a little taller than the label; the box keeps the label's height so the strips don't move.
                    Item {
                        Layout.preferredWidth: 8 * 160 + 7 * 10   // as wide as the eight strips under it
                        Layout.preferredHeight: 14
                    RowLayout {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6
                        Text {
                            text: win.sectionLabel("01", "Inputs")
                            color: win.dim
                            textFormat: Text.StyledText
                            font.family: win.mono
                            font.pixelSize: win.soft ? 12 : 11
                            font.weight: win.soft ? Font.Medium : Font.Normal
                            font.letterSpacing: win.soft || win.diamond ? 0.3 : 2
                        }
                        Item { Layout.fillWidth: true }
                        // Saved scenes (make them in Settings): one click swaps in a whole layout.
                        Repeater {
                            model: Math.min(win.scenes.length, 5)
                            Chip {
                                required property int index
                                app: win
                                Layout.alignment: Qt.AlignVCenter
                                implicitHeight: 22
                                text: win.scenes[index].name
                                checked: win.sceneActive(index)
                                tip: "Scene: " + win.scenes[index].name
                                onToggled: win.applyScene(index)
                            }
                        }
                    }
                    }
                    RowLayout {
                        Layout.fillHeight: true
                        spacing: 10
                        Repeater {
                            model: 8
                            StripCard {
                                app: win
                                Layout.fillHeight: true
                                Layout.preferredWidth: 160
                            }
                        }
                    }
                }

                Rectangle { Layout.fillHeight: true; Layout.preferredWidth: 1; color: win.soft ? "transparent" : win.line }

                // The right-hand side flips to the settings (gear button, bottom right) and back.
                Item {
                    id: rightSide
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    property real turn: Qt.application.arguments.indexOf("--settings") >= 0 ? 180 : 0   // --settings is a dev aid for screenshots
                    readonly property bool showingBack: turn >= 90
                    Behavior on turn { NumberAnimation { duration: 380; easing.type: Easing.InOutCubic } }
                    transform: Rotation {
                        origin.x: rightSide.width / 2
                        origin.y: rightSide.height / 2
                        axis { x: 0; y: 1; z: 0 }
                        angle: rightSide.turn < 90 ? rightSide.turn : rightSide.turn - 180
                    }

                    ColumnLayout {
                        visible: !rightSide.showingBack
                        anchors.fill: parent
                        spacing: 10

                        Text {
                            text: win.sectionLabel("02", "Listen  ·  A")
                            color: win.dim
                            textFormat: Text.StyledText
                            font.family: win.mono
                            font.pixelSize: win.soft ? 12 : 11
                            font.weight: win.soft ? Font.Medium : Font.Normal
                            font.letterSpacing: win.soft || win.diamond ? 0.3 : 2
                        }
                        Repeater {
                            model: 5
                            BusRow { app: win; Layout.fillWidth: true }
                        }

                        Item { Layout.preferredHeight: 8 }

                        Text {
                            text: win.sectionLabel("03", "Send as mic  ·  B")
                            color: win.dim
                            textFormat: Text.StyledText
                            font.family: win.mono
                            font.pixelSize: win.soft ? 12 : 11
                            font.weight: win.soft ? Font.Medium : Font.Normal
                            font.letterSpacing: win.soft || win.diamond ? 0.3 : 2
                        }
                        Repeater {
                            model: 3
                            BusRow { app: win; offset: 5; Layout.fillWidth: true }
                        }

                        Item { Layout.preferredHeight: 8 }

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            Layout.minimumHeight: 110
                            color: win.diamond ? "transparent" : win.panelFill
                            radius: win.rCard
                            border.color: win.diamond ? "transparent" : win.edge

                            Glass { app: win; radius: win.rCard }
                            CutFrame { visible: win.diamond; anchors.fill: parent; cut: win.cut; fill: win.panelFill; stroke: win.frameDim }

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 10

                                RowLayout {
                                    Layout.fillWidth: true
                                    Text {
                                        Layout.fillWidth: true
                                        text: win.t("Used by")
                                        color: win.dim
                                        font.family: win.mono
                                        font.pixelSize: 10
                                        font.letterSpacing: 1
                                    }
                                    Chip {
                                        app: win
                                        text: win.micsMuted ? win.t("Mics muted") : win.t("Mute all mics")
                                        checked: win.micsMuted
                                        onColor: win.danger
                                        tip: "Mutes B1, B2 and B3 together, so nobody on a call or stream hears you"
                                        onToggled: win.muteMics(!win.micsMuted)
                                    }
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    spacing: 10
                                    Repeater {
                                        model: ["b1", "b2", "b3"]
                                        ColumnLayout {
                                            required property string modelData
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            spacing: 6
                                            Text {
                                                text: modelData.toUpperCase()
                                                color: win.accent
                                                font.family: win.mono
                                                font.pixelSize: 12
                                                font.weight: Font.Bold
                                            }
                                            StreamList {
                                                Layout.fillWidth: true
                                                Layout.fillHeight: true
                                                app: win
                                                target: modelData
                                                mutable: false
                                                emptyText: "Nobody is using this mic"
                                            }
                                        }
                                    }
                                }

                                // Result of the two buttons below, right above them.
                                Rectangle {
                                    visible: win.status !== "" || win.engineError !== ""
                                    Layout.alignment: Qt.AlignRight
                                    implicitWidth: statusText.implicitWidth + 24
                                    implicitHeight: 24
                                    radius: win.diamond ? 0 : 12
                                    color: Qt.alpha(win.engineError !== "" ? win.danger : win.accent, 0.15)
                                    border.color: win.soft ? "transparent" : (win.engineError !== "" ? win.danger : win.accent)
                                    Text {
                                        id: statusText
                                        anchors.centerIn: parent
                                        text: win.engineError !== "" ? win.engineError : win.status
                                        color: win.engineError !== "" ? win.danger : win.accent
                                        font.pixelSize: 12
                                    }
                                }
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6
                                    Item { Layout.fillWidth: true }
                                    TextButton {
                                        app: win
                                        text: win.diamond ? "use as system output" : "Use as system output"
                                        tip: "Programs play into the Apps strip, like setting Voicemeeter as your Windows output"
                                        onClicked: win.makeDefault("vox_pro_apps", "System output is now Vox Pro Apps.")
                                    }
                                    TextButton {
                                        app: win
                                        text: win.diamond ? "use b1 as system mic" : "Use B1 as system mic"
                                        tip: "Programs that use the default microphone hear B1"
                                        onClicked: win.makeDefault("vox_pro_b1", "System microphone is now Vox Pro B1.")
                                    }
                                    Item { Layout.preferredWidth: 30; Layout.preferredHeight: 32 }   // the gear sits here
                                }
                            }
                        }
                    }

                    SettingsPanel {
                        visible: rightSide.showingBack
                        anchors.fill: parent
                        app: win
                    }

                    // Same spot on both faces, so the gear and "Done" are one click apart.
                    TextButton {
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: 12
                        width: rightSide.showingBack ? implicitWidth : 30
                        app: win
                        text: rightSide.showingBack ? "Done  ⟲" : "⚙"
                        tip: rightSide.showingBack ? "Back to the mixer" : "Settings and themes"
                        onClicked: rightSide.turn = rightSide.showingBack ? 0 : 180
                    }
                }
            }
        }
    }
}
