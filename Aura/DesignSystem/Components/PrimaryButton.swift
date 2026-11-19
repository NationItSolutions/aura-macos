import SwiftUI

/// Botón principal con el gradiente de marca. Estados: hover, presionado, deshabilitado y cargando.
struct PrimaryButton: View {
    let title: String
    var symbol: String?
    var isLoading: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.xs) {
                if isLoading {
                    ProgressView().controlSize(.small).tint(.white)
                } else if let symbol {
                    Image(systemName: symbol).font(.system(size: 14, weight: .semibold))
                }
                Text(title).font(.system(size: 14, weight: .semibold))
            }
        }
        .buttonStyle(PrimaryButtonStyle())
        .disabled(isLoading)
        .accessibilityLabel(title)
    }
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverReader { hovering, isEnabled in
            configuration.label
                .foregroundStyle(.white)
                .padding(.horizontal, Theme.Spacing.md)
                .frame(height: 36)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .fill(Theme.brandGradient)
                        .brightness(hovering ? 0.06 : 0)
                )
                .shadow(color: Theme.Palette.primaryGlow, radius: hovering ? 14 : 8, y: 2)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .opacity(isEnabled ? 1 : 0.45)
                .animation(Theme.Motion.quick, value: configuration.isPressed)
                .animation(Theme.Motion.quick, value: hovering)
                .contentShape(Rectangle())
        }
    }
}

/// Botón secundario sobre superficie.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverReader { hovering, isEnabled in
            configuration.label
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.Palette.textPrimary)
                .padding(.horizontal, Theme.Spacing.sm)
                .frame(height: 32)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .fill(hovering ? Theme.Palette.surfaceElevated : Theme.Palette.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                        .strokeBorder(Theme.Palette.border)
                )
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .opacity(isEnabled ? 1 : 0.45)
                .animation(Theme.Motion.quick, value: configuration.isPressed)
                .contentShape(Rectangle())
        }
    }
}
