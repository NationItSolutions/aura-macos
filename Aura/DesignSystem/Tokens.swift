import SwiftUI

extension Color {
    /// Color desde un entero RGB (`0x2F7BFF`) y alfa opcional.
    init(rgb: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255,
            opacity: alpha
        )
    }

    /// Color desde un string `#RRGGBB` o `#RRGGBBAA`. Devuelve `nil` si es inválido.
    init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6 || value.count == 8, let number = UInt64(value, radix: 16) else { return nil }
        if value.count == 6 {
            self.init(rgb: UInt32(number))
        } else {
            self.init(rgb: UInt32(number >> 8), alpha: Double(number & 0xFF) / 255)
        }
    }
}

/// Tokens de diseño de Aura. Dark-first, azul como único acento principal.
enum Theme {
    enum Palette {
        static let background = Color(rgb: 0x070B14)
        static let surface = Color(rgb: 0x0E1424)
        static let surfaceElevated = Color(rgb: 0x151D33)
        static let border = Color(rgb: 0xFFFFFF, alpha: 0x14 / 255)
        static let primary = Color(rgb: 0x2F7BFF)
        static let primaryHover = Color(rgb: 0x4A8DFF)
        static let primaryGlow = Color(rgb: 0x2F7BFF, alpha: 0x40 / 255)
        static let accent = Color(rgb: 0x38BDF8)
        static let textPrimary = Color(rgb: 0xE8EEF9)
        static let textSecondary = Color(rgb: 0x8B97B0)
        static let textTertiary = Color(rgb: 0x5B6680)
        static let success = Color(rgb: 0x34D399)
        static let warning = Color(rgb: 0xF5A524)
        static let danger = Color(rgb: 0xF43F5E)
        static let islandBackground = Color.black
    }

    /// Gradiente de marca (135°): solo en elementos destacados.
    static let brandGradient = LinearGradient(
        colors: [Palette.primary, Palette.accent],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let heatGradient = LinearGradient(
        colors: [Color(rgb: 0xF5A524), Color(rgb: 0xFF6B3D)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    enum Radius {
        static let control: CGFloat = 12
        static let card: CGFloat = 16
        static let sheet: CGFloat = 24
        static let island: CGFloat = 28
    }

    /// Grilla de 4 pt.
    enum Spacing {
        static let xxs: CGFloat = 4
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 48
    }

    enum IconSize {
        static let small: CGFloat = 16
        static let medium: CGFloat = 20
        static let large: CGFloat = 28
    }

    enum Motion {
        static let spring = Animation.spring(response: 0.35, dampingFraction: 0.8)
        static let quick = Animation.spring(response: 0.22, dampingFraction: 0.85)
    }
}

extension ButtonTint {
    var color: Color {
        switch self {
        case .neutral: Theme.Palette.textSecondary
        case .blue: Theme.Palette.primary
        case .cyan: Theme.Palette.accent
        case .green: Theme.Palette.success
        case .amber: Theme.Palette.warning
        case .red: Theme.Palette.danger
        }
    }
}
