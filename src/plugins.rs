//! LV2 plugin hosting. A strip or an output can carry a short chain of plugins (reverb, de-esser, noise
//! suppression, anything installed in /usr/lib/lv2 or ~/.lv2 that takes mono or stereo audio in and out).
//!
//! The plugin world lives on its own thread ("vox-plugins"): it scans what is installed, builds plugin
//! instances when a chain changes, runs the plugins' background work, and frees old instances. The audio
//! thread only ever runs finished chains, so loading a plugin never stalls the sound.
//!
//! Plugins are other people's code running inside Vox. If one crashes while it loads, the next start
//! comes up with plugins switched off (see `safe_mode`) instead of crashing again.

use crate::dsp::SAMPLE_RATE;
use livi::event::LV2AtomSequence;
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, HashMap};
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::mpsc::{self, RecvTimeoutError};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::{Duration, Instant};

/// The most plugins one strip or output can carry.
pub const MAX_SLOTS: usize = 6;
/// The biggest PipeWire cycle we hand to a plugin in one go; longer ones are cut into pieces.
const MAX_BLOCK: usize = 8192;

/// One plugin in a chain, as it is saved.
#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct Slot {
    pub uri: String,
    /// The plugin's name when it was added, shown even if the plugin is no longer installed.
    pub name: String,
    pub on: bool,
    /// Control values by port symbol. Ports not listed keep the plugin's defaults.
    pub params: BTreeMap<String, f32>,
}

pub fn sanitize(slots: &mut Vec<Slot>) {
    slots.retain(|s| !s.uri.is_empty());
    slots.truncate(MAX_SLOTS);
    for slot in slots.iter_mut() {
        slot.params.retain(|_, v| v.is_finite());
    }
}

/// Where a chain sits.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Target {
    Strip(usize),
    Bus(usize),
}

/// One loaded plugin: a stereo instance, or two mono instances side by side.
struct Unit {
    uri: String,
    on: bool,
    instances: Vec<livi::Instance>,
    stereo: bool,
    symbols: HashMap<String, livi::PortIndex>,
    /// What each control was last set to, so unchanged values aren't sent again.
    sent: HashMap<String, f32>,
    /// Event buffers the plugins expect to be connected (they stay empty; we send no MIDI).
    seq_in: Vec<Vec<LV2AtomSequence>>,
    seq_out: Vec<Vec<LV2AtomSequence>>,
}

/// The loaded plugins of one strip or output, run in order on the audio thread.
#[derive(Default)]
pub struct Chain {
    units: Vec<Unit>,
    l: Vec<f32>,
    r: Vec<f32>,
    out_l: Vec<f32>,
    out_r: Vec<f32>,
}

impl Chain {
    /// Whether this chain was built for exactly these plugins, in this order.
    pub fn matches(&self, slots: &[Slot]) -> bool {
        self.units.len() == slots.len() && self.units.iter().zip(slots).all(|(u, s)| u.uri == s.uri)
    }

    pub fn is_empty(&self) -> bool {
        self.units.is_empty()
    }

    /// Take over the on/off switches and control values from the settings. A plugin that failed to load stays off.
    pub fn apply(&mut self, slots: &[Slot]) {
        for (unit, slot) in self.units.iter_mut().zip(slots) {
            unit.on = slot.on && !unit.instances.is_empty();
            for (symbol, &value) in &slot.params {
                if unit.sent.get(symbol) == Some(&value) {
                    continue;
                }
                if let Some(&port) = unit.symbols.get(symbol) {
                    for instance in unit.instances.iter_mut() {
                        instance.set_control_input(port, value);
                    }
                    unit.sent.insert(symbol.clone(), value);
                }
            }
        }
    }

    /// Run the chain over one cycle of interleaved stereo, in place.
    pub fn process(&mut self, frames: &mut [[f32; 2]]) {
        if !self.units.iter().any(|u| u.on) {
            return;
        }
        for piece in frames.chunks_mut(MAX_BLOCK) {
            let n = piece.len();
            for (i, f) in piece.iter().enumerate() {
                self.l[i] = f[0];
                self.r[i] = f[1];
            }
            for unit in self.units.iter_mut().filter(|u| u.on) {
                let ok = unit.run(n, &self.l, &self.r, &mut self.out_l, &mut self.out_r);
                // A plugin that fails, or puts out something that isn't a number, is passed over for this cycle.
                if ok && self.out_l[..n].iter().chain(&self.out_r[..n]).all(|x| x.is_finite()) {
                    std::mem::swap(&mut self.l, &mut self.out_l);
                    std::mem::swap(&mut self.r, &mut self.out_r);
                }
            }
            for (i, f) in piece.iter_mut().enumerate() {
                *f = [self.l[i], self.r[i]];
            }
        }
    }
}

