//! CLAP plugin hosting (the audio side only, no plugin windows). Used by plugins.rs.
//!
//! A plugin is named "clap:<path of the .clap file>|<the plugin's id>". Libraries are loaded once and
//! never unloaded: plenty of plugins misbehave when their code goes away while a thread still lingers.

#![allow(unsafe_op_in_unsafe_fn)]

use clap_sys::audio_buffer::clap_audio_buffer;
use clap_sys::entry::clap_plugin_entry;
use clap_sys::events::*;
use clap_sys::ext::audio_ports::*;
use clap_sys::ext::params::*;
use clap_sys::factory::plugin_factory::*;
use clap_sys::host::clap_host;
use clap_sys::plugin::{clap_plugin, clap_plugin_descriptor};
use clap_sys::process::{clap_process, CLAP_PROCESS_ERROR};
use clap_sys::version::CLAP_VERSION;
use std::collections::HashMap;
use std::ffi::{c_char, c_void, CStr, CString};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, OnceLock};

/// What a scan finds: enough to list the plugin.
pub struct Found {
    pub id: String,
    pub name: String,
    pub author: String,
    pub category: String,
    pub stereo: bool,
}

struct Lib {
    _lib: libloading::Library,
    factory: *const clap_plugin_factory,
}
unsafe impl Send for Lib {}
unsafe impl Sync for Lib {}

fn libs() -> &'static Mutex<HashMap<PathBuf, Option<Arc<Lib>>>> {
    static LIBS: OnceLock<Mutex<HashMap<PathBuf, Option<Arc<Lib>>>>> = OnceLock::new();
    LIBS.get_or_init(Default::default)
}

fn open(path: &Path) -> Option<Arc<Lib>> {
    let mut libs = libs().lock().unwrap();
    libs.entry(path.to_path_buf())
        .or_insert_with(|| unsafe {
            let lib = libloading::Library::new(path).ok()?;
            let entry: *const clap_plugin_entry = *lib.get::<*const clap_plugin_entry>(b"clap_entry\0").ok()?;
            if entry.is_null() {
                return None;
            }
            let cpath = CString::new(path.to_str()?).ok()?;
            if !((*entry).init?)(cpath.as_ptr()) {
                return None;
            }
            let factory = ((*entry).get_factory?)(CLAP_PLUGIN_FACTORY_ID.as_ptr()) as *const clap_plugin_factory;
            if factory.is_null() {
                return None;
            }
            Some(Arc::new(Lib { _lib: lib, factory }))
        })
        .clone()
}

unsafe fn text(p: *const c_char) -> String {
    if p.is_null() { String::new() } else { CStr::from_ptr(p).to_string_lossy().into_owned() }
}

fn fixed(buf: &[c_char]) -> String {
    let bytes: Vec<u8> = buf.iter().take_while(|&&c| c != 0).map(|&c| c as u8).collect();
    String::from_utf8_lossy(&bytes).into_owned()
}

unsafe fn features(d: &clap_plugin_descriptor) -> Vec<String> {
    let mut out = Vec::new();
    let mut p = d.features;
    while !p.is_null() && !(*p).is_null() {
        out.push(text(*p));
        p = p.add(1);
    }
    out
}

/// Every effect the `.clap` file at `path` offers.
pub fn scan_file(path: &Path) -> Vec<Found> {
    let Some(lib) = open(path) else { return Vec::new() };
    let mut found = Vec::new();
    unsafe {
        let f = &*lib.factory;
        let (Some(count), Some(get)) = (f.get_plugin_count, f.get_plugin_descriptor) else { return found };
        for i in 0..count(lib.factory) {
            let d = get(lib.factory, i);
            if d.is_null() {
                continue;
            }
            let d = &*d;
            let feats = features(d);
            let has = |name: &str| feats.iter().any(|f| f == name);
            if ["instrument", "note-effect", "note-detector", "analyzer", "synthesizer", "sampler"].iter().any(|n| has(n)) {
                continue;
            }
            if has("surround") || has("ambisonic") {
                continue;
            }
            let category = feats
                .iter()
                .find(|f| !matches!(f.as_str(), "audio-effect" | "mono" | "stereo" | "utility"))
                .map(|f| {
                    let mut c = f.replace('-', " ");
                    c[..1].make_ascii_uppercase();
                    c
                })
                .unwrap_or_else(|| "Other".into());
            found.push(Found {
                id: format!("clap:{}|{}", path.display(), text(d.id)),
                name: text(d.name),
                author: text(d.vendor),
                category,
                stereo: !(has("mono") && !has("stereo")),
            });
        }
    }
    found
}

