// Vox runs on a QApplication rather than a plain QGuiApplication: Qt's tray icon (and its menu) are
// widget classes and refuse to work without one. cxx-qt-lib has no QApplication, so it is made here.
// It also stops Qt from quitting when the window closes, so Vox can live on in the tray; the QML
// quits explicitly when it should really exit.
#include <QApplication>
#include <QGuiApplication>
#include <QWindow>
#include <QQuickWindow>
#ifndef VOX_NO_KWINDOWSYSTEM
#include <KWindowEffects>
#endif

extern "C" void vox_app_new(int argc, char **argv, const char *name) {
    static int stored_argc = argc;   // QApplication keeps references to these, so they must outlive it
    QQuickWindow::setDefaultAlphaBuffer(true);   // the Glass themes draw a see-through window
    auto *app = new QApplication(stored_argc, argv);
    app->setApplicationName(QString::fromUtf8(name));
    QApplication::setQuitOnLastWindowClosed(false);
}

extern "C" int vox_app_exec() { return QApplication::exec(); }

// Glass themes: have the compositor blur the desktop behind the window (KWin's blur effect).
// Builds without KWindowSystem (the AppImage, built on a distribution that doesn't package KF6) skip the blur;
// the Glass themes are then see-through without it.
extern "C" void vox_blur_behind(bool on) {
#ifdef VOX_NO_KWINDOWSYSTEM
    (void)on;
#else
    for (QWindow *w : QGuiApplication::topLevelWindows())
        KWindowEffects::enableBlurBehind(w, on);
#endif
}

// ---- Tray icon ----
// Qt's widget tray (QSystemTrayIcon + QMenu) rather than Qt.labs.platform's SystemTrayIcon: outside
// Plasma, the labs tray's D-Bus menu crashed whenever the panel asked for it (seen on niri with
// noctalia, Qt 6.12). On Plasma both end up as the same StatusNotifierItem, so nothing changes there.
// The QML owns the state and sends it as JSON (vox_tray_update); clicks come back as events the
// QML already polls for (vox_push_event, see bridge.rs).
#include <QAction>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMenu>
#include <QSystemTrayIcon>

extern "C" void vox_push_event(const char *name);   // in bridge.rs

namespace {
struct Tray {
    QSystemTrayIcon *icon = nullptr;
    QMenu *menu = nullptr;
    QAction *showHide = nullptr;
    QAction *mute = nullptr;
    QMenu *scenes = nullptr;
};
Tray tray;

void ensureTray() {
    if (tray.icon || QGuiApplication::platformName() == QLatin1String("offscreen")) return;
    tray.menu = new QMenu;
    tray.showHide = tray.menu->addAction(QString());
    QObject::connect(tray.showHide, &QAction::triggered, [] { vox_push_event("show-hide"); });
    tray.menu->addSeparator();
    tray.mute = tray.menu->addAction(QString());
    QObject::connect(tray.mute, &QAction::triggered, [] { vox_push_event("tray-mute"); });
    tray.scenes = tray.menu->addMenu(QStringLiteral("Scenes"));
    tray.menu->addSeparator();
    QObject::connect(tray.menu->addAction(QStringLiteral("Quit")), &QAction::triggered, [] { vox_push_event("tray-quit"); });

    tray.icon = new QSystemTrayIcon;
    tray.icon->setContextMenu(tray.menu);
    QObject::connect(tray.icon, &QSystemTrayIcon::activated, [](QSystemTrayIcon::ActivationReason reason) {
        if (reason == QSystemTrayIcon::Trigger) vox_push_event("show-hide");
    });
}
}

// An icon by name from the desktop's icon theme; failing that, the one shipped next to the program
// (an AppImage's icon isn't installed in the system, so the theme doesn't know it).
static QIcon trayIcon(const QString &name) {
    if (QIcon::hasThemeIcon(name)) return QIcon::fromTheme(name);
    const QString shipped = QCoreApplication::applicationDirPath() + "/../share/icons/hicolor/scalable/apps/" + name + ".svg";
    return QFile::exists(shipped) ? QIcon(shipped) : QIcon::fromTheme(name);
}

// `json`: {icon, tooltip, showHide, mute, scenes: [{name, active}]}. Shows the tray on first call.
extern "C" void vox_tray_update(const char *json) {
    ensureTray();
    if (!tray.icon) return;
    const QJsonObject s = QJsonDocument::fromJson(QByteArray(json)).object();
    tray.icon->setIcon(trayIcon(s.value("icon").toString()));
    tray.icon->setToolTip(s.value("tooltip").toString());
    tray.showHide->setText(s.value("showHide").toString());
    tray.mute->setText(s.value("mute").toString());

    const QJsonArray scenes = s.value("scenes").toArray();
    tray.scenes->clear();
    for (int i = 0; i < scenes.size(); i++) {
        const QJsonObject sc = scenes.at(i).toObject();
        QAction *a = tray.scenes->addAction(sc.value("name").toString());
        a->setCheckable(true);
        a->setChecked(sc.value("active").toBool());
        const QByteArray event = "tray-scene:" + QByteArray::number(i);
        QObject::connect(a, &QAction::triggered, [event] { vox_push_event(event.constData()); });
    }
    tray.scenes->menuAction()->setVisible(!scenes.isEmpty());
    tray.icon->show();
}

// Whether there is a tray to put the icon in (a StatusNotifierItem host on Wayland).
extern "C" bool vox_tray_available() {
    return QGuiApplication::platformName() != QLatin1String("offscreen") && QSystemTrayIcon::isSystemTrayAvailable();
}
