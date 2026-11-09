// Vox runs on a QApplication rather than a plain QGuiApplication: Qt's tray icon (and its menu) are
// widget classes and refuse to work without one. cxx-qt-lib has no QApplication, so it is made here.
// It also stops Qt from quitting when the window closes, so Vox can live on in the tray; the QML
// quits explicitly when it should really exit.
#include <QApplication>

extern "C" void vox_app_new(int argc, char **argv, const char *name) {
    static int stored_argc = argc;   // QApplication keeps references to these, so they must outlive it
    auto *app = new QApplication(stored_argc, argv);
    app->setApplicationName(QString::fromUtf8(name));
    QApplication::setQuitOnLastWindowClosed(false);
}

extern "C" int vox_app_exec() { return QApplication::exec(); }
