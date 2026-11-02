import AppKit
import SwiftUI

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
}

struct LightScene: Identifiable, Hashable {
    let id: Int
    let name: String
    let symbol: String
    let colors: [Color]
}

enum NavigationItem: String, CaseIterable, Identifiable {
    case home = "Genel Bakış"
    case lights = "Işıklar"
    case scenes = "Sahneler"
    var id: String { rawValue }
    var symbol: String { switch self { case .home: "sparkles"; case .lights: "lightbulb.led"; case .scenes: "square.stack.3d.up.fill" } }
}

let wizScenes: [LightScene] = [
    .init(id: 1, name: "Okyanus", symbol: "water.waves", colors: [.cyan, .blue]),
    .init(id: 2, name: "Romantik", symbol: "heart.fill", colors: [.pink, .red]),
    .init(id: 3, name: "Gün Batımı", symbol: "sun.horizon.fill", colors: [.orange, .pink]),
    .init(id: 4, name: "Parti", symbol: "party.popper.fill", colors: [.purple, .blue, .pink]),
    .init(id: 5, name: "Şömine", symbol: "flame.fill", colors: [.red, .orange]),
    .init(id: 6, name: "Rahatlama", symbol: "leaf.fill", colors: [.green, .cyan]),
    .init(id: 7, name: "Pastel", symbol: "paintpalette.fill", colors: [.mint, .pink]),
    .init(id: 8, name: "Uyanış", symbol: "sunrise.fill", colors: [.yellow, .orange]),
    .init(id: 9, name: "Yatak Zamanı", symbol: "moon.stars.fill", colors: [.indigo, .purple]),
    .init(id: 10, name: "Sıcak", symbol: "sun.max.fill", colors: [.yellow, .orange]),
    .init(id: 11, name: "Gündüz", symbol: "cloud.sun.fill", colors: [.white, .cyan]),
    .init(id: 12, name: "Soğuk Beyaz", symbol: "snowflake", colors: [.white, .blue])
]
