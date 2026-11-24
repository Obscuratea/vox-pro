//! The mixer layout the user builds, saved as JSON in ~/.config/vox-pro/settings.json.
//! The UI owns the settings and sends a full copy to the engine on every change.

use crate::peq::{self, Cell};
use crate::plugins::{self, Slot};
use serde::{Deserialize, Serialize};
use std::path::PathBuf;

/// How many of each kind of channel there can be. At least one of each always stays.
/// (qml/Main.qml has the same numbers in `limits`.)
pub const MAX_HW: usize = 6;
pub const MAX_VIRT: usize = 8;
pub const MAX_A: usize = 6;
pub const MAX_B: usize = 4;
/// The most strips and buses there can be, for the fixed-size meter tables.
pub const MAX_STRIPS: usize = MAX_HW + MAX_VIRT;
pub const MAX_BUSES: usize = MAX_A + MAX_B;

/// Labels for hardware strips, and for virtual strips (which also name their device), first unused first.
pub const HW_LABELS: [&str; MAX_HW] = ["Mic", "Input 2", "Input 3", "Input 4", "Input 5", "Input 6"];
pub const VIRT_LABELS: [&str; MAX_VIRT] = ["Apps", "Media", "Game", "Chat", "Browser", "Music", "Stream", "Aux"];

/// The PipeWire node.name part for a virtual device: "Apps" -> "apps", "B1" -> "b1".
pub fn slug(label: &str) -> String {
    label.chars().map(|c| if c.is_ascii_alphanumeric() { c.to_ascii_lowercase() } else { '_' }).collect()
}

/// One input: a hardware source, or a virtual device programs play into ("Apps" for
/// everything, "Media" for the programs you pick).
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct Strip {
    pub label: String,
    /// The name shown in the window, if the user gave one. The label stays as it is: it names the virtual device.
    pub name: String,
    /// The app bus is a virtual device we create; it has no source to pick.
    pub virtual_input: bool,
    /// PipeWire node.name of the source, empty for none.
    pub source: String,
    pub gain_db: f32,
    pub mute: bool,
    /// Which outputs this strip feeds, one per bus in the order of `Settings::buses`.
    pub routes: Vec<bool>,
    pub gate_on: bool,
    pub gate_threshold_db: f32,
    pub bass_db: f32,
    pub brightness_db: f32,
    pub pitch_semitones: f32,
    /// The A buses play this strip without the pitch shift (and its ~80 ms delay), so you hear your
    /// natural voice while the B mics still carry the pitched one.
    pub a_hears_dry: bool,
    /// Auto-duck: while this (mic) strip is louder than `duck_threshold_db`, Apps and Media drop by
    /// `duck_db` on the buses ticked below, and come back a moment after you stop talking.
    pub duck_on: bool,
    pub duck_threshold_db: f32,
    pub duck_db: f32,
    /// Duck what the B mics carry / what the A buses play.
    pub duck_b: bool,
    pub duck_a: bool,
    /// Parametric EQ: six cells (see peq.rs), then an output gain in dB.
    pub eq_on: bool,
    pub eq: Vec<Cell>,
    pub eq_gain_db: f32,
    /// The three-band EQ of 0.1.0, read from old saves and turned into the first cells. Never written.
    #[serde(skip_serializing)]
    pub eq_hz: Option<[f32; 3]>,
    #[serde(skip_serializing)]
    pub eq_db: Option<[f32; 3]>,
    /// LV2 plugins, run in order after the EQ and compressor (see plugins.rs).
    pub plugins: Vec<Slot>,
    /// The whole plugin chain is in use (the FX switch on the strip); off bypasses every plugin at once.
    pub fx_on: bool,
    /// Compressor: evens out loud and quiet parts of the voice.
    pub comp_on: bool,
    pub comp_threshold_db: f32,
    pub comp_ratio: f32,
    pub comp_attack_ms: f32,
    pub comp_release_ms: f32,
    pub comp_makeup_db: f32,
    /// Listen-only solo: while any strip is soloed the A buses play only the soloed strips. The B mics
    /// are unaffected. Not saved: Vox always starts with nothing soloed.
    #[serde(skip_serializing)]
    pub solo: bool,
}

