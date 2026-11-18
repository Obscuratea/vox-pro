//! VST3 plugin hosting (the audio side only, no plugin windows). Used by plugins.rs.
//!
//! A plugin is named "vst3:<path of the .vst3>|<class id as 32 hex digits>". As with CLAP, libraries
//! are loaded once and never unloaded.

#![allow(non_snake_case, unsafe_op_in_unsafe_fn)]

use std::cell::Cell;
use std::collections::HashMap;
use std::ffi::{c_char, c_void};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex, OnceLock};
use vst3::Steinberg::Vst::*;
use vst3::Steinberg::*;
use vst3::{Class, ComPtr, ComWrapper, Interface};

pub struct Found {
    pub id: String,
    pub name: String,
    pub author: String,
    pub category: String,
    pub stereo: bool,
}

struct Lib {
    _lib: libloading::Library,
    factory: ComPtr<IPluginFactory>,
}
unsafe impl Send for Lib {}
unsafe impl Sync for Lib {}

fn libs() -> &'static Mutex<HashMap<PathBuf, Option<Arc<Lib>>>> {
    static LIBS: OnceLock<Mutex<HashMap<PathBuf, Option<Arc<Lib>>>>> = OnceLock::new();
    LIBS.get_or_init(Default::default)
}

/// The shared library inside a `.vst3` bundle (or the file itself when it is a bare library).
fn binary(path: &Path) -> Option<PathBuf> {
    if path.is_dir() {
        let stem = path.file_stem()?.to_str()?;
        let so = path.join("Contents").join("x86_64-linux").join(format!("{stem}.so"));
        so.exists().then_some(so)
    } else {
        Some(path.to_path_buf())
    }
}

fn open(path: &Path) -> Option<Arc<Lib>> {
    let mut libs = libs().lock().unwrap();
    libs.entry(path.to_path_buf())
        .or_insert_with(|| unsafe {
            let lib = libloading::Library::new(binary(path)?).ok()?;
            if let Ok(entry) = lib.get::<unsafe extern "C" fn(*mut c_void) -> bool>(b"ModuleEntry\0") {
                if !entry(std::ptr::null_mut()) {
                    return None;
                }
            }
            let get: libloading::Symbol<unsafe extern "C" fn() -> *mut IPluginFactory> = lib.get(b"GetPluginFactory\0").ok()?;
            let factory = ComPtr::from_raw(get())?;
            Some(Arc::new(Lib { _lib: lib, factory }))
        })
        .clone()
}

fn narrow(buf: &[c_char]) -> String {
    let bytes: Vec<u8> = buf.iter().take_while(|&&c| c != 0).map(|&c| c as u8).collect();
    String::from_utf8_lossy(&bytes).into_owned()
}

fn wide(buf: &[TChar]) -> String {
    let units: Vec<u16> = buf.iter().take_while(|&&c| c != 0).map(|&c| c as u16).collect();
    String::from_utf16_lossy(&units)
}

fn hex(cid: &TUID) -> String {
    cid.iter().map(|&b| format!("{:02x}", b as u8)).collect()
}

fn unhex(s: &str) -> Option<TUID> {
    if s.len() != 32 {
        return None;
    }
    let mut out = [0 as c_char; 16];
    for (i, o) in out.iter_mut().enumerate() {
        *o = u8::from_str_radix(s.get(i * 2..i * 2 + 2)?, 16).ok()? as c_char;
    }
    Some(out)
}

