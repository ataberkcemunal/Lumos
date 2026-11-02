import AppKit
import SwiftUI

extension View {
    /// A card surface: the system Liquid Glass material, tinted with the lamp's
    /// color through the glass effect's own tint on macOS 26 and later.
    @ViewBuilder
    func lumosGlassSurface<S: Shape>(tint: Color? = nil, in shape: S) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular.tint(tint), in: shape)
        } else {
            background(Color(nsColor: .controlBackgroundColor), in: shape)
                .overlay(shape.fill(tint ?? .clear).allowsHitTesting(false))
        }
    }

    @ViewBuilder
    func lumosGlassOnly<S: Shape>(tint: Color? = nil, in shape: S) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular.tint(tint), in: shape)
        } else {
            self
        }
    }

    @ViewBuilder
    func lumosLegacyBorder<S: Shape>(_ shape: S, color: Color) -> some View {
        if #available(macOS 26.0, *) {
            self
        } else {
            overlay(shape.stroke(color))
        }
    }
}

/// Groups glass surfaces so the system renders them together, as native
/// Liquid Glass does for neighboring elements.
struct LumosGlassContainer<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 24) { content }
        } else {
            content
        }
    }
}

/// On macOS 26 and later the window itself is an NSGlassEffectView, so the
/// SwiftUI layer stays clear instead of drawing a second glass pane.
struct LumosWindowBackground: View {
    var body: some View {
        if #available(macOS 26.0, *) {
            Color.clear
        } else {
            Color(nsColor: .windowBackgroundColor)
        }
    }
}
