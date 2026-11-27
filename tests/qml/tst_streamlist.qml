import QtQuick
import QtTest
import "../../qml"

Item {
    id: win; width: 760; height: 420
    QtObject {
        id: fakeApp
        property var streams: [
            { id: 7, name: "Audio 10 - Out 1/2 (Main)", icon: "", target: "here", muted: false, device: true },
            { id: 8, name: "Spotify", icon: "", target: "here", muted: false, device: false },
            { id: 9, name: "Audio 10 - Out 3/4", icon: "", target: "other", muted: false, device: true }
        ]
        property color accent: "#e040a0"; property color accentEnd: "#a040e0"; property color accentInk: "white"
        property color controlEdge: "#444"; property color danger: "red"; property color dim: "#888"; property color edge: "#555"
        property color frameDim: "#333"; property color hover: "#2a2a3a"; property color ink: "white"; property color line: "#444"
        property color line2: "#666"; property color card2: "#333"
        property color onFill: "white"; property color select: "#404"; property color tonal: "#303040"
        property bool cut: false; property bool diamond: false; property bool mono: false; property bool soft: true
        property real rChip: 12
        property var sent: []
        function t(s) { return s }
        function muteStream(id, m) {}
        function sendBack(id, name) { sent = sent.concat([id]) }
    }
    Rectangle {
        x: 440; y: 40; width: 300; height: 100; clip: true; color: "#202030"
        StreamList { id: here; x: 10; y: 10; width: 280; height: 74; app: fakeApp; target: "here" }
    }
    Rectangle {
        x: 440; y: 200; width: 300; height: 60; clip: true; color: "#202030"
        StreamList { id: other; x: 10; y: 10; width: 280; height: 34; app: fakeApp; target: "other" }
    }
    DropArea {
        id: strip; x: 20; y: 40; width: 120; height: 300
        keys: ["vox-stream"]
        property var got: null
        onDropped: drop => got = drop.source.stream
    }
    TestCase {
        name: "StreamList"; when: windowShown
        function pill(list, i) { return list.children[1].itemAtIndex(i).children[0]; }
        function find(item, pred) {
            if (pred(item)) return item;
            for (let k = 0; k < item.children.length; k++) { const r = find(item.children[k], pred); if (r) return r; }
            return null;
        }
        function backButton(p) { return find(p, c => c.icon === "back"); }
        function init() { fakeApp.sent = []; strip.got = null; }
        function drag(p, toX, toY) {          // from inside the pill to a point in window coordinates
            const s = p.mapToItem(win, 0, 0);
            mousePress(p, 40, 17);
            const steps = 25;
            for (let i = 1; i <= steps; i++) { mouseMove(p, 40 + (toX - s.x - 40) * i / steps, 17 + (toY - s.y - 17) * i / steps); wait(5); }
            mouseRelease(p, toX - s.x, toY - s.y);
            wait(50);
        }
        function test_badges_and_buttons() {
            const dev = pill(here, 0), app = pill(here, 1), far = pill(other, 0);
            verify(find(dev, c => c.name === "speaker" && c.visible), "device stream shows the speaker badge");
            verify(!find(app, c => c.name === "speaker" && c.visible), "a program has no speaker badge");
            verify(backButton(dev).visible, "send-back button in Playing here");
            verify(backButton(app).visible);
            verify(!backButton(far).visible, "no send-back in Playing elsewhere");
            compare(backButton(dev).tip, "Send Audio 10 - Out 1/2 (Main) back to its sound card");
            compare(backButton(app).tip, "Send Spotify back to the default output");
        }
        function test_button_sends_back() {
            const b = backButton(pill(here, 0));
            mouseClick(b);
            compare(fakeApp.sent, [7]);
        }
        function test_drag_out_sends_back() {
            const p = pill(here, 0);
            drag(p, 300, 380);                // empty space: not the list, not a strip
            compare(fakeApp.sent, [7]);
            compare(strip.got, null);
            const after = p.mapToItem(win, 0, 0);
            compare(after.x, 450); compare(after.y, 50);
        }
        function test_drag_onto_strip_moves_only() {
            drag(pill(here, 1), 80, 150);
            verify(strip.got !== null, "strip got the drop");
            compare(strip.got.id, 8);
            compare(fakeApp.sent, []);
        }
        function test_short_drag_inside_list_does_nothing() {
            const p = pill(here, 1);
            mousePress(p, 60, 17);
            for (let i = 1; i <= 8; i++) { mouseMove(p, 60 - i * 4, 17); wait(5); }
            mouseRelease(p, 28, 17); wait(50);
            compare(fakeApp.sent, []); compare(strip.got, null);
        }
        function test_elsewhere_drag_out_does_nothing() {
            drag(pill(other, 0), 300, 380);
            compare(fakeApp.sent, []);
        }
    }
}
