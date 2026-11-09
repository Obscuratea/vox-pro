//! Global shortcuts (push to talk, mute the mics) through KDE's shortcut service, KGlobalAccel,
//! the same service System Settings > Shortcuts edits. The service stores the keys, so they survive
//! restarts and show up in System Settings under "Vox Pro". Wayland apps can't grab keys
//! themselves, which is why this goes over D-Bus. On other desktops there is no such service and the
//! settings simply say shortcuts aren't available.
//!
//! A key is a Qt key code: the key plus its modifier flags (Shift 0x02000000, Ctrl 0x04000000,
//! Alt 0x08000000, Meta 0x10000000), which is what QML's key events give.

use crate::engine::Shared;
use std::sync::Arc;
use std::sync::atomic::Ordering;
use zbus::blocking::{Connection, MessageIterator};
use zbus::message::Type;
use zbus::MatchRule;

const COMPONENT: &str = "vox-pro";
const SERVICE: &str = "org.kde.kglobalaccel";
const ACCEL_PATH: &str = "/kglobalaccel";
const ACCEL: &str = "org.kde.KGlobalAccel";
const COMPONENT_IFACE: &str = "org.kde.kglobalaccel.Component";

/// (action id, label shown in System Settings)
pub const ACTIONS: [(&str, &str); 2] = [("ptt", "Push to talk"), ("mute-mics", "Mute or unmute the microphones")];

pub struct Accel {
    conn: Connection,
    component: String,
}

fn action_id(component: &str, name: &str) -> Option<Vec<String>> {
    let (_, label) = ACTIONS.iter().find(|(id, _)| *id == name)?;
    Some(vec![component.into(), name.into(), "Vox Pro".into(), (*label).into()])
}

/// KGlobalAccel's object path for a component: its name with dots and dashes turned into underscores.
fn component_path(component: &str) -> String {
    format!("/component/{}", component.replace(['-', '.'], "_"))
}

impl Accel {
    pub fn start(shared: Arc<Shared>) -> Option<Accel> {
        Self::start_as(COMPONENT, shared)
    }

    /// Register the actions (the service gives back any key already stored for them) and start
    /// listening for presses. None when there is no KGlobalAccel on the bus.
    fn start_as(component: &str, shared: Arc<Shared>) -> Option<Accel> {
        let conn = Connection::session().ok()?;
        for (name, _) in ACTIONS {
            conn.call_method(Some(SERVICE), ACCEL_PATH, Some(ACCEL), "doRegister", &action_id(component, name)?).ok()?;
        }
        let listener = Connection::session().ok()?;
        let rule = MatchRule::builder()
            .msg_type(Type::Signal)
            .interface(COMPONENT_IFACE)
            .ok()?
            .path(component_path(component))
            .ok()?
            .build();
        let messages = MessageIterator::for_match_rule(rule, &listener, None).ok()?;
        std::thread::Builder::new()
            .name("vox-shortcuts".into())
            .spawn(move || {
                let _keep = listener;
                for message in messages.flatten() {
                    let header = message.header();
                    let Some(member) = header.member() else { continue };
                    let Ok((_, action, _)) = message.body().deserialize::<(String, String, i64)>() else { continue };
                    on_signal(&shared, member.as_str(), &action);
                }
            })
            .ok()?;
        Some(Accel { conn, component: component.into() })
    }

    /// The key currently bound to an action, 0 for none.
    pub fn key(&self, name: &str) -> i32 {
        let Some(id) = action_id(&self.component, name) else { return 0 };
        self.conn
            .call_method(Some(SERVICE), ACCEL_PATH, Some(ACCEL), "shortcut", &id)
            .ok()
            .and_then(|reply| reply.body().deserialize::<Vec<i32>>().ok())
            .and_then(|keys| keys.first().copied())
            .unwrap_or(0)
    }

    /// Bind a key (0 clears it). Returns what ended up bound, or -1 when the key is already used by
    /// the other Vox action or by another program's global shortcut (nothing is changed then).
    pub fn set_key(&self, name: &str, key: i32) -> i32 {
        let Some(id) = action_id(&self.component, name) else { return 0 };
        if key != 0 {
            let taken_here = ACTIONS.iter().any(|(other, _)| *other != name && self.key(other) == key);
            let free_elsewhere = self
                .conn
                .call_method(Some(SERVICE), ACCEL_PATH, Some(ACCEL), "isGlobalShortcutAvailable", &(key, self.component.as_str()))
                .ok()
                .and_then(|reply| reply.body().deserialize::<bool>().ok())
                .unwrap_or(true);
            if taken_here || !free_elsewhere {
                return -1;
            }
        }
        let keys: Vec<i32> = if key == 0 { Vec::new() } else { vec![key] };
        // 2 = the action is present, 4 = don't reload the old binding over this one.
        let flags: u32 = 2 | 4;
        self.conn
            .call_method(Some(SERVICE), ACCEL_PATH, Some(ACCEL), "setShortcut", &(id, keys, flags))
            .ok()
            .and_then(|reply| reply.body().deserialize::<Vec<i32>>().ok())
            .and_then(|keys| keys.first().copied())
            .unwrap_or(0)
    }
}

fn on_signal(shared: &Shared, member: &str, action: &str) {
    match (member, action) {
        ("globalShortcutPressed", "ptt") => shared.ptt_held.store(true, Ordering::Relaxed),
        ("globalShortcutReleased", "ptt") => shared.ptt_held.store(false, Ordering::Relaxed),
        ("globalShortcutPressed", "mute-mics") => shared.events.lock().unwrap().push("mute-mics".into()),
        _ => {}
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Needs KDE's shortcut service on the session bus, so it only runs on request:
    /// cargo test shortcuts -- --ignored
    #[test]
    #[ignore]
    fn keys_bind_and_presses_arrive() {
        let shared = Arc::new(Shared::new());
        let name = "vox-pro-selftest";
        let accel = Accel::start_as(name, shared.clone()).expect("KGlobalAccel is running");
        let key = 0x04000000 | 0x08000000 | 0x0100003b; // Ctrl+Alt+F12
        assert_eq!(accel.set_key("ptt", key), key, "the key should be accepted");
        assert_eq!(accel.key("ptt"), key);
        // The same key for a second action must be refused.
        assert_eq!(accel.set_key("mute-mics", key), -1, "one key can't drive two actions");
        assert_eq!(accel.key("ptt"), key);
        assert_eq!(accel.set_key("mute-mics", 0x04000000 | 0x08000000 | 0x0100003a), 0x0D00003A);
        // A press from the service reaches us (invokeShortcut makes the service send one).
        accel
            .conn
            .call_method(Some(SERVICE), component_path(name).as_str(), Some(COMPONENT_IFACE), "invokeShortcut", &"mute-mics")
            .unwrap();
        std::thread::sleep(std::time::Duration::from_millis(500));
        assert_eq!(shared.events.lock().unwrap().as_slice(), ["mute-mics"]);
        // Tidy up so the test leaves nothing in the user's shortcut settings.
        for (action, _) in ACTIONS {
            let _ = accel.conn.call_method(Some(SERVICE), ACCEL_PATH, Some(ACCEL), "unregister", &(name, action));
        }
    }
}