impl Default for Strip {
    fn default() -> Self {
        Self {
            label: String::new(),
            name: String::new(),
            virtual_input: false,
            source: String::new(),
            gain_db: 0.0,
            mute: false,
            routes: Vec::new(),
            gate_on: false,
            gate_threshold_db: -45.0,
            bass_db: 0.0,
            brightness_db: 0.0,
            pitch_semitones: 0.0,
            a_hears_dry: false,
            duck_on: false,
            duck_threshold_db: -40.0,
            duck_db: -10.0,
            duck_b: true,
            duck_a: false,
            eq_on: false,
            eq: peq::default_cells(),
            eq_gain_db: 0.0,
            eq_hz: None,
            eq_db: None,
            plugins: Vec::new(),
            fx_on: true,
            comp_on: false,
            comp_threshold_db: -18.0,
            comp_ratio: 3.0,
            comp_attack_ms: 10.0,
            comp_release_ms: 120.0,
            comp_makeup_db: 0.0,
            solo: false,
        }
    }
}

/// One output: A buses play on hardware, B buses are virtual mics other programs record from.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct Bus {
    pub label: String,
    /// The name shown beside the A1/B1 tag, if the user gave one.
    pub name: String,
    pub virtual_output: bool,
    /// PipeWire node.name of the sink for A buses, empty for none.
    pub device: String,
    pub gain_db: f32,
    pub mute: bool,
    /// Brickwall limiter: nothing leaves this output louder than `limiter_db`.
    pub limiter_on: bool,
    pub limiter_db: f32,
    /// Parametric EQ on what this output plays: six cells (see peq.rs), then an output gain in dB.
    pub eq_on: bool,
    pub eq: Vec<Cell>,
    pub eq_gain_db: f32,
    /// LV2 plugins on the mix, before the EQ.
    pub plugins: Vec<Slot>,
    /// The whole plugin chain is in use (the FX switch); off bypasses every plugin at once.
    pub fx_on: bool,
}

impl Default for Bus {
    fn default() -> Self {
        Self {
            label: String::new(),
            name: String::new(),
            virtual_output: false,
            device: String::new(),
            gain_db: 0.0,
            mute: false,
            limiter_on: false,
            limiter_db: -1.0,
            eq_on: false,
            eq: peq::default_cells(),
            eq_gain_db: 0.0,
            plugins: Vec::new(),
            fx_on: true,
        }
    }
}

/// A saved layout: every strip and bus as it was (devices, routes, levels, voice tools). Loading one
/// swaps those in and leaves the look (theme, picture) alone.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Scene {
    pub name: String,
    pub strips: Vec<Strip>,
    pub buses: Vec<Bus>,
}

/// How the window is laid out: which groups of channels are shown, and whether strips are slimmed down.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct Ui {
    pub show_inputs: bool,
    pub show_virtual: bool,
    pub show_outputs: bool,
    /// Strips show only the fader, meter and mute; the rest is in the inspector.
    pub compact: bool,
    /// The inspector panel is open.
    pub inspector: bool,
}

impl Default for Ui {
    fn default() -> Self {
        Self { show_inputs: true, show_virtual: true, show_outputs: true, compact: false, inspector: true }
    }
}

/// Preferences from the Settings page that aren't about the mixer itself.
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct Prefs {
    // Layout
    /// Smaller windows slim the strips down on their own; off keeps full strips and scrolls instead.
    pub fit_detail: bool,
    /// Clicking a strip opens the inspector when it is closed.
    pub inspector_on_select: bool,
    // Appearance
    /// Glass themes ask KWin to blur what is behind the window.
    pub blur: bool,
    /// Use the desktop's accent colour instead of the theme's.
    pub system_accent: bool,
    /// "gradient", "segments" or "solid".
    pub meter_style: String,
    /// A tick stays at the loudest recent level on each meter.
    pub peak_hold: bool,
    pub animations: bool,
    // Behaviour
    /// Start with the computer (an entry in ~/.config/autostart).
    pub autostart: bool,
    /// Start in the tray, without the window.
    pub start_hidden: bool,
    /// Load the last scene used when Vox starts.
    pub restore_scene: bool,
    pub last_scene: String,
    /// Ask before a channel is removed.
    pub confirm_remove: bool,
    // Audio
    /// The rate Vox runs at and asks PipeWire for (44100, 48000 or 96000). Used from the next start.
    pub sample_rate: u32,
    /// "low", "balanced" or "safe": the buffer Vox asks PipeWire for.
    pub latency: String,
    /// Keep the first B mic as the system microphone / the first virtual input as the system output.
    pub default_mic: bool,
    pub default_output: bool,
    /// Mute the B mics while the screen is locked.
    pub lock_mute: bool,
    // Recording
    /// Where recordings go; empty for ~/Music/<app name>.
    pub record_dir: String,
    /// The tray icon gets a red dot while something records.
    pub tray_rec_dot: bool,
}

