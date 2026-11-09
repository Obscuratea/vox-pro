//! "Check for updates" and "Update": looks at the newest GitHub release, and on request downloads its
//! package, checks it and installs it with pacman (the desktop asks for your password through polkit).
//! Settings live in ~/.config and are never touched. All the slow work runs on a thread; the UI polls
//! `status_json()`.

use serde::Serialize;
use std::io::Read;
use std::path::PathBuf;
use std::process::{Command, Stdio};
use std::sync::Mutex;

const REPO: &str = "Obscuratea/vox-pro";
const PACKAGE: &str = "vox-pro";

#[derive(Clone, Default, Serialize)]
pub struct Status {
    /// idle, checking, uptodate, available, downloading, installing, installed, error
    pub state: &'static str,
    pub current: String,
    pub latest: String,
    pub notes: String,
    /// Download progress, 0-100.
    pub progress: u32,
    pub message: String,
    #[serde(skip)]
    url: String,
    #[serde(skip)]
    sha_url: String,
    #[serde(skip)]
    size: u64,
}

static STATUS: Mutex<Option<Status>> = Mutex::new(None);

fn with<R>(f: impl FnOnce(&mut Status) -> R) -> R {
    let mut guard = STATUS.lock().unwrap();
    let s = guard.get_or_insert_with(|| Status { state: "idle", current: env!("CARGO_PKG_VERSION").into(), ..Status::default() });
    f(s)
}

pub fn status_json() -> String {
    serde_json::to_string(&with(|s| s.clone())).unwrap_or_default()
}

fn set(state: &'static str, message: impl Into<String>) {
    with(|s| {
        s.state = state;
        s.message = message.into();
    });
}

/// Is `a` a newer version than `b`? Compares the numbers in "1.2.3" (a leading "v" is ignored).
pub fn newer(a: &str, b: &str) -> bool {
    let parts = |v: &str| -> Vec<u64> {
        v.trim_start_matches('v').split(|c: char| !c.is_ascii_digit()).filter(|p| !p.is_empty()).map(|p| p.parse().unwrap_or(0)).collect()
    };
    let (mut x, mut y) = (parts(a), parts(b));
    let n = x.len().max(y.len());
    x.resize(n, 0);
    y.resize(n, 0);
    x > y
}

/// Only https, except when a debug build is pointed at a local test server.
fn proto() -> &'static str {
    if dev_api().is_some() { "=https,http" } else { "=https" }
}

fn curl_text(url: &str) -> Result<String, String> {
    let out = Command::new("curl")
        .args(["-fsSL", "--proto", proto(), "--max-time", "20", "-H", "Accept: application/vnd.github+json", "-A", "vox-updater", url])
        .output()
        .map_err(|e| format!("curl is not available: {e}"))?;
    if out.status.code() == Some(22) {
        return Err("none".into()); // HTTP 404 and the like: no release published
    }
    if !out.status.success() {
        return Err("Couldn't reach GitHub. Check your connection.".into());
    }
    String::from_utf8(out.stdout).map_err(|e| e.to_string())
}

/// Testing aid, debug builds only: VOX_UPDATE_API points the check at another address.
fn dev_api() -> Option<String> {
    if cfg!(debug_assertions) { std::env::var("VOX_UPDATE_API").ok() } else { None }
}

/// Look for a newer release (on a thread).
pub fn check() {
    if matches!(with(|s| s.state), "checking" | "downloading" | "installing") {
        return;
    }
    set("checking", "");
    std::thread::spawn(|| {
        let api = dev_api().unwrap_or_else(|| format!("https://api.github.com/repos/{REPO}/releases/latest"));
        match curl_text(&api).and_then(|text| parse_release(&text)) {
            Ok(Some(found)) => with(|s| {
                s.state = "available";
                s.latest = found.latest;
                s.notes = found.notes;
                s.url = found.url;
                s.sha_url = found.sha_url;
                s.size = found.size;
                s.message = String::new();
            }),
            Ok(None) => set("uptodate", "You have the newest version."),
            Err(e) if e == "none" => set("uptodate", "No releases published yet."),
            Err(e) => set("error", e),
        }
    });
}

struct Found {
    latest: String,
    notes: String,
    url: String,
    sha_url: String,
    size: u64,
}

