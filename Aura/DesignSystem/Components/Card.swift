import SwiftUI

/// Tarjeta sólida con borde de 1 px. En estado activo: borde primary + halo.
struct Card<Content: View>: View {
    var isActive: Bool = false
    var padding: CGFloat = Theme.Spacing.md
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .fill(isActive ? Theme.Palette.surfaceElevated : Theme.Palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                    .strokeBorder(isActive ? Theme.Palette.primary.opacity(0.7) : Theme.Palette.border, lineWidth: 1)
            )
            .shadow(color: isActive ? Theme.Palette.primaryGlow : .clear, radius: 16)
    }
}

/// Modificador para superficies interactivas: hover sutil y escala al presionar.
struct HoverLift: ViewModifier {
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .brightness(hovering ? 0.03 : 0)
            .scaleEffect(hovering && !reduceMotion ? 1.01 : 1)
            .animation(Theme.Motion.quick, value: hovering)
            .onHover { hovering = $0 }
    }
}

extension View {
    func hoverLift() -> some View { modifier(HoverLift()) }
}