fn host() -> &'static clap_host {
    unsafe extern "C" fn get_extension(_: *const clap_host, _: *const c_char) -> *const c_void {
        std::ptr::null()
    }
    unsafe extern "C" fn nothing(_: *const clap_host) {}
    static HOST: clap_host = clap_host {
        clap_version: CLAP_VERSION,
        host_data: std::ptr::null_mut(),
        name: c"Vox Pro".as_ptr(),
        vendor: c"Obscuratea".as_ptr(),
        url: c"https://github.com/Obscuratea/vox-pro".as_ptr(),
        version: c"0.2".as_ptr(),
        get_extension: Some(get_extension),
        request_restart: Some(nothing),
        request_process: Some(nothing),
        request_callback: Some(nothing),
    };
    &HOST
}

/// One running plugin.
struct Instance {
    plugin: *const clap_plugin,
    _lib: Arc<Lib>,
    channels: u32,
    /// Audio inputs beyond the first (sidechains) get silence.
    extra_in: u32,
    extra_out: u32,
    active: bool,
    started: bool,
    bufs_in: Vec<clap_audio_buffer>,
    bufs_out: Vec<clap_audio_buffer>,
    params: Option<*const clap_plugin_params>,
    /// Parameter changes waiting for the next cycle: (id, value).
    pending: Vec<(u32, f64)>,
    events: Vec<clap_event_param_value>,
    silence: Vec<f32>,
    scratch: Vec<f32>,
}
unsafe impl Send for Instance {}

impl Instance {
    unsafe fn create(id: &str) -> Option<Instance> {
        let (path, plugin_id) = id.strip_prefix("clap:")?.split_once('|')?;
        let lib = open(Path::new(path))?;
        let cid = CString::new(plugin_id).ok()?;
        let plugin = ((*lib.factory).create_plugin?)(lib.factory, host(), cid.as_ptr());
        if plugin.is_null() {
            return None;
        }
        let p = &*plugin;
        if !(p.init?)(plugin) {
            (p.destroy?)(plugin);
            return None;
        }
        let ports = (p.get_extension?)(plugin, CLAP_EXT_AUDIO_PORTS.as_ptr()) as *const clap_plugin_audio_ports;
        let (mut channels, mut extra_in, mut extra_out) = (2, 0, 0);
        if !ports.is_null() {
            let (count, get) = ((*ports).count?, (*ports).get?);
            let (n_in, n_out) = (count(plugin, true), count(plugin, false));
            let mut info: clap_audio_port_info = std::mem::zeroed();
            if n_in == 0 || n_out == 0 || !get(plugin, 0, true, &mut info) {
                (p.destroy?)(plugin);
                return None;
            }
            channels = info.channel_count;
            let mut out_info: clap_audio_port_info = std::mem::zeroed();
            if !get(plugin, 0, false, &mut out_info) || out_info.channel_count != channels || !(1..=2).contains(&channels) {
                (p.destroy?)(plugin);
                return None;
            }
            extra_in = n_in - 1;
            extra_out = n_out - 1;
        }
        let params = (p.get_extension?)(plugin, CLAP_EXT_PARAMS.as_ptr()) as *const clap_plugin_params;
        Some(Instance {
            plugin,
            _lib: lib,
            channels,
            extra_in,
            extra_out,
            active: false,
            started: false,
            bufs_in: Vec::with_capacity(16),
            bufs_out: Vec::with_capacity(16),
            params: (!params.is_null()).then_some(params),
            pending: Vec::with_capacity(512),
            events: Vec::with_capacity(512),
            silence: Vec::new(),
            scratch: Vec::new(),
        })
    }

    unsafe fn activate(&mut self, rate: f64, max: u32) -> bool {
        let p = &*self.plugin;
        let ok = p.activate.is_some_and(|f| f(self.plugin, rate, 1, max));
        self.active = ok;
        let n = max as usize;
        self.silence = vec![0.0; n];
        self.scratch = vec![0.0; n];
        ok
    }

