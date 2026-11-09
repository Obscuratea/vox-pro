//! Recording an output to a WAV file. The audio thread hands each cycle's frames to a writer
//! thread over a bounded channel, so disk trouble can never stall the sound; if the disk falls too
//! far behind, those cycles are dropped (and the file stays valid).

use std::fs::File;
use std::io::{self, BufWriter, Seek, SeekFrom, Write};
use std::path::PathBuf;
use std::sync::mpsc::{SyncSender, sync_channel};
use std::thread::JoinHandle;

/// WAV sizes are 32-bit; stop a little short of 4 GB (about 3 hours of 32-bit float stereo).
const MAX_BYTES: u64 = 4_000_000_000;
const HEADER: usize = 58;
/// FLAC frames are this many samples per channel (about 85 ms).
const FLAC_BLOCK: usize = 4096;

/// What a recording is saved as.
#[derive(Clone, Copy, PartialEq, Debug)]
pub enum Format {
    /// 32-bit float, exactly what the output carries. Biggest files.
    Wav,
    /// 24-bit, lossless, roughly half the size of the WAV.
    Flac,
    /// 16-bit-class lossy, 192 kbps. Smallest files.
    Mp3,
}

impl Format {
    pub fn parse(name: &str) -> Self {
        match name {
            "wav" => Self::Wav,
            "mp3" => Self::Mp3,
            _ => Self::Flac,
        }
    }

    fn extension(self) -> &'static str {
        match self {
            Self::Wav => "wav",
            Self::Flac => "flac",
            Self::Mp3 => "mp3",
        }
    }
}

/// One file being written, fed interleaved stereo f32 by the writer thread.
trait Sink: Send {
    fn write(&mut self, samples: &[f32]) -> io::Result<()>;
    /// Called about once a second: get everything written so far to disk in a playable state.
    fn checkpoint(&mut self) -> io::Result<()>;
    fn finish(&mut self) -> io::Result<()>;
}

pub struct Recorder {
    tx: Option<SyncSender<Vec<f32>>>,
    writer: Option<JoinHandle<()>>,
    pub path: PathBuf,
}

/// Where recordings go: ~/Music/Vox Pro.
pub fn folder() -> Option<PathBuf> {
    std::env::var_os("HOME").map(|h| PathBuf::from(h).join("Music").join("Vox Pro"))
}

fn stamp() -> String {
    std::process::Command::new("date")
        .arg("+%Y%m%d-%H%M%S")
        .output()
        .ok()
        .and_then(|o| String::from_utf8(o.stdout).ok())
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| "recording".into())
}

impl Recorder {
    /// Start a new file for the bus called `label`.
    pub fn start(label: &str, rate: u32, format: Format) -> Result<Self, String> {
        let dir = folder().ok_or("no home folder")?;
        std::fs::create_dir_all(&dir).map_err(|e| format!("can't make {}: {e}", dir.display()))?;
        Self::to_path(dir.join(format!("{label}-{}.{}", stamp(), format.extension())), rate, format)
    }

    pub fn to_path(path: PathBuf, rate: u32, format: Format) -> Result<Self, String> {
        let file = BufWriter::new(File::create(&path).map_err(|e| format!("can't write {}: {e}", path.display()))?);
        let mut sink: Box<dyn Sink> = match format {
            Format::Wav => Box::new(WavSink::new(file, rate).map_err(|e| e.to_string())?),
            Format::Flac => Box::new(FlacSink::new(file, rate).map_err(|e| e.to_string())?),
            Format::Mp3 => Box::new(Mp3Sink::new(file, rate)?),
        };
        let (tx, rx) = sync_channel::<Vec<f32>>(256);
        // LAME keeps big buffers on the stack, more than a spawned thread gets by default.
        let writer = std::thread::Builder::new().stack_size(16 << 20).spawn(move || {
            let mut chunks = 0u32;
            for chunk in rx {
                if sink.write(&chunk).is_err() {
                    return;
                }
                // About once a second, so a crash or kill still leaves a playable file.
                chunks += 1;
                if chunks % 200 == 0 && sink.checkpoint().is_err() {
                    return;
                }
            }
            let _ = sink.finish();
        }).map_err(|e| e.to_string())?;
        Ok(Self { tx: Some(tx), writer: Some(writer), path })
    }