/// Every effect the `.vst3` at `path` offers.
pub fn scan_file(path: &Path) -> Vec<Found> {
    let Some(lib) = open(path) else { return Vec::new() };
    let mut found = Vec::new();
    unsafe {
        let factory = &lib.factory;
        let factory2 = factory.cast::<IPluginFactory2>();
        let vendor = {
            let mut info: PFactoryInfo = std::mem::zeroed();
            factory.getFactoryInfo(&mut info);
            narrow(&info.vendor)
        };
        for i in 0..factory.countClasses() {
            let (cid, name, category, subs, author) = if let Some(f2) = &factory2 {
                let mut info: PClassInfo2 = std::mem::zeroed();
                if f2.getClassInfo2(i, &mut info) != kResultOk {
                    continue;
                }
                let author = narrow(&info.vendor);
                (info.cid, narrow(&info.name), narrow(&info.category), narrow(&info.subCategories), if author.is_empty() { vendor.clone() } else { author })
            } else {
                let mut info: PClassInfo = std::mem::zeroed();
                if factory.getClassInfo(i, &mut info) != kResultOk {
                    continue;
                }
                (info.cid, narrow(&info.name), narrow(&info.category), String::new(), vendor.clone())
            };
            if category != "Audio Module Class" || subs.contains("Instrument") || subs.contains("Analyzer") || subs.contains("Generator") {
                continue;
            }
            let kind = subs.split('|').find(|s| !matches!(*s, "Fx" | "Stereo" | "Mono" | "Surround" | "")).unwrap_or("Other").to_string();
            found.push(Found {
                id: format!("vst3:{}|{}", path.display(), hex(&cid)),
                name,
                author,
                category: kind,
                stereo: !(subs.contains("Mono") && !subs.contains("Stereo")),
            });
        }
    }
    found
}

// ---- the host side the plugin talks to -------------------------------------------------------

struct HostApp;
impl Class for HostApp {
    type Interfaces = (IHostApplication,);
}
impl IHostApplicationTrait for HostApp {
    unsafe fn getName(&self, name: *mut String128) -> tresult {
        for (i, c) in "Vox Pro".encode_utf16().chain(std::iter::once(0)).enumerate() {
            (*name)[i] = c as TChar;
        }
        kResultOk
    }
    unsafe fn createInstance(&self, _cid: *mut TUID, _iid: *mut TUID, _obj: *mut *mut c_void) -> tresult {
        kNotImplemented
    }
}

struct Handler;
impl Class for Handler {
    type Interfaces = (IComponentHandler,);
}
impl IComponentHandlerTrait for Handler {
    unsafe fn beginEdit(&self, _id: ParamID) -> tresult {
        kResultOk
    }
    unsafe fn performEdit(&self, _id: ParamID, _value: ParamValue) -> tresult {
        kResultOk
    }
    unsafe fn endEdit(&self, _id: ParamID) -> tresult {
        kResultOk
    }
    unsafe fn restartComponent(&self, _flags: int32) -> tresult {
        kResultOk
    }
}

/// One parameter's changes for this cycle: a single point at the start.
struct Queue {
    id: Cell<u32>,
    value: Cell<f64>,
    points: Cell<i32>,
}
impl Class for Queue {
    type Interfaces = (IParamValueQueue,);
}
impl IParamValueQueueTrait for Queue {
    unsafe fn getParameterId(&self) -> ParamID {
        self.id.get()
    }
    unsafe fn getPointCount(&self) -> int32 {
        self.points.get()
    }
    unsafe fn getPoint(&self, index: int32, offset: *mut int32, value: *mut ParamValue) -> tresult {
        if index != 0 || self.points.get() == 0 {
            return kInvalidArgument;
        }
        *offset = 0;
        *value = self.value.get();
        kResultOk
    }
    unsafe fn addPoint(&self, _offset: int32, value: ParamValue, index: *mut int32) -> tresult {
        self.value.set(value);
        self.points.set(1);
        *index = 0;
        kResultOk
    }
}

