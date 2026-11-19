import SwiftUI

/// Botón de ícono redondo. `isActive` lo pinta con el azul principal y halo.
struct IconButton: View {
    let symbol: String
    let label: String
    var size: CGFloat = 40
    var isActive: Bool = false
    var activeColor: Color = Theme.Palette.primary
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if isLoading {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: symbol)
                        .font(.system(size: size * 0.4, weight: .semibold))
                        .symbolRenderingMode(.hierarchical)
                }
            }
            .frame(width: size, height: size)
        }
        .buttonStyle(IconButtonStyle(isActive: isActive, activeColor: activeColor))
        .disabled(isLoading)
        .accessibilityLabel(label)
        .help(label)
    }
}

struct IconButtonStyle: ButtonStyle {
    var isActive: Bool
    var activeColor: Color = Theme.Palette.primary
    func makeBody(configuration: Configuration) -> some View {
        HoverReader { hovering, isEnabled in
            configuration.label
                .foregroundStyle(isActive ? Color.white : Theme.Palette.textPrimary)
                .background(
                    Circle().fill(isActive ? activeColor : (hovering ? Theme.Palette.surfaceElevated.opacity(1) : Theme.Palette.surfaceElevated.opacity(0.7)))
                )
                .overlay(Circle().strokeBorder(isActive ? Color.clear : Theme.Palette.border))
                .shadow(color: isActive ? activeColor.opacity(0.45) : .clear, radius: 12)
                .scaleEffect(configuration.isPressed ? 0.92 : 1)
                .opacity(isEnabled ? 1 : 0.4)
                .animation(Theme.Motion.quick, value: configuration.isPressed)
                .animation(Theme.Motion.quick, value: isActive)
                .contentShape(Circle())
        }
    }
}

/// Botón cuadrado con ícono y texto (grillas de controles).
struct TileButton: View {
    let symbol: String
    let title: String
    var tint: Color = Theme.Palette.textSecondary
    var isActive: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Theme.Spacing.xs) {
                Image(systemName: symbol)
                    .font(.system(size: Theme.IconSize.medium, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(isActive ? Color.white : tint)
                Text(title)
                    .font(Typography.label)
                    .foregroundStyle(isActive ? Color.white : Theme.Palette.textPrimary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 72)
        }
        .buttonStyle(TileButtonStyle(isActive: isActive, tint: tint))
        .accessibilityLabel(title)
    }
}

struct TileButtonStyle: ButtonStyle {
    var isActive: Bool
    var tint: Color
    func makeBody(configuration: Configuration) -> some View {
        HoverReader { hovering, isEnabled in
            configuration.label
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .fill(isActive ? AnyShapeStyle(Theme.brandGradient)
                              : AnyShapeStyle(hovering ? Theme.Palette.surfaceElevated : Theme.Palette.surface))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .strokeBorder(isActive ? Color.clear : Theme.Palette.border)
                )
                .scaleEffect(configuration.isPressed ? 0.96 : 1)
                .animation(Theme.Motion.quick, value: configuration.isPressed)
                .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.control))
        }
    }
}
