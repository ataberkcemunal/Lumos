import AppKit
import SwiftUI

/// A message shown at the bottom of the main window. Errors and information
/// use different icons so a successful adjustment does not look like a failure.
struct ToastMessage: Equatable {
    let text: String
    var isError = true
}

extension Color {
    /// Parses six-digit HEX, with or without a leading `#`.
    init?(hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard clean.count == 6, let value = Int(clean, radix: 16) else { return nil }
        self.init(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }

    /// 0–255 sRGB channels, as WiZ expects them.
    var rgb255: (red: Int, green: Int, blue: Int)? {
        guard let srgb = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        return (Int((srgb.redComponent * 255).rounded()), Int((srgb.greenComponent * 255).rounded()), Int((srgb.blueComponent * 255).rounded()))
    }

    var hexString: String {
        guard let rgb = rgb255 else { return "FFFFFF" }
        return String(format: "%02X%02X%02X", rgb.red, rgb.green, rgb.blue)
    }
}

/// A perceptual UI palette for tunable-white lamps. The anchors deliberately
/// keep 3000 K creamy yellow instead of the brownish orange produced by a
/// single linear interpolation across the full CCT range.
func whiteTemperatureColor(_ kelvin: Int) -> Color {
    let value = min(6500, max(2200, kelvin))
    let anchors: [(kelvin: Int, red: Double, green: Double, blue: Double)] = [
        (2200, 1.00, 0.48, 0.12),
        (3000, 1.00, 0.76, 0.34),
        (4000, 1.00, 0.90, 0.68),
        (6500, 0.84, 0.91, 1.00)
    ]
    guard let upperIndex = anchors.firstIndex(where: { value <= $0.kelvin }) else {
        return Color(red: 0.84, green: 0.91, blue: 1.00)
    }
    if upperIndex == 0 {
        let color = anchors[0]
        return Color(red: color.red, green: color.green, blue: color.blue)
    }
    let lower = anchors[upperIndex - 1]
    let upper = anchors[upperIndex]
    let fraction = Double(value - lower.kelvin) / Double(upper.kelvin - lower.kelvin)
    return Color(
        red: lower.red + (upper.red - lower.red) * fraction,
        green: lower.green + (upper.green - lower.green) * fraction,
        blue: lower.blue + (upper.blue - lower.blue) * fraction
    )
}

/// Keeps the represented lamp color identical across controls and appearances.
func interfaceAccentColor(_ color: Color, for scheme: ColorScheme) -> Color {
    color
}

/// Preserves hue while giving small symbols enough contrast on light glass.
func interfaceSymbolColor(_ color: Color, for scheme: ColorScheme) -> Color {
    guard scheme == .light,
          let source = NSColor(color).usingColorSpace(.deviceRGB) else { return color }
    var hue: CGFloat = 0, saturation: CGFloat = 0, brightness: CGFloat = 0, alpha: CGFloat = 0
    source.getHue(&hue, saturation: &saturation, brightness: &brightness, alpha: &alpha)
    return Color(nsColor: NSColor(
        deviceHue: hue,
        saturation: max(saturation, 0.62),
        brightness: min(brightness, 0.56),
        alpha: alpha
    ))
}

struct LightDevice: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var ip: String
    var room: String
    var mac: String? = nil
    var isOn = false
    var brightness = 100
    var temperature = 3000
    var red = 255
    var green = 187
    var blue = 110
    var sceneID: Int? = nil
    var speed = 100
    var isReachable = true
    var isColorMode: Bool? = false

    var color: Color { Color(red: Double(red)/255, green: Double(green)/255, blue: Double(blue)/255) }
    var hex: String { String(format: "%02X%02X%02X", red, green, blue) }

    /// The desk lamp gets its own symbol; the room lamp is a bulb.
    var symbolName: String {
        let base = name == "Çalışma Masası Lambası" ? "lamp.desk" : "lightbulb.led"
        return isReachable && isOn ? "\(base).fill" : base
    }
}
