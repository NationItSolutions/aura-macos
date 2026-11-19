import SwiftUI

/// Alta de un dispositivo IR: nombre, tipo, habitación y puente. Al crear, abre el asistente.
struct AddDeviceSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let onCreated: (Device) -> Void

    @State private var name = ""
    @State private var kind: DeviceKind = .light
    @State private var roomID: UUID?
    @State private var bridgeID: UUID?

    /// Tipos disponibles en esta versión (aire en M3, TV en M4).
    private let kinds: [DeviceKind] = [.light, .fan, .generic]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Nuevo dispositivo").auraText(Typography.title)
            Text("Se controla por infrarrojo a través de tu Broadlink.")
                .auraText(Typography.callout, Theme.Palette.textSecondary)

            Text("Tipo").auraText(Typography.label, Theme.Palette.textSecondary)
            HStack(spacing: Theme.Spacing.xs) {
                ForEach(kinds) { candidate in
                    TileButton(symbol: candidate.defaultSymbol, title: candidate.displayName,
                               tint: Theme.Palette.accent, isActive: kind == candidate) { kind = candidate }
                }
            }

            Form {
                TextField("Nombre", text: $name, prompt: Text(kind.displayName))
                Picker("Habitación", selection: $roomID) {
                    Text("Sin habitación").tag(UUID?.none)
                    ForEach(model.store.rooms) { Text($0.name).tag(UUID?.some($0.id)) }
                }
                Picker("Broadlink", selection: $bridgeID) {
                    if model.store.bridges.isEmpty { Text("Ninguno configurado").tag(UUID?.none) }
                    ForEach(model.store.bridges) { Text("\($0.name) · \($0.host)").tag(UUID?.some($0.id)) }
                }
            }
            .formStyle(.columns)

            if model.store.bridges.isEmpty {
                Label("Primero agregá tu Broadlink en Ajustes → Puentes.", systemImage: "exclamationmark.circle")
                    .auraText(Typography.label, Theme.Palette.warning)
            }

            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }.buttonStyle(SecondaryButtonStyle())
                PrimaryButton(title: String(localized: "Crear y grabar códigos"), symbol: "dot.radiowaves.left.and.right") {
                    create()
                }
                .disabled(bridgeID == nil)
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(width: 520)
        .background(Theme.Palette.surfaceElevated)
        .onAppear {
            bridgeID = model.store.bridges.first?.id
            roomID = model.store.rooms.first?.id
        }
    }

    private func create() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let device = Device(name: trimmed.isEmpty ? kind.displayName : trimmed, roomID: roomID, kind: kind,
                            transport: .broadlink(bridgeID: bridgeID), isFavorite: true)
        model.store.upsert(device)
        dismiss()
        onCreated(device)
    }
}
