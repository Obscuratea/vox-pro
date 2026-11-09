//! SoundTouch, the pitch engine EasyEffects uses, through a small C shim (soundtouch_shim.cpp).

use std::ffi::c_void;

unsafe extern "C" {
    fn vox_st_new(rate: u32, channels: u32) -> *mut c_void;
    fn vox_st_free(st: *mut c_void);
    fn vox_st_set_pitch(st: *mut c_void, semitones: f64);
    fn vox_st_get_setting(st: *mut c_void, id: i32) -> i32;
    fn vox_st_clear(st: *mut c_void);
    fn vox_st_put(st: *mut c_void, samples: *const f32, frames: u32);
    fn vox_st_receive(st: *mut c_void, out: *mut f32, max_frames: u32) -> u32;
}

/// How many frames SoundTouch hands back in one burst.
pub const SETTING_NOMINAL_OUTPUT_SEQUENCE: i32 = 7;

/// A stereo pitch shifter. Audio goes in and comes out in chunks that don't line up one for one.
pub struct SoundTouch(*mut c_void);

// It is only ever used from the one audio thread that owns it.
unsafe impl Send for SoundTouch {}

impl SoundTouch {
    pub fn new(rate: u32) -> Self {
        Self(unsafe { vox_st_new(rate, 2) })
    }

    pub fn set_semitones(&mut self, semitones: f64) {
        unsafe { vox_st_set_pitch(self.0, semitones) }
    }

    pub fn setting(&self, id: i32) -> i32 {
        unsafe { vox_st_get_setting(self.0, id) }
    }

    pub fn clear(&mut self) {
        unsafe { vox_st_clear(self.0) }
    }

    pub fn put(&mut self, frames: &[[f32; 2]]) {
        unsafe { vox_st_put(self.0, frames.as_ptr().cast(), frames.len() as u32) }
    }

    /// Everything that has come out so far, appended to `out`.
    pub fn receive_into(&mut self, out: &mut Vec<[f32; 2]>) {
        const CHUNK: usize = 1024;
        loop {
            let start = out.len();
            out.resize(start + CHUNK, [0.0; 2]);
            let got = unsafe { vox_st_receive(self.0, out[start..].as_mut_ptr().cast(), CHUNK as u32) } as usize;
            out.truncate(start + got);
            if got < CHUNK {
                return;
            }
        }
    }
}

impl Drop for SoundTouch {
    fn drop(&mut self) {
        unsafe { vox_st_free(self.0) }
    }
}