    /// Hand over one cycle of stereo frames (dropped if the writer is behind).
    pub fn push(&self, frames: &[[f32; 2]]) {
        if let Some(tx) = &self.tx {
            let mut samples = Vec::with_capacity(frames.len() * 2);
            for f in frames {
                samples.push(f[0]);
                samples.push(f[1]);
            }
            let _ = tx.try_send(samples);
        }
    }

    /// Finish the file: close the channel, wait for the writer to finish it off.
    pub fn finish(mut self) -> PathBuf {
        self.close();
        self.path.clone()
    }

    fn close(&mut self) {
        self.tx = None;
        if let Some(w) = self.writer.take() {
            let _ = w.join();
        }
    }
}

impl Drop for Recorder {
    fn drop(&mut self) {
        self.close();
    }
}

// ---- WAV: 32-bit float ----

struct WavSink {
    file: BufWriter<File>,
    rate: u32,
    bytes: u64,
}

impl WavSink {
    fn new(mut file: BufWriter<File>, rate: u32) -> io::Result<Self> {
        file.write_all(&wav_header(rate, 0))?;
        Ok(Self { file, rate, bytes: 0 })
    }

    fn patch(&mut self) -> io::Result<()> {
        self.file.flush()?;
        let f = self.file.get_mut();
        f.seek(SeekFrom::Start(0))?;
        f.write_all(&wav_header(self.rate, self.bytes))?;
        f.seek(SeekFrom::End(0))?;
        Ok(())
    }
}

impl Sink for WavSink {
    fn write(&mut self, samples: &[f32]) -> io::Result<()> {
        if self.bytes + (samples.len() * 4) as u64 > MAX_BYTES {
            return Ok(()); // full: keep draining so the audio thread never blocks
        }
        for sample in samples {
            self.file.write_all(&sample.to_le_bytes())?;
        }
        self.bytes += (samples.len() * 4) as u64;
        Ok(())
    }

    fn checkpoint(&mut self) -> io::Result<()> {
        self.patch()
    }

    fn finish(&mut self) -> io::Result<()> {
        self.patch()
    }
}

/// A 32-bit float stereo WAV header for `data_bytes` of audio.
fn wav_header(rate: u32, data_bytes: u64) -> [u8; HEADER] {
    let data = data_bytes as u32;
    let mut h = Vec::with_capacity(HEADER);
    h.extend(b"RIFF");
    h.extend((HEADER as u32 - 8 + data).to_le_bytes());
    h.extend(b"WAVE");
    h.extend(b"fmt ");
    h.extend(18u32.to_le_bytes());
    h.extend(3u16.to_le_bytes()); // IEEE float
    h.extend(2u16.to_le_bytes());
    h.extend(rate.to_le_bytes());
    h.extend((rate * 8).to_le_bytes());
    h.extend(8u16.to_le_bytes());
    h.extend(32u16.to_le_bytes());
    h.extend(0u16.to_le_bytes());
    h.extend(b"fact");
    h.extend(4u32.to_le_bytes());
    h.extend((data / 8).to_le_bytes());
    h.extend(b"data");
    h.extend(data.to_le_bytes());
    h.try_into().unwrap()
}

// ---- FLAC: 24-bit, lossless ----

struct FlacSink {
    file: BufWriter<File>,
    config: flacenc::config::Encoder,
    info: flacenc::component::StreamInfo,
    /// Interleaved 24-bit samples waiting for a full block.
    pending: Vec<i32>,
    frame: usize,
    /// Samples per channel written so far.
    total: usize,
}

fn flac_header(info: &flacenc::component::StreamInfo, total: usize) -> io::Result<Vec<u8>> {
    use flacenc::component::{BitRepr, Stream};
    let mut info = info.clone();
    info.set_total_samples(total);
    let mut sink = flacenc::bitsink::ByteSink::new();
    Stream::with_stream_info(info).write(&mut sink).map_err(|e| io::Error::other(e.to_string()))?;
    let mut bytes = sink.as_slice().to_vec();
    // The block sizes in STREAMINFO (min, max) stay unset when no frame went through the stream object.
    bytes[8..10].copy_from_slice(&(FLAC_BLOCK as u16).to_be_bytes());
    bytes[10..12].copy_from_slice(&(FLAC_BLOCK as u16).to_be_bytes());
    Ok(bytes)
}

