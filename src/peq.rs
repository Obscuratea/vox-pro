//! Parametric EQ: six cells in series, each a biquad (RBJ cookbook) with its own type, frequency, gain and Q.
//! The same file is used by Vox Obscurus and Vox Pro. qml/PeqEditor.qml draws the curve with the same formulas.

use crate::dsp::SAMPLE_RATE;
use serde::{Deserialize, Serialize};

pub const CELLS: usize = 6;

/// One cell as it is saved. `kind` is "peak", "lowshelf", "highshelf", "highpass", "lowpass" or "notch".
#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct Cell {
    pub on: bool,
    pub kind: String,
    pub hz: f32,
    pub db: f32,
    pub q: f32,
}

impl Default for Cell {
    fn default() -> Self {
        Self { on: true, kind: "peak".into(), hz: 1000.0, db: 0.0, q: 1.0 }
    }
}

/// The cells a new EQ starts with: flat, a shelf at each end and four bells between them.
pub fn default_cells() -> Vec<Cell> {
    let cell = |kind: &str, hz: f32, q: f32| Cell { on: true, kind: kind.into(), hz, db: 0.0, q };
    vec![
        cell("lowshelf", 80.0, 0.71),
        cell("peak", 200.0, 1.0),
        cell("peak", 600.0, 1.0),
        cell("peak", 2000.0, 1.0),
        cell("peak", 5000.0, 1.0),
        cell("highshelf", 10_000.0, 0.71),
    ]
}

/// Bring saved cells into range, and to exactly `CELLS` of them.
pub fn sanitize(cells: &mut Vec<Cell>) {
    let defaults = default_cells();
    cells.truncate(CELLS);
    cells.extend(defaults[cells.len()..].iter().cloned());
    for cell in cells.iter_mut() {
        if !matches!(cell.kind.as_str(), "peak" | "lowshelf" | "highshelf" | "highpass" | "lowpass" | "notch") {
            cell.kind = "peak".into();
        }
        cell.hz = if cell.hz.is_finite() { cell.hz.clamp(20.0, 20_000.0) } else { 1000.0 };
        cell.db = if cell.db.is_finite() { cell.db.clamp(-18.0, 18.0) } else { 0.0 };
        cell.q = if cell.q.is_finite() { cell.q.clamp(0.3, 12.0) } else { 1.0 };
    }
}

/// Normalised biquad coefficients (a0 = 1).
#[derive(Clone, Copy, PartialEq)]
struct Coefs {
    b0: f64,
    b1: f64,
    b2: f64,
    a1: f64,
    a2: f64,
}

const FLAT: Coefs = Coefs { b0: 1.0, b1: 0.0, b2: 0.0, a1: 0.0, a2: 0.0 };

fn coefs(cell: &Cell) -> Coefs {
    let gained = matches!(cell.kind.as_str(), "peak" | "lowshelf" | "highshelf");
    if !cell.on || (gained && cell.db.abs() < 0.05) {
        return FLAT;
    }
    let a = 10f64.powf(cell.db as f64 / 40.0);
    let w0 = 2.0 * std::f64::consts::PI * (cell.hz as f64).clamp(20.0, SAMPLE_RATE as f64 * 0.45) / SAMPLE_RATE as f64;
    let (sin, cos) = w0.sin_cos();
    let alpha = sin / (2.0 * (cell.q as f64).max(0.1));
    let k = 2.0 * a.sqrt() * alpha;
    let (b0, b1, b2, a0, a1, a2) = match cell.kind.as_str() {
        "lowshelf" => (
            a * ((a + 1.0) - (a - 1.0) * cos + k),
            2.0 * a * ((a - 1.0) - (a + 1.0) * cos),
            a * ((a + 1.0) - (a - 1.0) * cos - k),
            (a + 1.0) + (a - 1.0) * cos + k,
            -2.0 * ((a - 1.0) + (a + 1.0) * cos),
            (a + 1.0) + (a - 1.0) * cos - k,
        ),
        "highshelf" => (
            a * ((a + 1.0) + (a - 1.0) * cos + k),
            -2.0 * a * ((a - 1.0) + (a + 1.0) * cos),
            a * ((a + 1.0) + (a - 1.0) * cos - k),
            (a + 1.0) - (a - 1.0) * cos + k,
            2.0 * ((a - 1.0) - (a + 1.0) * cos),
            (a + 1.0) - (a - 1.0) * cos - k,
        ),
        "highpass" => ((1.0 + cos) / 2.0, -(1.0 + cos), (1.0 + cos) / 2.0, 1.0 + alpha, -2.0 * cos, 1.0 - alpha),
        "lowpass" => ((1.0 - cos) / 2.0, 1.0 - cos, (1.0 - cos) / 2.0, 1.0 + alpha, -2.0 * cos, 1.0 - alpha),
        "notch" => (1.0, -2.0 * cos, 1.0, 1.0 + alpha, -2.0 * cos, 1.0 - alpha),
        _ => (1.0 + alpha * a, -2.0 * cos, 1.0 - alpha * a, 1.0 + alpha / a, -2.0 * cos, 1.0 - alpha / a),
    };
    Coefs { b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0 }
}

/// The running filter for one strip or bus. Changing the cells keeps the filter state, so edits don't click.
pub struct Peq {
    on: bool,
    coefs: [Coefs; CELLS],
    /// Cells that do something; the flat ones are skipped.
    active: [bool; CELLS],
    z1: [[f64; 2]; CELLS],
    z2: [[f64; 2]; CELLS],
}

