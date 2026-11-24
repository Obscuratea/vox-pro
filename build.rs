use cxx_qt_build::{CxxQtBuilder, QmlModule};

fn main() {
    // A QML file missing from the list below only fails at run time ("X is not a type"), so catch it here.
    let listed = include_str!("build.rs");
    for entry in std::fs::read_dir("qml").unwrap().flatten() {
        let name = entry.file_name().to_string_lossy().to_string();
        if name.ends_with(".qml") && !listed.contains(&format!("\"qml/{name}\"")) {
            panic!("qml/{name} is not in build.rs's qml_files list");
        }
    }

    CxxQtBuilder::new_qml_module(QmlModule::new("org.obscura.vox").qml_files([
        "qml/Main.qml",
        "qml/Card.qml",
        "qml/ChannelRow.qml",
        "qml/ChannelStrip.qml",
        "qml/Chip.qml",
        "qml/CutFrame.qml",
        "qml/DevicePicker.qml",
        "qml/EqView.qml",
        "qml/Fader.qml",
        "qml/Glass.qml",
        "qml/Icon.qml",
        "qml/IconButton.qml",
        "qml/Inspector.qml",
        "qml/KeyCapture.qml",
        "qml/Knob.qml",
        "qml/LevelMeter.qml",
        "qml/MixerView.qml",
        "qml/PeqCurve.qml",
        "qml/PeqEditor.qml",
        "qml/Pill.qml",
        "qml/PluginRack.qml",
        "qml/Raised.qml",
        "qml/RoutingView.qml",
        "qml/SettingsPanel.qml",
        "qml/StreamList.qml",
        "qml/Tag.qml",
        "qml/TextButton.qml",
        "qml/Themes.qml",
        "qml/Toggle.qml",
        "qml/ToneSlider.qml",
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
    println!("cargo:rustc-link-lib=KF6WindowSystem");
    if let Ok(out) = std::process::Command::new("pkg-config").args(["--cflags", "Qt6Widgets", "Qt6Quick"]).output() {
        for flag in String::from_utf8_lossy(&out.stdout).split_whitespace() {
            qt.flag(flag);
        }
    }
    qt.flag("-I/usr/include/KF6/KWindowSystem");
    qt.compile("qt_shim");
    println!("cargo:rerun-if-changed=src/qt_shim.cpp");
}
