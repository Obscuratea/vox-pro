import QtQuick

// The looks Vox can wear. "default" is the Vox logo look; "system" follows the Plasma colour scheme; the rest bring their own colours.
// style is "soft" (rounded, tonal), "diamond" (violet outlines, cut corners) or "sharp" (square, outlined).
QtObject {
    readonly property var list: [
        // The Vox look: the logo's night-violet panel, magenta-to-violet fader fills, rounded knobs.
        { id: "default", name: "Default", note: "Vox logo · dark", style: "soft",
          window: "#170e30", text: "#efe9ff", highlight: "#33245c", highlightedText: "#f4ecff",
          accent: "#ff4fd8", accentEnd: "#8b5cff" },
        { id: "system", name: "Follow system", note: "Plasma colours", style: "auto" },
        { id: "matos-dark", name: "Lavender", note: "Soft · dark", style: "soft",
          window: "#201f25", text: "#e3e1ea", highlight: "#52348e", highlightedText: "#e5defe", accent: "#ccbdff" },
        { id: "matos-light", name: "Lavender Light", note: "Soft · light", style: "soft",
          window: "#eeedf6", text: "#1c1b21", highlight: "#e5defe", highlightedText: "#280056", accent: "#694da9" },
        { id: "diamond", name: "Crystal", note: "Outlined · dark", style: "diamond",
          window: "#1f122a", text: "#efe9f5", highlight: "#4b3a85", highlightedText: "#efe9f5", accent: "#77acff" },
        { id: "obscura-dark", name: "Mint", note: "Sharp · dark", style: "sharp",
          window: "#121316", text: "#f2f1ee", highlight: "#00aa88", highlightedText: "#101014", accent: "#00aa88" },
        { id: "obscura-light", name: "Mint Light", note: "Sharp · light", style: "sharp",
          window: "#f2f1ee", text: "#101014", highlight: "#00aa88", highlightedText: "#101014", accent: "#00aa88" },
        // OLED: true black window so the pixels switch off, boxes are outlines (outline: true); the gradient runs light grey to mid grey, no colour.
        { id: "pureblack", name: "Pure Black", note: "OLED · dark", style: "soft", outline: true,
          window: "#000000", text: "#ececec", highlight: "#2b2b2b", highlightedText: "#f5f5f5",
          accent: "#e4e4e4", accentEnd: "#7d7d7d" }
    ]

    function find(id) {
        for (const t of list)
            if (t.id === id)
                return t;
        return null;
    }
}
