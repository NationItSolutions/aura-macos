import SwiftUI

/// Escala tipográfica (SF Pro del sistema).
enum Typography {
    static let display = Font.system(size: 34, weight: .semibold)
    static let title = Font.system(size: 28, weight: .semibold)
    static let headline = Font.system(size: 17, weight: .semibold)
    static let body = Font.system(size: 15, weight: .regular)
    static let callout = Font.system(size: 13, weight: .regular)
    static let label = Font.system(size: 12, weight: .medium)
    static let caption = Font.system(size: 11, weight: .medium)

    /// Valores grandes (temperatura): SF Pro Rounded con dígitos monoespaciados.
    static func value(_ size: CGFloat = 64) -> Font {
        Font.system(size: size, weight: .medium, design: .rounded).monospacedDigit()
    }
}

extension View {
    func auraText(_ font: Font, _ color: Color = Theme.Palette.textPrimary) -> some View {
        self.font(font).foregroundStyle(color)
    }

    /// Respeta "Reducir movimiento": con la opción activa solo hay fundidos.
    func auraAnimation<V: Equatable>(_ value: V, reduceMotion: Bool) -> some View {
        animation(reduceMotion ? .easeInOut(duration: 0.15) : Theme.Motion.spring, value: value)
    }
}