impl Unit {
    fn run(&mut self, n: usize, l: &[f32], r: &[f32], out_l: &mut [f32], out_r: &mut [f32]) -> bool {
        for seqs in self.seq_out.iter_mut() {
            seqs.iter_mut().for_each(|s| s.clear_as_chunk());
        }
        let mut ok = true;
        if self.stereo {
            let ports = livi::EmptyPortConnections::new()
                .with_audio_inputs([&l[..n], &r[..n]].into_iter())
                .with_audio_outputs([&mut out_l[..n], &mut out_r[..n]].into_iter())
                .with_atom_sequence_inputs(self.seq_in[0].iter())
                .with_atom_sequence_outputs(self.seq_out[0].iter_mut());
            ok &= unsafe { self.instances[0].run(n, ports) }.is_ok();
        } else {
            for (i, (input, output)) in [(&l[..n], &mut out_l[..n]), (&r[..n], &mut out_r[..n])].into_iter().enumerate() {
                let ports = livi::EmptyPortConnections::new()
                    .with_audio_inputs(std::iter::once(input))
                    .with_audio_outputs(std::iter::once(output))
                    .with_atom_sequence_inputs(self.seq_in[i].iter())
                    .with_atom_sequence_outputs(self.seq_out[i].iter_mut());
                ok &= unsafe { self.instances[i].run(n, ports) }.is_ok();
            }
        }
        ok
    }
}

/// Called on the plugin thread with a finished chain; hands it to the audio thread.
type Deliver = Box<dyn FnOnce(Chain) + Send>;

enum Request {
    Scan,
    Info(String, mpsc::Sender<String>),
    Build(Vec<Slot>, Deliver),
    Drop(Chain),
}

pub struct Host {
    tx: Mutex<mpsc::Sender<Request>>,
    /// The list of usable plugins as JSON, "" until the first scan is done.
    catalog: Arc<Mutex<String>>,
    /// Plugins are switched off because one crashed Vox while loading last time.
    safe: Arc<AtomicBool>,
}

static HOST: OnceLock<Host> = OnceLock::new();

pub fn host() -> &'static Host {
    HOST.get_or_init(|| {
        let (tx, rx) = mpsc::channel();
        let catalog = Arc::new(Mutex::new(String::new()));
        let safe = Arc::new(AtomicBool::new(marker().is_some_and(|m| m.exists())));
        let thread_catalog = catalog.clone();
        std::thread::Builder::new()
            .name("vox-plugins".into())
            .spawn(move || serve(rx, thread_catalog))
            .expect("failed to start the plugin thread");
        Host { tx: Mutex::new(tx), catalog, safe }
    })
}

impl Host {
    fn send(&self, request: Request) {
        let _ = self.tx.lock().unwrap().send(request);
    }

    /// JSON list of the plugins that can be used, or "" while the first scan is still running.
    pub fn catalog(&self) -> String {
        let catalog = self.catalog.lock().unwrap().clone();
        if catalog.is_empty() {
            self.send(Request::Scan);
        }
        catalog
    }

    /// JSON description of one plugin's controls ("" if it isn't installed). Waits for the answer.
    pub fn info(&self, uri: &str) -> String {
        let (tx, rx) = mpsc::channel();
        self.send(Request::Info(uri.to_string(), tx));
        rx.recv_timeout(Duration::from_secs(8)).unwrap_or_default()
    }

    /// Load these plugins and hand the finished chain to `deliver` (on the plugin thread).
    pub fn build(&self, slots: Vec<Slot>, deliver: Deliver) {
        self.send(Request::Build(slots, deliver));
    }

    /// Free a chain that is no longer used, away from the audio thread.
    pub fn discard(&self, chain: Chain) {
        if !chain.is_empty() {
            self.send(Request::Drop(chain));
        }
    }

