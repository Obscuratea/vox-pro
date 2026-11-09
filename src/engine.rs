//! The PipeWire side. Every input strip and output bus is a PipeWire stream:
//! - hardware strips capture from a source; the Apps and Media strips record the
//!   "Vox Pro Apps" / "Vox Pro Media" devices that programs play into
//! - A buses play to a hardware sink; B buses play into the "Vox Pro B1/B2" virtual mics
//!
//! All streams share one node group, so PipeWire schedules them on one clock, and one link
//! group, so WirePlumber never wires them into each other (no feedback loops through us).
//! Processing runs on this thread's main loop, so the stream callbacks and the command
//! handler share the mixer without locks. Strips write processed audio into ring buffers
//! and each bus reads from them, which costs at most one graph cycle of delay.

use crate::dsp::{CompParams, SAMPLE_RATE, Voice, db_to_lin};
use crate::settings::{A_BUSES, BUSES, STRIPS, Settings};
use pipewire as pw;
use pw::properties::properties;
use pw::spa;
use std::cell::{Cell, RefCell};
use std::collections::HashMap;
use std::rc::Rc;
use std::sync::atomic::{AtomicBool, AtomicU32, Ordering};
use std::sync::{Arc, Mutex};

const GROUP: &str = "vox-pro";
const OWN_PREFIX: &str = "vox_pro";

/// Programs can play into these sinks (one per virtual strip), and record from the B microphones.
const SINKS: [&str; 5] = ["apps", "media", "game", "chat", "browser"];
const MICS: [&str; 3] = ["b1", "b2", "b3"];

/// The devices other programs see: (node.name, description, media.class).
fn virtual_devices() -> Vec<(String, String, &'static str)> {
    let title = |l: &str| {
        let mut c = l.chars();
        c.next().map(|f| f.to_uppercase().collect::<String>() + c.as_str()).unwrap_or_default()
    };
    SINKS
        .iter()
        .map(|l| (format!("{OWN_PREFIX}_{l}"), format!("Vox Pro {}", title(l)), "Audio/Sink"))
        .chain(MICS.iter().map(|l| {
            (format!("{OWN_PREFIX}_{l}"), format!("Vox Pro {} (Mic)", l.to_uppercase()), "Audio/Source/Virtual")
        }))
        .collect()
}
const RING: usize = 16_384;
const STRIDE: usize = 2 * std::mem::size_of::<f32>();

/// Per-sample step toward a new gain, about 10 ms to settle, so faders and mutes don't click.
fn smoothing() -> f32 {
    1.0 - (-1.0 / (0.01 * SAMPLE_RATE)).exp()
}

#[derive(Clone, Debug, serde::Serialize)]
pub struct Device {
    pub name: String,
    pub description: String,
}

#[derive(Default, serde::Serialize)]
pub struct Devices {
    pub sources: Vec<Device>,
    pub sinks: Vec<Device>,
}

/// State the UI thread reads.
pub struct Shared {
    pub strip_peaks: [[AtomicU32; 2]; STRIPS],
    pub bus_peaks: [[AtomicU32; 2]; BUSES],
    /// Deepest compressor / limiter gain reduction (dB, positive) since the UI last asked.
    pub strip_reduction: [AtomicU32; STRIPS],
    pub bus_reduction: [AtomicU32; BUSES],
    pub devices: Mutex<Devices>,
    /// node.name -> global id of the nodes we created, so they can be made system defaults.
    pub own_nodes: Mutex<HashMap<String, u32>>,
    /// Programs currently playing into Apps/Media or recording from B1/B2, as JSON.
    pub streams: Mutex<String>,
    /// Set when the PipeWire connection can't be made or is lost; the UI shows it. Empty when all is well.
    pub status: Mutex<String>,
    /// True while the push-to-talk key is held (set by the shortcut listener).
    pub ptt_held: AtomicBool,
    /// Things the desktop asked for that the UI has to carry out (e.g. "mute-mics"), oldest first.
    pub events: Mutex<Vec<String>>,
}

impl Shared {
    pub(crate) fn new() -> Self {
        Self {
            strip_peaks: std::array::from_fn(|_| std::array::from_fn(|_| AtomicU32::new(0))),
            bus_peaks: std::array::from_fn(|_| std::array::from_fn(|_| AtomicU32::new(0))),
            strip_reduction: std::array::from_fn(|_| AtomicU32::new(0)),
            bus_reduction: std::array::from_fn(|_| AtomicU32::new(0)),
            devices: Mutex::default(),
            own_nodes: Mutex::default(),
            streams: Mutex::new("[]".into()),
            status: Mutex::default(),
            ptt_held: AtomicBool::new(false),
            events: Mutex::default(),
        }
    }
}

// Non-negative floats order the same as their bit patterns, so fetch_max works on the bits.
fn record_peak(cell: &AtomicU32, value: f32) {
    cell.fetch_max(value.to_bits(), Ordering::Relaxed);
}

/// The loudest sample since the last call.
pub fn take_peak(cell: &AtomicU32) -> f32 {
    f32::from_bits(cell.swap(0, Ordering::Relaxed))
}

pub enum Command {
    Apply(Settings),
    /// Mute or unmute one program's stream (by PipeWire node id).
    MuteStream(u32, bool),
    /// Send one program's playback to "apps" or "media" (by PipeWire node id).
    MoveStream(u32, String),
}

pub struct Handle {
    pub shared: Arc<Shared>,
    pub sender: Mutex<pw::channel::Sender<Command>>,
}

pub fn start(settings: Settings) -> Handle {
    let shared = Arc::new(Shared::new());
    let (sender, receiver) = pw::channel::channel();
    let thread_shared = shared.clone();
    std::thread::Builder::new()
        .name("vox-pipewire".into())
        .spawn(move || {
            if let Err(e) = run(settings, thread_shared.clone(), receiver) {
                eprintln!("vox-pro: PipeWire engine stopped: {e}");
                *thread_shared.status.lock().unwrap() =
                    "Can't reach PipeWire. Is it running? Restart Vox once it is.".into();
            }
        })
        .expect("failed to start the audio thread");
    Handle { shared, sender: Mutex::new(sender) }
}

struct Ring {
    frames: Vec<[f32; 2]>,
    write: u64,
}

impl Ring {
    fn push(&mut self, frame: [f32; 2]) {
        self.frames[(self.write % RING as u64) as usize] = frame;
        self.write += 1;
    }