/// The list of changed parameters handed to the plugin. Plugins that report changes back write into a
/// second one of these, which is simply thrown away.
struct Changes {
    queues: Vec<ComWrapper<Queue>>,
    used: Cell<usize>,
}
impl Class for Changes {
    type Interfaces = (IParameterChanges,);
}
impl Changes {
    fn new() -> ComWrapper<Changes> {
        let queues = (0..256).map(|_| ComWrapper::new(Queue { id: Cell::new(0), value: Cell::new(0.0), points: Cell::new(0) })).collect();
        ComWrapper::new(Changes { queues, used: Cell::new(0) })
    }
    fn push(&self, id: u32, value: f64) {
        let n = self.used.get();
        if let Some(q) = self.queues.get(n) {
            q.id.set(id);
            q.value.set(value);
            q.points.set(1);
            self.used.set(n + 1);
        }
    }
}
impl IParameterChangesTrait for Changes {
    unsafe fn getParameterCount(&self) -> int32 {
        self.used.get() as int32
    }
    unsafe fn getParameterData(&self, index: int32) -> *mut IParamValueQueue {
        match self.queues.get(index as usize).filter(|_| (index as usize) < self.used.get()) {
            Some(q) => q.as_com_ref::<IParamValueQueue>().map_or(std::ptr::null_mut(), |r| r.as_ptr()),
            None => std::ptr::null_mut(),
        }
    }
    unsafe fn addParameterData(&self, id: *const ParamID, index: *mut int32) -> *mut IParamValueQueue {
        let n = self.used.get();
        let Some(q) = self.queues.get(n) else { return std::ptr::null_mut() };
        q.id.set(*id);
        q.points.set(0);
        self.used.set(n + 1);
        *index = n as int32;
        q.as_com_ref::<IParamValueQueue>().map_or(std::ptr::null_mut(), |r| r.as_ptr())
    }
}

/// One running plugin.
struct Instance {
    _lib: Arc<Lib>,
    component: ComPtr<IComponent>,
    processor: ComPtr<IAudioProcessor>,
    controller: Option<ComPtr<IEditController>>,
    /// The controller is its own object (not the component), so it needs its own shutdown.
    separate: bool,
    _host: ComWrapper<HostApp>,
    _handler: ComWrapper<Handler>,
    channels: usize,
    /// Which buses exist: (is main, channel count) for inputs and outputs.
    in_buses: Vec<usize>,
    out_buses: Vec<usize>,
    active: bool,
    processing: bool,
    changes_in: ComWrapper<Changes>,
    changes_out: ComWrapper<Changes>,
    pending: Vec<(u32, f64)>,
    context: ProcessContext,
    silence: Vec<f32>,
    scratch: Vec<f32>,
    inputs: Vec<AudioBusBuffers>,
    outputs: Vec<AudioBusBuffers>,
    in_ptrs: [[*mut f32; 2]; 8],
    out_ptrs: [[*mut f32; 2]; 8],
}
unsafe impl Send for Instance {}

unsafe fn create<I: Interface>(factory: &ComPtr<IPluginFactory>, cid: &TUID) -> Option<ComPtr<I>> {
    let mut obj: *mut c_void = std::ptr::null_mut();
    let r = factory.createInstance(cid.as_ptr(), I::IID.as_ptr() as *const c_char, &mut obj);
    if r == kResultOk { ComPtr::from_raw(obj as *mut I) } else { None }
}

