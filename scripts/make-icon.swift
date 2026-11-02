// Renders the Lumos app icon (1024×1024 PNG) with Core Graphics.
// Usage: swift scripts/make-icon.swift <output.png>
// scripts/build-icon.sh turns the PNG into Resources/Lumos.icns.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
// Draw in top-left coordinates like a design canvas.
context.translateBy(x: 0, y: CGFloat(size))
context.scaleBy(x: 1, y: -1)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [
        CGFloat((hex >> 16) & 255) / 255, CGFloat((hex >> 8) & 255) / 255, CGFloat(hex & 255) / 255, alpha
    ])!
}

func gradient(_ stops: [(CGFloat, CGColor)]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: stops.map(\.1) as CFArray, locations: stops.map(\.0))!
}

/// The macOS icon body: an 824-point superellipse on the 1024 canvas.
func squircle(center: CGPoint, radius: CGFloat, exponent: Double = 5) -> CGPath {
    let path = CGMutablePath()
    for step in 0...720 {
        let t = Double(step) / 720 * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = Double(radius) * (c < 0 ? -1 : 1) * pow(abs(c), 2 / exponent)
        let y = Double(radius) * (s < 0 ? -1 : 1) * pow(abs(s), 2 / exponent)
        let point = CGPoint(x: center.x + x, y: center.y + y)
        step == 0 ? path.move(to: point) : path.addLine(to: point)
    }
    path.closeSubpath()
    return path
}

/// A bulb: a round head that narrows into a neck.
func bulb(center: CGPoint, radius r: CGFloat, neckBottom: CGFloat, neckHalfWidth: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let open = 55.0 * .pi / 180
    func onCircle(_ angle: Double) -> CGPoint {
        CGPoint(x: center.x + r * CGFloat(cos(angle)), y: center.y + r * CGFloat(sin(angle)))
    }
    let right = onCircle(open), left = onCircle(.pi - open)
    path.move(to: right)
    path.addQuadCurve(to: CGPoint(x: center.x + neckHalfWidth, y: neckBottom),
                      control: CGPoint(x: center.x + neckHalfWidth + 14, y: right.y + (neckBottom - right.y) * 0.45))
    path.addLine(to: CGPoint(x: center.x - neckHalfWidth, y: neckBottom))
    path.addQuadCurve(to: left,
                      control: CGPoint(x: center.x - neckHalfWidth - 14, y: left.y + (neckBottom - left.y) * 0.45))
    // Over the top, from the left opening back round to the right one.
    for step in 1...240 {
        let angle = (.pi - open) + Double(step) / 240 * (2 * .pi - (.pi - 2 * open))
        path.addLine(to: onCircle(angle))
    }
    path.closeSubpath()
    return path
}

func star(center: CGPoint, radius: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let waist = radius * 0.22
    path.move(to: CGPoint(x: center.x, y: center.y - radius))
    path.addQuadCurve(to: CGPoint(x: center.x + radius, y: center.y), control: CGPoint(x: center.x + waist, y: center.y - waist))
    path.addQuadCurve(to: CGPoint(x: center.x, y: center.y + radius), control: CGPoint(x: center.x + waist, y: center.y + waist))
    path.addQuadCurve(to: CGPoint(x: center.x - radius, y: center.y), control: CGPoint(x: center.x - waist, y: center.y + waist))
    path.addQuadCurve(to: CGPoint(x: center.x, y: center.y - radius), control: CGPoint(x: center.x - waist, y: center.y - waist))
    return path
}

let center = CGPoint(x: 512, y: 512)
let body = squircle(center: center, radius: 412)

// Body with a soft drop shadow.
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: 12), blur: 28, color: color(0x000000, 0.35))
context.addPath(body)
context.setFillColor(color(0x161331))
context.fillPath()
context.restoreGState()

// Night-sky gradient and a glassy sheen across the top.
context.saveGState()
context.addPath(body)
context.clip()
context.drawLinearGradient(gradient([(0, color(0x2E2A63)), (0.55, color(0x1C1840)), (1, color(0x0F0C22))]),
                           start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
let bulbCenter = CGPoint(x: 512, y: 440)
context.drawRadialGradient(gradient([(0, color(0xFFC468, 0.55)), (0.45, color(0xFF9F3D, 0.18)), (1, color(0xFF9F3D, 0))]),
                           startCenter: bulbCenter, startRadius: 0, endCenter: bulbCenter, endRadius: 400, options: [])
context.drawLinearGradient(gradient([(0, color(0xFFFFFF, 0.16)), (1, color(0xFFFFFF, 0))]),
                           start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 470), options: [])
context.restoreGState()

// Thin rim highlight, as on system glass.
context.saveGState()
context.addPath(body)
context.setStrokeColor(color(0xFFFFFF, 0.14))
context.setLineWidth(3)
context.strokePath()
context.restoreGState()

// Bulb: warm core fading to amber, with an outer glow.
let glass = bulb(center: bulbCenter, radius: 196, neckBottom: 676, neckHalfWidth: 62)
context.saveGState()
context.setShadow(offset: .zero, blur: 60, color: color(0xFFB347, 0.85))
context.addPath(glass)
context.setFillColor(color(0xFFB347))
context.fillPath()
context.restoreGState()

context.saveGState()
context.addPath(glass)
context.clip()
context.drawRadialGradient(gradient([(0, color(0xFFFBEF)), (0.35, color(0xFFE2A3)), (0.75, color(0xFFB347)), (1, color(0xF2862B))]),
                           startCenter: CGPoint(x: 512, y: 420), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 470), endRadius: 290, options: [.drawsAfterEndLocation])
// Specular highlight on the upper left of the glass.
context.addPath(CGPath(ellipseIn: CGRect(x: 380, y: 282, width: 120, height: 170), transform: nil))
context.setFillColor(color(0xFFFFFF, 0.38))
context.fillPath()
context.restoreGState()

// Screw base: three rounded metal bands.
let bands: [(y: CGFloat, width: CGFloat, height: CGFloat)] = [(690, 136, 26), (726, 124, 26), (762, 78, 20)]
for band in bands {
    let rect = CGRect(x: 512 - band.width / 2, y: band.y, width: band.width, height: band.height)
    let path = CGPath(roundedRect: rect, cornerWidth: band.height / 2, cornerHeight: band.height / 2, transform: nil)
    context.saveGState()
    context.addPath(path)
    context.clip()
    context.drawLinearGradient(gradient([(0, color(0xE9E6F2)), (1, color(0x8D88A6))]),
                               start: CGPoint(x: 512, y: rect.minY), end: CGPoint(x: 512, y: rect.maxY), options: [])
    context.restoreGState()
}

// A small sparkle: the spell being cast.
context.saveGState()
context.setShadow(offset: .zero, blur: 18, color: color(0xFFE7B0, 0.9))
context.addPath(star(center: CGPoint(x: 712, y: 262), radius: 46))
context.addPath(star(center: CGPoint(x: 316, y: 236), radius: 22))
context.setFillColor(color(0xFFF6E0))
context.fillPath()
context.restoreGState()

let output = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "icon.png")
let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
precondition(CGImageDestinationFinalize(destination), "Could not write \(output.path)")
print(output.path)