impl Default for Prefs {
    fn default() -> Self {
        Self {
            fit_detail: true,
            inspector_on_select: true,
            blur: true,
            system_accent: false,
            meter_style: "gradient".into(),
            peak_hold: true,
            animations: true,
            autostart: false,
            start_hidden: false,
            restore_scene: false,
            last_scene: String::new(),
            confirm_remove: true,
            sample_rate: 48_000,
            latency: "balanced".into(),
            default_mic: false,
            default_output: false,
            lock_mute: false,
            record_dir: String::new(),
            tray_rec_dot: true,
        }
    }
}

impl Prefs {
    fn sanitized(mut self) -> Self {
        if !matches!(self.meter_style.as_str(), "gradient" | "segments" | "solid") {
            self.meter_style = "gradient".into();
        }
        if !matches!(self.sample_rate, 44_100 | 48_000 | 96_000) {
            self.sample_rate = 48_000;
        }
        if !matches!(self.latency.as_str(), "low" | "balanced" | "safe") {
            self.latency = "balanced".into();
        }
        self
    }

    /// Frames per PipeWire cycle Vox asks for.
    pub fn quantum(&self) -> u32 {
        let at_48k = match self.latency.as_str() {
            "low" => 128,
            "safe" => 1024,
            _ => 256,
        };
        (at_48k as u64 * self.sample_rate as u64 / 48_000).next_power_of_two() as u32
    }
}

/// The longest name a strip or output can be given.
pub const NAME_LEN: usize = 18;

fn clean_name(name: &str) -> String {
    name.trim().chars().filter(|c| !c.is_control()).take(NAME_LEN).collect()
}

/// The most scenes that can be saved.
pub const MAX_SCENES: usize = 12;

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Settings {
    pub strips: Vec<Strip>,
    pub buses: Vec<Bus>,
    /// Look of the window: an id from qml/Themes.qml ("night", "glass", "light", "gold"). Older ids are mapped there.
    #[serde(default = "default_theme")]
    pub theme: String,
    /// Use `bg_image` as the window background (frosted boxes, accent colours taken from the picture).
    #[serde(default)]
    pub bg_enabled: bool,
    /// file:// URL of the background picture, empty for none.
    #[serde(default)]
    pub bg_image: String,
    #[serde(default)]
    pub scenes: Vec<Scene>,
    /// Push to talk: while on, the mic strips only reach the B mics while the PTT key is held.
    /// (The key itself is kept by the desktop's shortcut service, see shortcuts.rs.)
    #[serde(default)]
    pub ptt_enabled: bool,
    /// What recordings are saved as: "wav" (32-bit float), "flac" (24-bit lossless) or "opus" (128 kbps).
    #[serde(default = "default_format")]
    pub record_format: String,
    /// Look for a newer version once at launch (one request to GitHub).
    #[serde(default = "yes")]
    pub check_updates: bool,
    /// Closing the window leaves Vox running in the tray.
    #[serde(default)]
    pub close_to_tray: bool,
    #[serde(default)]
    pub ui: Ui,
    #[serde(default)]
    pub prefs: Prefs,
}

fn yes() -> bool {
    true
}

fn default_format() -> String {
    "flac".into()
}

fn default_theme() -> String {
    "gold".into()
}

impl Default for Settings {
    fn default() -> Self {
        // Buses: A1-A5, then B1-B3.
        let strip = |label: &str, virtual_input, routes: &[usize]| {
            let mut r = vec![false; 8];
            for &i in routes {
                r[i] = true;
            }
            Strip { label: label.into(), virtual_input, routes: r, ..Strip::default() }
        };
        let bus = |label: &str, virtual_output| Bus { label: label.into(), virtual_output, ..Bus::default() };
        Self {
            strips: vec![
                // Mics go to the first virtual mic by default, apps go to your headphones.
                strip("Mic", false, &[5]),
                strip("Input 2", false, &[]),
                strip("Input 3", false, &[]),
                strip("Apps", true, &[0]),
                strip("Media", true, &[0]),
                strip("Game", true, &[0]),
                strip("Chat", true, &[0]),
                strip("Browser", true, &[0]),
            ],
            buses: ["A1", "A2", "A3", "A4", "A5"]
                .iter()
                .map(|l| bus(l, false))
                .chain(["B1", "B2", "B3"].iter().map(|l| bus(l, true)))
                .collect(),
            theme: default_theme(),
            bg_enabled: false,
            bg_image: String::new(),
            scenes: Vec::new(),
            ptt_enabled: false,
            record_format: default_format(),
            check_updates: true,
            close_to_tray: false,
            ui: Ui::default(),
            prefs: Prefs::default(),
        }
    }
}