impl FlacSink {
    fn new(mut file: BufWriter<File>, rate: u32) -> io::Result<Self> {
        let info = flacenc::component::StreamInfo::new(rate as usize, 2, 24).map_err(|e| io::Error::other(e.to_string()))?;
        file.write_all(&flac_header(&info, 0)?)?;
        Ok(Self { file, config: flacenc::config::Encoder::default(), info, pending: Vec::new(), frame: 0, total: 0 })
    }

    /// Encode and write one block of `frames` samples per channel from the front of `pending`.
    fn emit(&mut self, frames: usize) -> io::Result<()> {
        use flacenc::component::BitRepr;
        use flacenc::error::Verify;
        use flacenc::source::{Fill, FrameBuf};
        let verified = self.config.clone().into_verified().map_err(|e| io::Error::other(format!("{e:?}")))?;
        let mut fb = FrameBuf::with_size(2, frames).map_err(|e| io::Error::other(e.to_string()))?;
        fb.fill_interleaved(&self.pending[..frames * 2]).map_err(|e| io::Error::other(e.to_string()))?;
        let frame = flacenc::encode_fixed_size_frame(&verified, &fb, self.frame, &self.info)
            .map_err(|e| io::Error::other(e.to_string()))?;
        let mut sink = flacenc::bitsink::ByteSink::new();
        frame.write(&mut sink).map_err(|e| io::Error::other(e.to_string()))?;
        self.file.write_all(sink.as_slice())?;
        self.pending.drain(..frames * 2);
        self.frame += 1;
        self.total += frames;
        Ok(())
    }

    fn patch(&mut self) -> io::Result<()> {
        self.file.flush()?;
        let header = flac_header(&self.info, self.total)?;
        let f = self.file.get_mut();
        f.seek(SeekFrom::Start(0))?;
        f.write_all(&header)?;
        f.seek(SeekFrom::End(0))?;
        Ok(())
    }
}

impl Sink for FlacSink {
    fn write(&mut self, samples: &[f32]) -> io::Result<()> {
        self.pending.extend(samples.iter().map(|x| (x.clamp(-1.0, 1.0) * 8_388_607.0).round() as i32));
        while self.pending.len() >= FLAC_BLOCK * 2 {
            self.emit(FLAC_BLOCK)?;
        }
        Ok(())
    }

    fn checkpoint(&mut self) -> io::Result<()> {
        self.patch()
    }

    fn finish(&mut self) -> io::Result<()> {
        let rest = self.pending.len() / 2;
        if rest > 0 {
            self.emit(rest)?;
        }
        self.patch()
    }
}

// ---- MP3: lossy, 192 kbps ----

struct Mp3Sink {
    file: BufWriter<File>,
    encoder: mp3lame_encoder::Encoder,
    out: Vec<u8>,
}

impl Mp3Sink {
    fn new(file: BufWriter<File>, rate: u32) -> Result<Self, String> {
        let mut b = mp3lame_encoder::Builder::new().ok_or("can't start the MP3 encoder")?;
        b.set_num_channels(2).map_err(|e| format!("{e:?}"))?;
        b.set_sample_rate(rate).map_err(|e| format!("{e:?}"))?;
        b.set_brate(mp3lame_encoder::Bitrate::Kbps192).map_err(|e| format!("{e:?}"))?;
        b.set_quality(mp3lame_encoder::Quality::Good).map_err(|e| format!("{e:?}"))?;
        let encoder = b.build().map_err(|e| format!("{e:?}"))?;
        Ok(Self { file, encoder, out: Vec::new() })
    }
}

impl Sink for Mp3Sink {
    fn write(&mut self, samples: &[f32]) -> io::Result<()> {
        let pcm = |x: f32| (x.clamp(-1.0, 1.0) * 32_767.0).round() as i16;
        let left: Vec<i16> = samples.chunks_exact(2).map(|f| pcm(f[0])).collect();
        let right: Vec<i16> = samples.chunks_exact(2).map(|f| pcm(f[1])).collect();
        self.out.clear();
        self.out.reserve(mp3lame_encoder::max_required_buffer_size(left.len()));
        self.encoder
            .encode_to_vec(mp3lame_encoder::DualPcm { left: &left, right: &right }, &mut self.out)
            .map_err(|e| io::Error::other(format!("{e:?}")))?;
        self.file.write_all(&self.out)
    }

