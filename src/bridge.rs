//! The `Mixer` object QML talks to. QML keeps the settings as a plain JS object and hands
//! the whole thing back as JSON on every change; meters and devices come back as JSON too.

use crate::engine::{self, Command, Handle};
use crate::settings::{self, Settings};
use crate::shortcuts::Accel;
use std::sync::{Mutex, OnceLock};

#[cxx_qt::bridge]
pub mod qobject {
    unsafe extern "C++" {
        include!("cxx-qt-lib/qstring.h");
        type QString = cxx_qt_lib::QString;
    }

    extern "RustQt" {
        #[qobject]
        #[qml_element]
        type Mixer = super::MixerRust;

        // The current settings as JSON.
        #[qinvokable]
        fn settings(self: &Mixer) -> QString;

        // `{sources: [...], sinks: [...]}`, each `{name, description}`.
        #[qinvokable]
        fn devices(self: &Mixer) -> QString;

        // Peak levels since the last call: `{strips: [[l, r], ...], buses: [[l, r], ...]}`.
        #[qinvokable]
        fn meters(self: &Mixer) -> QString;

        // Send new settings (JSON) to the engine.
        #[qinvokable]
        fn apply(self: &Mixer, json: &QString);

        // Write the current settings to disk.
        #[qinvokable]
        fn persist(self: &Mixer);

        // Programs using Apps, Media, B1 and B2: `[{id, name, target, muted}, ...]`.
        #[qinvokable]
        fn streams(self: &Mixer) -> QString;

        // Mute or unmute one program's stream by node id.
        #[qinvokable]
        #[cxx_name = "muteStream"]
        fn mute_stream(self: &Mixer, id: i32, muted: bool);

        // A message when PipeWire can't be reached or was lost, "" when all is well.
        #[qinvokable]
        #[cxx_name = "engineStatus"]
        fn engine_status(self: &Mixer) -> QString;

        // The program's version, and the text of THIRD_PARTY.txt (the credits and licences shown in About).
        #[qinvokable]
        fn version(self: &Mixer) -> QString;
        #[qinvokable]
        fn licenses(self: &Mixer) -> QString;

        // Updates: `updateStatus` is JSON ({state, current, latest, notes, progress, message}); the other
        // three start work on a thread. See updater.rs.
        #[qinvokable]
        #[cxx_name = "updateStatus"]
        fn update_status(self: &Mixer) -> QString;
        #[qinvokable]
        #[cxx_name = "updateCheck"]
        fn update_check(self: &Mixer);
        #[qinvokable]
        #[cxx_name = "updateInstall"]
        fn update_install(self: &Mixer);
        #[qinvokable]
        #[cxx_name = "updateRestart"]
        fn update_restart(self: &Mixer);

        // The scheme's accent (its window focus colour) as "#rrggbb", or "" if it can't be read.
        #[qinvokable]
        #[cxx_name = "schemeAccent"]
        fn scheme_accent(self: &Mixer) -> QString;

        // Things the desktop asked for, as a JSON array of names (e.g. ["mute-mics"]); emptied by the call.
        #[qinvokable]
        #[cxx_name = "takeEvents"]
        fn take_events(self: &Mixer) -> QString;

        // Global shortcuts: whether the desktop offers them, the Qt key code bound to an action
        // ("ptt", "mute-mics"; 0 = none), and binding a new one (returns what ended up bound).
        #[qinvokable]
        #[cxx_name = "shortcutsAvailable"]
        fn shortcuts_available(self: &Mixer) -> bool;
        #[qinvokable]
        #[cxx_name = "shortcutKey"]
        fn shortcut_key(self: &Mixer, action: &QString) -> i32;
        #[qinvokable]
        #[cxx_name = "setShortcutKey"]
        fn set_shortcut_key(self: &Mixer, action: &QString, key: i32) -> i32;

        // Recording: one entry per output, the file being written, "!reason" if it failed, "" when idle.
        #[qinvokable]
        fn recording(self: &Mixer) -> QString;
        #[qinvokable]
        fn record(self: &Mixer, bus: i32, on: bool);

        // Send one program's playback to a strip: target is "apps" or "media".
        #[qinvokable]
        #[cxx_name = "moveStream"]
        fn move_stream(self: &Mixer, id: i32, target: &QString);

        // Make one of our nodes (by node.name) the system default output or microphone.
        #[qinvokable]
        #[cxx_name = "makeDefault"]
        fn make_default(self: &Mixer, node: &QString) -> bool;
    }
}

struct State {
    engine: Handle,
    current: Mutex<Settings>,
    accel: Option<Accel>,
}

static STATE: OnceLock<State> = OnceLock::new();

/// Called once from main before the UI loads.
pub fn init(engine: Handle, settings: Settings) {
    let accel = Accel::start(engine.shared.clone());
    let _ = STATE.set(State { engine, current: Mutex::new(settings), accel });
}

fn state() -> &'static State {
    STATE.get().expect("bridge::init runs before the UI")
}

