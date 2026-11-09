use cxx_qt_build::{CxxQtBuilder, QmlModule};

fn main() {
    CxxQtBuilder::new_qml_module(QmlModule::new("org.obscura.vox").qml_files([
        "qml/Main.qml",
        "qml/StripCard.qml",
        "qml/BusRow.qml",
        "qml/Fader.qml",
        "qml/LevelMeter.qml",
        "qml/Chip.qml",
        "qml/StreamList.qml",
        "qml/DevicePicker.qml",
        "qml/TextButton.qml",
        "qml/ToneSlider.qml",
        "qml/CutFrame.qml",
        "qml/Themes.qml",
        "qml/Glass.qml",
        "qml/SettingsPanel.qml",
        "qml/KeyCapture.qml",
        "qml/Tray.qml",
    ]))
    .file("src/bridge.rs")
    .build();

    // SoundTouch (the pitch engine EasyEffects uses) is C++, so it gets a small C shim.
    cc::Build::new().cpp(true).file("src/soundtouch_shim.cpp").compile("soundtouch_shim");
    println!("cargo:rerun-if-changed=src/soundtouch_shim.cpp");
    println!("cargo:rustc-link-lib=SoundTouch");

    // The QApplication (see qt_shim.cpp): the tray icon needs Qt Widgets.
    let mut qt = cc::Build::new();
    qt.cpp(true).file("src/qt_shim.cpp").flag_if_supported("-fPIC");
    println!("cargo:rustc-link-lib=Qt6Widgets");
    if let Ok(out) = std::process::Command::new("pkg-config").args(["--cflags", "Qt6Widgets"]).output() {
        for flag in String::from_utf8_lossy(&out.stdout).split_whitespace() {
            qt.flag(flag);
        }
    }
    qt.compile("qt_shim");
    println!("cargo:rerun-if-changed=src/qt_shim.cpp");
}