    /// Run one cycle. `inputs` and `outputs` hold `channels` slices each.
    unsafe fn process(&mut self, n: usize, inputs: &mut [*mut f32], outputs: &mut [*mut f32]) -> bool {
        let p = &*self.plugin;
        if !self.started {
            if !p.start_processing.is_some_and(|f| f(self.plugin)) {
                return false;
            }
            self.started = true;
        }
        self.events.clear();
        for &(id, value) in &self.pending {
            self.events.push(clap_event_param_value {
                header: clap_event_header {
                    size: std::mem::size_of::<clap_event_param_value>() as u32,
                    time: 0,
                    space_id: CLAP_CORE_EVENT_SPACE_ID,
                    type_: CLAP_EVENT_PARAM_VALUE,
                    flags: CLAP_EVENT_IS_LIVE,
                },
                param_id: id,
                cookie: std::ptr::null_mut(),
                note_id: -1,
                port_index: -1,
                channel: -1,
                key: -1,
                value,
            });
        }
        self.pending.clear();

        unsafe extern "C" fn size(list: *const clap_input_events) -> u32 {
            (&*((*list).ctx as *const Vec<clap_event_param_value>)).len() as u32
        }
        unsafe extern "C" fn get(list: *const clap_input_events, i: u32) -> *const clap_event_header {
            match (&*((*list).ctx as *const Vec<clap_event_param_value>)).get(i as usize) {
                Some(e) => &e.header,
                None => std::ptr::null(),
            }
        }
        unsafe extern "C" fn push(_: *const clap_output_events, _: *const clap_event_header) -> bool {
            true
        }
        let in_events = clap_input_events { ctx: &self.events as *const _ as *mut c_void, size: Some(size), get: Some(get) };
        let out_events = clap_output_events { ctx: std::ptr::null_mut(), try_push: Some(push) };

        let silent = self.silence.as_mut_ptr();
        let dump = self.scratch.as_mut_ptr();
        let mut in_ptrs: [*mut f32; 2] = [silent; 2];
        let mut out_ptrs: [*mut f32; 2] = [dump; 2];
        for c in 0..self.channels as usize {
            in_ptrs[c] = inputs[c];
            out_ptrs[c] = outputs[c];
        }
        let mut sidechain: [*mut f32; 2] = [silent; 2];
        let mut side_out: [*mut f32; 2] = [dump; 2];
        let buffers_in = &mut self.bufs_in;
        let buffers_out = &mut self.bufs_out;
        buffers_in.clear();
        buffers_out.clear();
        buffers_in.push(clap_audio_buffer { data32: in_ptrs.as_mut_ptr(), data64: std::ptr::null_mut(), channel_count: self.channels, latency: 0, constant_mask: 0 });
        buffers_out.push(clap_audio_buffer { data32: out_ptrs.as_mut_ptr(), data64: std::ptr::null_mut(), channel_count: self.channels, latency: 0, constant_mask: 0 });
        for _ in 0..self.extra_in.min(7) {
            buffers_in.push(clap_audio_buffer { data32: sidechain.as_mut_ptr(), data64: std::ptr::null_mut(), channel_count: 2, latency: 0, constant_mask: 0 });
        }
        for _ in 0..self.extra_out.min(7) {
            buffers_out.push(clap_audio_buffer { data32: side_out.as_mut_ptr(), data64: std::ptr::null_mut(), channel_count: 2, latency: 0, constant_mask: 0 });
        }
        let process = clap_process {
            steady_time: -1,
            frames_count: n as u32,
            transport: std::ptr::null(),
            audio_inputs: buffers_in.as_ptr(),
            audio_outputs: buffers_out.as_mut_ptr(),
            audio_inputs_count: buffers_in.len() as u32,
            audio_outputs_count: buffers_out.len() as u32,
            in_events: &in_events,
            out_events: &out_events,
        };
        p.process.is_some_and(|f| f(self.plugin, &process) != CLAP_PROCESS_ERROR)
    }
}

impl Drop for Instance {
    fn drop(&mut self) {
        unsafe {
            let p = &*self.plugin;
            if self.started {
                if let Some(f) = p.stop_processing {
                    f(self.plugin);
                }
            }
            if self.active {
                if let Some(f) = p.deactivate {
                    f(self.plugin);
                }
            }
            if let Some(f) = p.destroy {
                f(self.plugin);
            }
        }
    }
}

/// One loaded plugin: a stereo instance, or two mono instances side by side.
pub struct Unit {
    instances: Vec<Instance>,
    pub stereo: bool,
}

