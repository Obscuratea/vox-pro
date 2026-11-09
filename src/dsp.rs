//! Per-strip voice processing: a noise gate, then a bass shelf and a brightness shelf, then pitch.
//! Everything works on interleaved stereo frames at a fixed sample rate.

use crate::stretch::{self, SoundTouch};
use std::collections::VecDeque;

pub const SAMPLE_RATE: f32 = 48_000.0;

const BASS_HZ: f32 = 150.0;
const BRIGHTNESS_HZ: f32 = 4_500.0;

pub fn db_to_lin(db: f32) -> f32 {
    10f32.powf(db / 20.0)
}

/// RBJ cookbook shelf filter (shelf slope 1), transposed direct form II, one state per channel.
#[derive(Clone, Copy)]
pub struct Shelf {
    b0: f32,
    b1: f32,
    b2: f32,
    a1: f32,
    a2: f32,
    z1: [f32; 2],
    z2: [f32; 2],
}

impl Default for Shelf {
    fn default() -> Self {
        Self { b0: 1.0, b1: 0.0, b2: 0.0, a1: 0.0, a2: 0.0, z1: [0.0; 2], z2: [0.0; 2] }
    }
}

impl Shelf {
    /// Recompute coefficients, keeping the filter state so changes don't click.
    pub fn set(&mut self, high: bool, freq: f32, gain_db: f32) {
        if gain_db.abs() < 0.05 {
            *self = Self { z1: self.z1, z2: self.z2, ..Self::default() };
            return;
        }
        let a = 10f32.powf(gain_db / 40.0);
        let w0 = 2.0 * std::f32::consts::PI * freq / SAMPLE_RATE;
        let (sin, cos) = w0.sin_cos();
        let alpha = sin / 2.0 * std::f32::consts::SQRT_2;
        let k = 2.0 * a.sqrt() * alpha;
        let (b0, b1, b2, a0, a1, a2) = if high {
            (
                a * ((a + 1.0) + (a - 1.0) * cos + k),
                -2.0 * a * ((a - 1.0) + (a + 1.0) * cos),
                a * ((a + 1.0) + (a - 1.0) * cos - k),
                (a + 1.0) - (a - 1.0) * cos + k,
                2.0 * ((a - 1.0) - (a + 1.0) * cos),
                (a + 1.0) - (a - 1.0) * cos - k,
            )
        } else {
            (
                a * ((a + 1.0) - (a - 1.0) * cos + k),
                2.0 * a * ((a - 1.0) - (a + 1.0) * cos),
                a * ((a + 1.0) - (a - 1.0) * cos - k),
                (a + 1.0) + (a - 1.0) * cos + k,
                -2.0 * ((a - 1.0) + (a + 1.0) * cos),
                (a + 1.0) + (a - 1.0) * cos - k,
            )
        };
        self.b0 = b0 / a0;
        self.b1 = b1 / a0;
        self.b2 = b2 / a0;
        self.a1 = a1 / a0;
        self.a2 = a2 / a0;
    }

    fn process(&mut self, ch: usize, x: f32) -> f32 {
        let y = self.b0 * x + self.z1[ch];
        self.z1[ch] = self.b1 * x - self.a1 * y + self.z2[ch];
        self.z2[ch] = self.b2 * x - self.a2 * y;
        y
    }
}

/// Noise gate: opens fast when the level crosses the threshold, holds briefly,
/// then fades out. Closes a few dB below the threshold so it doesn't chatter.
pub struct Gate {
    env: f32,
    gain: f32,
    hold: u32,
    // Time constants, worked out once.
    env_decay: f32,
    attack: f32,
    release: f32,
    hold_frames: u32,
}

impl Default for Gate {
    fn default() -> Self {
        Self {
            env: 0.0,
            gain: 1.0,
            hold: 0,
            env_decay: coef(0.05),
            attack: coef(0.002),
            release: coef(0.08),
            hold_frames: (0.1 * SAMPLE_RATE) as u32,
        }
    }
}

fn coef(seconds: f32) -> f32 {
    (-1.0 / (seconds * SAMPLE_RATE)).exp()
}

