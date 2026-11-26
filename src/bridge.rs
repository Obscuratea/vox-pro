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

        // Plugins (see plugins.rs): the list of usable LV2 plugins ("" while the first scan runs), one plugin's
        // controls, and whether plugins are switched off after a crash (and switching them back on).
        #[qinvokable]
        #[cxx_name = "pluginCatalog"]
        fn plugin_catalog(self: &Mixer) -> QString;
        #[qinvokable]
        #[cxx_name = "pluginInfo"]
        fn plugin_info(self: &Mixer, uri: &QString) -> QString;
        #[qinvokable]
        #[cxx_name = "pluginsRescan"]
        fn plugins_rescan(self: &Mixer);
        // Copy a dropped plugin (.clap file, .vst3 or .lv2 folder) into the user's plugin folder and rescan. Returns "" or what went wrong.
        #[qinvokable]
        #[cxx_name = "pluginsInstall"]
        fn plugins_install(self: &Mixer, path: &QString) -> QString;
        #[qinvokable]
        #[cxx_name = "pluginsSafeMode"]
        fn plugins_safe_mode(self: &Mixer) -> bool;
        #[qinvokable]
        #[cxx_name = "pluginsResume"]
        fn plugins_resume(self: &Mixer);

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

        // Send one program's playback to a strip: target is the strip's slug ("apps", "game").
        #[qinvokable]
        #[cxx_name = "moveStream"]
        fn move_stream(self: &Mixer, id: i32, target: &QString);
        // Undo moveStream: the stream goes back to where it would play by itself.
        #[qinvokable]
        #[cxx_name = "sendBack"]
        fn send_back(self: &Mixer, id: i32);

        // Glass themes: ask the compositor to blur the desktop behind the see-through window.
        #[qinvokable]
        #[cxx_name = "blurBehind"]
        fn blur_behind(self: &Mixer, on: bool);

        // The tray icon (qt_shim.cpp): its state as JSON, see vox_tray_update; and whether there is a tray.
        #[qinvokable]
        #[cxx_name = "trayUpdate"]
        fn tray_update(self: &Mixer, json: &QString);
        #[qinvokable]
        #[cxx_name = "trayAvailable"]
        fn tray_available(self: &Mixer) -> bool;

        // What Vox itself uses: `{cpu, ram, rate, cycle}`, cpu in % of one core since the last call, ram in MiB,
        // the sample rate and one PipeWire cycle in ms.
        #[qinvokable]
        fn usage(self: &Mixer) -> QString;

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

/// Called by the tray (qt_shim.cpp, on the Qt thread) when it is clicked: queues `name` for the QML,
/// which picks events up with takeEvents.
#[unsafe(no_mangle)]
pub extern "C" fn vox_push_event(name: *const std::ffi::c_char) {
    if name.is_null() {
        return;
    }
    let name = unsafe { std::ffi::CStr::from_ptr(name) }.to_string_lossy().into_owned();
    if let Some(state) = STATE.get() {
        state.engine.shared.events.lock().unwrap().push(name);
    }
}

/// Called once from main before the UI loads.
pub fn init(engine: Handle, settings: Settings) {
    let accel = Accel::start(engine.shared.clone());
    crate::desktop::watch_lock(engine.shared.clone());
    crate::desktop::set_autostart(settings.prefs.autostart);
    let _ = STATE.set(State { engine, current: Mutex::new(settings), accel });
}

/// CPU time (in clock ticks) this process has used, from /proc/self/stat (utime + stime, all threads).
fn cpu_ticks() -> Option<u64> {
    let stat = std::fs::read_to_string("/proc/self/stat").ok()?;
    // The program name in field 2 can hold spaces, so count fields from the ")" that closes it.
    let rest = &stat[stat.rfind(')')? + 2..];
    let fields: Vec<&str> = rest.split_whitespace().collect();
    Some(fields.get(11)?.parse::<u64>().ok()? + fields.get(12)?.parse::<u64>().ok()?)
}