    fn get(&self, pos: u64) -> [f32; 2] {
        self.frames[(pos % RING as u64) as usize]
    }
}

/// How long the ducking stays down after the mic goes quiet.
const DUCK_HOLD_SECONDS: f32 = 0.8;

struct StripState {
    voice: Voice,
    /// Frames left before this mic strip stops ducking Apps and Media.
    duck_hold: u32,
    ring: Ring,
    /// The same audio before the pitch shifter, for A buses set to hear the natural voice.
    dry_ring: Ring,
    gain: f32,
}

struct BusState {
    /// How far this bus has read into each strip's ring.
    cursors: [u64; STRIPS],
    /// Push-to-talk gate per strip (1 open, 0 shut), eased over each cycle so the key doesn't click.
    ptt_gate: [f32; STRIPS],
    /// The limiter's current gain (1 = not limiting).
    limit: f32,
    /// Ducking gain per strip (1 = not ducked), eased per sample: down fast, back up slowly.
    duck_gain: [f32; STRIPS],
    gain: f32,
}

struct Mixer {
    settings: Settings,
    strips: Vec<StripState>,
    buses: Vec<BusState>,
    scratch: Vec<[f32; 2]>,
    /// One cycle of a strip's audio while it goes through the voice processing.
    block: Vec<[f32; 2]>,
    /// The same cycle before pitch shifting.
    dry: Vec<[f32; 2]>,
    shared: Arc<Shared>,
}

impl Mixer {
    fn new(shared: Arc<Shared>) -> Self {
        Self {
            settings: Settings::default(),
            strips: (0..STRIPS)
                .map(|_| StripState {
                    voice: Voice::default(),
                    duck_hold: 0,
                    ring: Ring { frames: vec![[0.0; 2]; RING], write: 0 },
                    dry_ring: Ring { frames: vec![[0.0; 2]; RING], write: 0 },
                    gain: 0.0,
                })
                .collect(),
            buses: (0..BUSES).map(|_| BusState { cursors: [0; STRIPS], ptt_gate: [1.0; STRIPS], duck_gain: [1.0; STRIPS], limit: 1.0, gain: 0.0 }).collect(),
            scratch: Vec::new(),
            block: Vec::new(),
            dry: Vec::new(),
            shared,
        }
    }

    fn capture(&mut self, index: usize, bytes: &[u8]) {
        let strip = &self.settings.strips[index];
        let target = if strip.mute { 0.0 } else { db_to_lin(strip.gain_db) };
        let gate = strip.gate_on.then(|| db_to_lin(strip.gate_threshold_db));
        let state = &mut self.strips[index];
        let step = smoothing();
        let mut peak = [0f32; 2];
        self.block.clear();
        for frame in bytes.chunks_exact(STRIDE) {
            let input = [read_f32(&frame[0..4]), read_f32(&frame[4..8])];
            self.block.push(state.voice.process(input, gate));
        }
        self.dry.clear();
        self.dry.extend_from_slice(&self.block);
        // Nobody hears a muted strip or one routed nowhere, so don't run the pitch shifter for it.
        let heard = strip.routes.iter().any(|&r| r) && (!strip.mute || state.gain > 1e-3);
        if heard {
            state.voice.shift(&mut self.block);
        } else {
            state.voice.park();
        }
        for (voiced, natural) in self.block.iter().zip(&self.dry) {
            state.gain += (target - state.gain) * step;
            let out = [voiced[0] * state.gain, voiced[1] * state.gain];
            peak[0] = peak[0].max(out[0].abs());
            peak[1] = peak[1].max(out[1].abs());
            state.ring.push(out);
            state.dry_ring.push([natural[0] * state.gain, natural[1] * state.gain]);
        }
        for ch in 0..2 {
            record_peak(&self.shared.strip_peaks[index][ch], peak[ch]);
        }
        record_peak(&self.shared.strip_reduction[index], state.voice.comp_reduction_db().max(0.0));
        // Auto-duck trigger: a mic strip that is talking keeps Apps and Media ducked for a moment.
        let config = &self.settings.strips[index];
        if config.duck_on && !config.virtual_input {
            let talking = peak[0].max(peak[1]) > db_to_lin(config.duck_threshold_db);
            state.duck_hold = if talking {
                (DUCK_HOLD_SECONDS * SAMPLE_RATE) as u32
            } else {
                state.duck_hold.saturating_sub(self.block.len() as u32)
            };
        } else {
            state.duck_hold = 0;
        }
    }