impl Gate {
    fn process(&mut self, l: f32, r: f32, threshold: f32) -> f32 {
        let level = l.abs().max(r.abs());
        self.env = if level > self.env { level } else { self.env * self.env_decay };
        if self.env > threshold {
            self.hold = self.hold_frames;
        } else if self.env < threshold * 0.7 && self.hold > 0 {
            self.hold -= 1;
        }
        let target = if self.hold > 0 { 1.0 } else { 0.0 };
        let c = if target > self.gain { self.attack } else { self.release };
        self.gain = target + (self.gain - target) * c;
        self.gain
    }
}

/// Pitch shifting with SoundTouch, the same engine as EasyEffects' Pitch. SoundTouch takes audio
/// in chunks and gives it back in bursts, so a small queue of silence is kept in front of its
/// output; that keeps every cycle supplied, at the cost of that much delay while pitch is on.
/// At 0 semitones nothing is touched and nothing is delayed.
pub struct PitchStage {
    engine: Option<SoundTouch>,
    semitones: f32,
    queue: VecDeque<[f32; 2]>,
    out: Vec<[f32; 2]>,
    /// Whether the queue holds its lead of silence (it is refilled after the stage was parked).
    primed: bool,
    /// How many times the lead had to be topped up (read by the tests).
    topups: u32,
}

impl Default for PitchStage {
    fn default() -> Self {
        Self { engine: None, semitones: 0.0, queue: VecDeque::new(), out: Vec::new(), primed: false, topups: 0 }
    }
}

impl PitchStage {
    pub fn set_semitones(&mut self, semitones: f32) {
        if (semitones - self.semitones).abs() < 1e-3 {
            return;
        }
        self.semitones = semitones;
        if semitones.abs() < 0.005 {
            self.engine = None;
            self.queue.clear();
            self.primed = false;
            return;
        }
        let engine = self.engine.get_or_insert_with(|| SoundTouch::new(SAMPLE_RATE as u32));
        engine.set_semitones(semitones as f64);
    }

    /// Nobody is listening to this strip right now: drop what is buffered so the shifter doesn't
    /// keep working (or hold old audio). It restarts clean, with its lead, on the next block.
    pub fn park(&mut self) {
        if self.primed {
            if let Some(engine) = self.engine.as_mut() {
                engine.clear();
            }
            self.queue.clear();
            self.primed = false;
        }
    }

    /// Shift a block in place. The block comes out the same length, delayed.
    pub fn process_block(&mut self, frames: &mut [[f32; 2]]) {
        let Some(engine) = self.engine.as_mut() else { return };
        if !self.primed {
            engine.clear();
            let lead = engine.setting(stretch::SETTING_NOMINAL_OUTPUT_SEQUENCE).max(0) as usize;
            self.queue.clear();
            self.queue.extend(std::iter::repeat_n([0.0; 2], lead));
            self.primed = true;
        }
        engine.put(frames);
        self.out.clear();
        engine.receive_into(&mut self.out);
        self.queue.extend(self.out.drain(..));
        // SoundTouch hands audio back in bursts, so the queue rises and falls. With a small or a
        // large PipeWire buffer it can dip below one cycle; add the shortfall (plus a little) to the
        // lead once, so the delay settles at what that buffer size needs instead of crackling.
        if self.queue.len() < frames.len() {
            self.topups += 1;
            let missing = frames.len() - self.queue.len() + 64;
            for _ in 0..missing {
                self.queue.push_front([0.0; 2]);
            }
        }
        for frame in frames.iter_mut() {
            *frame = self.queue.pop_front().unwrap_or([0.0; 2]);
        }
    }
}

#[derive(Default)]
pub struct Voice {
    bass: Shelf,
    brightness: Shelf,
    gate: Gate,
    pitch: PitchStage,
}

impl Voice {
    pub fn configure(&mut self, bass_db: f32, brightness_db: f32, pitch_semitones: f32) {
        self.bass.set(false, BASS_HZ, bass_db);
        self.brightness.set(true, BRIGHTNESS_HZ, brightness_db);
        self.pitch.set_semitones(pitch_semitones);
    }

    /// Gate and tone for one frame. Pitch comes after, on the whole block (`shift`).
    /// `gate_threshold` is linear amplitude, or `None` with the gate off.
    pub fn process(&mut self, frame: [f32; 2], gate_threshold: Option<f32>) -> [f32; 2] {
        let g = match gate_threshold {
            Some(t) => self.gate.process(frame[0], frame[1], t),
            None => 1.0,
        };
        let mut out = [0.0; 2];
        for ch in 0..2 {
            let x = frame[ch] * g;
            out[ch] = self.brightness.process(ch, self.bass.process(ch, x));
        }
        out
    }