/// The kdeglobals text, re-read only when the file's modification time changes (the UI asks every second).
fn read_kdeglobals() -> String {
    static CACHE: Mutex<Option<(std::time::SystemTime, String)>> = Mutex::new(None);
    let base = std::env::var_os("XDG_CONFIG_HOME")
        .map(std::path::PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|h| std::path::PathBuf::from(h).join(".config")));
    let Some(path) = base.map(|b| b.join("kdeglobals")) else { return String::new() };
    let Ok(modified) = std::fs::metadata(&path).and_then(|m| m.modified()) else { return String::new() };
    let mut cache = CACHE.lock().unwrap();
    if let Some((when, text)) = cache.as_ref() {
        if *when == modified {
            return text.clone();
        }
    }
    let text = std::fs::read_to_string(&path).unwrap_or_default();
    *cache = Some((modified, text.clone()));
    text
}

#[derive(Default)]
pub struct MixerRust;

impl qobject::Mixer {
    fn settings(&self) -> qobject::QString {
        qobject::QString::from(&state().current.lock().unwrap().to_json())
    }

    fn version(&self) -> qobject::QString {
        qobject::QString::from(env!("CARGO_PKG_VERSION"))
    }

    fn licenses(&self) -> qobject::QString {
        qobject::QString::from(include_str!("../THIRD_PARTY.txt"))
    }

    fn update_status(&self) -> qobject::QString {
        qobject::QString::from(&crate::updater::status_json())
    }

    fn update_check(&self) {
        crate::updater::check();
    }

    fn update_install(&self) {
        crate::updater::install();
    }

    fn update_restart(&self) {
        crate::updater::restart();
    }

    fn devices(&self) -> qobject::QString {
        let devices = state().engine.shared.devices.lock().unwrap();
        qobject::QString::from(&serde_json::to_string(&*devices).unwrap_or_default())
    }

    fn streams(&self) -> qobject::QString {
        qobject::QString::from(&*state().engine.shared.streams.lock().unwrap())
    }

    fn mute_stream(&self, id: i32, muted: bool) {
        let _ = state().engine.sender.lock().unwrap().send(Command::MuteStream(id as u32, muted));
    }

    fn recording(&self) -> qobject::QString {
        qobject::QString::from(&serde_json::to_string(&*state().engine.shared.recording.lock().unwrap()).unwrap_or_default())
    }

    fn record(&self, bus: i32, on: bool) {
        if bus >= 0 {
            let _ = state().engine.sender.lock().unwrap().send(Command::Record(bus as usize, on));
        }
    }

    fn move_stream(&self, id: i32, target: &qobject::QString) {
        let _ = state().engine.sender.lock().unwrap().send(Command::MoveStream(id as u32, target.to_string()));
    }

    fn meters(&self) -> qobject::QString {
        let shared = &state().engine.shared;
        let pair = |cells: &[std::sync::atomic::AtomicU32; 2]| [engine::take_peak(&cells[0]), engine::take_peak(&cells[1])];
        let strips: Vec<_> = shared.strip_peaks.iter().map(pair).collect();
        let buses: Vec<_> = shared.bus_peaks.iter().map(pair).collect();
        let comp: Vec<_> = shared.strip_reduction.iter().map(engine::take_peak).collect();
        let limit: Vec<_> = shared.bus_reduction.iter().map(engine::take_peak).collect();
        let json = serde_json::json!({ "strips": strips, "buses": buses, "comp": comp, "limit": limit });
        qobject::QString::from(&json.to_string())
    }

    fn apply(&self, json: &qobject::QString) {
        let Some(settings) = Settings::from_json(&json.to_string()) else { return };
        let state = state();
        *state.current.lock().unwrap() = settings.clone();
        let _ = state.engine.sender.lock().unwrap().send(Command::Apply(settings));
    }

    fn persist(&self) {
        settings::save(&state().current.lock().unwrap());
    }

    fn engine_status(&self) -> qobject::QString {
        qobject::QString::from(&*state().engine.shared.status.lock().unwrap())
    }

    fn scheme_accent(&self) -> qobject::QString {
        let text = read_kdeglobals();
        let mut in_window = false;
        for line in text.lines() {
            if line.starts_with('[') {
                in_window = line.trim() == "[Colors:Window]";
            } else if let (true, Some(rgb)) = (in_window, line.strip_prefix("DecorationFocus=")) {
                let c: Vec<u8> = rgb.split(',').filter_map(|v| v.trim().parse().ok()).collect();
                if let [r, g, b] = c[..] {
                    return qobject::QString::from(&format!("#{r:02x}{g:02x}{b:02x}"));
                }
            }
        }
        qobject::QString::from("")
    }

    fn take_events(&self) -> qobject::QString {
        let events = std::mem::take(&mut *state().engine.shared.events.lock().unwrap());
        qobject::QString::from(&serde_json::to_string(&events).unwrap_or_default())
    }

    fn shortcuts_available(&self) -> bool {
        state().accel.is_some()
    }

    fn shortcut_key(&self, action: &qobject::QString) -> i32 {
        state().accel.as_ref().map_or(0, |a| a.key(&action.to_string()))
    }

    fn set_shortcut_key(&self, action: &qobject::QString, key: i32) -> i32 {
        state().accel.as_ref().map_or(0, |a| a.set_key(&action.to_string(), key))
    }

    fn make_default(&self, node: &qobject::QString) -> bool {
        let id = state().engine.shared.own_nodes.lock().unwrap().get(&node.to_string()).copied();
        let Some(id) = id else { return false };
        std::process::Command::new("wpctl")
            .args(["set-default", &id.to_string()])
            .status()
            .is_ok_and(|s| s.success())
    }
}