    fn playback(&mut self, index: usize, out: &mut [u8]) {
        let n = out.len() / STRIDE;
        self.scratch.clear();
        self.scratch.resize(n, [0.0; 2]);
        // The A buses are what you listen on: a soloed strip silences the others there (not on the mics).
        let listening = index < A_BUSES;
        // Push to talk shuts the mic strips (not Apps or Media) out of the B mics until the key is held.
        let ptt_shut = !listening && self.settings.ptt_enabled && !self.shared.ptt_held.load(Ordering::Relaxed);
        let solo_active = listening && self.settings.strips.iter().any(|s| s.solo);
        // The deepest duck any talking mic asks for on this bus (1.0 = none).
        let duck_target = self
            .strips
            .iter()
            .zip(&self.settings.strips)
            .filter(|(state, c)| c.duck_on && !c.virtual_input && state.duck_hold > 0 && if listening { c.duck_a } else { c.duck_b })
            .map(|(_, c)| db_to_lin(c.duck_db))
            .fold(1.0f32, f32::min);
        let attack = 1.0 - (-1.0 / (0.02 * SAMPLE_RATE)).exp();
        let recover = 1.0 - (-1.0 / (0.4 * SAMPLE_RATE)).exp();
        for (s, strip) in self.strips.iter().enumerate() {
            let config = &self.settings.strips[s];
            if !config.routes[index] || (solo_active && !config.solo) {
                continue;
            }
            let ring = if listening && config.a_hears_dry { &strip.dry_ring } else { &strip.ring };
            let bus_state = &mut self.buses[index];
            let cursor = &mut bus_state.cursors[s];
            let write = strip.ring.write;
            // Fallen too far behind (route just turned on, or clocks drifted): skip to near live.
            if write - *cursor > (3 * n).min(RING - n) as u64 {
                *cursor = write.saturating_sub(n as u64);
            }
            // Not enough new audio yet this cycle: leave this strip out rather than repeat old audio.
            if write - *cursor < n as u64 {
                continue;
            }
            let from = bus_state.ptt_gate[s];
            let to = if ptt_shut && !config.virtual_input { 0.0 } else { 1.0 };
            bus_state.ptt_gate[s] = to;
            let duck_to = if config.virtual_input { duck_target } else { 1.0 };
            let mut duck = bus_state.duck_gain[s];
            for (k, mixed) in self.scratch.iter_mut().enumerate() {
                let frame = ring.get(*cursor + k as u64);
                let ptt = if from == to { to } else { from + (to - from) * (k + 1) as f32 / n as f32 };
                duck += (duck_to - duck) * if duck_to < duck { attack } else { recover };
                let gate = ptt * duck;
                mixed[0] += frame[0] * gate;
                mixed[1] += frame[1] * gate;
            }
            bus_state.duck_gain[s] = duck;
            *cursor += n as u64;
        }

        let bus = &self.settings.buses[index];
        let target = if bus.mute { 0.0 } else { db_to_lin(bus.gain_db) };
        let state = &mut self.buses[index];
        let step = smoothing();
        let mut peak = [0f32; 2];
        let ceiling = bus.limiter_on.then(|| db_to_lin(bus.limiter_db));
        let release = 1.0 - (-1.0 / (0.15 * SAMPLE_RATE)).exp();
        if ceiling.is_none() {
            state.limit = 1.0;
        }
        let mut deepest = 1.0f32;
        for (frame, bytes) in self.scratch.iter().zip(out.chunks_exact_mut(STRIDE)) {
            state.gain += (target - state.gain) * step;
            let mut l = frame[0] * state.gain;
            let mut r = frame[1] * state.gain;
            if let Some(ceiling) = ceiling {
                // Brickwall: turn down at once for a peak above the ceiling, ease back up afterwards.
                let needed = (ceiling / l.abs().max(r.abs()).max(1e-9)).min(1.0);
                state.limit = needed.min(state.limit + (1.0 - state.limit) * release);
                l *= state.limit;
                r *= state.limit;
                deepest = deepest.min(state.limit);
            }
            peak[0] = peak[0].max(l.abs());
            peak[1] = peak[1].max(r.abs());
            bytes[0..4].copy_from_slice(&l.to_le_bytes());
            bytes[4..8].copy_from_slice(&r.to_le_bytes());
        }
        for ch in 0..2 {
            record_peak(&self.shared.bus_peaks[index][ch], peak[ch]);
        }
        record_peak(&self.shared.bus_reduction[index], -20.0 * deepest.log10());
    }
}

fn read_f32(bytes: &[u8]) -> f32 {
    f32::from_le_bytes([bytes[0], bytes[1], bytes[2], bytes[3]])
}

#[derive(Clone, Copy)]
enum Role {
    Strip(usize),
    Bus(usize),
}

struct Live {
    // Drop the listener before the stream it listens to.
    _listener: pw::stream::StreamListener<()>,
    _stream: pw::stream::StreamRc,
}

#[derive(Default)]
struct Streams {
    strips: Vec<Option<Live>>,
    buses: Vec<Option<Live>>,
}

fn format_param() -> Vec<u8> {
    let mut info = spa::param::audio::AudioInfoRaw::new();
    info.set_format(spa::param::audio::AudioFormat::F32LE);
    info.set_rate(SAMPLE_RATE as u32);
    info.set_channels(2);
    let mut position = [0u32; spa::sys::SPA_AUDIO_MAX_CHANNELS as usize];
    position[0] = spa::sys::SPA_AUDIO_CHANNEL_FL;
    position[1] = spa::sys::SPA_AUDIO_CHANNEL_FR;
    info.set_position(position);
    let object = spa::pod::Object {
        type_: spa::utils::SpaTypes::ObjectParamFormat.as_raw(),
        id: spa::param::ParamType::EnumFormat.as_raw(),
        properties: info.into(),
    };
    spa::pod::serialize::PodSerializer::serialize(std::io::Cursor::new(Vec::new()), &spa::pod::Value::Object(object))
        .expect("audio format serializes")
        .0
        .into_inner()
}

/// Properties for each stream. Returns None when the stream shouldn't exist yet
/// (a hardware strip or bus with no device picked).
fn stream_props(role: Role, settings: &Settings) -> Option<pw::properties::PropertiesBox> {
    let mut props = properties! {
        "media.type" => "Audio",
        "node.group" => GROUP,
        "node.link-group" => GROUP,
        "audio.position" => "FL,FR",
    };
    let target = match role {
        Role::Strip(i) => {
            let strip = &settings.strips[i];
            props.insert("media.category", "Capture");
            props.insert("node.name", format!("{OWN_PREFIX}_in{}", i + 1));
            props.insert("node.description", format!("Vox Pro Input {}", i + 1));
            if strip.virtual_input {
                // Record what programs play into the virtual device named after the strip.
                props.insert("stream.capture.sink", "true");
                format!("{OWN_PREFIX}_{}", strip.label.to_lowercase())
            } else {
                strip.source.clone()
            }
        }
        Role::Bus(i) => {
            let bus = &settings.buses[i];
            let label = bus.label.to_lowercase();
            props.insert("media.category", "Playback");
            props.insert("node.name", format!("{OWN_PREFIX}_out_{label}"));
            props.insert("node.description", format!("Vox Pro {}", bus.label));
            if bus.virtual_output {
                // WirePlumber only links playback streams to sinks, so we link this one to
                // its virtual mic ourselves (see link_virtual_mics).
                return Some(props);
            }
            bus.device.clone()
        }
    };
    if target.is_empty() {
        return None;
    }
    props.insert("target.object", target);
    props.insert("node.dont-fallback", "true");
    props.insert("node.dont-reconnect", "true");
    Some(props)
}

