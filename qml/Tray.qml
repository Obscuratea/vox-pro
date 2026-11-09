import QtQuick
import Qt.labs.platform as Platform

// The tray icon: click to show or hide the window; the menu has mute, the scenes and quit.
// Kept in its own file so Main.qml can skip it where there are no native menus (the offscreen test platform).
Platform.SystemTrayIcon {
    required property var app
    id: tray
    visible: available
    icon.name: "vox-pro"
    tooltip: "Vox Pro"
    onActivated: reason => { if (reason === Platform.SystemTrayIcon.Trigger) app.toggleWindow(); }
    menu: Platform.Menu {
        Platform.MenuItem { text: app.visible ? "Hide Vox Pro" : "Show Vox Pro"; onTriggered: app.toggleWindow() }
        Platform.MenuSeparator {}
        Platform.MenuItem { text: app.micsMuted ? "Unmute microphones" : "Mute microphones"; onTriggered: app.muteMics(!app.micsMuted) }
        Platform.Menu {
            id: sceneMenu
            title: "Scenes"
            visible: app.scenes.length > 0
            Instantiator {
                model: app.scenes
                delegate: Platform.MenuItem {
                    required property var modelData
                    required property int index
                    text: modelData.name
                    checkable: true
                    checked: app.sceneActive(index)
                    onTriggered: app.applyScene(index)
                }
                onObjectAdded: (i, obj) => sceneMenu.insertItem(i, obj)
                onObjectRemoved: (i, obj) => sceneMenu.removeItem(obj)
            }
        }
        Platform.MenuSeparator {}
        Platform.MenuItem { text: "Quit"; onTriggered: { app.quitApp(); } }
    }
}

