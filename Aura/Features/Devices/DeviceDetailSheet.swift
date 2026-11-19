import SwiftUI

/// Ficha del dispositivo con el control completo según su tipo.
struct DeviceDetailSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let deviceID: UUID
    @State private var showingSync = false
    @State private var showingLearning = false

    var body: some View {
        Group {
            if let device = model.store.device(deviceID) {
                VStack(spacing: 0) {
                    header(device)
                    Divider().overlay(Theme.Palette.border)
                    ScrollView {
                        control(for: device)
                            .padding(Theme.Spacing.lg)
                    }
                    .scrollIndicators(.never)
                }
                .sheet(isPresented: $showingSync) {
                    SyncStateSheet(device: device).environment(model)
                }
                .sheet(isPresented: $showingLearning) {
                    LearningWizardSheet(model: model, deviceID: device.id, slots: device.learningSlots,
                                        allowsCustom: device.kind != .airConditioner)
                        .environment(model)
                }
            } else {
                EmptyStateView(symbol: "questionmark.circle", title: String(localized: "Dispositivo no encontrado"),
                               message: String(localized: "Puede que se haya eliminado."))
                    .padding()
            }
        }
        .frame(width: 620, height: 640)
        .background(Theme.Palette.surfaceElevated)
        .overlay(alignment: .bottom) { FeedbackToast().padding(.bottom, Theme.Spacing.md) }
        .onKeyPress(.escape) { dismiss(); return .handled }
    }

    private func header(_ device: Device) -> some View {
        let state = model.store.state(for: device.id)
        return HStack(spacing: Theme.Spacing.sm) {
            DeviceIcon(device: device, isOn: state.isOn, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(device.name).auraText(Typography.headline)
                HStack(spacing: 6) {
                    Text(model.store.room(device.roomID)?.name ?? device.kind.displayName)
                    Text("·")
                    Text(device.transport.kind.displayName)
                    if device.transport.kind != .samsungTizen {
                        Text("·")
                        Text("Estado asumido").help(Text("El IR es de una sola vía: Aura muestra el último estado que envió."))
                    }
                }
                .auraText(Typography.label, Theme.Palette.textSecondary)
            }
            Spacer()
            if case .broadlink = device.transport {
                Button {
                    showingLearning = true
                } label: {
                    Label("Grabar códigos", systemImage: "dot.radiowaves.left.and.right")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            Button {
                showingSync = true
            } label: {
                Label("Sincronizar", systemImage: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(SecondaryButtonStyle())
            .help(Text("Corregir el estado a mano sin enviar comandos"))
            IconButton(symbol: "xmark", label: String(localized: "Cerrar"), size: 30) { dismiss() }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
    }

    @ViewBuilder
    private func control(for device: Device) -> some View {
        switch device.kind {
        case .airConditioner: ACControlView(device: device)
        case .television: TVRemoteView(device: device)
        case .light: LightControlView(device: device)
        case .fan, .generic: GenericRemoteView(device: device)
        }
    }
}

/// Corrige el estado asumido sin mandar nada al dispositivo.
struct SyncStateSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let device: Device
    @State private var isOn = false
    @State private var ac = ACSettings()

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Sincronizar estado").auraText(Typography.headline)
            Text("Si usaste el control físico, ajustá acá cómo está el equipo ahora. No se envía ningún comando.")
                .auraText(Typography.callout, Theme.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Toggle("Encendido", isOn: $isOn)
            if device.kind == .airConditioner {
                Picker("Modo", selection: $ac.mode) {
                    ForEach(ACMode.allCases) { Text($0.displayName).tag($0) }
                }
                Stepper(value: $ac.temperature, in: device.temperatureRange) {
                    Text("Temperatura: \(ac.temperature) °C")
                }
                Picker("Ventilador", selection: $ac.fan) {
                    ForEach(FanSpeed.allCases) { Text($0.displayName).tag($0) }
                }
                Toggle("Swing", isOn: $ac.swing)
            }
            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }.buttonStyle(SecondaryButtonStyle())
                PrimaryButton(title: String(localized: "Guardar")) {
                    model.syncState(device) { state in
                        state.isOn = isOn
                        if device.kind == .airConditioner { state.ac = ac }
                        state.lastUpdated = .now
                    }
                    dismiss()
                }
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(width: 380)
        .onAppear {
            let state = model.store.state(for: device.id)
            isOn = state.isOn
            ac = state.ac ?? ACSettings()
        }
    }
}