fn open_stream(core: &pw::core::CoreRc, mixer: &Rc<RefCell<Mixer>>, role: Role) -> Option<Live> {
    let props = stream_props(role, &mixer.borrow().settings)?;
    let linked_by_us = matches!(role, Role::Bus(i) if mixer.borrow().settings.buses[i].virtual_output);
    let name = match role {
        Role::Strip(i) => format!("vox-strip-{i}"),
        Role::Bus(i) => format!("vox-bus-{i}"),
    };
    let result = (|| {
        let stream = pw::stream::StreamRc::new(core.clone(), &name, props)?;
        let mixer = mixer.clone();
        let listener = stream
            .add_local_listener_with_user_data(())
            .process(move |stream, _| {
                let Some(mut buffer) = stream.dequeue_buffer() else { return };
                let requested = buffer.requested() as usize;
                let datas = buffer.datas_mut();
                let Some(data) = datas.first_mut() else { return };
                match role {
                    Role::Strip(i) => {
                        let offset = data.chunk().offset() as usize;
                        let size = data.chunk().size() as usize;
                        if let Some(bytes) = data.data() {
                            let end = (offset + size).min(bytes.len());
                            mixer.borrow_mut().capture(i, &bytes[offset.min(end)..end]);
                        }
                    }
                    Role::Bus(i) => {
                        let mut frames = 0;
                        if let Some(bytes) = data.data() {
                            let max = bytes.len() / STRIDE;
                            frames = if requested == 0 { max } else { requested.min(max) };
                            mixer.borrow_mut().playback(i, &mut bytes[..frames * STRIDE]);
                        }
                        let chunk = data.chunk_mut();
                        *chunk.offset_mut() = 0;
                        *chunk.stride_mut() = STRIDE as _;
                        *chunk.size_mut() = (frames * STRIDE) as _;
                    }
                }
            })
            .register()?;
        let format = format_param();
        let mut params = [spa::pod::Pod::from_bytes(&format).expect("valid format pod")];
        let direction = match role {
            Role::Strip(_) => spa::utils::Direction::Input,
            Role::Bus(_) => spa::utils::Direction::Output,
        };
        let mut flags = pw::stream::StreamFlags::MAP_BUFFERS;
        if !linked_by_us {
            flags |= pw::stream::StreamFlags::AUTOCONNECT;
        }
        stream.connect(direction, None, flags, &mut params)?;
        Ok::<_, pw::Error>(Live { _listener: listener, _stream: stream })
    })();
    result.map_err(|e| eprintln!("vox-pro: could not open {name}: {e}")).ok()
}

/// Whether a slot should have a stream open right now.
enum Want {
    Never,
    Always,
    /// Only while this device (PipeWire node.name) exists.
    Device(String),
}

fn want(role: Role, settings: &Settings) -> Want {
    let named = |name: &str| if name.is_empty() { Want::Never } else { Want::Device(name.to_string()) };
    match role {
        Role::Strip(i) => {
            let strip = &settings.strips[i];
            if strip.virtual_input {
                Want::Device(format!("{OWN_PREFIX}_{}", strip.label.to_lowercase()))
            } else {
                named(&strip.source)
            }
        }
        Role::Bus(i) => {
            let bus = &settings.buses[i];
            if bus.virtual_output { Want::Always } else { named(&bus.device) }
        }
    }
}

/// Bring one slot in line: reopen it if its device changed, open it once its device exists,
/// close it when its device is gone (so a replugged USB device comes back by itself).
fn sync_slot(
    core: &pw::core::CoreRc,
    mixer: &Rc<RefCell<Mixer>>,
    slot: &mut Option<Live>,
    role: Role,
    settings: &Settings,
    present: &dyn Fn(&str) -> bool,
    changed: bool,
) {
    let wanted = match want(role, settings) {
        Want::Never => false,
        Want::Always => true,
        Want::Device(name) => present(&name),
    };
    if changed {
        *slot = None;
    }
    match (slot.is_some(), wanted) {
        (false, true) => *slot = open_stream(core, mixer, role),
        (true, false) => *slot = None,
        _ => {}
    }
}

fn reconcile(
    core: &pw::core::CoreRc,
    mixer: &Rc<RefCell<Mixer>>,
    streams: &mut Streams,
    present: &dyn Fn(&str) -> bool,
    changed: &dyn Fn(Role) -> bool,
) {
    let settings = mixer.borrow().settings.clone();
    for i in 0..STRIPS {
        let role = Role::Strip(i);
        sync_slot(core, mixer, &mut streams.strips[i], role, &settings, present, changed(role));
    }
    for i in 0..BUSES {
        let role = Role::Bus(i);
        sync_slot(core, mixer, &mut streams.buses[i], role, &settings, present, changed(role));
    }
}

/// Take new settings; reopen only the streams whose device changed.
fn apply(
    core: &pw::core::CoreRc,
    mixer: &Rc<RefCell<Mixer>>,
    streams: &mut Streams,
    present: &dyn Fn(&str) -> bool,
    new: Settings,
    first: bool,
) {
    let old = {
        let mut m = mixer.borrow_mut();
        for (state, strip) in m.strips.iter_mut().zip(&new.strips) {
            state.voice.configure(strip.bass_db, strip.brightness_db, strip.pitch_semitones);
            state.voice.set_eq(strip.eq_on.then(|| {
                [0, 1, 2].map(|i| (strip.eq_hz[i], strip.eq_db[i]))
            }));
            state.voice.set_comp(strip.comp_on.then(|| CompParams {
                threshold_db: strip.comp_threshold_db,
                ratio: strip.comp_ratio,
                attack_ms: strip.comp_attack_ms,
                release_ms: strip.comp_release_ms,
                makeup_db: strip.comp_makeup_db,
            }));
        }
        std::mem::replace(&mut m.settings, new.clone())
    };
    let changed = |role: Role| {
        first
            || match role {
                Role::Strip(i) => old.strips[i].source != new.strips[i].source,
                Role::Bus(i) => old.buses[i].device != new.buses[i].device,
            }
    };
    reconcile(core, mixer, streams, present, &changed);
}

struct NodeInfo {
    class: String,
    device: Device,
}

/// A program's playback or recording stream, so the UI can list who is using Apps, Media, B1 and B2.
struct AppStream {
    name: String,
    /// file:// URL of the program's icon in the user's icon theme; empty when none was found.
    icon: String,
    /// True for a recording stream (reads a B mic), false for a playback stream.
    capture: bool,
    muted: bool,
    node: pw::node::Node,
    _listener: pw::node::NodeListener,
}

type AppStreams = Rc<RefCell<HashMap<u32, AppStream>>>;
/// PipeWire's "default" metadata, where a stream's `target.object` says which device it should play to.
type DefaultMetadata = Rc<RefCell<Option<pw::metadata::Metadata>>>;
/// link id -> (output node, input node)
type Routes = Rc<RefCell<HashMap<u32, (u32, u32)>>>;

const PROP_MUTE: u32 = 0x10004;