    pub fn shift(&mut self, block: &mut [[f32; 2]]) {
        self.pitch.process_block(block);
    }

    /// The strip is not being heard (muted, or routed nowhere): skip the pitch shifter.
    pub fn park(&mut self) {
        self.pitch.park();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The strongest frequency between 50 and 1000 Hz, to the nearest Hz (Goertzel per bin).
    fn frequency(samples: &[f32]) -> f32 {
        let power = |freq: f32| {
            let coeff = 2.0 * (2.0 * std::f32::consts::PI * freq / SAMPLE_RATE).cos();
            let (mut s1, mut s2) = (0.0f32, 0.0f32);
            for &x in samples {
                let s0 = x + coeff * s1 - s2;
                s2 = s1;
                s1 = s0;
            }
            s1 * s1 + s2 * s2 - coeff * s1 * s2
        };
        (50..=1000).map(|f| f as f32).max_by(|a, b| power(*a).total_cmp(&power(*b))).unwrap()
    }

    /// Run a signal through the stage in 256-frame blocks, like a PipeWire cycle.
    fn run(semitones: f32, signal: impl Fn(usize) -> f32, frames: usize) -> Vec<f32> {
        let mut stage = PitchStage::default();
        stage.set_semitones(semitones);
        let mut out = Vec::with_capacity(frames);
        for start in (0..frames).step_by(256) {
            let mut block: Vec<[f32; 2]> = (start..start + 256).map(|n| [signal(n), signal(n)]).collect();
            stage.process_block(&mut block);
            out.extend(block.iter().map(|f| f[0]));
        }
        out
    }

    fn sine(hz: f32) -> impl Fn(usize) -> f32 {
        move |n| (2.0 * std::f32::consts::PI * hz * n as f32 / SAMPLE_RATE).sin() * 0.5
    }

    #[test]
    fn pitch_moves_by_octaves() {
        for (semitones, expected) in [(12.0, 440.0), (-12.0, 110.0), (5.0, 293.7)] {
            let out = run(semitones, sine(220.0), SAMPLE_RATE as usize * 2);
            let got = frequency(&out[SAMPLE_RATE as usize..]);
            assert!((got - expected).abs() <= 3.0, "{semitones} st gave {got}, wanted {expected}");
        }
    }

    #[test]
    fn pitch_never_runs_dry() {
        // Once audio is flowing there must be no silent gaps from the stage running out.
        let out = run(3.5, sine(180.0), SAMPLE_RATE as usize * 3);
        let steady = &out[SAMPLE_RATE as usize..];
        let silent = steady.chunks(48).filter(|c| c.iter().all(|v| v.abs() < 1e-4)).count();
        assert_eq!(silent, 0, "{silent} silent 1 ms chunks in the shifted voice");
    }

    #[test]
    fn pitch_at_zero_is_untouched() {
        let mut stage = PitchStage::default();
        let mut block = [[0.25, -0.5]; 4];
        stage.process_block(&mut block);
        assert_eq!(block, [[0.25, -0.5]; 4]);
    }

    /// Odd PipeWire buffer sizes used to leave the shifted voice with the odd silent gap.
    /// After a few seconds of settling, none may remain at any size.
    #[test]
    fn pitch_supply_holds_at_other_buffer_sizes() {
        for n in [64usize, 128, 512, 1024, 2048] {
            for semitones in [3.5f32, -5.0, 12.0] {
                let mut stage = PitchStage::default();
                stage.set_semitones(semitones);
                let mut seed = 1u32;
                let cycles = SAMPLE_RATE as usize * 90 / n;
                let settle = SAMPLE_RATE as usize * 20 / n;
                let mut late_gaps = 0;
                for cycle in 0..cycles {
                    let mut block: Vec<[f32; 2]> = (0..n)
                        .map(|_| {
                            seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
                            let v = ((seed >> 8) as f32 / 8_388_608.0 - 1.0) * 0.2;
                            [v, v]
                        })
                        .collect();
                    let topups = stage.topups;
                    stage.process_block(&mut block);
                    if cycle > settle && stage.topups != topups {
                        late_gaps += 1;
                    }
                }
                assert_eq!(late_gaps, 0, "{late_gaps} gaps at {n} frames, {semitones} st");
            }
        }
    }
}