impl Instance {
    unsafe fn create(id: &str, rate: f64, max: usize) -> Option<Instance> {
        let (path, cid) = id.strip_prefix("vst3:")?.split_once('|')?;
        let cid = unhex(cid)?;
        let lib = open(Path::new(path))?;
        let component: ComPtr<IComponent> = create(&lib.factory, &cid)?;
        let host = ComWrapper::new(HostApp);
        let handler = ComWrapper::new(Handler);
        let host_ptr = host.to_com_ptr::<IHostApplication>()?.as_ptr() as *mut FUnknown;
        if component.initialize(host_ptr) != kResultOk {
            return None;
        }
        let fail = |component: &ComPtr<IComponent>| {
            component.terminate();
        };
        let Some(processor) = component.cast::<IAudioProcessor>() else {
            fail(&component);
            return None;
        };
        // The controller is either the component itself or a separate class.
        let mut separate = false;
        let mut controller = component.cast::<IEditController>();
        if controller.is_none() {
            let mut ctrl_cid: TUID = [0; 16];
            if component.getControllerClassId(&mut ctrl_cid) == kResultOk {
                if let Some(c) = create::<IEditController>(&lib.factory, &ctrl_cid) {
                    if c.initialize(host_ptr) == kResultOk {
                        separate = true;
                        controller = Some(c);
                    }
                }
            }
        }
        if let Some(c) = &controller {
            c.setComponentHandler(handler.to_com_ptr::<IComponentHandler>()?.as_ptr());
            if separate {
                if let (Some(a), Some(b)) = (component.cast::<IConnectionPoint>(), c.cast::<IConnectionPoint>()) {
                    a.connect(b.as_ptr());
                    b.connect(a.as_ptr());
                }
            }
        }

        // Buses: the first of each direction is the main one; the rest (sidechains) stay off.
        let count = |dir| component.getBusCount(MediaTypes_::kAudio as MediaType, dir as BusDirection).max(0) as usize;
        let bus_channels = |dir: BusDirections, i: usize| -> Option<usize> {
            let mut info: BusInfo = std::mem::zeroed();
            (component.getBusInfo(MediaTypes_::kAudio as MediaType, dir as BusDirection, i as i32, &mut info) == kResultOk).then_some(info.channelCount.max(0) as usize)
        };
        let (n_in, n_out) = (count(BusDirections_::kInput), count(BusDirections_::kOutput));
        let channels = bus_channels(BusDirections_::kInput, 0).unwrap_or(0);
        if n_in == 0 || n_out == 0 || !(1..=2).contains(&channels) {
            fail(&component);
            return None;
        }
        let arrangement = if channels == 1 { SpeakerArr::kMono } else { SpeakerArr::kStereo };
        let mut ins = vec![SpeakerArr::kStereo; n_in];
        let mut outs = vec![SpeakerArr::kStereo; n_out];
        ins[0] = arrangement;
        outs[0] = arrangement;
        processor.setBusArrangements(ins.as_mut_ptr(), n_in as i32, outs.as_mut_ptr(), n_out as i32);
        let out_channels = bus_channels(BusDirections_::kOutput, 0).unwrap_or(0);
        if out_channels != channels {
            fail(&component);
            return None;
        }
        for i in 0..n_in {
            component.activateBus(MediaTypes_::kAudio as MediaType, BusDirections_::kInput as BusDirection, i as i32, (i == 0) as u8);
        }
        for i in 0..n_out {
            component.activateBus(MediaTypes_::kAudio as MediaType, BusDirections_::kOutput as BusDirection, i as i32, (i == 0) as u8);
        }
        if processor.canProcessSampleSize(SymbolicSampleSizes_::kSample32 as int32) != kResultOk {
            fail(&component);
            return None;
        }
        let mut setup = ProcessSetup {
            processMode: ProcessModes_::kRealtime as int32,
            symbolicSampleSize: SymbolicSampleSizes_::kSample32 as int32,
            maxSamplesPerBlock: max as int32,
            sampleRate: rate,
        };
        if processor.setupProcessing(&mut setup) != kResultOk {
            fail(&component);
            return None;
        }
        let mut context: ProcessContext = std::mem::zeroed();
        context.state = (ProcessContext_::StatesAndFlags_::kTempoValid | ProcessContext_::StatesAndFlags_::kTimeSigValid) as u32;
        context.sampleRate = rate;
        context.tempo = 120.0;
        context.timeSigNumerator = 4;
        context.timeSigDenominator = 4;
        let blank = AudioBusBuffers { numChannels: 0, silenceFlags: 0, __field0: AudioBusBuffers__type0 { channelBuffers32: std::ptr::null_mut() } };
        Some(Instance {
            _lib: lib,
            component,
            processor,
            controller,
            separate,
            _host: host,
            _handler: handler,
            channels,
            in_buses: (0..n_in).map(|i| if i == 0 { channels } else { 0 }).collect(),
            out_buses: (0..n_out).map(|i| if i == 0 { channels } else { 0 }).collect(),
            active: false,
            processing: false,
            changes_in: Changes::new(),
            changes_out: Changes::new(),
            pending: Vec::with_capacity(512),
            context,
            silence: vec![0.0; max],
            scratch: vec![0.0; max],
            inputs: (0..n_in).map(|_| blank).collect(),
            outputs: (0..n_out).map(|_| blank).collect(),
            in_ptrs: [[std::ptr::null_mut(); 2]; 8],
            out_ptrs: [[std::ptr::null_mut(); 2]; 8],
        })
    }