fn read_mute(pod: &spa::pod::Pod) -> Option<bool> {
    let (_, value) = spa::pod::deserialize::PodDeserializer::deserialize_any_from(pod.as_bytes()).ok()?;
    let spa::pod::Value::Object(object) = value else { return None };
    object.properties.iter().find(|p| p.key == PROP_MUTE).and_then(|p| match p.value {
        spa::pod::Value::Bool(muted) => Some(muted),
        _ => None,
    })
}

fn set_mute(stream: &AppStream, muted: bool) {
    let object = spa::pod::Object {
        type_: spa::utils::SpaTypes::ObjectParamProps.as_raw(),
        id: spa::param::ParamType::Props.as_raw(),
        properties: vec![spa::pod::Property::new(PROP_MUTE, spa::pod::Value::Bool(muted))],
    };
    let Ok((cursor, _)) = spa::pod::serialize::PodSerializer::serialize(
        std::io::Cursor::new(Vec::new()),
        &spa::pod::Value::Object(object),
    ) else {
        return;
    };
    if let Some(pod) = spa::pod::Pod::from_bytes(cursor.get_ref()) {
        stream.node.set_param(spa::param::ParamType::Props, 0, pod);
    }
}

/// Work out which of our devices each program is wired to, and hand the list to the UI.
fn publish_streams(apps: &AppStreams, routes: &Routes, shared: &Shared) {
    let own = shared.own_nodes.lock().unwrap().clone();
    let id_of = |label: &str| own.get(&format!("{OWN_PREFIX}_{label}")).copied();
    let targets: Vec<(&str, Option<u32>)> = SINKS.iter().chain(MICS.iter()).map(|&l| (l, id_of(l))).collect();
    let routes = routes.borrow();
    let mut list = Vec::new();
    for (&id, stream) in apps.borrow().iter() {
        let mut elsewhere = false;
        let mut placed = false;
        for &(output, input) in routes.values() {
            let (mine, other) = if stream.capture { (input, output) } else { (output, input) };
            if mine != id {
                continue;
            }
            if let Some((label, _)) = targets.iter().find(|(_, node)| *node == Some(other)) {
                list.push(serde_json::json!({ "id": id, "name": stream.name, "icon": stream.icon, "target": label, "muted": stream.muted }));
                placed = true;
                break;
            }
            // Playing somewhere that isn't one of ours (a program sent straight to hardware).
            if !stream.capture && !own.values().any(|&node| node == other) {
                elsewhere = true;
            }
        }
        if elsewhere && !placed {
            list.push(serde_json::json!({ "id": id, "name": stream.name, "icon": stream.icon, "target": "other", "muted": stream.muted }));
        }
    }
    list.sort_by_key(|item| (item["name"].as_str().unwrap_or_default().to_lowercase(), item["id"].as_u64()));
    *shared.streams.lock().unwrap() = serde_json::Value::Array(list).to_string();
}

struct PortInfo {
    node: u32,
    output: bool,
    channel: String,
}

/// Connect each B bus stream to its virtual mic, channel by channel, once both sides' ports exist.
fn link_virtual_mics(
    core: &pw::core::CoreRc,
    shared: &Shared,
    ports: &HashMap<u32, PortInfo>,
    links: &mut HashMap<(u32, u32), pw::link::Link>,
) {
    let own = shared.own_nodes.lock().unwrap();
    for label in MICS {
        let (Some(&from), Some(&to)) =
            (own.get(&format!("{OWN_PREFIX}_out_{label}")), own.get(&format!("{OWN_PREFIX}_{label}")))
        else {
            continue;
        };
        for (&out_port, out) in ports.iter().filter(|(_, p)| p.node == from && p.output) {
            let Some((&in_port, _)) = ports.iter().find(|(_, p)| p.node == to && !p.output && p.channel == out.channel)
            else {
                continue;
            };
            if links.contains_key(&(out_port, in_port)) {
                continue;
            }
            let link = core.create_object::<pw::link::Link>(
                "link-factory",
                &properties! {
                    "link.output.node" => from.to_string(),
                    "link.output.port" => out_port.to_string(),
                    "link.input.node" => to.to_string(),
                    "link.input.port" => in_port.to_string(),
                },
            );
            match link {
                Ok(link) => {
                    links.insert((out_port, in_port), link);
                }
                Err(e) => eprintln!("vox-pro: could not link {label}: {e}"),
            }
        }
    }
}

fn publish_devices(nodes: &HashMap<u32, NodeInfo>, shared: &Shared) {
    let mut devices = Devices::default();
    for node in nodes.values() {
        match node.class.as_str() {
            "Audio/Sink" => devices.sinks.push(node.device.clone()),
            _ => devices.sources.push(node.device.clone()),
        }
    }
    devices.sources.sort_by(|a, b| a.description.cmp(&b.description));
    devices.sinks.sort_by(|a, b| a.description.cmp(&b.description));
    *shared.devices.lock().unwrap() = devices;
}