impl Unit {
    pub fn load(id: &str, rate: f64, max_block: usize) -> Option<Unit> {
        unsafe {
            let mut first = Instance::create(id)?;
            let stereo = first.channels == 2;
            let mut instances = Vec::new();
            if !first.activate(rate, max_block as u32) {
                return None;
            }
            instances.push(first);
            if !stereo {
                let mut second = Instance::create(id)?;
                if !second.activate(rate, max_block as u32) {
                    return None;
                }
                instances.push(second);
            }
            Some(Unit { instances, stereo })
        }
    }

    /// Queue a parameter value (by the id's number as text). Sent with the next cycle.
    pub fn set(&mut self, symbol: &str, value: f32) {
        let Ok(id) = symbol.parse::<u32>() else { return };
        for inst in self.instances.iter_mut() {
            match inst.pending.iter().position(|(i, _)| *i == id) {
                Some(at) => inst.pending[at].1 = value as f64,
                None if inst.pending.len() < inst.pending.capacity() => inst.pending.push((id, value as f64)),
                None => {}
            }
        }
    }

    pub fn run(&mut self, n: usize, l: &[f32], r: &[f32], out_l: &mut [f32], out_r: &mut [f32]) -> bool {
        // Plugins take mutable input pointers by API; ours are only read.
        let (lp, rp) = (l.as_ptr() as *mut f32, r.as_ptr() as *mut f32);
        unsafe {
            if self.stereo {
                self.instances[0].process(n, &mut [lp, rp], &mut [out_l.as_mut_ptr(), out_r.as_mut_ptr()])
            } else {
                let a = self.instances[0].process(n, &mut [lp], &mut [out_l.as_mut_ptr()]);
                let b = self.instances[1].process(n, &mut [rp], &mut [out_r.as_mut_ptr()]);
                a && b
            }
        }
    }
}

/// JSON description of a plugin's controls, same shape as the LV2 one.
pub fn info(id: &str, rate: f64, max_block: usize) -> Option<String> {
    unsafe {
        let inst = Instance::create(id)?;
        let (path, plugin_id) = id.strip_prefix("clap:")?.split_once('|')?;
        let name = scan_file(Path::new(path)).into_iter().find(|f| f.id.ends_with(&format!("|{plugin_id}"))).map(|f| f.name).unwrap_or_default();
        let mut params = Vec::new();
        if let Some(pp) = inst.params {
            let (count, get_info) = ((*pp).count?, (*pp).get_info?);
            for i in 0..count(inst.plugin) {
                let mut pi: clap_param_info = std::mem::zeroed();
                if !get_info(inst.plugin, i, &mut pi) || pi.flags & (CLAP_PARAM_IS_HIDDEN | CLAP_PARAM_IS_READONLY) != 0 {
                    continue;
                }
                let stepped = pi.flags & (CLAP_PARAM_IS_STEPPED | CLAP_PARAM_IS_ENUM) != 0;
                let (min, max) = (pi.min_value, pi.max_value.max(pi.min_value));
                let mut options = Vec::new();
                if stepped && max - min >= 1.0 && max - min <= 63.0 {
                    if let Some(to_text) = (*pp).value_to_text {
                        for v in (min as i64)..=(max as i64) {
                            let mut buf = [0 as c_char; 128];
                            if to_text(inst.plugin, pi.id, v as f64, buf.as_mut_ptr(), 128) {
                                options.push(serde_json::json!({ "value": v, "label": fixed(&buf) }));
                            }
                        }
                    }
                }
                let kind = if stepped && max - min == 1.0 && options.iter().all(|o| o["label"].as_str().is_some_and(|l| l.chars().any(|c| !c.is_ascii_digit()))) && pi.flags & CLAP_PARAM_IS_ENUM == 0 {
                    "toggle"
                } else if stepped && options.len() >= 2 && options.iter().any(|o| o["label"].as_str().is_some_and(|l| l.chars().any(|c| c.is_alphabetic()))) {
                    "pick"
                } else if stepped {
                    "int"
                } else {
                    "float"
                };
                let module = fixed(&pi.module);
                let name = fixed(&pi.name);
                params.push(serde_json::json!({
                    "symbol": pi.id.to_string(),
                    "name": if module.is_empty() { name } else { format!("{module} · {name}") },
                    "min": min, "max": max, "def": pi.default_value.clamp(min, max),
                    "kind": kind, "log": false, "unit": "", "options": options,
                }));
            }
        }
        let _ = (rate, max_block);
        Some(serde_json::json!({ "uri": id, "name": name, "stereo": inst.channels == 2, "params": params }).to_string())
    }
}