impl Default for Peq {
    fn default() -> Self {
        Self { on: false, coefs: [FLAT; CELLS], active: [false; CELLS], z1: [[0.0; 2]; CELLS], z2: [[0.0; 2]; CELLS] }
    }
}

impl Peq {
    pub fn set(&mut self, on: bool, cells: &[Cell]) {
        self.on = on;
        for i in 0..CELLS {
            let c = cells.get(i).map_or(FLAT, coefs);
            self.coefs[i] = c;
            let active = on && c != FLAT;
            if !active && self.active[i] {
                self.z1[i] = [0.0; 2];
                self.z2[i] = [0.0; 2];
            }
            self.active[i] = active;
        }
    }

    pub fn is_on(&self) -> bool {
        self.on && self.active.iter().any(|&a| a)
    }

    pub fn process(&mut self, frame: [f32; 2]) -> [f32; 2] {
        let mut out = [frame[0] as f64, frame[1] as f64];
        for i in 0..CELLS {
            if !self.active[i] {
                continue;
            }
            let c = &self.coefs[i];
            for ch in 0..2 {
                let x = out[ch];
                let y = c.b0 * x + self.z1[i][ch];
                self.z1[i][ch] = c.b1 * x - c.a1 * y + self.z2[i][ch];
                self.z2[i][ch] = c.b2 * x - c.a2 * y;
                out[ch] = y;
            }
        }
        [out[0] as f32, out[1] as f32]
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// Gain (dB) a steady tone comes out with.
    fn measured_db(cells: &[Cell], hz: f32) -> f32 {
        let mut eq = Peq::default();
        eq.set(true, cells);
        let n = SAMPLE_RATE as usize;
        let mut sum = 0.0f64;
        for i in 0..n {
            let x = 0.1 * (2.0 * std::f32::consts::PI * hz * i as f32 / SAMPLE_RATE).sin();
            let y = eq.process([x, x])[0];
            if i >= n / 2 {
                sum += (y as f64).powi(2);
            }
        }
        let rms = (sum / (n / 2) as f64).sqrt();
        20.0 * (rms / (0.1 / std::f64::consts::SQRT_2)).log10() as f32
    }

    fn one(kind: &str, hz: f32, db: f32, q: f32) -> Vec<Cell> {
        let mut cells = default_cells();
        cells[2] = Cell { on: true, kind: kind.into(), hz, db, q };
        cells
    }

    #[test]
    fn flat_cells_change_nothing() {
        let mut eq = Peq::default();
        eq.set(true, &default_cells());
        assert!(!eq.is_on());
        assert_eq!(eq.process([0.25, -0.5]), [0.25, -0.5]);
    }

    #[test]
    fn a_bell_boosts_its_centre_and_a_narrow_one_leaves_neighbours() {
        assert!((measured_db(&one("peak", 1000.0, 9.0, 1.0), 1000.0) - 9.0).abs() < 0.2);
        assert!((measured_db(&one("peak", 1000.0, -12.0, 1.0), 1000.0) + 12.0).abs() < 0.2);
        let wide = measured_db(&one("peak", 1000.0, 9.0, 0.5), 2000.0);
        let narrow = measured_db(&one("peak", 1000.0, 9.0, 8.0), 2000.0);
        assert!(wide > 3.0 && narrow < 0.5, "wide {wide} dB, narrow {narrow} dB an octave up");
    }

    #[test]
    fn shelves_lift_their_side_only() {
        let low = one("lowshelf", 200.0, 6.0, 0.71);
        assert!((measured_db(&low, 40.0) - 6.0).abs() < 0.4 && measured_db(&low, 5000.0).abs() < 0.2);
        let high = one("highshelf", 4000.0, -6.0, 0.71);
        assert!((measured_db(&high, 16_000.0) + 6.0).abs() < 0.4 && measured_db(&high, 200.0).abs() < 0.2);
    }

    #[test]
    fn pass_filters_and_notch_cut_where_they_should() {
        assert!(measured_db(&one("highpass", 200.0, 0.0, 0.71), 50.0) < -20.0);
        assert!(measured_db(&one("highpass", 200.0, 0.0, 0.71), 2000.0).abs() < 0.2);
        assert!(measured_db(&one("lowpass", 2000.0, 0.0, 0.71), 16_000.0) < -30.0);
        assert!(measured_db(&one("notch", 1000.0, 0.0, 4.0), 1000.0) < -40.0);
        assert!(measured_db(&one("notch", 1000.0, 0.0, 4.0), 250.0).abs() < 0.3);
    }

    #[test]
    fn a_cell_that_is_off_or_an_eq_that_is_off_is_skipped() {
        let mut cells = one("peak", 1000.0, 9.0, 1.0);
        cells[2].on = false;
        assert!(measured_db(&cells, 1000.0).abs() < 0.01);
        let mut eq = Peq::default();
        eq.set(false, &one("peak", 1000.0, 9.0, 1.0));
        assert_eq!(eq.process([0.25, 0.25]), [0.25, 0.25]);
    }

    #[test]
    fn saved_cells_are_brought_into_range() {
        let mut cells = vec![Cell { on: true, kind: "weird".into(), hz: 5.0, db: 99.0, q: f32::NAN }];
        sanitize(&mut cells);
        assert_eq!(cells.len(), CELLS);
        assert_eq!((cells[0].kind.as_str(), cells[0].hz, cells[0].db, cells[0].q), ("peak", 20.0, 18.0, 1.0));
    }
}
