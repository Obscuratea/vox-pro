import QtQuick
import QtQuick.Layouts
import QtQuick.Controls.Basic
import QtQuick.Dialogs

// Back of the right-hand side: look, scenes, shortcuts and behaviour. It scrolls when it is taller than the window.
Flickable {
    id: scroller
    required property var app
    clip: true
    contentWidth: width
    contentHeight: panel.implicitHeight + 64   // room under the last row for the Done button
    boundsBehavior: Flickable.StopAtBounds
    ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded; width: 6 }
    // Dev aid for screenshots: --scroll <pixels>
    Component.onCompleted: { const i = Qt.application.arguments.indexOf("--scroll"); if (i >= 0) contentY = parseInt(Qt.application.arguments[i + 1]); }

ColumnLayout {
    id: panel
    property var app: scroller.app
    width: scroller.width - 10
    spacing: 10

    function swatch(t) {
        return t.style === "auto"
            ? { bg: panel.app.systemWindow, text: panel.app.systemText, accent: panel.app.systemAccent }
            : { bg: t.window, text: t.text, accent: t.accent };
    }

    Text {
        text: panel.app.t("Settings")
        color: panel.app.dim
        font.family: panel.app.mono
        font.pixelSize: panel.app.soft ? 12 : 11
        font.weight: panel.app.soft ? Font.Medium : Font.Normal
        font.letterSpacing: panel.app.soft || panel.app.diamond ? 0.3 : 2
    }

    Text {
        Layout.topMargin: 6
        text: panel.app.t("Theme")
        color: panel.app.dim
        font.family: panel.app.mono
        font.pixelSize: 10
        font.letterSpacing: 1
    }

    GridLayout {
        Layout.fillWidth: true
        columns: 2
        columnSpacing: 10
        rowSpacing: 10

        Repeater {
            model: panel.app.themeList
            Rectangle {
                id: card
                required property var modelData
                readonly property var sw: panel.swatch(modelData)
                readonly property bool selected: panel.app.theme.id === modelData.id
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.preferredHeight: 72
                radius: panel.app.rBox
                color: mouse.containsMouse ? Qt.tint(panel.app.panel, Qt.alpha(panel.app.accent, 0.10)) : panel.app.panel
                border.width: selected ? 2 : 1
                border.color: selected ? panel.app.accent : (panel.app.soft ? panel.app.controlEdge : panel.app.line)

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 12

                    // A tiny preview of the theme's own colours.
                    Rectangle {
                        Layout.preferredWidth: 52
                        Layout.preferredHeight: 40
                        radius: card.modelData.style === "soft" ? 8 : 0
                        color: card.sw.bg
                        border.color: Qt.alpha(card.sw.text, 0.3)
                        Rectangle { x: 8; y: 9; width: 22; height: 6; radius: parent.radius > 0 ? 3 : 0; color: card.sw.accent }
                        Rectangle { x: 8; y: 21; width: 36; height: 4; radius: parent.radius > 0 ? 2 : 0; color: Qt.alpha(card.sw.text, 0.7) }
                        Rectangle { x: 8; y: 29; width: 26; height: 4; radius: parent.radius > 0 ? 2 : 0; color: Qt.alpha(card.sw.text, 0.35) }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Text {
                            Layout.fillWidth: true
                            text: card.modelData.name
                            color: panel.app.ink
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        Text {
                            Layout.fillWidth: true
                            text: card.modelData.note
                            color: panel.app.dim
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                    }
                }

                MouseArea {
                    id: mouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: panel.app.change(c => c.theme = card.modelData.id)
                }
            }
        }
    }

    // Optional picture behind everything. The theme underneath stays as it is: switch the picture off and it is back.
    Text {
        Layout.topMargin: 10
        text: panel.app.t("Background")
        color: panel.app.dim
        font.family: panel.app.mono
        font.pixelSize: 10
        font.letterSpacing: 1
    }

    FileDialog {
        id: picker
        title: "Choose a background picture"
        nameFilters: ["Pictures (*.png *.jpg *.jpeg *.webp *.bmp *.gif)", "All files (*)"]
        onAccepted: panel.app.change(c => { c.bg_image = selectedFile.toString(); c.bg_enabled = true; })
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 72
        radius: panel.app.rBox
        color: panel.app.panelFill
        border.color: panel.app.soft ? panel.app.controlEdge : panel.app.line

        RowLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 12

            // What it will look like: the picture cropped to fill, never squashed.
            Rectangle {
                Layout.preferredWidth: 78
                Layout.preferredHeight: 48
                radius: panel.app.soft ? 8 : 0
                color: panel.app.tonal
                clip: true
                Image {
                    anchors.fill: parent
                    source: panel.app.cfg.bg_image || ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: 240
                    visible: status === Image.Ready
                }
                Text {
                    anchors.centerIn: parent
                    visible: !panel.app.cfg.bg_image
                    text: "none"
                    color: panel.app.dim
                    font.pixelSize: 11
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text {
                    Layout.fillWidth: true
                    text: "Picture background"
                    color: panel.app.ink
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }
                Text {
                    Layout.fillWidth: true
                    readonly property string path: decodeURIComponent((panel.app.cfg.bg_image || "").toString())
                    text: path === "" ? "Pick a picture to put behind the mixer" : path.substring(path.lastIndexOf("/") + 1)
                    color: panel.app.dim
                    font.pixelSize: 11
                    elide: Text.ElideMiddle
                }
            }
            TextButton {
                app: panel.app
                text: panel.app.diamond ? "choose…" : "Choose…"
                tip: "Pick a picture. It is cropped to fit, never squashed."
                onClicked: picker.open()
            }
            Chip {
                app: panel.app
                text: checked ? panel.app.t("On") : panel.app.t("Off")
                checked: !!panel.app.cfg.bg_enabled && !!panel.app.cfg.bg_image
                tip: "Turn the picture background on or off"
                onToggled: {
                    if (!panel.app.cfg.bg_image)
                        picker.open();
                    else
                        panel.app.change(c => c.bg_enabled = !c.bg_enabled);
                }
            }
        }
    }

    // ---- Scenes ----
    Text {
        Layout.topMargin: 10
        text: panel.app.t("Scenes")
        color: panel.app.dim
        font.family: panel.app.mono
        font.pixelSize: 10
        font.letterSpacing: 1
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        TextField {
            id: sceneName
            Layout.fillWidth: true
            Layout.preferredHeight: 32
            placeholderText: "Name this layout (Gaming, Call, Stream…)"
            placeholderTextColor: panel.app.dim
            color: panel.app.ink
            font.pixelSize: 12
            leftPadding: 14
            selectByMouse: true
            background: Rectangle {
                radius: panel.app.soft ? height / 2 : 0
                color: panel.app.soft ? panel.app.tonal : "transparent"
                border.color: sceneName.activeFocus ? panel.app.accent : panel.app.soft ? panel.app.controlEdge : panel.app.line
            }
            onAccepted: save.clicked()
        }
        TextButton {
            id: save
            app: panel.app
            text: panel.app.diamond ? "save scene" : "Save scene"
            tip: "Save every strip and bus as they are now (devices, routes, levels, voice tools)"
            onClicked: { panel.app.saveScene(sceneName.text); sceneName.text = ""; }
        }
    }
    Repeater {
        model: panel.app.scenes
        Rectangle {
            id: sceneRow
            required property var modelData
            required property int index
            Layout.fillWidth: true
            Layout.preferredHeight: 44
            radius: panel.app.rBox
            color: panel.app.panelFill
            border.color: panel.app.soft ? panel.app.controlEdge : panel.app.line
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 8
                spacing: 6
                Text {
                    Layout.fillWidth: true
                    text: sceneRow.modelData.name
                    color: panel.app.ink
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                Text {
                    visible: panel.app.sceneActive(sceneRow.index)
                    text: "current"
                    color: panel.app.accent
                    font.pixelSize: 11
                }
                TextButton { app: panel.app; text: "Load"; tip: "Switch to this layout"; onClicked: panel.app.applyScene(sceneRow.index) }
                TextButton { app: panel.app; text: "Update"; tip: "Replace this scene with the mixer as it is now"; onClicked: panel.app.saveScene(sceneRow.modelData.name) }
                TextButton { app: panel.app; text: "✕"; tip: "Delete this scene"; onClicked: panel.app.deleteScene(sceneRow.index) }
            }
        }
    }
    Text {
        Layout.fillWidth: true
        visible: panel.app.scenes.length === 0
        text: "No scenes yet. Set the mixer up, give it a name and save it; the first five show above the inputs."
        color: panel.app.dim
        font.pixelSize: 11
        wrapMode: Text.WordWrap
    }

    // ---- Shortcuts ----
    Text {
        Layout.topMargin: 10
        text: panel.app.t("Shortcuts")
        color: panel.app.dim
        font.family: panel.app.mono
        font.pixelSize: 10
        font.letterSpacing: 1
    }
    Text {
        Layout.fillWidth: true
        visible: !panel.app.shortcutsOk
        text: "Global shortcuts need KDE's shortcut service, which isn't available here."
        color: panel.app.warning
        font.pixelSize: 11
        wrapMode: Text.WordWrap
    }
    Rectangle {
        visible: panel.app.shortcutsOk
        Layout.fillWidth: true
        Layout.preferredHeight: 128
        radius: panel.app.rBox
        color: panel.app.panelFill
        border.color: panel.app.soft ? panel.app.controlEdge : panel.app.line
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text { text: "Push to talk"; color: panel.app.ink; font.pixelSize: 13; font.weight: Font.DemiBold }
                    Text {
                        Layout.fillWidth: true
                        text: "Mic reaches B mics only while held"
                        color: panel.app.dim
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                }
                Chip {
                    app: panel.app
                    text: checked ? panel.app.t("On") : panel.app.t("Off")
                    checked: !!panel.app.cfg.ptt_enabled
                    tip: "Turn push to talk on or off"
                    onToggled: {
                        if (!panel.app.cfg.ptt_enabled && panel.app.pttKey === 0) {
                            panel.app.flash("Pick a key first, then turn it on.");
                            return;
                        }
                        panel.app.change(c => c.ptt_enabled = !c.ptt_enabled);
                    }
                }
                KeyCapture { app: panel.app; key: panel.app.pttKey; onCaptured: k => panel.app.setShortcut("ptt", k) }
                TextButton {
                    app: panel.app
                    text: "✕"
                    tip: "Clear the key (and turn push to talk off)"
                    onClicked: { panel.app.setShortcut("ptt", 0); if (panel.app.cfg.ptt_enabled) panel.app.change(c => c.ptt_enabled = false); }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text { text: "Mute microphones"; color: panel.app.ink; font.pixelSize: 13; font.weight: Font.DemiBold }
                    Text {
                        Layout.fillWidth: true
                        text: "One key mutes or unmutes the B mics"
                        color: panel.app.dim
                        font.pixelSize: 11
                        elide: Text.ElideRight
                    }
                }
                KeyCapture { app: panel.app; key: panel.app.muteKey; onCaptured: k => panel.app.setShortcut("mute-mics", k) }
                TextButton { app: panel.app; text: "✕"; tip: "Clear the key"; onClicked: panel.app.setShortcut("mute-mics", 0) }
            }
        }
    }

    // ---- Recording ----
    Text {
        Layout.topMargin: 10
        text: panel.app.t("Recording")
        color: panel.app.dim
        font.family: panel.app.mono
        font.pixelSize: 10
        font.letterSpacing: 1
    }
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 56 + 3 * 46
        radius: panel.app.rBox
        color: panel.app.panelFill
        border.color: panel.app.soft ? panel.app.controlEdge : panel.app.line
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 8
            Text {
                Layout.fillWidth: true
                text: "Rec on an output saves what it carries to Music/Vox Pro. Sizes are per hour of stereo."
                color: panel.app.dim
                font.pixelSize: 11
                wrapMode: Text.WordWrap
            }
            Repeater {
                model: [
                    { id: "flac", name: "FLAC", note: "24-bit, lossless · about 0.5 GB an hour" },
                    { id: "wav", name: "WAV", note: "32-bit float, lossless, biggest · about 1.4 GB an hour" },
                    { id: "opus", name: "Opus", note: "128 kbps, lossy, smallest · about 55 MB an hour" }
                ]
                RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 12
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Text { text: parent.parent.modelData.name; color: panel.app.ink; font.pixelSize: 13; font.weight: Font.DemiBold }
                        Text { Layout.fillWidth: true; text: parent.parent.modelData.note; color: panel.app.dim; font.pixelSize: 11; elide: Text.ElideRight }
                    }
                    Chip {
                        app: panel.app
                        text: checked ? panel.app.t("Selected") : panel.app.t("Use")
                        checked: (panel.app.cfg.record_format || "flac") === parent.modelData.id
                        onToggled: panel.app.change(c => c.record_format = parent.modelData.id)
                    }
                }
            }
        }
    }

    // ---- Behaviour ----
    Text {
        Layout.topMargin: 10
        text: panel.app.t("Behaviour")
        color: panel.app.dim
        font.family: panel.app.mono
        font.pixelSize: 10
        font.letterSpacing: 1
    }
    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 56
        radius: panel.app.rBox
        color: panel.app.panelFill
        border.color: panel.app.soft ? panel.app.controlEdge : panel.app.line
        RowLayout {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 12
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                Text { text: "Keep running in the tray"; color: panel.app.ink; font.pixelSize: 13; font.weight: Font.DemiBold }
                Text {
                    Layout.fillWidth: true
                    text: panel.app.trayOn ? "Closing the window leaves the mixer running; use the tray icon to bring it back" : "No system tray found"
                    color: panel.app.dim
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }
            }
            Chip {
                app: panel.app
                enabled: panel.app.trayOn
                opacity: enabled ? 1 : 0.5
                text: checked ? panel.app.t("On") : panel.app.t("Off")
                checked: !!panel.app.cfg.close_to_tray
                onToggled: panel.app.change(c => c.close_to_tray = !c.close_to_tray)
            }
        }
    }

    // ---- About ----
    Text {
        Layout.topMargin: 10
        text: panel.app.t("About")
        color: panel.app.dim
        font.family: panel.app.mono
        font.pixelSize: 10
        font.letterSpacing: 1
    }
    Rectangle {
        id: aboutBox
        Layout.fillWidth: true
        Layout.preferredHeight: aboutColumn.implicitHeight + 24
        radius: panel.app.rBox
        color: panel.app.panelFill
        border.color: panel.app.soft ? panel.app.controlEdge : panel.app.line
        ColumnLayout {
            id: aboutColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 12
            spacing: 10
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text { text: "Vox Pro " + panel.app.version; color: panel.app.ink; font.pixelSize: 13; font.weight: Font.DemiBold }
                    Text {
                        Layout.fillWidth: true
                        text: "Support its development."
                        color: panel.app.dim
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }
                }
                TextButton { app: panel.app; text: "Ko-fi"; tip: "ko-fi.com/obscuratea"; onClicked: Qt.openUrlExternally("https://ko-fi.com/obscuratea") }
                TextButton { app: panel.app; text: "Patreon"; tip: "patreon.com/Obscuratea"; onClicked: Qt.openUrlExternally("https://patreon.com/Obscuratea") }
            }
            // ---- Updates ----
            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: panel.app.soft ? "transparent" : panel.app.line }
            RowLayout {
                id: updateRow
                readonly property var u: panel.app.update
                readonly property bool busy: u.state === "checking" || u.state === "downloading" || u.state === "installing"
                Layout.fillWidth: true
                spacing: 12
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Text {
                        Layout.fillWidth: true
                        color: updateRow.u.state === "error" ? panel.app.danger : panel.app.ink
                        font.pixelSize: 13
                        font.weight: Font.DemiBold
                        wrapMode: Text.WordWrap
                        text: ({ idle: "Updates", checking: "Checking for updates...", uptodate: "Up to date",
                                 available: "Version " + updateRow.u.latest + " is available", downloading: "Downloading " + updateRow.u.latest + "...",
                                 installing: "Installing...", installed: "Updated to " + updateRow.u.latest, error: "Couldn't update" })[updateRow.u.state] || "Updates"
                    }
                    Text {
                        Layout.fillWidth: true
                        visible: text !== ""
                        text: updateRow.u.state === "error" ? updateRow.u.message : ""
                        color: panel.app.dim
                        font.pixelSize: 11
                        wrapMode: Text.WordWrap
                    }
                    Rectangle {
                        visible: updateRow.u.state === "downloading"
                        Layout.fillWidth: true
                        Layout.topMargin: 4
                        Layout.preferredHeight: 6
                        radius: 3
                        color: panel.app.hover
                        Rectangle {
                            width: parent.width * updateRow.u.progress / 100
                            height: parent.height
                            radius: 3
                            color: panel.app.accent
                        }
                    }
                }
                TextButton {
                    visible: !updateRow.busy && updateRow.u.state !== "available" && updateRow.u.state !== "installed"
                    app: panel.app
                    text: updateRow.u.state === "error" ? "Try again" : "Check for updates"
                    onClicked: panel.app.checkForUpdate()
                }
                TextButton {
                    visible: updateRow.u.state === "available"
                    app: panel.app
                    text: "Update to " + updateRow.u.latest
                    tip: "Downloads the new version, checks it and installs it. Your settings are not touched."
                    onClicked: panel.app.installUpdate()
                }
                TextButton {
                    visible: updateRow.u.state === "installed"
                    app: panel.app
                    text: "Restart now"
                    onClicked: panel.app.restartAfterUpdate()
                }
            }
            Text {
                visible: updateRow.u.state === "available" && updateRow.u.notes !== ""
                Layout.fillWidth: true
                text: updateRow.u.notes
                color: panel.app.dim
                font.pixelSize: 11
                wrapMode: Text.WordWrap
                maximumLineCount: 8
                elide: Text.ElideRight
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                Text {
                    Layout.fillWidth: true
                    text: "Auto-check for updates"
                    color: panel.app.ink
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    wrapMode: Text.WordWrap
                }
                Chip {
                    app: panel.app
                    text: checked ? panel.app.t("On") : panel.app.t("Off")
                    checked: panel.app.cfg.check_updates !== false
                    onToggled: panel.app.change(c => c.check_updates = !(c.check_updates !== false))
                }
            }
            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: panel.app.soft ? "transparent" : panel.app.line }
            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                Text {
                    Layout.fillWidth: true
                    text: "Credits and Licenses"
                    color: panel.app.ink
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                }
                TextButton {
                    app: panel.app
                    text: "Show"
                    onClicked: licencePopup.open()
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
            radius: panel.app.rBox
            color: panel.app.bg
            border.color: panel.app.soft ? panel.app.controlEdge : panel.app.line
        }
        contentItem: ColumnLayout {
            spacing: 10
            RowLayout {
                Layout.fillWidth: true
                Text {
                    Layout.fillWidth: true
                    text: "Credits and Licenses"
                    color: panel.app.ink
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                }
                TextButton { app: panel.app; text: "Close"; onClicked: licencePopup.close() }
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
                    text: licencePopup.visible ? panel.app.licensesText() : ""
                    color: panel.app.ink
                    font.family: "monospace"
                    font.pixelSize: 11
                    wrapMode: Text.WordWrap
                    textFormat: Text.PlainText
                }
            }
        }
    }
}
}
