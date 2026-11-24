import QtQuick

// The frequency response of a parametric EQ (six cells, see src/peq.rs), drawn from the same filter formulas the
// engine runs. Small on a card, big with a grid in the editor.
Canvas {
    id: curve
    required property var app
    property var cells: []
    property bool on: true
    /// Output gain after the cells (dB): the whole curve moves up or down by it.
    property real gain: 0
    property bool grid: false
    /// The cell whose own curve is drawn too (editor), or -1.
    property int selected: -1
    readonly property real range: 18        // dB above and below the middle
    readonly property real rate: 48000

    function xOf(hz) { return Math.log(hz / 20) / Math.log(1000) * width; }
    function hzAt(x) { return 20 * Math.pow(1000, Math.max(0, Math.min(1, x / width))); }
    function yOf(db) { return height / 2 - db / range * (height / 2 - (grid ? 10 : 2)); }
    function dbAt(y) { return (height / 2 - y) / (height / 2 - (grid ? 10 : 2)) * range; }
    function gained(cell) { return cell.kind === "peak" || cell.kind === "lowshelf" || cell.kind === "highshelf"; }

    // Biquad coefficients [b0, b1, b2, a1, a2] for one cell, or null when it does nothing.
    function coefs(cell) {
        if (!cell.on || (gained(cell) && Math.abs(cell.db) < 0.05)) return null;
        const a = Math.pow(10, cell.db / 40);
        const w0 = 2 * Math.PI * Math.max(20, Math.min(rate * 0.45, cell.hz)) / rate;
        const sin = Math.sin(w0), cos = Math.cos(w0);
        const alpha = sin / (2 * Math.max(0.1, cell.q));
        const k = 2 * Math.sqrt(a) * alpha;
        let b0, b1, b2, a0, a1, a2;
        switch (cell.kind) {
        case "lowshelf":
            b0 = a * ((a + 1) - (a - 1) * cos + k); b1 = 2 * a * ((a - 1) - (a + 1) * cos); b2 = a * ((a + 1) - (a - 1) * cos - k);
            a0 = (a + 1) + (a - 1) * cos + k; a1 = -2 * ((a - 1) + (a + 1) * cos); a2 = (a + 1) + (a - 1) * cos - k; break;
        case "highshelf":
            b0 = a * ((a + 1) + (a - 1) * cos + k); b1 = -2 * a * ((a - 1) + (a + 1) * cos); b2 = a * ((a + 1) + (a - 1) * cos - k);
            a0 = (a + 1) - (a - 1) * cos + k; a1 = 2 * ((a - 1) - (a + 1) * cos); a2 = (a + 1) - (a - 1) * cos - k; break;
        case "highpass":
            b0 = (1 + cos) / 2; b1 = -(1 + cos); b2 = (1 + cos) / 2; a0 = 1 + alpha; a1 = -2 * cos; a2 = 1 - alpha; break;
        case "lowpass":
            b0 = (1 - cos) / 2; b1 = 1 - cos; b2 = (1 - cos) / 2; a0 = 1 + alpha; a1 = -2 * cos; a2 = 1 - alpha; break;
        case "notch":
            b0 = 1; b1 = -2 * cos; b2 = 1; a0 = 1 + alpha; a1 = -2 * cos; a2 = 1 - alpha; break;
        default:
            b0 = 1 + alpha * a; b1 = -2 * cos; b2 = 1 - alpha * a; a0 = 1 + alpha / a; a1 = -2 * cos; a2 = 1 - alpha / a;
        }
        return [b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0];
    }
    function gainDb(c, hz) {
        if (!c) return 0;
        const w = 2 * Math.PI * hz / rate, c1 = Math.cos(w), c2 = Math.cos(2 * w);
        const num = c[0] * c[0] + c[1] * c[1] + c[2] * c[2] + 2 * (c[0] * c[1] + c[1] * c[2]) * c1 + 2 * c[0] * c[2] * c2;
        const den = 1 + c[3] * c[3] + c[4] * c[4] + 2 * (c[3] + c[3] * c[4]) * c1 + 2 * c[4] * c2;
        return 10 * Math.log(Math.max(1e-12, num / den)) / Math.LN10;
    }

    onCellsChanged: requestPaint()
    onOnChanged: requestPaint()
    onGainChanged: requestPaint()
    onSelectedChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    readonly property color stroke: app.accent
    readonly property color strokeEnd: app.accentEnd
    readonly property color ink: app.ink
    onStrokeChanged: requestPaint()
    onStrokeEndChanged: requestPaint()
    onInkChanged: requestPaint()

    onPaint: {
        const ctx = getContext("2d");
        ctx.reset();
        const w = width, h = height;
        if (w < 4 || h < 4) return;
        if (grid) {
            ctx.lineWidth = 1;
            ctx.font = "10px sans-serif";
            for (const hz of [20, 30, 40, 50, 60, 70, 80, 90, 100, 200, 300, 400, 500, 600, 700, 800, 900, 1000, 2000, 3000, 4000, 5000, 6000, 7000, 8000, 9000, 10000, 20000]) {
                const major = hz === 100 || hz === 1000 || hz === 10000;
                ctx.strokeStyle = Qt.alpha(ink, major ? 0.16 : 0.06);
                const x = Math.round(xOf(hz)) + 0.5;
                ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, h); ctx.stroke();
            }
            ctx.fillStyle = Qt.alpha(ink, 0.45);
            for (const [hz, text] of [[50, "50"], [100, "100"], [200, "200"], [500, "500"], [1000, "1k"], [2000, "2k"], [5000, "5k"], [10000, "10k"]])
                ctx.fillText(text, xOf(hz) + 4, h - 5);
            for (let db = -12; db <= 12; db += 6) {
                ctx.strokeStyle = Qt.alpha(ink, db === 0 ? 0.28 : 0.08);
                const y = Math.round(yOf(db)) + 0.5;
                ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(w, y); ctx.stroke();
                ctx.fillText((db > 0 ? "+" : db < 0 ? "−" : "") + Math.abs(db) + " dB", 6, y - 4);
            }
        } else {
            ctx.strokeStyle = Qt.alpha(ink, 0.14);
            ctx.lineWidth = 1;
            const y0 = Math.round(h / 2) + 0.5;
            ctx.beginPath(); ctx.moveTo(0, y0); ctx.lineTo(w, y0); ctx.stroke();
        }

        const all = cells.map(c => coefs(c));
        const step = grid ? 2 : 1;
        const lift = gain;
        function trace(list) {
            ctx.beginPath();
            for (let x = 0; x <= w; x += step) {
                const hz = hzAt(x);
                let db = lift;
                for (const c of list) db += gainDb(c, hz);
                const y = Math.max(-4, Math.min(h + 4, yOf(db)));
                if (x === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
            }
        }
        const alive = on ? 1 : 0.35;
        if (grid && selected >= 0 && selected < all.length && all[selected]) {
            // The selected cell on its own, as a soft fill.
            trace([all[selected]]);
            ctx.lineTo(w, yOf(lift)); ctx.lineTo(0, yOf(lift)); ctx.closePath();
            ctx.fillStyle = Qt.alpha(strokeEnd, 0.16 * alive);
            ctx.fill();
        }
        if (Math.abs(lift) >= 0.05) {
            // Where "flat" now sits, so the lift or cut reads against the 0 dB line.
            const y = Math.round(yOf(lift)) + 0.5;
            ctx.strokeStyle = Qt.alpha(strokeEnd, 0.55 * alive);
            ctx.lineWidth = 1;
            ctx.setLineDash([5, 4]);
            ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(w, y); ctx.stroke();
            ctx.setLineDash([]);
            if (grid) {
                ctx.fillStyle = Qt.alpha(strokeEnd, 0.9 * alive);
                ctx.font = "bold 11px sans-serif";
                const text = "Output " + (lift > 0 ? "+" : "−") + Math.abs(lift).toFixed(1) + " dB";
                ctx.fillText(text, w - ctx.measureText(text).width - 12, lift > 0 ? y - 6 : y + 15);
            }
        }
        const sweep = ctx.createLinearGradient(0, 0, w, 0);
        sweep.addColorStop(0, Qt.alpha(stroke, alive));
        sweep.addColorStop(1, Qt.alpha(strokeEnd, alive));
        trace(all);
        ctx.lineTo(w, yOf(0)); ctx.lineTo(0, yOf(0)); ctx.closePath();
        ctx.fillStyle = Qt.alpha(stroke, (grid ? 0.10 : 0.16) * alive);
        ctx.fill();
        trace(all);
        ctx.strokeStyle = sweep;
        ctx.lineWidth = grid ? 2.5 : 1.5;
        ctx.lineJoin = "round";
        ctx.stroke();
    }
}
