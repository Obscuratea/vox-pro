// 1px outline (and optional fill) with 45-degree cut corners. The top edge can have up to two
// gaps (for titles set into the border line, btop style), each closed with a short tick.
import QtQuick
import QtQuick.Shapes

Shape {
    id: frame
    property real cut: 3
    property color stroke: "transparent"
    property color fill: "transparent"
    // gaps on the top edge: [start, end] in local x; set start < 0 to disable
    property real gap1Start: -1
    property real gap1End: -1
    property real gap2Start: -1
    property real gap2End: -1
    property real tick: 4

    readonly property real w: width - 0.5
    readonly property real h: height - 0.5
    readonly property real o: 0.5   // half-pixel offset: crisp 1px lines

    preferredRendererType: Shape.CurveRenderer
    antialiasing: true

    function outline() {
        const c = cut, o = frame.o, w = frame.w, h = frame.h
        return [Qt.point(w - c, o), Qt.point(w, o + c), Qt.point(w, h - c), Qt.point(w - c, h),
                Qt.point(o + c, h), Qt.point(o, h - c), Qt.point(o, o + c), Qt.point(o + c, o)]
    }
    // main stroke: from the end of the last gap, round the frame, to the start of the first gap
    function mainPath() {
        const pts = outline()
        const has1 = gap1Start >= 0, has2 = gap2Start >= 0
        const startX = has2 ? gap2End : (has1 ? gap1End : -1)
        const endX = has1 ? gap1Start : -1
        if (startX < 0)
            return pts.concat([pts[0]])
        return [Qt.point(startX, o)].concat(pts).concat([Qt.point(endX, o)])
    }

    ShapePath {
        strokeColor: "transparent"
        fillColor: frame.fill
        PathPolyline { path: frame.outline() }
    }
    ShapePath {
        strokeColor: frame.stroke
        strokeWidth: 1
        fillColor: "transparent"
        joinStyle: ShapePath.MiterJoin
        capStyle: ShapePath.FlatCap
        PathPolyline { path: frame.mainPath() }
    }
    // top-edge segment between the two gaps
    ShapePath {
        strokeColor: frame.gap1Start >= 0 && frame.gap2Start >= 0 ? frame.stroke : "transparent"
        strokeWidth: 1
        fillColor: "transparent"
        PathPolyline { path: [Qt.point(frame.gap1End, frame.o), Qt.point(Math.max(frame.gap1End, frame.gap2Start), frame.o)] }
    }
    // ticks closing each gap: the ┐title┌ look
    ShapePath {
        strokeColor: frame.gap1Start >= 0 ? frame.stroke : "transparent"
        strokeWidth: 1
        fillColor: "transparent"
        PathPolyline { path: [Qt.point(frame.gap1Start, frame.o + frame.tick), Qt.point(frame.gap1Start, frame.o)] }
    }
    ShapePath {
        strokeColor: frame.gap1Start >= 0 ? frame.stroke : "transparent"
        strokeWidth: 1
        fillColor: "transparent"
        PathPolyline { path: [Qt.point(frame.gap1End, frame.o), Qt.point(frame.gap1End, frame.o + frame.tick)] }
    }
    ShapePath {
        strokeColor: frame.gap2Start >= 0 ? frame.stroke : "transparent"
        strokeWidth: 1
        fillColor: "transparent"
        PathPolyline { path: [Qt.point(frame.gap2Start, frame.o + frame.tick), Qt.point(frame.gap2Start, frame.o)] }
    }
    ShapePath {
        strokeColor: frame.gap2Start >= 0 ? frame.stroke : "transparent"
        strokeWidth: 1
        fillColor: "transparent"
        PathPolyline { path: [Qt.point(frame.gap2End, frame.o), Qt.point(frame.gap2End, frame.o + frame.tick)] }
    }
}
