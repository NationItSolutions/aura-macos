import SwiftUI

/// Control IR genérico: grilla de botones grabados.
/// (La edición con drag & drop y el asistente de grabación llegan en M2.)
struct GenericRemoteView: View {
    @Environment(AppModel.self) private var model
    let device: Device

    private var state: DeviceState { model.store.state(for: device.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            if device.codes["power_on"] != nil || device.codes["power_off"] != nil {
                HStack(spacing: Theme.Spacing.md) {
                    IconButton(symbol: "power", label: String(localized: "Encender o apagar"), size: 56,
                               isActive: state.isOn, isLoading: model.bus.isBusy(device.id)) {
                        model.togglePower(device)
                    }
                    Text(state.isOn ? String(localized: "Encendido") : String(localized: "Apagado"))
                        .auraText(Typography.headline)
                }
            }
            Card {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Botones").auraText(Typography.label, Theme.Palette.textSecondary)
                    if device.buttons.isEmpty {
                        Text("Este control todavía no tiene botones.").auraText(Typography.callout, Theme.Palette.textTertiary)
                    } else {
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
    }
}
