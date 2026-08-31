import SwiftUI
import AppKit

// MARK: - Hex <-> Color

extension Color {
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("#") { s.removeFirst() }
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        let r, g, b, a: Double
        if s.count == 8 {
            r = Double((v >> 24) & 0xFF) / 255
            g = Double((v >> 16) & 0xFF) / 255
            b = Double((v >> 8) & 0xFF) / 255
            a = Double(v & 0xFF) / 255
        } else {
            r = Double((v >> 16) & 0xFF) / 255
            g = Double((v >> 8) & 0xFF) / 255
            b = Double(v & 0xFF) / 255
            a = 1
        }
        self.init(.sRGB, red: r, green: g, blue: b, opacity: a)
    }

    /// "#RRGGBB", or "#RRGGBBAA" when translucent.
    var hexString: String {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return "#000000" }
        let r = Int((c.redComponent * 255).rounded())
        let g = Int((c.greenComponent * 255).rounded())
        let b = Int((c.blueComponent * 255).rounded())
        let a = Int((c.alphaComponent * 255).rounded())
        return a >= 255 ? String(format: "#%02X%02X%02X", r, g, b)
                        : String(format: "#%02X%02X%02X%02X", r, g, b, a)
    }
}

// MARK: - Theme

/// Every color the widget draws with. Hex strings so it round-trips through JSON
/// in UserDefaults and stays readable if anyone edits it by hand.
struct Theme: Codable, Equatable {
    var name: String
    var cardTop: String        // turntable card, gradient start
    var cardBottom: String     // turntable card, gradient end
    var vinyl: String          // the record
    var panel: String          // control card background
    var knob: String           // control button faces
    var accent: String         // progress + active toggles
    var text: String           // track title
    var arm: String            // tonearm metal

    var cardTopColor: Color { Color(hex: cardTop) }
    var cardBottomColor: Color { Color(hex: cardBottom) }
    var vinylColor: Color { Color(hex: vinyl) }
    var panelColor: Color { Color(hex: panel) }
    var knobColor: Color { Color(hex: knob) }
    var accentColor: Color { Color(hex: accent) }
    var textColor: Color { Color(hex: text) }
    var armColor: Color { Color(hex: arm) }

    static let presets: [Theme] = [
        Theme(name: "Studio",
              cardTop: "#A9A9A9", cardBottom: "#808080", vinyl: "#161616",
              panel: "#212121", knob: "#3A3A3A", accent: "#1DD65F",
              text: "#FFFFFF", arm: "#E2E2E2"),

        Theme(name: "Midnight",
              cardTop: "#39415A", cardBottom: "#232838", vinyl: "#0B0D14",
              panel: "#161A24", knob: "#2C3346", accent: "#7AA2F7",
              text: "#EAF0FF", arm: "#C3CBE0"),

        Theme(name: "Cream",
              cardTop: "#EDE0C8", cardBottom: "#D3BE9C", vinyl: "#201911",
              panel: "#2A2118", knob: "#413324", accent: "#D08A45",
              text: "#FFF6E6", arm: "#F0E4CE"),

        Theme(name: "Rose",
              cardTop: "#F2C3CF", cardBottom: "#D794A6", vinyl: "#1B1114",
              panel: "#26181D", knob: "#3D2830", accent: "#FF6E8A",
              text: "#FFEAF0", arm: "#F7DDE4"),

        Theme(name: "Forest",
              cardTop: "#A6C0A1", cardBottom: "#748E70", vinyl: "#0E140D",
              panel: "#161F14", knob: "#28351F", accent: "#6BD97F",
              text: "#EAF7E9", arm: "#D9E7D6"),

        Theme(name: "Mono",
              cardTop: "#1C1C1C", cardBottom: "#0E0E0E", vinyl: "#050505",
              panel: "#111111", knob: "#262626", accent: "#FFFFFF",
              text: "#FFFFFF", arm: "#8A8A8A"),

        Theme(name: "Sunset",
              cardTop: "#F0A868", cardBottom: "#CC6B47", vinyl: "#1A0F0C",
              panel: "#26150F", knob: "#3C231A", accent: "#FFB870",
              text: "#FFF0E2", arm: "#FFDCC0"),

        Theme(name: "Ocean",
              cardTop: "#9CC4D6", cardBottom: "#6B96AF", vinyl: "#071219",
              panel: "#0F1C25", knob: "#1D303D", accent: "#4FC3E8",
              text: "#E6F6FF", arm: "#D2E8F2"),
    ]

    static var `default`: Theme { presets[0] }
}
