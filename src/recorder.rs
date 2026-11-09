//! Recording an output to a WAV file. The audio thread hands each cycle's frames to a writer
//! thread over a bounded channel, so disk trouble can never stall the sound; if the disk falls too
//! far behind, those cycles are dropped (and the file stays valid).

use std::fs::File;
use std::io::{BufWriter, Seek, SeekFrom, Write};
use std::path::PathBuf;
use std::sync::mpsc::{SyncSender, sync_channel};
use std::thread::JoinHandle;

/// WAV sizes are 32-bit; stop a little short of 4 GB (about 3 hours of 32-bit float stereo).
const MAX_BYTES: u64 = 4_000_000_000;
const HEADER: usize = 58;

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
    pub fn start(label: &str, rate: u32) -> Result<Self, String> {
        let dir = folder().ok_or("no home folder")?;
        std::fs::create_dir_all(&dir).map_err(|e| format!("can't make {}: {e}", dir.display()))?;
        Self::to_path(dir.join(format!("{label}-{}.wav", stamp())), rate)
    }

    pub fn to_path(path: PathBuf, rate: u32) -> Result<Self, String> {
        let mut file = BufWriter::new(File::create(&path).map_err(|e| format!("can't write {}: {e}", path.display()))?);
        file.write_all(&header(rate, 0)).map_err(|e| e.to_string())?;
        let (tx, rx) = sync_channel::<Vec<f32>>(256);
        let writer = std::thread::spawn(move || {
            let mut bytes: u64 = 0;
            let mut chunks = 0u32;
            for chunk in rx {
                if bytes + (chunk.len() * 4) as u64 > MAX_BYTES {
                    continue; // full: keep draining so the audio thread never blocks
                }
                for sample in &chunk {
                    if file.write_all(&sample.to_le_bytes()).is_err() {
                        return;
                    }
                }
                bytes += (chunk.len() * 4) as u64;
                // About once a second, bring the header up to date, so a crash or kill still leaves a playable file.
                chunks += 1;
                if chunks % 200 == 0 && patch(&mut file, rate, bytes).is_err() {
                    return;
                }
            }
            let _ = patch(&mut file, rate, bytes);
        });
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

    /// Finish the file: close the channel, wait for the writer to patch the header.
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

/// Write out what is buffered and rewrite the header for the audio so far.
fn patch(file: &mut BufWriter<File>, rate: u32, bytes: u64) -> std::io::Result<()> {
    file.flush()?;
    let f = file.get_mut();
    f.seek(SeekFrom::Start(0))?;
    f.write_all(&header(rate, bytes))?;
    f.seek(SeekFrom::End(0))?;
    Ok(())
}

/// A 32-bit float stereo WAV header for `data_bytes` of audio.
fn header(rate: u32, data_bytes: u64) -> [u8; HEADER] {
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


#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_recording_is_a_valid_wav_with_the_right_length() {
        let path = std::env::temp_dir().join(format!("vox-pro-rec-test-{}.wav", std::process::id()));
        let rec = Recorder::to_path(path.clone(), 48_000).unwrap();
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
}
