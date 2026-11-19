import SwiftUI

/// Slider por pasos (p. ej. brillo de LED por IR, que solo sube o baja de a un paso).
struct StepSlider: View {
    @Binding var value: Int
    let steps: Int
    var label: String = String(localized: "Brillo")
    var symbolLow: String = "sun.min"
    var symbolHigh: String = "sun.max.fill"
    /// Recibe +1 o −1 por cada paso que el usuario mueve.
    let onStep: (Int) -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            IconButton(symbol: symbolLow, label: String(localized: "\(label) −"), size: 32) { move(-1) }
                .disabled(value <= 1)
            HStack(spacing: 4) {
                ForEach(1...max(steps, 1), id: \.self) { index in
                    Capsule()
                        .fill(index <= value ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(Theme.Palette.surfaceElevated))
                        .frame(height: 10)
                        .shadow(color: index <= value ? Theme.Palette.primaryGlow : .clear, radius: 6)
                        .contentShape(Rectangle())
                        .onTapGesture { jump(to: index) }
                }
            }
            .animation(Theme.Motion.quick, value: value)
            IconButton(symbol: symbolHigh, label: String(localized: "\(label) +"), size: 32) { move(+1) }
                .disabled(value >= steps)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
        .accessibilityValue(Text("\(value) de \(steps)"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: move(+1)
            case .decrement: move(-1)
            @unknown default: break
            }
        }
    }

    private func move(_ delta: Int) {
        let next = value + delta
        guard (1...steps).contains(next) else { return }
        value = next
        onStep(delta)
    }

    private func jump(to target: Int) {
        let delta = target - value
        guard delta != 0 else { return }
        let direction = delta > 0 ? 1 : -1
        for _ in 0..<abs(delta) { onStep(direction) }
        value = target
    }
}

/// Encabezado de sección.
struct SectionHeader: View {
    let title: String
    var subtitle: String?
    var trailing: AnyView?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Typography.headline).foregroundStyle(Theme.Palette.textPrimary)
                if let subtitle {
                    Text(subtitle).font(Typography.callout).foregroundStyle(Theme.Palette.textSecondary)
                }
            }
            Spacer()
            if let trailing { trailing }
        }
    }
}