impl Settings {
    /// Saved files from older or hand-edited versions may have the wrong shape. Keep between one and the
    /// most of each kind of channel, give every virtual strip and every bus a label of its own (labels name
    /// devices, so they must be unique), and give every strip one route per bus.
    fn sanitized(self) -> Self {
        let defaults = Self::default();
        let mut s = self;

        // Strips: at most so many of each kind, and at least one.
        let (mut hw, mut virt) = (0, 0);
        s.strips.retain(|strip| {
            let count = if strip.virtual_input { &mut virt } else { &mut hw };
            *count += 1;
            *count <= if strip.virtual_input { MAX_VIRT } else { MAX_HW }
        });
        if !s.strips.iter().any(|x| !x.virtual_input) {
            s.strips.insert(0, defaults.strips[0].clone());
        }
        if !s.strips.iter().any(|x| x.virtual_input) {
            s.strips.push(defaults.strips[3].clone());
        }
        let mut used: Vec<String> = Vec::new();
        for i in 0..s.strips.len() {
            let strip = &mut s.strips[i];
            let pool: &[&str] = if strip.virtual_input { &VIRT_LABELS } else { &HW_LABELS };
            let fine = !strip.label.trim().is_empty() && (!strip.virtual_input || pool.contains(&strip.label.as_str()));
            if !fine || used.contains(&strip.label) {
                strip.label = pool.iter().find(|l| !used.iter().any(|u| u == *l)).unwrap_or(&pool[0]).to_string();
            }
            used.push(strip.label.clone());
        }

        // Buses: A1.. play on hardware, B1.. are virtual mics; the number in the label stays with the bus.
        // Each strip's routes line up with the buses, so they are cut and padded together.
        let width = s.buses.len();
        for strip in s.strips.iter_mut() {
            strip.routes.resize(width, false);
        }
        let (mut a, mut b) = (0, 0);
        let keep: Vec<bool> = s
            .buses
            .iter()
            .map(|bus| {
                let count = if bus.virtual_output { &mut b } else { &mut a };
                *count += 1;
                *count <= if bus.virtual_output { MAX_B } else { MAX_A }
            })
            .collect();
        let mut kept = keep.iter();
        s.buses.retain(|_| *kept.next().unwrap());
        for strip in s.strips.iter_mut() {
            let mut kept = keep.iter();
            strip.routes.retain(|_| *kept.next().unwrap());
        }
        if a == 0 {
            s.buses.insert(0, defaults.buses[0].clone());
            s.strips.iter_mut().for_each(|x| x.routes.insert(0, false));
        }
        if b == 0 {
            s.buses.push(defaults.buses[5].clone());
            s.strips.iter_mut().for_each(|x| x.routes.push(false));
        }
        let mut used: Vec<String> = Vec::new();
        for bus in s.buses.iter_mut() {
            let letter = if bus.virtual_output { 'B' } else { 'A' };
            let max = if bus.virtual_output { MAX_B } else { MAX_A };
            let number = bus.label.strip_prefix(letter).and_then(|n| n.parse::<usize>().ok());
            if !number.is_some_and(|n| (1..=max).contains(&n)) || used.contains(&bus.label) {
                let free = (1..=max).map(|n| format!("{letter}{n}")).find(|l| !used.contains(l));
                bus.label = free.unwrap_or_else(|| format!("{letter}1"));
            }
            used.push(bus.label.clone());
        }

        for strip in s.strips.iter_mut() {
            strip.name = clean_name(&strip.name);
            strip.gain_db = strip.gain_db.clamp(-60.0, 12.0);
            strip.gate_threshold_db = strip.gate_threshold_db.clamp(-80.0, 0.0);
            strip.bass_db = strip.bass_db.clamp(-12.0, 12.0);
            strip.brightness_db = strip.brightness_db.clamp(-12.0, 12.0);
            strip.pitch_semitones = strip.pitch_semitones.clamp(-12.0, 12.0);
            strip.duck_threshold_db = strip.duck_threshold_db.clamp(-80.0, -6.0);
            strip.duck_db = strip.duck_db.clamp(-30.0, 0.0);
            // A save from 0.1.0 has three bells instead of cells: carry them over as cells 2, 3 and 5.
            if let (Some(hz), Some(db)) = (strip.eq_hz.take(), strip.eq_db.take()) {
                if strip.eq == peq::default_cells() {
                    for (band, cell) in [1usize, 2, 4].into_iter().enumerate() {
                        strip.eq[cell] = Cell { on: true, kind: "peak".into(), hz: hz[band], db: db[band], q: 1.0 };
                    }
                }
            }
            peq::sanitize(&mut strip.eq);
            strip.eq_gain_db = peq::sanitize_gain(strip.eq_gain_db);
            plugins::sanitize(&mut strip.plugins);
            strip.comp_threshold_db = strip.comp_threshold_db.clamp(-60.0, 0.0);
            strip.comp_ratio = strip.comp_ratio.clamp(1.0, 20.0);
            strip.comp_attack_ms = strip.comp_attack_ms.clamp(0.5, 200.0);
            strip.comp_release_ms = strip.comp_release_ms.clamp(10.0, 1000.0);
            strip.comp_makeup_db = strip.comp_makeup_db.clamp(0.0, 24.0);
        }
        for bus in s.buses.iter_mut() {
            bus.name = clean_name(&bus.name);
            bus.gain_db = bus.gain_db.clamp(-60.0, 12.0);
            bus.limiter_db = bus.limiter_db.clamp(-24.0, 0.0);
            peq::sanitize(&mut bus.eq);
            bus.eq_gain_db = peq::sanitize_gain(bus.eq_gain_db);
            plugins::sanitize(&mut bus.plugins);
        }
        if !matches!(s.record_format.as_str(), "wav" | "flac" | "opus") {
            s.record_format = default_format();
        }
        s.prefs = s.prefs.sanitized();
        s.scenes.truncate(MAX_SCENES);
        for scene in s.scenes.iter_mut() {
            for strip in scene.strips.iter_mut() {
                peq::sanitize(&mut strip.eq);
                strip.eq_gain_db = peq::sanitize_gain(strip.eq_gain_db);
                plugins::sanitize(&mut strip.plugins);
            }
            for bus in scene.buses.iter_mut() {
                peq::sanitize(&mut bus.eq);
                bus.eq_gain_db = peq::sanitize_gain(bus.eq_gain_db);
                plugins::sanitize(&mut bus.plugins);
            }
        }
        s
    }

