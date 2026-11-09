// A plain-C door into SoundTouch (the library EasyEffects' Pitch uses), since Rust can't call C++ classes.
#include <soundtouch/SoundTouch.h>

extern "C" {

void *vox_st_new(unsigned rate, unsigned channels) {
    auto *st = new soundtouch::SoundTouch();
    st->setSampleRate(rate);
    st->setChannels(channels);
    return st;
}

void vox_st_free(void *st) { delete static_cast<soundtouch::SoundTouch *>(st); }

void vox_st_set_pitch(void *st, double semitones) {
    static_cast<soundtouch::SoundTouch *>(st)->setPitchSemiTones(semitones);
}

int vox_st_get_setting(void *st, int id) { return static_cast<soundtouch::SoundTouch *>(st)->getSetting(id); }

void vox_st_clear(void *st) { static_cast<soundtouch::SoundTouch *>(st)->clear(); }

// `samples` is interleaved floats; `frames` counts frames, not floats.
void vox_st_put(void *st, const float *samples, unsigned frames) {
    static_cast<soundtouch::SoundTouch *>(st)->putSamples(samples, frames);
}

unsigned vox_st_receive(void *st, float *out, unsigned max_frames) {
    return static_cast<soundtouch::SoundTouch *>(st)->receiveSamples(out, max_frames);
}

}