    pub fn safe_mode(&self) -> bool {
        self.safe.load(Ordering::Relaxed)
    }

    /// The user asked for plugins to be loaded again after a crash.
    pub fn leave_safe_mode(&self) {
        if let Some(m) = marker() {
            let _ = std::fs::remove_file(m);
        }
        self.safe.store(false, Ordering::Relaxed);
    }
}

/// A file that exists while plugins are being loaded. Finding it at start means the last load crashed.
fn marker() -> Option<PathBuf> {
    let base = std::env::var_os("XDG_CACHE_HOME")
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".cache")))?;
    Some(base.join("vox-pro").join("plugins-loading"))
}

/// How long a freshly loaded chain has to run before the load counts as survived.
const SETTLE: Duration = Duration::from_secs(4);

struct World {
    world: livi::World,
    features: Arc<livi::Features>,
}

impl World {
    fn load() -> Option<Self> {
        let world = livi::World::new();
        let features = world
            .try_build_features(livi::FeaturesBuilder { min_block_length: 1, max_block_length: MAX_BLOCK })
            .ok()?;
        Some(Self { world, features })
    }

    /// Plugins we can run: mono or stereo effects (no instruments, no analysers, no CV ports).
    fn usable(plugin: &livi::Plugin) -> Option<bool> {
        let c = plugin.port_counts();
        let stereo = c.audio_inputs == 2 && c.audio_outputs == 2;
        let mono = c.audio_inputs == 1 && c.audio_outputs == 1;
        let skipped = plugin.classes().any(|class| {
            matches!(class, "Instrument Plugin" | "Analyser Plugin" | "Generator Plugin" | "Oscillator Plugin" | "MIDI Plugin")
        });
        ((stereo || mono) && c.cv_inputs == 0 && c.cv_outputs == 0 && !skipped).then_some(stereo)
    }

    fn catalog(&self) -> String {
        let mut list: Vec<serde_json::Value> = self
            .world
            .iter_plugins()
            .filter_map(|p| {
                let stereo = Self::usable(&p)?;
                let category = p.classes().next().unwrap_or("Plugin").trim_end_matches(" Plugin").to_string();
                let author = p.raw().author_name().and_then(|n| n.as_str().map(str::to_string)).unwrap_or_default();
                Some(serde_json::json!({
                    "uri": p.uri(), "name": p.name(), "author": author,
                    "category": if category == "Plugin" { "Other".to_string() } else { category },
                    "stereo": stereo,
                }))
            })
            .collect();
        list.sort_by_key(|p| p["name"].as_str().unwrap_or_default().to_lowercase());
        serde_json::Value::Array(list).to_string()
    }

    fn info(&self, uri: &str) -> String {
        let Some(plugin) = self.world.plugin_by_uri(uri) else { return String::new() };
        let w = self.world.raw();
        let core = |name: &str| w.new_uri(&format!("http://lv2plug.in/ns/lv2core#{name}"));
        let props = |name: &str| w.new_uri(&format!("http://lv2plug.in/ns/ext/port-props#{name}"));
        let units = |name: &str| w.new_uri(&format!("http://lv2plug.in/ns/extensions/units#{name}"));
        let (toggled, integer, enumeration) = (core("toggled"), core("integer"), core("enumeration"));
        let (logarithmic, hidden) = (props("logarithmic"), props("notOnGUI"));
        let (unit, unit_symbol) = (units("unit"), units("symbol"));
        let mut params = Vec::new();
        for port in plugin.ports_with_type(livi::PortType::ControlInput) {
            let Some(raw) = plugin.raw().port_by_index(port.index.0) else { continue };
            if raw.has_property(&hidden) {
                continue;
            }
            let number = |n: lilv::node::Node| n.as_float().or_else(|| n.as_int().map(|i| i as f32));
            let mut options: Vec<(f32, String)> = raw
                .scale_points()
                .iter()
                .filter_map(|p| Some((number(p.value())?, p.label().as_str()?.to_string())))
                .collect();
            options.sort_by(|a, b| a.0.total_cmp(&b.0));
            let toggle = raw.has_property(&toggled);
            let pick = raw.has_property(&enumeration) && options.len() >= 2;
            let min = port.min_value.filter(|v| v.is_finite()).unwrap_or(0.0);
            let max = port.max_value.filter(|v| v.is_finite()).unwrap_or(1.0).max(min);
            // "db", "hz", "ms"... for the standard units, or the plugin's own symbol (LSP's "G" for a gain factor).
            let unit_name = raw.get(&unit).and_then(|node| match node.as_uri() {
                Some(uri) => uri.rsplit('#').next().map(str::to_string),
                None => w.find_nodes(Some(&node), &unit_symbol, None).iter().next().and_then(|s| s.as_str().map(str::to_string)),
            });
            params.push(serde_json::json!({
                "symbol": port.symbol, "name": port.name,
                "min": min, "max": max, "def": port.default_value.clamp(min, max),
                "kind": if toggle { "toggle" } else if pick { "pick" } else if raw.has_property(&integer) { "int" } else { "float" },
                "log": raw.has_property(&logarithmic),
                "unit": unit_name.unwrap_or_default(),
                "options": options.iter().map(|(v, l)| serde_json::json!({ "value": v, "label": l })).collect::<Vec<_>>(),
            }));
        }
        serde_json::json!({ "uri": uri, "name": plugin.name(), "stereo": Self::usable(&plugin).unwrap_or(true), "params": params }).to_string()
    }