fn parse_release(text: &str) -> Result<Option<Found>, String> {
    let json: serde_json::Value = serde_json::from_str(text).map_err(|_| "GitHub's answer wasn't understood.".to_string())?;
    let tag = json["tag_name"].as_str().ok_or("That release has no version.")?;
    let latest = tag.trim_start_matches('v').to_string();
    if !newer(&latest, env!("CARGO_PKG_VERSION")) {
        return Ok(None);
    }
    let assets = json["assets"].as_array().cloned().unwrap_or_default();
    let pick = |matches: &dyn Fn(&str) -> bool| assets.iter().find(|a| a["name"].as_str().is_some_and(matches));
    let pkg = pick(&|n| n.ends_with(".pkg.tar.zst") && n.contains("x86_64"))
        .ok_or("That release has no package to install yet.")?;
    let pkg_name = pkg["name"].as_str().unwrap_or_default().to_string();
    let url = pkg["browser_download_url"].as_str().unwrap_or_default().to_string();
    // Only ever download from this project's own releases.
    if dev_api().is_none() && !url.starts_with(&format!("https://github.com/{REPO}/releases/download/")) {
        return Err("The package isn't from the project's releases, so it was not trusted.".into());
    }
    let sha_url = pick(&|n| n == format!("{pkg_name}.sha256"))
        .and_then(|a| a["browser_download_url"].as_str())
        .ok_or("That release has no checksum file, so it can't be verified.")?
        .to_string();
    let mut notes = json["body"].as_str().unwrap_or_default().trim().to_string();
    if notes.chars().count() > 1500 {
        notes = notes.chars().take(1500).collect::<String>() + "...";
    }
    Ok(Some(Found { latest, notes, url, sha_url, size: pkg["size"].as_u64().unwrap_or(0) }))
}

fn cache_dir() -> PathBuf {
    let base = std::env::var_os("XDG_CACHE_HOME")
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".cache")))
        .unwrap_or_else(std::env::temp_dir);
    base.join(PACKAGE).join("update")
}

/// Download, verify and install the release found by `check` (on a thread).
pub fn install() {
    let (url, sha_url, size) = with(|s| (s.url.clone(), s.sha_url.clone(), s.size));
    if with(|s| s.state) != "available" || url.is_empty() {
        return;
    }
    std::thread::spawn(move || {
        let result = (|| -> Result<(), String> {
            let dir = cache_dir();
            let _ = std::fs::remove_dir_all(&dir);
            std::fs::create_dir_all(&dir).map_err(|e| format!("Can't make {}: {e}", dir.display()))?;
            let file = dir.join(url.rsplit('/').next().unwrap_or("update.pkg.tar.zst"));
            with(|s| {
                s.state = "downloading";
                s.progress = 0;
                s.message = String::new();
            });
            let mut child = Command::new("curl")
                .args(["-fL", "--proto", proto(), "--max-time", "900", "-sS", "-o"])
                .arg(&file)
                .arg(&url)
                .stderr(Stdio::piped())
                .spawn()
                .map_err(|e| format!("curl is not available: {e}"))?;
            loop {
                match child.try_wait().map_err(|e| e.to_string())? {
                    Some(status) if status.success() => break,
                    Some(_) => return Err("The download failed. Try again in a moment.".into()),
                    None => {
                        let have = std::fs::metadata(&file).map(|m| m.len()).unwrap_or(0);
                        if size > 0 {
                            with(|s| s.progress = ((have * 100) / size).min(99) as u32);
                        }
                        std::thread::sleep(std::time::Duration::from_millis(200));
                    }
                }
            }
            with(|s| s.progress = 100);
            // Checksum.
            let expected = curl_text(&sha_url).map_err(|_| "Couldn't fetch the checksum.".to_string())?;
            let expected = expected.split_whitespace().next().unwrap_or_default().to_lowercase();
            let sum = Command::new("sha256sum").arg(&file).output().map_err(|e| format!("sha256sum is not available: {e}"))?;
            let actual = String::from_utf8_lossy(&sum.stdout).split_whitespace().next().unwrap_or_default().to_lowercase();
            if expected.len() != 64 || expected != actual {
                return Err("The download didn't match its checksum, so it was not installed.".into());
            }
            // It must really be this program's package.
            let info = Command::new("pacman").arg("-Qp").arg(&file).output().map_err(|e| e.to_string())?;
            if String::from_utf8_lossy(&info.stdout).split_whitespace().next() != Some(PACKAGE) {
                return Err("The download isn't a Vox package, so it was not installed.".into());
            }
            if cfg!(debug_assertions) && std::env::var_os("VOX_UPDATE_DRY_RUN").is_some() {
                return Err("dry run: downloaded and verified, not installed".into()); // testing aid, debug builds only
            }
            // Install. The desktop's password prompt appears here.
            set("installing", "Waiting for your password...");
            let mut child = Command::new("pkexec")
                .args(["pacman", "-U", "--noconfirm"])
                .arg(&file)
                .stdout(Stdio::null())
                .stderr(Stdio::piped())
                .spawn()
                .map_err(|e| format!("Can't ask for permission (pkexec): {e}"))?;
            let status = child.wait().map_err(|e| e.to_string())?;
            let mut err = String::new();
            if let Some(mut e) = child.stderr.take() {
                let _ = e.read_to_string(&mut err);
            }
            let _ = std::fs::remove_dir_all(&dir);
            match status.code() {
                Some(0) => Ok(()),
                Some(126) | Some(127) => Err("The update was cancelled.".into()),
                _ => Err(format!("The install failed: {}", err.lines().last().unwrap_or("unknown error"))),
            }
        })();
        match result {
            Ok(()) => set("installed", "Updated. Restart to use the new version."),
            Err(e) => set("error", e),
        }
    });
}

