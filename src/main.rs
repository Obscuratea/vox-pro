mod bridge;
mod dsp;
mod engine;
mod icons;
mod recorder;
mod settings;
mod shortcuts;
mod stretch;

use cxx_qt_lib::{QQmlApplicationEngine, QUrl};
use std::ffi::{CString, c_char};
use std::fs::{File, OpenOptions, TryLockError};
use std::path::PathBuf;

/// Only one copy may run: a second one would create a second set of devices with the same
/// names. The lock lasts as long as the returned file is open, and the OS drops it if we crash.
/// Returns None when another copy holds it; if the lock file can't be made, we run anyway.
fn claim_single_instance() -> Option<Option<File>> {
    let dir = std::env::var_os("XDG_RUNTIME_DIR").map(PathBuf::from).unwrap_or_else(std::env::temp_dir);
    let Ok(file) = OpenOptions::new().create(true).truncate(false).write(true).open(dir.join("vox-pro.lock"))
    else {
        return Some(None);
    };
    match file.try_lock() {
        Err(TryLockError::WouldBlock) => None,
        _ => Some(Some(file)),
    }
}

unsafe extern "C" {
    fn vox_app_new(argc: i32, argv: *mut *mut c_char, name: *const c_char);
    fn vox_app_exec() -> i32;
}

fn main() {
    let Some(_instance) = claim_single_instance() else {
        eprintln!("vox-pro: already running");
        // Launched from the app menu there's no terminal, so say it on the desktop too.
        let _ = std::process::Command::new("notify-send")
            .args(["--app-name=Vox Pro", "Vox Pro is already running"])
            .status();
        return;
    };

    let settings = settings::load();
    bridge::init(engine::start(settings.clone()), settings);

    // Qt keeps pointers to argv for the life of the program, so it is leaked on purpose.
    let args: Vec<CString> = std::env::args().filter_map(|a| CString::new(a).ok()).collect();
    let mut argv: Vec<*mut c_char> = args.iter().map(|a| a.as_ptr() as *mut c_char).collect();
    argv.push(std::ptr::null_mut());
    let argc = args.len() as i32;
    std::mem::forget(args);
    let argv = Box::leak(argv.into_boxed_slice());
    unsafe { vox_app_new(argc, argv.as_mut_ptr(), c"Vox Pro".as_ptr()) };
    let mut qml = QQmlApplicationEngine::new();
    if let Some(qml) = qml.as_mut() {
        qml.load(&QUrl::from("qrc:/qt/qml/org/obscura/vox/qml/Main.qml"));
    }
    unsafe { vox_app_exec() };
}