    fn build(&self, slots: &[Slot]) -> Chain {
        let mut chain = Chain {
            units: Vec::new(),
            l: vec![0.0; MAX_BLOCK],
            r: vec![0.0; MAX_BLOCK],
            out_l: vec![0.0; MAX_BLOCK],
            out_r: vec![0.0; MAX_BLOCK],
        };
        for slot in slots {
            // A plugin that isn't installed (any more) leaves an empty unit, so the chain still lines up with its slots.
            let mut unit = Unit {
                uri: slot.uri.clone(),
                on: false,
                instances: Vec::new(),
                stereo: true,
                symbols: HashMap::new(),
                sent: HashMap::new(),
                seq_in: Vec::new(),
                seq_out: Vec::new(),
            };
            if let Some((plugin, stereo)) = self.world.plugin_by_uri(&slot.uri).and_then(|p| Some((Self::usable(&p)?, p)).map(|(s, p)| (p, s))) {
                let counts = *plugin.port_counts();
                for _ in 0..if stereo { 1 } else { 2 } {
                    match unsafe { plugin.instantiate(self.features.clone(), SAMPLE_RATE as f64) } {
                        Ok(instance) => {
                            unit.instances.push(instance);
                            let seqs = |n: usize| (0..n).map(|_| LV2AtomSequence::new(&self.features, 32_768)).collect::<Vec<_>>();
                            unit.seq_in.push(seqs(counts.atom_sequence_inputs));
                            unit.seq_out.push(seqs(counts.atom_sequence_outputs));
                        }
                        Err(e) => eprintln!("vox-pro: could not load plugin {}: {e}", slot.uri),
                    }
                }
                unit.stereo = stereo;
                if unit.instances.len() != if stereo { 1 } else { 2 } {
                    unit.instances.clear();
                }
                unit.symbols = plugin.ports_with_type(livi::PortType::ControlInput).map(|p| (p.symbol, p.index)).collect();
            }
            chain.units.push(unit);
        }
        chain.apply(slots);
        chain
    }
}

