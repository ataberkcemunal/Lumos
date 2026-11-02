import AppKit
import SwiftUI

extension View {
    @ViewBuilder
    func lumosIsolatedGlassSurface<S: Shape>(tint: Color? = nil, in shape: S) -> some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: 0) {
                background(shape.fill(tint ?? .clear))
                    .glassEffect(.regular, in: shape)
            }
            .clipShape(shape)
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

struct LumosWindowBackground: View {
    var body: some View {
        if #available(macOS 26.0, *) {
            Rectangle()
                .fill(.clear)
                .glassEffect(.regular, in: Rectangle())
        } else {
            Color(nsColor: .windowBackgroundColor)
        }
    }
}