fn run(settings: Settings, shared: Arc<Shared>, receiver: pw::channel::Receiver<Command>) -> Result<(), pw::Error> {
    pw::init();
    let mainloop = pw::main_loop::MainLoopRc::new(None)?;
    let context = pw::context::ContextRc::new(&mainloop, None)?;
    let core = context.connect_rc(None)?;

    // Track the devices the user can pick, the ids of our own nodes, and ports for the B links.
    let nodes: Rc<RefCell<HashMap<u32, NodeInfo>>> = Rc::default();
    let ports: Rc<RefCell<HashMap<u32, PortInfo>>> = Rc::default();
    let links: Rc<RefCell<HashMap<(u32, u32), pw::link::Link>>> = Rc::default();
    let apps: AppStreams = Rc::default();
    let routes: Routes = Rc::default();
    let metadata: DefaultMetadata = Rc::default();
    let registry = core.get_registry_rc()?;

    let mixer = Rc::new(RefCell::new(Mixer::new(shared.clone())));
    let streams = Rc::new(RefCell::new(Streams {
        strips: (0..STRIPS).map(|_| None).collect(),
        buses: (0..BUSES).map(|_| None).collect(),
    }));
    // Streams are only opened once the registry has listed what exists (see the sync below), and
    // after that whenever a device a slot wants appears or goes away.
    let ready = Rc::new(Cell::new(false));
    let present: Rc<dyn Fn(&str) -> bool> = Rc::new({
        let nodes = nodes.clone();
        let shared = shared.clone();
        move |name| {
            nodes.borrow().values().any(|n| n.device.name == name) || shared.own_nodes.lock().unwrap().contains_key(name)
        }
    });
    let refresh: Rc<dyn Fn()> = Rc::new({
        let (core, mixer, streams, ready, present) =
            (core.clone(), mixer.clone(), streams.clone(), ready.clone(), present.clone());
        move || {
            if !ready.get() {
                return;
            }
            if let Ok(mut streams) = streams.try_borrow_mut() {
                reconcile(&core, &mixer, &mut streams, &*present, &|_| false);
            }
        }
    });

    let _registry_listener = registry
        .add_listener_local()
        .global({
            let nodes = nodes.clone();
            let ports = ports.clone();
            let links = links.clone();
            let shared = shared.clone();
            let core = core.clone();
            let apps = apps.clone();
            let routes = routes.clone();
            let registry = registry.clone();
            let refresh = refresh.clone();
            let metadata = metadata.clone();
            move |global| {
                let Some(props) = global.props else { return };
                if global.type_ == pw::types::ObjectType::Metadata {
                    if props.get("metadata.name") == Some("default") {
                        if let Ok(bound) = registry.bind::<pw::metadata::Metadata, _>(global) {
                            *metadata.borrow_mut() = Some(bound);
                        }
                    }
                    return;
                }
                if global.type_ == pw::types::ObjectType::Link {
                    let end = |key| props.get(key).and_then(|id| id.parse::<u32>().ok());
                    if let (Some(output), Some(input)) = (end("link.output.node"), end("link.input.node")) {
                        routes.borrow_mut().insert(global.id, (output, input));
                        publish_streams(&apps, &routes, &shared);
                    }
                    return;
                }
                if global.type_ == pw::types::ObjectType::Port {
                    let node = props.get("node.id").and_then(|id| id.parse().ok());
                    let (Some(node), Some(direction), Some(channel)) =
                        (node, props.get("port.direction"), props.get("audio.channel"))
                    else {
                        return;
                    };
                    let info = PortInfo { node, output: direction == "out", channel: channel.to_string() };
                    ports.borrow_mut().insert(global.id, info);
                    // Only our own B streams and mics need linking; skip every other port.
                    let ours = shared.own_nodes.lock().unwrap().values().any(|&id| id == node);
                    if ours {
                        link_virtual_mics(&core, &shared, &ports.borrow(), &mut links.borrow_mut());
                    }
                    return;
                }
                if global.type_ != pw::types::ObjectType::Node {
                    return;
                }
                let name = props.get("node.name").unwrap_or_default();
                if name.starts_with(OWN_PREFIX) {
                    shared.own_nodes.lock().unwrap().insert(name.to_string(), global.id);
                    refresh();
                    return;
                }
                let class = props.get("media.class").unwrap_or_default();
                if matches!(class, "Stream/Output/Audio" | "Stream/Input/Audio") {
                    let label = props
                        .get("application.name")
                        .or_else(|| props.get("node.description"))
                        .unwrap_or(name);
                    let Ok(node) = registry.bind::<pw::node::Node, _>(global) else { return };
                    let id = global.id;
                    let listener = node
                        .add_listener_local()
                        // The registry's copy of the properties lacks the icon, so read it from the node itself.
                        .info({
                            let apps = apps.clone();
                            let routes = routes.clone();
                            let shared = shared.clone();
                            move |info| {
                                let Some(props) = info.props() else { return };
                                let icon_name = props
                                    .get("application.icon-name")
                                    .or_else(|| props.get("application.icon_name"))
                                    .or_else(|| props.get("application.process.binary"))
                                    .unwrap_or_default()
                                    .to_lowercase();
                                // Later updates can come without these properties; keep what we found.
                                if icon_name.is_empty() {
                                    return;
                                }
                                let icon = crate::icons::lookup(&icon_name);
                                let changed = apps.borrow_mut().get_mut(&id).is_some_and(|stream| {
                                    let changed = stream.icon != icon;
                                    stream.icon = icon;
                                    changed
                                });
                                if changed {
                                    publish_streams(&apps, &routes, &shared);
                                }
                            }
                        })
                        .param({
                            let apps = apps.clone();
                            let routes = routes.clone();
                            let shared = shared.clone();
                            move |_, _, _, _, pod| {
                                let Some(muted) = pod.and_then(read_mute) else { return };
                                if let Some(stream) = apps.borrow_mut().get_mut(&id) {
                                    stream.muted = muted;
                                }
                                publish_streams(&apps, &routes, &shared);
                            }
                        })
                        .register();
                    node.subscribe_params(&[spa::param::ParamType::Props]);
                    let stream = AppStream {
                        name: label.to_string(),
                        icon: String::new(),
                        capture: class == "Stream/Input/Audio",
                        muted: false,
                        node,
                        _listener: listener,
                    };
                    apps.borrow_mut().insert(id, stream);
                    publish_streams(&apps, &routes, &shared);
                    return;
                }
                if !matches!(class, "Audio/Source" | "Audio/Source/Virtual" | "Audio/Sink") {
                    return;
                }
                let description =
                    props.get("node.description").or_else(|| props.get("node.nick")).unwrap_or(name);
                nodes.borrow_mut().insert(
                    global.id,
                    NodeInfo {
                        class: class.to_string(),
                        device: Device { name: name.to_string(), description: description.to_string() },
                    },
                );
                publish_devices(&nodes.borrow(), &shared);
                refresh();
            }
        })
        .global_remove({
            let refresh = refresh.clone();
            let nodes = nodes.clone();
            let shared = shared.clone();
            let apps = apps.clone();
            let routes = routes.clone();
            move |id| {
                let gone_stream = apps.borrow_mut().remove(&id).is_some();
                let gone_link = routes.borrow_mut().remove(&id).is_some();
                if gone_stream || gone_link {
                    publish_streams(&apps, &routes, &shared);
                }
                let gone_device = nodes.borrow_mut().remove(&id).is_some();
                if gone_device {
                    publish_devices(&nodes.borrow(), &shared);
                }
                let before = shared.own_nodes.lock().unwrap().len();
                shared.own_nodes.lock().unwrap().retain(|_, own| *own != id);
                let gone_own = shared.own_nodes.lock().unwrap().len() != before;
                if gone_device || gone_own {
                    refresh();
                }
                if ports.borrow_mut().remove(&id).is_some() {
                    links.borrow_mut().retain(|&(out, input), _| out != id && input != id);
                }
            }
        })
        .register();

    // Created on the server (like EasyEffects does), and removed when we disconnect. They get no
    // link group, so WirePlumber is free to connect our streams to them.
    let _virtual_devices = virtual_devices()
        .iter()
        .map(|(name, description, class)| {
            core.create_object::<pw::node::Node>(
                "adapter",
                &properties! {
                    "factory.name" => "support.null-audio-sink",
                    "node.name" => name.as_str(),
                    "node.description" => description.as_str(),
                    "media.class" => *class,
                    "audio.position" => "FL,FR",
                    // So the system volume (on the Apps device) also turns the Apps strip down.
                    "monitor.channel-volumes" => "true",
                },
            )
        })
        .collect::<Result<Vec<_>, _>>()?;

    // Wait for the registry's first listing (and our own devices) before opening any stream, so a
    // stream is only made for a device that exists. Then open everything with the saved settings.
    let first_settings: Rc<RefCell<Option<Settings>>> = Rc::new(RefCell::new(Some(settings)));
    let barrier = core.sync(0)?;
    let _core_listener = core
        .add_listener_local()
        .done({
            let (core, mixer, streams, ready, present, first) =
                (core.clone(), mixer.clone(), streams.clone(), ready.clone(), present.clone(), first_settings.clone());
            move |id, seq| {
                if id != 0 || seq != barrier || ready.get() {
                    return;
                }
                ready.set(true);
                if let Some(settings) = first.borrow_mut().take() {
                    apply(&core, &mixer, &mut streams.borrow_mut(), &*present, settings, true);
                }
            }
        })
        .error({
            let shared = shared.clone();
            let mainloop = mainloop.clone();
            move |id, _seq, res, message| {
                eprintln!("vox-pro: PipeWire error on {id}: {res} {message}");
                if id == 0 {
                    // The connection itself failed (the server went away); nothing here can recover.
                    *shared.status.lock().unwrap() = "Lost the connection to PipeWire. Restart Vox.".into();
                    mainloop.quit();
                }
            }
        })
        .register();

    let _commands = receiver.attach(mainloop.loop_(), {
        let core = core.clone();
        let apps = apps.clone();
        let (ready, present, first) = (ready.clone(), present.clone(), first_settings.clone());
        let metadata = metadata.clone();
        move |command| match command {
            Command::Apply(settings) => {
                if ready.get() {
                    apply(&core, &mixer, &mut streams.borrow_mut(), &*present, settings, false);
                } else {
                    // Still waiting for the first listing: the newest settings are the ones to start with.
                    *first.borrow_mut() = Some(settings);
                }
            }
            Command::MuteStream(id, muted) => {
                if let Some(stream) = apps.borrow().get(&id) {
                    set_mute(stream, muted);
                }
            }
            Command::MoveStream(id, target) => {
                let Some(label) = SINKS.iter().find(|l| **l == target) else { return };
                let device = format!("{OWN_PREFIX}_{label}");
                let device = device.as_str();
                // WirePlumber moves the stream when its target.object changes (what Plasma's volume menu does too).
                if apps.borrow().contains_key(&id) {
                    if let Some(metadata) = metadata.borrow().as_ref() {
                        metadata.set_property(id, "target.object", Some("Spa:String"), Some(device));
                    }
                }
            }
        }
    });

    mainloop.run();
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Feed a steady tone through strip 0 the way PipeWire does (256-frame cycles) with pitch on:
    /// every cycle must add exactly one cycle of audio to the strip's ring (so the buses never
    /// starve), and after the shifter's start-up delay the strip must be playing the tone.
    #[test]
    fn strip_with_pitch_keeps_a_steady_supply_of_sound() {
        let mut mixer = Mixer::new(Arc::new(Shared::new()));
        mixer.settings = Settings::default();
        mixer.strips[0].voice.configure(0.0, 0.0, 3.5);
        let mut loud_cycles = 0;
        for cycle in 0..400 {
            let mut bytes = Vec::new();
            for n in 0..256 {
                let t = (cycle * 256 + n) as f32 / SAMPLE_RATE;
                let x = 0.4 * (2.0 * std::f32::consts::PI * 180.0 * t).sin();
                bytes.extend_from_slice(&x.to_le_bytes());
                bytes.extend_from_slice(&x.to_le_bytes());
            }
            let before = mixer.strips[0].ring.write;
            mixer.capture(0, &bytes);
            assert_eq!(mixer.strips[0].ring.write - before, 256, "cycle {cycle} didn't supply a full cycle of audio");
            let ring = &mixer.strips[0].ring;
            let last: f32 = (0..256).map(|k| ring.get(ring.write - 256 + k)[0].abs()).fold(0.0, f32::max);
            if cycle > 100 && last > 0.05 {
                loud_cycles += 1;
            }
        }
        assert_eq!(loud_cycles, 299, "the shifted tone dropped out in {} cycles", 299 - loud_cycles);
    }

    fn tone_cycle(cycle: usize) -> Vec<u8> {
        let mut bytes = Vec::new();
        for n in 0..256 {
            let t = (cycle * 256 + n) as f32 / SAMPLE_RATE;
            let x = 0.4 * (2.0 * std::f32::consts::PI * 180.0 * t).sin();
            bytes.extend_from_slice(&x.to_le_bytes());
            bytes.extend_from_slice(&x.to_le_bytes());
        }
        bytes
    }

    fn loudest(out: &[u8]) -> f32 {
        out.chunks_exact(4).map(|b| read_f32(b).abs()).fold(0.0, f32::max)
    }

    /// With "A hears dry" on, the A bus plays the voice at once while the B mic still waits for the pitched one.
    #[test]
    fn a_bus_can_hear_the_voice_without_the_pitch_delay() {
        let mut mixer = Mixer::new(Arc::new(Shared::new()));
        mixer.settings = Settings::default();
        mixer.settings.strips[0].routes = [true, false, false, false, false, true, false, false];
        mixer.settings.strips[0].a_hears_dry = true;
        mixer.strips[0].voice.configure(0.0, 0.0, 3.5);
        let (mut a_first, mut b_first) = (0.0f32, 0.0f32);
        for cycle in 0..4 {
            mixer.capture(0, &tone_cycle(cycle));
            let (mut a, mut b) = (vec![0u8; 256 * STRIDE], vec![0u8; 256 * STRIDE]);
            mixer.playback(0, &mut a);
            mixer.playback(5, &mut b);
            if cycle == 3 {
                (a_first, b_first) = (loudest(&a), loudest(&b));
            }
        }
        assert!(a_first > 0.1, "A should hear the natural voice straight away, got {a_first}");
        assert!(b_first < 1e-4, "B should still be waiting for the pitched voice, got {b_first}");
    }

    /// Solo silences the other strips on the A buses only.
    #[test]
    fn solo_only_changes_what_the_a_buses_play() {
        let mut mixer = Mixer::new(Arc::new(Shared::new()));
        mixer.settings = Settings::default();
        for s in 0..2 {
            mixer.settings.strips[s].routes = [true, false, false, false, false, true, false, false];
        }
        mixer.settings.strips[1].solo = true;
        for cycle in 0..3 {
            mixer.capture(0, &tone_cycle(cycle)); // strip 0 plays, strip 1 stays silent
            let (mut a, mut b) = (vec![0u8; 256 * STRIDE], vec![0u8; 256 * STRIDE]);
            mixer.playback(0, &mut a);
            mixer.playback(5, &mut b);
            if cycle == 2 {
                assert!(loudest(&a) < 1e-4, "A should only play the soloed (silent) strip");
                assert!(loudest(&b) > 0.1, "B should be unaffected by the solo");
            }
        }
    }

    /// Push to talk shuts the mic strips out of the B mics until the key is held; Apps and the A buses are untouched.
    #[test]
    fn push_to_talk_gates_only_the_mic_strips_on_the_b_mics() {
        let shared = Arc::new(Shared::new());
        let mut mixer = Mixer::new(shared.clone());
        mixer.settings = Settings::default();
        mixer.settings.ptt_enabled = true;
        mixer.settings.strips[0].routes = [true, false, false, false, false, true, false, false];
        let play = |mixer: &mut Mixer, cycle: usize| {
            mixer.capture(0, &tone_cycle(cycle));
            let (mut a, mut b) = (vec![0u8; 256 * STRIDE], vec![0u8; 256 * STRIDE]);
            mixer.playback(0, &mut a);
            mixer.playback(5, &mut b);
            (loudest(&a), loudest(&b))
        };
        play(&mut mixer, 0); // the first cycles ease the gains in
        play(&mut mixer, 1);
        let (a, b) = play(&mut mixer, 2);
        assert!(a > 0.1 && b < 1e-4, "key up: you hear yourself on A (got {a}), the mic is shut (got {b})");
        shared.ptt_held.store(true, Ordering::Relaxed);
        let (_, b) = (play(&mut mixer, 3), play(&mut mixer, 4)).1;
        assert!(b > 0.1, "key down: the mic opens, got {b}");
        shared.ptt_held.store(false, Ordering::Relaxed);
        let (_, b) = (play(&mut mixer, 5), play(&mut mixer, 6)).1;
        assert!(b < 1e-4, "key up again: the mic shuts, got {b}");
    }

    /// Talking into a ducking mic pulls Apps down on the B mics (not the A buses unless asked), holds it a
    /// moment after you stop, then lets it come back.
    #[test]
    fn talking_ducks_apps_then_it_recovers() {
        let mut mixer = Mixer::new(Arc::new(Shared::new()));
        mixer.settings = Settings::default();
        mixer.settings.strips[0].duck_on = true; // -10 dB when louder than -40 dB
        mixer.settings.strips[0].routes = [false; BUSES]; // the mic only triggers, so the levels below are Apps alone
        mixer.settings.strips[3].routes = [true, false, false, false, false, true, false, false]; // Apps to A1 and B1
        let silence = vec![0u8; 256 * STRIDE];
        let mut run = |mixer: &mut Mixer, cycle: usize, talking: bool| {
            mixer.capture(0, &if talking { tone_cycle(cycle) } else { silence.clone() });
            mixer.capture(3, &tone_cycle(cycle));
            let (mut a, mut b) = (vec![0u8; 256 * STRIDE], vec![0u8; 256 * STRIDE]);
            mixer.playback(0, &mut a);
            mixer.playback(5, &mut b);
            (loudest(&a), loudest(&b))
        };
        let mut cycle = 0;
        let mut last = (0.0, 0.0);
        for _ in 0..40 {
            last = run(&mut mixer, cycle, false);
            cycle += 1;
        }
        let (a_open, b_open) = last;
        assert!(a_open > 0.3 && b_open > 0.3, "Apps should be at full level before anyone talks");
        for _ in 0..40 {
            last = run(&mut mixer, cycle, true);
            cycle += 1;
        }
        let ratio = last.1 / b_open;
        assert!((0.25..0.4).contains(&ratio), "B should be about 10 dB down (x0.316) while talking, got x{ratio}");
        assert!(last.0 / a_open > 0.95, "A is not ducked unless asked");
        for _ in 0..20 {
            last = run(&mut mixer, cycle, false); // 0.1 s after the last word: still held down
            cycle += 1;
        }
        assert!(last.1 / b_open < 0.45, "the duck holds for a moment after you stop");
        for _ in 0..500 {
            last = run(&mut mixer, cycle, false);
            cycle += 1;
        }
        assert!(last.1 / b_open > 0.95, "Apps comes back after the hold, got x{}", last.1 / b_open);
    }

    /// The limiter keeps an output under its ceiling no matter how hot the strips are.
    #[test]
    fn the_limiter_holds_a_bus_under_its_ceiling() {
        let mut mixer = Mixer::new(Arc::new(Shared::new()));
        mixer.settings = Settings::default();
        mixer.settings.strips[0].routes = [true, false, false, false, false, false, false, false];
        mixer.settings.strips[0].gain_db = 12.0;
        let mut last = 0.0;
        for cycle in 0..6 {
            mixer.capture(0, &tone_cycle(cycle));
            let mut a = vec![0u8; 256 * STRIDE];
            mixer.playback(0, &mut a);
            last = loudest(&a);
            if cycle == 1 {
                assert!(last > 0.5, "without a limiter the hot strip is loud, got {last}");
                mixer.settings.buses[0].limiter_on = true;
                mixer.settings.buses[0].limiter_db = -12.0;
            }
        }
        assert!(last <= db_to_lin(-12.0) + 1e-4, "limited peak should stay under -12 dB, got {last}");
    }
}