    fn checkpoint(&mut self) -> io::Result<()> {
        self.file.flush() // MP3 is a plain stream of frames, playable as it stands
    }

    fn finish(&mut self) -> io::Result<()> {
        self.out.clear();
        self.out.reserve(16_384);
        self.encoder
            .flush_to_vec::<mp3lame_encoder::FlushNoGap>(&mut self.out)
            .map_err(|e| io::Error::other(format!("{e:?}")))?;
        self.file.write_all(&self.out)?;
        self.file.flush()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_recording_is_a_valid_wav_with_the_right_length() {
        let path = std::env::temp_dir().join(format!("vox-pro-rec-test-{}.wav", std::process::id()));
        let rec = Recorder::to_path(path.clone(), 48_000, Format::Wav).unwrap();
        let cycle: Vec<[f32; 2]> = (0..256).map(|i| [i as f32 / 256.0, -(i as f32) / 256.0]).collect();
        for _ in 0..10 {
            rec.push(&cycle);
        }
        rec.finish();
        let bytes = std::fs::read(&path).unwrap();
        let _ = std::fs::remove_file(&path);
        assert_eq!(&bytes[0..4], b"RIFF");
        assert_eq!(bytes.len(), HEADER + 10 * 256 * 8);
        assert_eq!(u32::from_le_bytes(bytes[54..58].try_into().unwrap()) as usize, 10 * 256 * 8);
        assert_eq!(u32::from_le_bytes(bytes[4..8].try_into().unwrap()) as usize, bytes.len() - 8);
        let second = f32::from_le_bytes(bytes[HEADER + 8..HEADER + 12].try_into().unwrap());
        assert!((second - 1.0 / 256.0).abs() < 1e-6);
    }

    /// Record two seconds of a 1 kHz tone in `format` and return the file.
    fn record_tone(format: Format, name: &str) -> PathBuf {
        let path = std::env::temp_dir().join(format!("vox-pro-{name}-{}", std::process::id()));
        let rec = Recorder::to_path(path.clone(), 48_000, format).unwrap();
        for cycle in 0..375 {
            let frames: Vec<[f32; 2]> = (0..256)
                .map(|i| {
                    let n = (cycle * 256 + i) as f32;
                    let x = 0.5 * (2.0 * std::f32::consts::PI * 1000.0 * n / 48_000.0).sin();
                    [x, -x]
                })
                .collect();
            rec.push(&frames);
            std::thread::sleep(std::time::Duration::from_millis(2)); // a little faster than real time, never a flood
        }
        rec.finish();
        path
    }

    fn tool(name: &str, args: &[&str], path: &PathBuf) -> Option<std::process::Output> {
        std::process::Command::new(name).args(args).arg(path).output().ok()
    }

    #[test]
    fn flac_recordings_pass_the_reference_decoder() {
        let path = record_tone(Format::Flac, "t.flac");
        let size = std::fs::metadata(&path).unwrap().len();
        // 2 s of 24-bit stereo is 576 KB raw; a tone compresses well below that.
        assert!(size > 1000 && size < 576_000, "unexpected size {size}");
        if let Some(out) = tool("flac", &["-t", "-s"], &path) {
            assert!(out.status.success(), "flac -t failed: {}", String::from_utf8_lossy(&out.stderr));
        }
        if let Some(out) = tool("ffprobe", &["-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0"], &path) {
            let secs: f32 = String::from_utf8_lossy(&out.stdout).trim().parse().unwrap_or(0.0);
            assert!((secs - 2.0).abs() < 0.05, "expected 2 s, got {secs}");
        }
        let _ = std::fs::remove_file(&path);
    }

    #[test]
    fn mp3_recordings_decode_with_the_right_length() {
        let path = record_tone(Format::Mp3, "t.mp3");
        let size = std::fs::metadata(&path).unwrap().len();
        assert!((40_000..60_000).contains(&size), "2 s at 192 kbps is about 48 KB, got {size}");
        if let Some(out) = tool("ffprobe", &["-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0"], &path) {
            let secs: f32 = String::from_utf8_lossy(&out.stdout).trim().parse().unwrap_or(0.0);
            assert!((secs - 2.0).abs() < 0.2, "expected about 2 s, got {secs}");
        }
        let _ = std::fs::remove_file(&path);
    }
}