/// Resident memory of this process in MiB (VmRSS, what top and the system monitor show).
fn ram_mib() -> Option<f64> {
    let status = std::fs::read_to_string("/proc/self/status").ok()?;
    let line = status.lines().find(|l| l.starts_with("VmRSS:"))?;
    Some(line.split_whitespace().nth(1)?.parse::<f64>().ok()? / 1024.0)
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

    fn plugin_catalog(&self) -> qobject::QString {
        qobject::QString::from(&crate::plugins::host().catalog())
    }

    fn plugin_info(&self, uri: &qobject::QString) -> qobject::QString {
        qobject::QString::from(&crate::plugins::host().info(&uri.to_string()))
    }

    fn plugins_rescan(&self) {
        crate::plugins::host().rescan();
    }

    fn plugins_install(&self, path: &qobject::QString) -> qobject::QString {
        let result = crate::plugins::install(std::path::Path::new(&path.to_string()));
        if result.is_ok() {
            crate::plugins::host().rescan();
        }
        qobject::QString::from(&result.err().unwrap_or_default())
    }

    fn plugins_safe_mode(&self) -> bool {
        crate::plugins::host().safe_mode()
    }

    fn plugins_resume(&self) {
        crate::plugins::host().leave_safe_mode();
        let _ = state().engine.sender.lock().unwrap().send(Command::ReloadPlugins);
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

    fn blur_behind(&self, on: bool) {
        unsafe { crate::vox_blur_behind(on) }
    }

    fn tray_update(&self, json: &qobject::QString) {
        if let Ok(json) = std::ffi::CString::new(json.to_string()) {
            unsafe { crate::vox_tray_update(json.as_ptr()) }
        }
    }

    fn tray_available(&self) -> bool {
        unsafe { crate::vox_tray_available() }
    }

    fn usage(&self) -> qobject::QString {
        // Linux reports CPU time in USER_HZ ticks, which is 100 per second on every architecture it runs on.
        const TICKS_PER_SECOND: f64 = 100.0;
        static LAST: Mutex<Option<(std::time::Instant, u64)>> = Mutex::new(None);
        let now = std::time::Instant::now();
        let ticks = cpu_ticks().unwrap_or(0);
        let mut last = LAST.lock().unwrap();
        let cpu = match *last {
            Some((when, before)) if now > when => {
                (ticks.saturating_sub(before)) as f64 / TICKS_PER_SECOND / now.duration_since(when).as_secs_f64() * 100.0
            }
            _ => 0.0,
        };
        *last = Some((now, ticks));
        // One PipeWire cycle, in milliseconds: how long a sound waits in Vox before it moves on.
        let frames = state().engine.shared.cycle.load(std::sync::atomic::Ordering::Relaxed) as f64;
        let cycle = frames / crate::dsp::sample_rate() as f64 * 1000.0;
        let json = serde_json::json!({
            "cpu": (cpu * 10.0).round() / 10.0,
            "ram": ram_mib().unwrap_or(0.0).round(),
            "rate": crate::dsp::sample_rate() as u32,
            "cycle": (cycle * 10.0).round() / 10.0,
        });
        qobject::QString::from(&json.to_string())
    }

    fn recording(&self) -> qobject::QString {
        qobject::QString::from(&serde_json::to_string(&*state().engine.shared.recording.lock().unwrap()).unwrap_or_default())
    }

    fn record(&self, bus: i32, on: bool) {
        if bus >= 0 {
            let _ = state().engine.sender.lock().unwrap().send(Command::Record(bus as usize, on));
        }
    }

    fn send_back(&self, id: i32) {
        let _ = state().engine.sender.lock().unwrap().send(Command::SendBack(id as u32));
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
        let was = std::mem::replace(&mut *state.current.lock().unwrap(), settings.clone());
        if was.prefs.autostart != settings.prefs.autostart {
            crate::desktop::set_autostart(settings.prefs.autostart);
        }
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

#[cfg(test)]
mod tests {
    #[test]
    fn own_cpu_and_memory_can_be_read() {
        let before = super::cpu_ticks().expect("cpu time");
        let mut x = 0u64;
        let start = std::time::Instant::now();
        while start.elapsed().as_millis() < 300 { x = std::hint::black_box(x.wrapping_add(x | 1)); }
        assert!(x != 1);
        assert!(super::cpu_ticks().unwrap() > before, "busy work shows up as cpu time");
        let ram = super::ram_mib().expect("memory");
        assert!(ram > 1.0 && ram < 10_000.0, "{ram} MiB");
    }
}