    unsafe fn activate(&mut self) -> bool {
        if self.component.setActive(1) != kResultOk {
            return false;
        }
        self.active = true;
        self.processing = self.processor.setProcessing(1) != kNotImplemented;
        true
    }

    unsafe fn process(&mut self, n: usize, inputs: &mut [*mut f32], outputs: &mut [*mut f32]) -> bool {
        self.changes_in.used.set(0);
        self.changes_out.used.set(0);
        for &(id, v) in &self.pending {
            self.changes_in.push(id, v);
        }
        self.pending.clear();

        let silent = self.silence.as_mut_ptr();
        let dump = self.scratch.as_mut_ptr();
        // Main bus gets the audio; any further bus is off (no channels, no buffers).
        for (i, bus) in self.inputs.iter_mut().enumerate() {
            if i == 0 {
                for c in 0..self.channels {
                    self.in_ptrs[0][c] = if c < inputs.len() { inputs[c] } else { silent };
                }
                *bus = AudioBusBuffers { numChannels: self.channels as i32, silenceFlags: 0, __field0: AudioBusBuffers__type0 { channelBuffers32: self.in_ptrs[0].as_mut_ptr() } };
            } else {
                bus.numChannels = 0;
            }
        }
        for (i, bus) in self.outputs.iter_mut().enumerate() {
            if i == 0 {
                for c in 0..self.channels {
                    self.out_ptrs[0][c] = if c < outputs.len() { outputs[c] } else { dump };
                }
                *bus = AudioBusBuffers { numChannels: self.channels as i32, silenceFlags: 0, __field0: AudioBusBuffers__type0 { channelBuffers32: self.out_ptrs[0].as_mut_ptr() } };
            } else {
                bus.numChannels = 0;
            }
        }
        let _ = (&self.in_buses, &self.out_buses);
        let mut data = ProcessData {
            processMode: ProcessModes_::kRealtime as int32,
            symbolicSampleSize: SymbolicSampleSizes_::kSample32 as int32,
            numSamples: n as int32,
            numInputs: self.inputs.len() as int32,
            numOutputs: self.outputs.len() as int32,
            inputs: self.inputs.as_mut_ptr(),
            outputs: self.outputs.as_mut_ptr(),
            inputParameterChanges: self.changes_in.as_com_ref::<IParameterChanges>().map_or(std::ptr::null_mut(), |r| r.as_ptr()),
            outputParameterChanges: self.changes_out.as_com_ref::<IParameterChanges>().map_or(std::ptr::null_mut(), |r| r.as_ptr()),
            inputEvents: std::ptr::null_mut(),
            outputEvents: std::ptr::null_mut(),
            processContext: &mut self.context,
        };
        self.processor.process(&mut data) == kResultOk
    }

    fn param_count(&self) -> i32 {
        self.controller.as_ref().map_or(0, |c| unsafe { c.getParameterCount() })
    }
}

