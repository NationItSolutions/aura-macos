import SwiftUI

/// Control de LED: power, colores grabados, brillo por pasos y efectos.
struct LightControlView: View {
    @Environment(AppModel.self) private var model
    let device: Device
    @State private var brightness = LEDPalette.brightnessSteps

    private var state: DeviceState { model.store.state(for: device.id) }
    private let columns = [GridItem(.adaptive(minimum: 64), spacing: Theme.Spacing.sm)]

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            HStack(spacing: Theme.Spacing.lg) {
                ZStack {
                    Circle()
                        .fill(RadialGradient(colors: [currentColor.opacity(state.isOn ? 0.55 : 0.08), .clear],
                                             center: .center, startRadius: 10, endRadius: 110))
                        .frame(width: 200, height: 200)
                    Image(systemName: "lightbulb.led.fill")
                        .font(.system(size: 54, weight: .medium))
                        .foregroundStyle(state.isOn ? currentColor : Theme.Palette.textTertiary)
                        .shadow(color: state.isOn ? currentColor.opacity(0.8) : .clear, radius: 20)
                }
                .animation(Theme.Motion.spring, value: state.ledColor)
                .animation(Theme.Motion.spring, value: state.isOn)
                VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                    HStack(spacing: Theme.Spacing.sm) {
                        IconButton(symbol: "power", label: String(localized: "Encender o apagar"), size: 56,
                                   isActive: state.isOn, isLoading: model.bus.isBusy(device.id)) {
                            model.togglePower(device)
                        }
                        VStack(alignment: .leading) {
                            Text(state.isOn ? LEDPalette.displayName(for: state.ledColor ?? "white") : String(localized: "Apagado"))
                                .auraText(Typography.headline)
                            Text("Brillo \(brightness) de \(LEDPalette.brightnessSteps)")
                                .auraText(Typography.label, Theme.Palette.textSecondary)
                        }
                    }
                    StepSlider(value: $brightness, steps: LEDPalette.brightnessSteps) { delta in
                        model.send(.brightness(delta > 0 ? .up : .down), toDeviceID: device.id)
                    }
                }
            }

            Card {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Colores").auraText(Typography.label, Theme.Palette.textSecondary)
                    if device.recordedColors.isEmpty {
                        Text("Todavía no hay colores grabados.").auraText(Typography.callout, Theme.Palette.textTertiary)
                    } else {
                        LazyVGrid(columns: columns, spacing: Theme.Spacing.sm) {
                            ForEach(device.recordedColors, id: \.self) { color in
                                VStack(spacing: 6) {
                                    ColorSwatch(name: color, isSelected: state.isOn && state.ledColor == color, size: 38) {
                                        model.send(.color(color), toDeviceID: device.id)
                                    }
                                    Text(LEDPalette.displayName(for: color))
                                        .auraText(Typography.caption, Theme.Palette.textSecondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                    }
                }
            }

            if !device.buttons.isEmpty {
                Card {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("Efectos").auraText(Typography.label, Theme.Palette.textSecondary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: Theme.Spacing.xs)], spacing: Theme.Spacing.xs) {
                            ForEach(device.buttons) { button in
                                TileButton(symbol: button.symbol, title: button.name, tint: button.tint.color) {
                                    model.send(.button(button.codeName), toDeviceID: device.id)
                                }
                            }
                        }
                    }
                }
            }
        }
        .onAppear { brightness = state.brightnessLevel ?? LEDPalette.brightnessSteps }
    }

    private var currentColor: Color {
        LEDPalette.hex(for: state.ledColor ?? "white").map { Color(rgb: $0) } ?? Theme.Palette.accent
    }
}