    pub fn from_json(json: &str) -> Option<Self> {
        serde_json::from_str::<Self>(json).map_err(|e| eprintln!("vox-pro: settings: {e}")).ok().map(Self::sanitized)
    }

    pub fn to_json(&self) -> String {
        serde_json::to_string(self).unwrap_or_default()
    }
}

fn path() -> Option<PathBuf> {
    let base = std::env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".config")))?;
    Some(base.join("vox-pro").join("settings.json"))
}

fn read(path: &std::path::Path) -> Option<Settings> {
    std::fs::read_to_string(path).ok().and_then(|json| Settings::from_json(&json))
}

/// Load the saved layout. A good file is also copied to settings.json.bak; if the file is
/// unreadable (say a crash cut a write short) the backup is used and the broken file is kept
/// as settings.json.broken instead of being silently overwritten with defaults.
pub fn load() -> Settings {
    let Some(p) = path() else { return Settings::default() };
    let bak = p.with_extension("json.bak");
    if let Some(settings) = read(&p) {
        let _ = std::fs::copy(&p, &bak);
        return settings;
    }
    if p.exists() {
        eprintln!("vox-pro: settings.json could not be read; keeping it as settings.json.broken");
        let _ = std::fs::rename(&p, p.with_extension("json.broken"));
    }
    read(&bak).unwrap_or_default()
}

