import QtQuick

// Small line icons drawn in a 24-unit box, so they take any colour and size without an icon theme.
Canvas {
    id: icon
    property string name
    property color color: "white"
    property real weight: 1.8
    implicitWidth: 18
    implicitHeight: 18
    onNameChanged: requestPaint()
    onColorChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
        const c = getContext("2d");
        c.reset();
        const k = Math.min(width, height) / 24;
        c.scale(k, k);
        c.strokeStyle = color;
        c.fillStyle = color;
        c.lineWidth = weight;
        c.lineCap = "round";
        c.lineJoin = "round";
        function line(p) { c.beginPath(); c.moveTo(p[0], p[1]); for (let i = 2; i < p.length; i += 2) c.lineTo(p[i], p[i + 1]); c.stroke(); }
        function ring(x, y, r) { c.beginPath(); c.arc(x, y, r, 0, 2 * Math.PI); c.stroke(); }
        function dot(x, y, r) { c.beginPath(); c.arc(x, y, r, 0, 2 * Math.PI); c.fill(); }
        function box(x, y, w, h, r) { c.beginPath(); c.roundedRect(x, y, w, h, r, r); c.stroke(); }
        switch (name) {
        case "mixer":
            line([6, 4, 6, 20]); line([12, 4, 12, 20]); line([18, 4, 18, 20]);
            line([3.5, 9, 8.5, 9]); line([9.5, 15, 14.5, 15]); line([15.5, 7, 20.5, 7]);
            break;
        case "grid":
            for (const x of [6, 12, 18]) for (const y of [6, 12, 18]) dot(x, y, 1.5);
            break;
        case "wave":
            c.beginPath(); c.moveTo(3, 14); c.bezierCurveTo(7, 14, 7, 6, 11, 8); c.bezierCurveTo(15, 10, 14, 17, 21, 10); c.stroke();
            break;
        case "gear":
            ring(12, 12, 3.2);
            for (let i = 0; i < 8; i++) { const a = i * Math.PI / 4; line([12 + 6.2 * Math.cos(a), 12 + 6.2 * Math.sin(a), 12 + 8.6 * Math.cos(a), 12 + 8.6 * Math.sin(a)]); }
            break;
        case "mic":
            box(9, 3, 6, 11, 3);
            c.beginPath(); c.arc(12, 11, 6, 0, Math.PI); c.stroke();
            line([12, 17, 12, 21]);
            break;
        case "app":
            box(3.5, 5, 17, 14, 3); line([3.5, 9.5, 20.5, 9.5]);
            break;
        case "out":
            c.beginPath(); c.arc(12, 13, 8, Math.PI, 2 * Math.PI); c.stroke();
            box(3, 13, 4, 7, 1.6); box(17, 13, 4, 7, 1.6);
            break;
        case "speaker":
            line([4, 9.5, 8, 9.5, 13, 5, 13, 19, 8, 14.5, 4, 14.5, 4, 9.5]);
            c.beginPath(); c.arc(14, 12, 4.5, -Math.PI / 4, Math.PI / 4); c.stroke();
            c.beginPath(); c.arc(14, 12, 8, -Math.PI / 4, Math.PI / 4); c.stroke();
            break;
        case "back":
            c.beginPath(); c.moveTo(19, 18); c.lineTo(19, 13); c.arcTo(19, 9, 15, 9, 4); c.lineTo(5, 9); c.stroke();
            line([9, 5, 5, 9, 9, 13]);
            break;
        case "send":
            line([4, 12, 19, 12]); line([14, 7, 19, 12, 14, 17]);
            break;
        case "plus":
            line([12, 5, 12, 19]); line([5, 12, 19, 12]);
            break;
        case "minus":
            line([5, 12, 19, 12]);
            break;
        case "x":
            line([6, 6, 18, 18]); line([18, 6, 6, 18]);
            break;
        case "panel":
            box(3.5, 4.5, 17, 15, 3); line([14.5, 4.5, 14.5, 19.5]);
            break;
        case "rows":
            line([4, 7, 20, 7]); line([4, 12, 20, 12]); line([4, 17, 20, 17]);
            break;
        case "pen":
            line([5, 19, 6, 15, 16, 5, 19, 8, 9, 18, 5, 19]);
            break;
        case "chev":
            line([9, 6, 15, 12, 9, 18]);
            break;
        case "look":
            ring(12, 12, 8.5);
            c.beginPath(); c.arc(12, 12, 8.5, Math.PI / 2, 3 * Math.PI / 2); c.closePath(); c.fill();
            break;
        case "bolt":
            line([13, 3, 5, 14, 11, 14, 10, 21, 18, 10, 12, 10, 13, 3]);
            break;
        case "key":
            box(3, 6, 18, 12, 3);
            dot(7, 10, 1); dot(11, 10, 1); dot(15, 10, 1); line([8, 14, 16, 14]);
            break;
        case "rec":
            ring(12, 12, 8.5); dot(12, 12, 4);
            break;
        case "plug":
            line([9, 3, 9, 8]); line([15, 3, 15, 8]);
            box(6, 8, 12, 6, 2);
            c.beginPath(); c.moveTo(8, 14); c.quadraticCurveTo(12, 20, 12, 21); c.moveTo(16, 14); c.quadraticCurveTo(12, 20, 12, 21); c.stroke();
            break;
        case "logo":
            c.lineWidth = 2.6;
            line([4, 6, 4, 11]); line([8, 6, 8, 15]); line([12, 6, 12, 19]); line([16, 6, 16, 15]); line([20, 6, 20, 11]);
            break;
        }
    }
}
