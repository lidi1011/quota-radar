import SwiftUI

extension Color {
    init(hex: String) {
        let value = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: value).scanHexInt64(&int)
        let r, g, b: UInt64
        switch value.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xff, (int >> 8) & 0xff, int & 0xff)
        default:
            (r, g, b) = (37, 99, 235)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: 1
        )
    }

    func toHex() -> String {
        #if os(macOS)
        let nsColor = NSColor(self).usingColorSpace(.sRGB) ?? .controlAccentColor
        let red = Int(round(nsColor.redComponent * 255))
        let green = Int(round(nsColor.greenComponent * 255))
        let blue = Int(round(nsColor.blueComponent * 255))
        return String(format: "#%02X%02X%02X", red, green, blue)
        #else
        return "#2563EB"
        #endif
    }

    func mixed(with other: Color, fraction: Double) -> Color {
        #if os(macOS)
        let clamped = max(0, min(1, fraction))
        let lhs = NSColor(self).usingColorSpace(.sRGB) ?? .controlAccentColor
        let rhs = NSColor(other).usingColorSpace(.sRGB) ?? .white
        return Color(
            .sRGB,
            red: lhs.redComponent + (rhs.redComponent - lhs.redComponent) * clamped,
            green: lhs.greenComponent + (rhs.greenComponent - lhs.greenComponent) * clamped,
            blue: lhs.blueComponent + (rhs.blueComponent - lhs.blueComponent) * clamped,
            opacity: lhs.alphaComponent + (rhs.alphaComponent - lhs.alphaComponent) * clamped
        )
        #else
        return self
        #endif
    }
}
