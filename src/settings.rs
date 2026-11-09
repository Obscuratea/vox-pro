//! The mixer layout the user builds, saved as JSON in ~/.config/vox-pro/settings.json.
//! The UI owns the settings and sends a full copy to the engine on every change.

use serde::{Deserialize, Serialize};
use std::path::PathBuf;

pub const STRIPS: usize = 8;
pub const BUSES: usize = 8;
/// The first this-many buses are hardware outputs (A1-A5); the rest are virtual mics (B1-B3).
pub const A_BUSES: usize = 5;

/// One input: a hardware source, or a virtual device programs play into ("Apps" for
/// everything, "Media" for the programs you pick).
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct Strip {
    pub label: String,
    /// The app bus is a virtual device we create; it has no source to pick.
    pub virtual_input: bool,
    /// PipeWire node.name of the source, empty for none.
    pub source: String,
    pub gain_db: f32,
    pub mute: bool,
    /// Which outputs this strip feeds, in bus order: A1-A5, B1-B3.
    pub routes: [bool; BUSES],
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
    /// Three-band EQ (bell filters): frequency and gain of the low, mid and high bands.
    pub eq_on: bool,
    pub eq_hz: [f32; 3],
    pub eq_db: [f32; 3],
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
            virtual_input: false,
            source: String::new(),
            gain_db: 0.0,
            mute: false,
            routes: [false; BUSES],
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
            eq_hz: [250.0, 1000.0, 3500.0],
            eq_db: [0.0; 3],
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
    pub virtual_output: bool,
    /// PipeWire node.name of the sink for A buses, empty for none.
    pub device: String,
    pub gain_db: f32,
    pub mute: bool,
    /// Brickwall limiter: nothing leaves this output louder than `limiter_db`.
    pub limiter_on: bool,
    pub limiter_db: f32,
}

impl Default for Bus {
    fn default() -> Self {
        Self {
            label: String::new(),
            virtual_output: false,
            device: String::new(),
            gain_db: 0.0,
            mute: false,
            limiter_on: false,
            limiter_db: -1.0,
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

/// The most scenes that can be saved.
pub const MAX_SCENES: usize = 12;

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Settings {
    pub strips: Vec<Strip>,
    pub buses: Vec<Bus>,
    /// Look of the window: "default" is the Vox look, "system" follows Plasma, anything else is an id from qml/Themes.qml.
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
    /// What recordings are saved as: "wav" (32-bit float), "flac" (24-bit lossless) or "mp3" (192 kbps).
    #[serde(default = "default_format")]
    pub record_format: String,
    /// Closing the window leaves Vox running in the tray.
    #[serde(default)]
    pub close_to_tray: bool,
}

fn default_format() -> String {
    "flac".into()
}

fn default_theme() -> String {
    "pro".into()
}

impl Default for Settings {
    fn default() -> Self {
        let strip = |label: &str, virtual_input, routes: &[usize]| {
            let mut r = [false; BUSES];
            for &i in routes {
                r[i] = true;
            }
            Strip { label: label.into(), virtual_input, routes: r, ..Strip::default() }
        };
        let bus = |label: &str, virtual_output| Bus { label: label.into(), virtual_output, ..Bus::default() };
        Self {
            strips: vec![
                // Mics go to the first virtual mic by default, apps go to your headphones.
                strip("Mic", false, &[A_BUSES]),
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
            close_to_tray: false,
        }
    }
}

impl Settings {
    /// Saved files from older or hand-edited versions may have the wrong shape; fall back
    /// to defaults for anything that doesn't match the fixed strip and bus layout.
    fn sanitized(self) -> Self {
        let defaults = Self::default();
        let mut s = self;
        // Saves from before a strip or bus existed are shorter; new ones start from their defaults.
        // Anything beyond the fixed layout is dropped, but the rest of the save (theme, picture) is kept.
        s.strips.truncate(STRIPS);
        s.buses.truncate(BUSES);
        s.strips.extend(defaults.strips[s.strips.len()..].iter().cloned());
        s.buses.extend(defaults.buses[s.buses.len()..].iter().cloned());
        for (strip, d) in s.strips.iter_mut().zip(&defaults.strips) {
            strip.virtual_input = d.virtual_input;
            if d.virtual_input {
                // The label names the virtual device, so it can't change.
                strip.label = d.label.clone();
            }
            strip.gain_db = strip.gain_db.clamp(-60.0, 12.0);
            strip.gate_threshold_db = strip.gate_threshold_db.clamp(-80.0, 0.0);
            strip.bass_db = strip.bass_db.clamp(-12.0, 12.0);
            strip.brightness_db = strip.brightness_db.clamp(-12.0, 12.0);
            strip.pitch_semitones = strip.pitch_semitones.clamp(-12.0, 12.0);
            strip.duck_threshold_db = strip.duck_threshold_db.clamp(-80.0, -6.0);
            strip.duck_db = strip.duck_db.clamp(-30.0, 0.0);
            for i in 0..3 {
                strip.eq_hz[i] = strip.eq_hz[i].clamp(40.0, 12_000.0);
                strip.eq_db[i] = strip.eq_db[i].clamp(-12.0, 12.0);
            }
            strip.comp_threshold_db = strip.comp_threshold_db.clamp(-60.0, 0.0);
            strip.comp_ratio = strip.comp_ratio.clamp(1.0, 20.0);
            strip.comp_attack_ms = strip.comp_attack_ms.clamp(0.5, 200.0);
            strip.comp_release_ms = strip.comp_release_ms.clamp(10.0, 1000.0);
            strip.comp_makeup_db = strip.comp_makeup_db.clamp(0.0, 24.0);
        }
        for (bus, d) in s.buses.iter_mut().zip(&defaults.buses) {
            bus.virtual_output = d.virtual_output;
            bus.label = d.label.clone();
            bus.gain_db = bus.gain_db.clamp(-60.0, 12.0);
            bus.limiter_db = bus.limiter_db.clamp(-24.0, 0.0);
        }
        if !matches!(s.record_format.as_str(), "wav" | "flac" | "mp3") {
            s.record_format = default_format();
        }
        s.scenes.truncate(MAX_SCENES);
        s
    }

    pub fn from_json(json: &str) -> Option<Self> {
        serde_json::from_str::<Self>(json).ok().map(Self::sanitized)
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
    fn older_saves_gain_the_media_strip_and_keep_their_values() {
        let old = r#"{"strips":[{"label":"Mic","source":"quadcast","gain_db":-6.0},{"label":"Input 2"},{"label":"Apps"}],
                      "buses":[{"label":"A1"},{"label":"A2"},{"label":"A3"},{"label":"B1"},{"label":"B2"}]}"#;
        let s = Settings::from_json(old).expect("old save loads");
        assert_eq!(s.strips.len(), STRIPS);
        assert_eq!((s.strips[0].source.as_str(), s.strips[0].gain_db), ("quadcast", -6.0));
        assert_eq!(s.strips[3], Settings::default().strips[3]);
    }

    #[test]
    fn a_save_with_the_wrong_bus_count_keeps_its_theme() {
        let odd = r#"{"strips":[],"buses":[{"label":"A1","gain_db":-3.0}],"theme":"pureblack","bg_enabled":true}"#;
        let s = Settings::from_json(odd).expect("odd save loads");
        assert_eq!((s.theme.as_str(), s.bg_enabled, s.buses.len()), ("pureblack", true, BUSES));
        assert_eq!(s.buses[0].gain_db, -3.0);
    }
}
