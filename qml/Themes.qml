import QtQuick

// The four looks Vox wears. All of them are soft (rounded, gradient fills); Glass leaves the window see-through
// and lets the compositor blur the desktop behind it.
QtObject {
    readonly property var list: [
        // Night: the Vox logo look, night violet with magenta-to-violet fills.
        { id: "night", name: "Night", note: "Dark", style: "soft",
          window: "#120c24", text: "#f3efff", highlight: "#2c2152", highlightedText: "#ffffff",
          accent: "#ff4fd8", accentEnd: "#8b5cff" },
        // Glass: a dark, see-through window over the blurred desktop, faint white cards, blue-to-violet fills.
        { id: "glass", name: "Glass", note: "Dark · see-through", style: "soft",
          gradient: ["#161233", "#1d1440"], windowAlpha: 0.74, cardFill: "#ffffff", cardAlpha: 0.07, cardEdge: "#ffffff", edgeAlpha: 0.13,
          tonalFill: "#ffffff", tonalAlpha: 0.08, wash: 0.66,
          window: "#18133a", text: "#f3efff", highlight: "#332c6e", highlightedText: "#ffffff",
          accent: "#7c8cff", accentEnd: "#c26dff" },
        // Light: pale lavender with white cards.
        { id: "light", name: "Light", note: "Light", style: "soft",
          window: "#f4f2fb", text: "#1a1530", highlight: "#e6dffa", highlightedText: "#ffffff",
          accent: "#d43fc0", accentEnd: "#6f4dff" },
        // Gold: near black with warm gold fills.
        { id: "gold", name: "Gold", note: "Dark · warm", style: "soft",
          window: "#0d0c09", text: "#f6f1e4", highlight: "#2a2416", highlightedText: "#1c1404",
          accent: "#f7d478", accentEnd: "#c98a2b" }
    ]

    // Saves from before these four still pick something close.
    readonly property var older: ({ "default": "night", "system": "night", "matos-dark": "night", "diamond": "night", "obscura-dark": "night",
                                    "pureblack": "night", "pro": "gold", "w12-dark": "glass", "w12-light": "light", "matos-light": "light", "obscura-light": "light" })

    function find(id) {
        const wanted = older[id] || id;
        for (const t of list)
            if (t.id === wanted)
                return t;
        return null;
    }
}