/// Start the (new) program in a moment, once this one has quit.
pub fn restart() {
    let _ = Command::new("sh").args(["-c", &format!("sleep 1; exec {PACKAGE}")]).stdin(Stdio::null()).stdout(Stdio::null()).stderr(Stdio::null()).spawn();
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Needs a local server and a dry run (see Scripts/test_updater.sh): check, download and verify a fake release.
    #[test]
    #[ignore]
    fn the_whole_update_path_up_to_the_password_prompt() {
        check();
        for _ in 0..50 {
            std::thread::sleep(std::time::Duration::from_millis(100));
            if with(|s| s.state) != "checking" {
                break;
            }
        }
        let found = with(|s| s.clone());
        assert_eq!(found.state, "available", "check said {} {}", found.state, found.message);
        assert_eq!(found.latest, "9.0.0");
        install();
        let mut saw_download = false;
        for _ in 0..300 {
            std::thread::sleep(std::time::Duration::from_millis(100));
            let s = with(|s| s.clone());
            saw_download |= s.state == "downloading" || s.state == "installing";
            if matches!(s.state, "installed" | "error") {
                println!("final state {} / {}", s.state, s.message);
                assert!(saw_download);
                assert!(s.message.starts_with("dry run"), "stopped early: {}", s.message);
                return;
            }
        }
        panic!("never got past downloading");
    }

    #[test]
    fn versions_compare_by_number() {
        assert!(newer("0.2.0", "0.1.9"));
        assert!(newer("v1.0", "0.9.9"));
        assert!(newer("0.10.0", "0.9.0"));
        assert!(!newer("0.1.0", "0.1.0"));
        assert!(!newer("0.1", "0.1.0"));
        assert!(!newer("0.1.0", "0.2.0"));
    }

    #[test]
    fn a_release_needs_a_package_and_a_checksum() {
        let json = |assets: &str| format!(r#"{{"tag_name":"v9.0.0","body":"New things","assets":{assets}}}"#);
        let url = format!("https://github.com/{REPO}/releases/download/v9.0.0");
        let pkg = format!(r#"{{"name":"{PACKAGE}-9.0.0-1-x86_64.pkg.tar.zst","browser_download_url":"{url}/p.pkg.tar.zst","size":5}}"#);
        let sha = format!(r#"{{"name":"{PACKAGE}-9.0.0-1-x86_64.pkg.tar.zst.sha256","browser_download_url":"{url}/p.sha256"}}"#);
        let found = parse_release(&json(&format!("[{pkg},{sha}]"))).unwrap().expect("newer release is found");
        assert_eq!((found.latest.as_str(), found.size), ("9.0.0", 5));
        assert!(parse_release(&json(&format!("[{pkg}]"))).is_err(), "no checksum: not installable");
        assert!(parse_release(&json("[]")).is_err(), "no package: not installable");
        let evil = pkg.replace("https://github.com/", "https://example.com/");
        assert!(parse_release(&json(&format!("[{evil},{sha}]"))).is_err(), "foreign download host is refused");
        assert!(parse_release(r#"{"tag_name":"v0.0.1","assets":[]}"#).unwrap().is_none(), "older: nothing to do");
    }
}