/// Write to a temporary file and rename it into place, so a crash can't leave half a file.
pub fn save(settings: &Settings) {
    let Some(p) = path() else { return };
    if let Some(dir) = p.parent() {
        let _ = std::fs::create_dir_all(dir);
    }
    let Ok(json) = serde_json::to_string_pretty(settings) else { return };
    let tmp = p.with_extension("json.tmp");
    if std::fs::write(&tmp, json).is_ok() {
        let _ = std::fs::rename(&tmp, &p);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn saves_from_0_2_keep_their_values_and_their_layout() {
        // 0.2 saved all eight strips and buses with fixed eight-wide routes.
        let mut old = Settings::default();
        old.strips[0].source = "quadcast".into();
        old.strips[0].gain_db = -6.0;
        old.buses[6].limiter_on = true;
        let mut value: serde_json::Value = serde_json::from_str(&old.to_json().replace(r#""name":"","#, "")).unwrap();
        value.as_object_mut().unwrap().remove("ui");
        value.as_object_mut().unwrap().remove("prefs");
        let json = value.to_string();
        assert!(!json.contains("\"ui\""));
        let s = Settings::from_json(&json).expect("0.2 save loads");
        assert_eq!((s.strips.len(), s.buses.len()), (8, 8));
        assert_eq!((s.strips[0].source.as_str(), s.strips[0].gain_db), ("quadcast", -6.0));
        assert_eq!(s.strips[0].routes, old.strips[0].routes);
        assert_eq!((s.buses[6].label.as_str(), s.buses[6].limiter_on), ("B2", true));
        assert_eq!(s.ui, Ui::default());
    }

    #[test]
    fn at_least_one_of_each_stays_and_labels_are_unique() {
        let odd = r#"{"strips":[{"label":"Mic","routes":[true,true]},{"label":"Mic"}],"buses":[{"label":"A1"},{"label":"A1"}]}"#;
        let s = Settings::from_json(odd).expect("loads");
        assert_eq!(s.strips.iter().map(|x| x.label.as_str()).collect::<Vec<_>>(), ["Mic", "Input 2", "Apps"]);
        assert_eq!(s.buses.iter().map(|x| x.label.as_str()).collect::<Vec<_>>(), ["A1", "A2", "B1"]);
        assert_eq!(s.strips[0].routes, vec![true, true, false]);
        assert!(s.strips.iter().all(|x| x.routes.len() == 3));
    }

    #[test]
    fn a_removed_bus_takes_its_routes_with_it_and_numbers_stay() {
        let s = Settings::from_json(r#"{"strips":[{"label":"Mic","routes":[false,true]},{"label":"Apps","virtual_input":true}],
            "buses":[{"label":"A1"},{"label":"B2","virtual_output":true}]}"#).expect("loads");
        assert_eq!(s.buses[1].label, "B2");
        assert_eq!(s.strips[0].routes, vec![false, true]);
    }

    #[test]
    fn too_many_channels_are_cut_to_the_limit() {
        let strips: Vec<String> = (0..11).map(|_| r#"{"label":"x","virtual_input":true}"#.to_string()).collect();
        let s = Settings::from_json(&format!(r#"{{"strips":[{}],"buses":[]}}"#, strips.join(","))).expect("loads");
        assert_eq!(s.strips.iter().filter(|x| x.virtual_input).count(), MAX_VIRT);
        assert_eq!(s.strips.iter().filter(|x| x.virtual_input).map(|x| x.label.as_str()).collect::<Vec<_>>(), VIRT_LABELS);
    }

    #[test]
    fn names_are_trimmed() {
        let s = Settings::from_json(r#"{"strips":[{"label":"Mic","name":"  A very long name for a microphone  "}],"buses":[{"label":"A1","name":"Headphones"}]}"#).expect("loads");
        assert_eq!(s.strips[0].name, "A very long name f");
        assert_eq!((s.buses[0].name.as_str(), s.buses[0].label.as_str()), ("Headphones", "A1"));
    }

    #[test]
    fn the_three_band_eq_of_old_saves_becomes_cells() {
        let old = r#"{"strips":[{"label":"Mic","eq_on":true,"eq_hz":[300.0,1200.0,4000.0],"eq_db":[-2.0,0.0,3.0]}],"buses":[]}"#;
        let s = Settings::from_json(old).expect("old save loads");
        let eq = &s.strips[0].eq;
        assert_eq!(eq.len(), peq::CELLS);
        assert_eq!((eq[1].hz, eq[1].db, eq[4].hz, eq[4].db), (300.0, -2.0, 4000.0, 3.0));
        assert!(!s.to_json().contains("eq_hz"));
    }

    #[test]
    fn a_save_with_the_wrong_bus_count_keeps_its_theme() {
        let odd = r#"{"strips":[],"buses":[{"label":"A1","gain_db":-3.0}],"theme":"pureblack","bg_enabled":true}"#;
        let s = Settings::from_json(odd).expect("odd save loads");
        assert_eq!((s.theme.as_str(), s.bg_enabled, s.buses.len()), ("pureblack", true, 2));
        assert_eq!(s.buses[0].gain_db, -3.0);
    }
}
