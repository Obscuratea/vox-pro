//! Bits of the desktop around Vox: starting with the computer (an entry in ~/.config/autostart) and
//! noticing the screen lock (org.freedesktop.ScreenSaver, which KDE and GNOME both offer on the session bus).

use crate::engine::Shared;
use std::path::PathBuf;
use std::sync::Arc;
use zbus::blocking::{Connection, MessageIterator};
use zbus::message::Type;
use zbus::MatchRule;

fn autostart_file() -> Option<PathBuf> {
    let base = std::env::var_os("XDG_CONFIG_HOME")
        .map(PathBuf::from)
        .or_else(|| std::env::var_os("HOME").map(|h| PathBuf::from(h).join(".config")))?;
    Some(base.join("autostart").join(format!("{}.desktop", crate::APP_ID)))
}

/// What the autostart entry says: run this program, as installed (or as built, when run from a build).
fn autostart_entry(exe: &str) -> String {
    format!(
        "[Desktop Entry]\nType=Application\nName={name}\nComment=Started with the computer by {name}\nExec=\"{exe}\"\nIcon={id}\nTerminal=false\nX-GNOME-Autostart-enabled=true\nX-KDE-autostart-phase=2\n",
        name = crate::APP_NAME,
        id = crate::APP_ID,
    )
}

/// Add or remove the autostart entry so it matches the setting. Only touches the file when it has to.
pub fn set_autostart(on: bool) {
    let Some(file) = autostart_file() else { return };
    if !on {
        if file.exists() {
            let _ = std::fs::remove_file(&file);
        }
        return;
    }
    let Some(exe) = std::env::current_exe().ok().and_then(|p| p.to_str().map(String::from)) else { return };
    let wanted = autostart_entry(&exe);
    if std::fs::read_to_string(&file).ok().as_deref() == Some(wanted.as_str()) {
        return;
    }
    if let Some(dir) = file.parent() {
        let _ = std::fs::create_dir_all(dir);
    }
    if let Err(e) = std::fs::write(&file, wanted) {
        eprintln!("{}: could not write {}: {e}", crate::APP_ID, file.display());
    }
}

/// Watch the screen lock and tell the UI ("screen-locked" / "screen-unlocked" in the event list).
pub fn watch_lock(shared: Arc<Shared>) {
    let _ = std::thread::Builder::new().name("vox-lock".into()).spawn(move || {
        let Ok(conn) = Connection::session() else { return };
        let Some(rule) = MatchRule::builder()
            .msg_type(Type::Signal)
            .interface("org.freedesktop.ScreenSaver")
            .ok()
            .and_then(|r| r.member("ActiveChanged").ok())
            .map(|r| r.build())
        else {
            return;
        };
        let Ok(messages) = MessageIterator::for_match_rule(rule, &conn, None) else { return };
        for message in messages.flatten() {
            let Ok(locked) = message.body().deserialize::<bool>() else { continue };
            shared.events.lock().unwrap().push(if locked { "screen-locked" } else { "screen-unlocked" }.into());
        }
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_autostart_entry_runs_this_program() {
        let entry = autostart_entry("/usr/bin/vox");
        assert!(entry.starts_with("[Desktop Entry]\n"));
        assert!(entry.contains("Exec=\"/usr/bin/vox\"\n"));
        assert!(entry.contains(&format!("Name={}\n", crate::APP_NAME)));
    }
}