fn serve(rx: mpsc::Receiver<Request>, catalog: Arc<Mutex<String>>) {
    let mut world: Option<World> = None;
    // When the last chain was built, while its marker file is still there.
    let mut loading: Option<Instant> = None;
    loop {
        let request = match rx.recv_timeout(Duration::from_millis(40)) {
            Ok(request) => Some(request),
            Err(RecvTimeoutError::Timeout) => None,
            Err(RecvTimeoutError::Disconnected) => return,
        };
        if request.is_some() && world.is_none() && !matches!(request, Some(Request::Drop(_))) {
            world = World::load();
            if let Some(w) = &world {
                *catalog.lock().unwrap() = w.catalog();
            }
        }
        match (request, &world) {
            (Some(Request::Info(uri, reply)), Some(w)) => {
                let _ = reply.send(w.info(&uri));
            }
            (Some(Request::Build(slots, deliver)), Some(w)) => {
                if !slots.is_empty() {
                    if let Some(m) = marker() {
                        let _ = m.parent().map(std::fs::create_dir_all);
                        let uris: Vec<&str> = slots.iter().map(|s| s.uri.as_str()).collect();
                        let _ = std::fs::write(m, uris.join("\n"));
                    }
                    loading = Some(Instant::now());
                }
                deliver(w.build(&slots));
            }
            (Some(Request::Drop(chain)), _) => drop(chain),
            _ => {}
        }
        if let Some(w) = &world {
            w.features.worker_manager().run_workers();
        }
        if loading.is_some_and(|since| since.elapsed() > SETTLE) {
            if let Some(m) = marker() {
                let _ = std::fs::remove_file(m);
            }
            loading = None;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn slot(uri: &str) -> Slot {
        Slot { uri: uri.into(), name: String::new(), on: true, params: BTreeMap::new() }
    }

    /// Needs the Calf plugins (calf package). Run with `cargo test -- --ignored plugins`.
    #[test]
    #[ignore]
    fn a_real_plugin_loads_runs_and_obeys_its_controls() {
        let world = World::load().expect("lilv world");
        assert!(world.catalog().contains("calf"));
        let uri = "http://calf.sourceforge.net/plugins/Reverb";
        assert!(world.info(uri).contains("decay_time"));
        let tone = |n: usize| -> Vec<[f32; 2]> { (0..n).map(|i| [(i as f32 * 0.05).sin() * 0.5; 2]).collect() };
        let energy = |frames: &[[f32; 2]]| frames.iter().map(|f| f[0] * f[0]).sum::<f32>();

        // Dry muted, so only the reverb comes out: clearly different from the input.
        let mut wet = slot(uri);
        wet.params.insert("dry".into(), 0.0);
        wet.params.insert("amount".into(), 1.0);
        let mut chain = world.build(&[wet.clone()]);
        assert!(chain.matches(&[wet.clone()]));
        let mut block = tone(4800);
        for piece in block.chunks_mut(256) {
            chain.process(piece);
        }
        assert!(block.iter().all(|f| f[0].is_finite()));
        let input = tone(4800);
        let difference: f32 = block.iter().zip(&input).map(|(a, b)| (a[0] - b[0]).powi(2)).sum();
        assert!(difference > 0.05 * energy(&input), "the reverb changed the sound");

        // Switched off, the chain passes audio through untouched.
        wet.on = false;
        chain.apply(&[wet]);
        let mut block = tone(256);
        chain.process(&mut block);
        assert_eq!(block, tone(256));
    }

    /// Writes the plugin list and one plugin's controls where the preview harness reads them (VOX_PLUGIN_DUMP=dir).
    #[test]
    #[ignore]
    fn dump_for_the_preview_harness() {
        let Some(dir) = std::env::var_os("VOX_PLUGIN_DUMP").map(PathBuf::from) else { return };
        let world = World::load().expect("lilv world");
        std::fs::write(dir.join("plugins.json"), world.catalog()).unwrap();
        for (file, uri) in [("reverb.json", "http://calf.sourceforge.net/plugins/Reverb"), ("deesser.json", "http://calf.sourceforge.net/plugins/Deesser")] {
            std::fs::write(dir.join(file), world.info(uri)).unwrap();
        }
    }

    #[test]
    fn a_missing_plugin_leaves_a_silent_slot_and_the_sound_alone() {
        let Some(world) = World::load() else { return };
        let missing = slot("urn:vox:not-installed");
        let mut chain = world.build(&[missing.clone()]);
        assert!(chain.matches(&[missing]));
        let mut block = vec![[0.25, -0.5]; 64];
        chain.process(&mut block);
        assert_eq!(block, vec![[0.25, -0.5]; 64]);
    }

    #[test]
    fn saved_slots_are_cleaned_up() {
        let mut slots: Vec<Slot> = (0..9).map(|i| slot(&format!("urn:p{i}"))).collect();
        slots.push(slot(""));
        slots[0].params.insert("x".into(), f32::NAN);
        sanitize(&mut slots);
        assert_eq!(slots.len(), MAX_SLOTS);
        assert!(slots[0].params.is_empty());
    }
}
