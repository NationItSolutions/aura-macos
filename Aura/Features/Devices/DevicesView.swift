import SwiftUI

struct DevicesView: View {
    @Environment(AppModel.self) private var model
    @State private var filter: DeviceKind?
    @State private var showingAdd = false
    @State private var nextStep: AddDeviceNextStep?
    private let columns = [GridItem(.adaptive(minimum: 250, maximum: 360), spacing: Theme.Spacing.md)]

    private var kinds: [DeviceKind] {
        DeviceKind.allCases.filter { kind in model.store.devices.contains { $0.kind == kind } }
    }

    private var filtered: [Device] {
        guard let filter else { return model.store.devices }
        return model.store.devices.filter { $0.kind == filter }
    }

    var body: some View {
        PageScroll(title: String(localized: "Dispositivos"),
                   subtitle: String(localized: "\(model.store.devices.count) dispositivos")) {
            HStack(spacing: Theme.Spacing.xs) {
                Chip(title: String(localized: "Todos"), isSelected: filter == nil) { filter = nil }
                ForEach(kinds) { kind in
                    Chip(title: kind.displayName, symbol: kind.defaultSymbol, isSelected: filter == kind) { filter = kind }
                }
                Spacer()
                PrimaryButton(title: String(localized: "Agregar dispositivo"), symbol: "plus") { showingAdd = true }
            }
            if filtered.isEmpty {
                EmptyStateView(symbol: "square.grid.2x2", title: String(localized: "Sin dispositivos"),
                               message: String(localized: "Importá tus códigos desde Ajustes."))
            } else {
                LazyVGrid(columns: columns, spacing: Theme.Spacing.md) {
                    ForEach(filtered) { DeviceCard(device: $0) }
                }
            }
        }
        .sheet(isPresented: $showingAdd) {
            AddDeviceSheet { step in
                // Espera a que cierre la hoja de alta antes de abrir el paso siguiente.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(350))
                    nextStep = step
                }
            }
            .environment(model)
        }
        .sheet(item: $nextStep) { step in
            AddDeviceNextStepView(step: step).environment(model)
        }
    }
}

/// Paso que sigue al alta: grabar códigos, emparejar la TV o configurar el webhook.
struct AddDeviceNextStepView: View {
    @Environment(AppModel.self) private var model
    let step: AddDeviceNextStep

    var body: some View {
        switch step {
        case .learn(let device, let slots):
            LearningWizardSheet(model: model, deviceID: device.id, slots: slots,
                                allowsCustom: device.kind != .airConditioner)
        case .pairTV(let device):
            TVPairingSheet(deviceID: device.id)
        case .editWebhook(let device):
            WebhookActionsSheet(deviceID: device.id)
        }
    }
}