impl Drop for Instance {
    fn drop(&mut self) {
        unsafe {
            if self.processing {
                self.processor.setProcessing(0);
            }
            if self.active {
                self.component.setActive(0);
            }
            if self.separate {
                if let (Some(a), Some(b)) = (self.component.cast::<IConnectionPoint>(), self.controller.as_ref().and_then(|c| c.cast::<IConnectionPoint>())) {
                    a.disconnect(b.as_ptr());
                    b.disconnect(a.as_ptr());
                }
                if let Some(c) = &self.controller {
                    c.terminate();
                }
            }
            self.component.terminate();
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
            let mut first = Instance::create(id, rate, max_block)?;
            let stereo = first.channels == 2;
            if !first.activate() {
                return None;
            }
            let mut instances = vec![first];
            if !stereo {
                let mut second = Instance::create(id, rate, max_block)?;
                if !second.activate() {
                    return None;
                }
                instances.push(second);
            }
            Some(Unit { instances, stereo })
        }
    }

    /// Queue a parameter value (given as the plugin's own plain value, by the id's number as text).
    pub fn set(&mut self, symbol: &str, value: f32) {
        let Ok(id) = symbol.parse::<u32>() else { return };
        for inst in self.instances.iter_mut() {
            let norm = match &inst.controller {
                Some(c) => unsafe {
                    let n = c.plainParamToNormalized(id, value as f64).clamp(0.0, 1.0);
                    c.setParamNormalized(id, n);
                    n
                },
                None => continue,
            };
            match inst.pending.iter().position(|(i, _)| *i == id) {
                Some(at) => inst.pending[at].1 = norm,
                None if inst.pending.len() < inst.pending.capacity() => inst.pending.push((id, norm)),
                None => {}
            }
        }
    }

    pub fn run(&mut self, n: usize, l: &[f32], r: &[f32], out_l: &mut [f32], out_r: &mut [f32]) -> bool {
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
        let inst = Instance::create(id, rate, max_block)?;
        let (path, cid) = id.strip_prefix("vst3:")?.split_once('|')?;
        let name = scan_file(Path::new(path)).into_iter().find(|f| f.id.ends_with(&format!("|{cid}"))).map(|f| f.name).unwrap_or_default();
        let mut params = Vec::new();
        if let Some(c) = &inst.controller {
            for i in 0..inst.param_count() {
                let mut pi: ParameterInfo = std::mem::zeroed();
                if c.getParameterInfo(i, &mut pi) != kResultOk {
                    continue;
                }
                if pi.flags & (ParameterInfo_::ParameterFlags_::kIsHidden | ParameterInfo_::ParameterFlags_::kIsReadOnly | ParameterInfo_::ParameterFlags_::kIsProgramChange) != 0 {
                    continue;
                }
                let (min, max) = (c.normalizedParamToPlain(pi.id, 0.0), c.normalizedParamToPlain(pi.id, 1.0));
                let (min, max) = if max >= min { (min, max) } else { (max, min) };
                let steps = pi.stepCount.max(0);
                let mut options = Vec::new();
                if steps >= 1 && steps <= 63 {
                    for s in 0..=steps {
                        let norm = s as f64 / steps as f64;
                        let mut text: String128 = [0; 128];
                        if c.getParamStringByValue(pi.id, norm, &mut text) == kResultOk {
                            options.push(serde_json::json!({ "value": c.normalizedParamToPlain(pi.id, norm), "label": wide(&text) }));
                        }
                    }
                }
                let wordy = options.iter().any(|o| o["label"].as_str().is_some_and(|l| l.chars().any(|ch| ch.is_alphabetic())));
                let kind = if steps == 1 {
                    "toggle"
                } else if steps > 1 && wordy {
                    "pick"
                } else if steps > 1 {
                    "int"
                } else {
                    "float"
                };
                let title = wide(&pi.title);
                params.push(serde_json::json!({
                    "symbol": pi.id.to_string(), "name": title,
                    "min": min, "max": max,
                    "def": c.normalizedParamToPlain(pi.id, pi.defaultNormalizedValue).clamp(min, max),
                    "kind": kind, "log": false, "unit": wide(&pi.units), "options": options,
                }));
            }
        }
        Some(serde_json::json!({ "uri": id, "name": name, "stereo": inst.channels == 2, "params": params }).to_string())
    }
}
