import SwiftUI

/// Chip en cápsula (escenas, filtros, modos).
struct Chip: View {
    let title: String
    var symbol: String?
    var isSelected: Bool = false
    var isLoading: Bool = false
    var large: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.xs) {
                if isLoading {
                    ProgressView().controlSize(.small)
                } else if let symbol {
                    Image(systemName: symbol)
                        .font(.system(size: large ? 15 : 12, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                }
                Text(title)
                    .font(.system(size: large ? 14 : 12, weight: .medium))
                    .lineLimit(1)
            }
            .padding(.horizontal, large ? Theme.Spacing.md : Theme.Spacing.sm)
            .frame(height: large ? 44 : 30)
        }
        .buttonStyle(ChipStyle(isSelected: isSelected))
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct ChipStyle: ButtonStyle {
    var isSelected: Bool
    func makeBody(configuration: Configuration) -> some View {
        HoverReader { hovering, isEnabled in
            configuration.label
                .foregroundStyle(isSelected ? Color.white : Theme.Palette.textPrimary)
                .background(
                    Capsule().fill(isSelected ? AnyShapeStyle(Theme.brandGradient)
                                   : AnyShapeStyle(hovering ? Theme.Palette.surfaceElevated : Theme.Palette.surface))
                )
                .overlay(Capsule().strokeBorder(isSelected ? Color.clear : Theme.Palette.border))
                .shadow(color: isSelected ? Theme.Palette.primaryGlow : .clear, radius: 10)
                .scaleEffect(configuration.isPressed ? 0.96 : 1)
                .opacity(isEnabled ? 1 : 0.45)
                .animation(Theme.Motion.quick, value: configuration.isPressed)
                .animation(Theme.Motion.quick, value: isSelected)
                .contentShape(Capsule())
        }
    }
}

/// Indicador de estado de conexión: punto de color + texto.
struct StatusPill: View {
    enum Status { case online, offline, connecting, demo }
    let title: String
    let status: Status

    private var color: Color {
        switch status {
        case .online: Theme.Palette.success
        case .offline: Theme.Palette.danger
        case .connecting: Theme.Palette.warning
        case .demo: Theme.Palette.accent
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
                .shadow(color: color.opacity(0.7), radius: 4)
            Text(title).font(Typography.label).foregroundStyle(Theme.Palette.textSecondary)
        }
        .padding(.horizontal, 10)
        .frame(height: 26)
        .background(Capsule().fill(Theme.Palette.surface))
        .overlay(Capsule().strokeBorder(Theme.Palette.border))
        .accessibilityElement(children: .combine)
    }
}
