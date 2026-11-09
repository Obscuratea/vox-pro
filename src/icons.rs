//! Finds a program's icon file in the user's Plasma icon theme (and the themes it inherits from),
//! so the UI can show it without depending on Qt having the same theme loaded.

use std::path::{Path, PathBuf};

fn search_dirs() -> Vec<PathBuf> {
    let home = std::env::var_os("HOME").map(PathBuf::from).unwrap_or_default();
    vec![home.join(".local/share/icons"), home.join(".icons"), PathBuf::from("/usr/share/icons")]
}

/// The icon theme named in Plasma's settings.
fn current_theme() -> Option<String> {
    let home = std::env::var_os("HOME")?;
    let text = std::fs::read_to_string(Path::new(&home).join(".config/kdeglobals")).ok()?;
    let mut in_icons = false;
    for line in text.lines() {
        if line.starts_with('[') {
            in_icons = line.trim() == "[Icons]";
        } else if in_icons && let Some(name) = line.strip_prefix("Theme=") {
            return Some(name.trim().to_string());
        }
    }
    None
}

/// The theme, then everything it inherits from, ending in hicolor.
fn theme_chain(dirs: &[PathBuf]) -> Vec<String> {
    let mut chain: Vec<String> = Vec::new();
    let mut queue: Vec<String> = current_theme().into_iter().collect();
    while let Some(theme) = queue.pop() {
        if chain.contains(&theme) || chain.len() > 8 {
            continue;
        }
        let parents = dirs
            .iter()
            .find_map(|dir| std::fs::read_to_string(dir.join(&theme).join("index.theme")).ok())
            .and_then(|text| text.lines().find_map(|l| l.strip_prefix("Inherits=").map(str::to_string)))
            .unwrap_or_default();
        chain.push(theme);
        queue.extend(parents.split(',').filter(|p| !p.is_empty()).map(|p| p.trim().to_string()).rev());
    }
    if !chain.iter().any(|t| t == "hicolor") {
        chain.push("hicolor".into());
    }
    chain
}

/// Themes lay icons out as `apps/48/name.svg` or `48x48/apps/name.png`. Prefer a vector, else the biggest.
fn find_in_theme(theme_dir: &Path, name: &str) -> Option<PathBuf> {
    let subdirs = |dir: &Path| -> Vec<(String, PathBuf)> {
        std::fs::read_dir(dir)
            .into_iter()
            .flatten()
            .flatten()
            .filter(|e| e.path().is_dir())
            .map(|e| (e.file_name().to_string_lossy().into_owned(), e.path()))
            .collect()
    };
    let mut best: Option<(u32, PathBuf)> = None;
    for (first, first_path) in subdirs(theme_dir) {
        for (second, second_path) in subdirs(&first_path) {
            if first != "apps" && second != "apps" {
                continue;
            }
            let size = if first == "apps" { &second } else { &first };
            let rank = if size.contains("scalable") {
                u32::MAX
            } else {
                size.chars().filter(char::is_ascii_digit).collect::<String>().parse().unwrap_or(0)
            };
            for ext in ["svg", "png"] {
                let file = second_path.join(format!("{name}.{ext}"));
                if file.is_file() && best.as_ref().is_none_or(|(r, _)| rank > *r) {
                    best = Some((rank, file));
                }
            }
        }
    }
    best.map(|(_, path)| path)
}

/// The icon file for an icon name, as a file:// URL, or an empty string when there isn't one.
pub fn lookup(name: &str) -> String {
    if name.is_empty() || name.contains('/') {
        return String::new();
    }
    let dirs = search_dirs();
    for theme in theme_chain(&dirs) {
        for dir in &dirs {
            if let Some(path) = find_in_theme(&dir.join(&theme), name) {
                return format!("file://{}", path.display());
            }
        }
    }
    let pixmap = PathBuf::from(format!("/usr/share/pixmaps/{name}.png"));
    if pixmap.is_file() { format!("file://{}", pixmap.display()) } else { String::new() }
}
