import SwiftUI

/// Qué hacer después de crear un dispositivo.
enum AddDeviceNextStep: Identifiable {
    case learn(Device, [LearningSlot])
    case pairTV(Device)
    case editWebhook(Device)

    var id: UUID {
        switch self {
        case .learn(let device, _), .pairTV(let device), .editWebhook(let device): device.id
        }
    }
}

/// Tipos que se pueden crear desde la app.
enum NewDeviceType: String, CaseIterable, Identifiable {
    case airConditioner, television, light, fan, generic, webhook

    var id: String { rawValue }

    var title: String {
        switch self {
        case .airConditioner: String(localized: "Aire")
        case .television: String(localized: "TV")
        case .light: String(localized: "Luces LED")
        case .fan: String(localized: "Ventilador")
        case .generic: String(localized: "Control IR")
        case .webhook: String(localized: "Webhook")
        }
    }

    var symbol: String {
        switch self {
        case .webhook: "link"
        default: kind.defaultSymbol
        }
    }

    var kind: DeviceKind {
        switch self {
        case .airConditioner: .airConditioner
        case .television: .television
        case .light: .light
        case .fan: .fan
        case .generic, .webhook: .generic
        }
    }

    var defaultName: String {
        switch self {
        case .webhook: String(localized: "Webhook")
        default: kind.displayName
        }
    }

    var subtitle: String {
        switch self {
        case .television: String(localized: "Por red (Smart TV Samsung) o por infrarrojo con tu Broadlink.")
        case .webhook: String(localized: "Pedidos HTTP a Home Assistant, Shelly, Tasmota, n8n…")
        default: String(localized: "Se controla por infrarrojo a través de tu Broadlink.")
        }
    }
}

/// Alta de un dispositivo: tipo, nombre, habitación y conexión. Después abre el paso que corresponda.
struct AddDeviceSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let onCreated: (AddDeviceNextStep) -> Void

    @State private var type: NewDeviceType = .airConditioner
    @State private var name = ""
    @State private var roomID: UUID?
    @State private var bridgeID: UUID?
    @State private var addingRoom = false

    // Aire
    @State private var acModes: Set<ACMode> = [.cool]
    @State private var minTemp = 17
    @State private var maxTemp = 26

    // TV
    @State private var tvByNetwork = true
    @State private var tvHost = ""
    @State private var tvFallbackBridge: UUID?
    @State private var foundTVs: [String] = []
    @State private var searchingTVs = false
    @State private var creating = false
    @State private var errorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Nuevo dispositivo").auraText(Typography.title)
            Text(type.subtitle).auraText(Typography.callout, Theme.Palette.textSecondary)

            HStack(spacing: Theme.Spacing.xs) {
                ForEach(NewDeviceType.allCases) { candidate in
                    TileButton(symbol: candidate.symbol, title: candidate.title,
                               tint: Theme.Palette.accent, isActive: type == candidate) { type = candidate }
                }
            }

            Form {
                TextField("Nombre", text: $name, prompt: Text(type.defaultName))
                HStack {
                    Picker("Habitación", selection: $roomID) {
                        Text("Sin habitación").tag(UUID?.none)
                        ForEach(model.store.rooms) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                    IconButton(symbol: "plus", label: String(localized: "Nueva habitación"), size: 26) { addingRoom = true }
                }
                if type == .television {
                    Picker("Conexión", selection: $tvByNetwork) {
                        Text("Por red (recomendado)").tag(true)
                        Text("Infrarrojo").tag(false)
                    }
                    .pickerStyle(.segmented)
                }
                if needsBridge {
                    bridgePicker(title: "Broadlink", selection: $bridgeID, allowNone: false)
                }
                if type == .television && tvByNetwork {
                    tvNetworkFields
                }
            }
            .formStyle(.columns)

            if type == .airConditioner { acOptions }

            if needsBridge && model.store.bridges.isEmpty {
                Label("Primero agregá tu Broadlink en Ajustes → Puentes.", systemImage: "exclamationmark.circle")
                    .auraText(Typography.label, Theme.Palette.warning)
            }
            if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle.fill")
                    .auraText(Typography.label, Theme.Palette.danger)
            }

            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }.buttonStyle(SecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                PrimaryButton(title: primaryTitle, symbol: primarySymbol, isLoading: creating) { create() }
                    .disabled(!canCreate)
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(width: 600)
        .background(Theme.Palette.surfaceElevated)
        .onAppear {
            bridgeID = model.store.bridges.first?.id
            tvFallbackBridge = model.store.bridges.first?.id
            roomID = model.store.rooms.first?.id
        }
        .sheet(isPresented: $addingRoom) {
            RoomEditorSheet(room: nil) { room in roomID = room.id }.environment(model)
        }
    }

    // MARK: - Secciones

    private func bridgePicker(title: LocalizedStringKey, selection: Binding<UUID?>, allowNone: Bool) -> some View {
        Picker(title, selection: selection) {
            if allowNone || model.store.bridges.isEmpty {
                Text(allowNone ? "Ninguno" : "Ninguno configurado").tag(UUID?.none)
            }
            ForEach(model.store.bridges) { Text("\($0.name) · \($0.host)").tag(UUID?.some($0.id)) }
        }
    }

    @ViewBuilder
    private var tvNetworkFields: some View {
        HStack {
            TextField("IP de la TV", text: $tvHost, prompt: Text("p. ej. 192.168.1.40"))
            Button {
                searchTVs()
            } label: {
                if searchingTVs { ProgressView().controlSize(.small) } else { Text("Buscar") }
            }
            .buttonStyle(SecondaryButtonStyle())
            .disabled(searchingTVs)
        }
        if !foundTVs.isEmpty {
            HStack(spacing: Theme.Spacing.xs) {
                Text("Encontradas:").auraText(Typography.label, Theme.Palette.textSecondary)
                ForEach(foundTVs, id: \.self) { host in
                    Chip(title: host, symbol: "tv", isSelected: tvHost == host) { tvHost = host }
                }
            }
        }
        bridgePicker(title: "Respaldo IR", selection: $tvFallbackBridge, allowNone: true)
    }

    private var acOptions: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Qué grabar").auraText(Typography.label, Theme.Palette.textSecondary)
                HStack(spacing: Theme.Spacing.xs) {
                    ForEach(ACMode.allCases) { mode in
                        Chip(title: mode.displayName, symbol: mode.symbol, isSelected: acModes.contains(mode)) {
                            if acModes.contains(mode) { acModes.remove(mode) } else { acModes.insert(mode) }
                        }
                    }
                }
                HStack(spacing: Theme.Spacing.lg) {
                    Stepper("Desde \(minTemp) °C", value: $minTemp, in: 16...maxTemp)
                    Stepper("Hasta \(maxTemp) °C", value: $maxTemp, in: minTemp...30)
                    Spacer()
                    Text("\(slotCount) códigos").auraText(Typography.label, Theme.Palette.textTertiary)
                }
                .auraText(Typography.callout)
                Text("Después podés grabar más modos o temperaturas desde la ficha del aire.")
                    .auraText(Typography.caption, Theme.Palette.textTertiary)
            }
        }
    }

    // MARK: - Estado

    private var needsBridge: Bool {
        switch type {
        case .webhook: false
        case .television: !tvByNetwork
        default: true
        }
    }

    private var orderedModes: [ACMode] { ACMode.allCases.filter { acModes.contains($0) } }

    private var slotCount: Int {
        LearningSlot.airConditioner(modes: orderedModes, range: minTemp...maxTemp).count
    }

    private var canCreate: Bool {
        if creating { return false }
        switch type {
        case .webhook: return true
        case .television where tvByNetwork: return LegacyCodesImporter.isValidIPv4(tvHost.trimmingCharacters(in: .whitespaces))
        case .airConditioner: return bridgeID != nil && !acModes.isEmpty
        default: return bridgeID != nil
        }
    }

    private var primaryTitle: String {
        switch type {
        case .television where tvByNetwork: String(localized: "Crear y emparejar")
        case .webhook: String(localized: "Crear y configurar")
        default: String(localized: "Crear y grabar códigos")
        }
    }

    private var primarySymbol: String {
        switch type {
        case .television where tvByNetwork: "link"
        case .webhook: "slider.horizontal.3"
        default: "dot.radiowaves.left.and.right"
        }
    }

    private var finalName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? type.defaultName : trimmed
    }

    // MARK: - Acciones

    private func searchTVs() {
        searchingTVs = true
        Task {
            let hosts = await LocalUDP.discoverSamsungTVs()
            foundTVs = hosts
            if tvHost.isEmpty, let first = hosts.first { tvHost = first }
            if hosts.isEmpty { errorText = String(localized: "No se encontró ninguna TV. Escribí su IP (Configuración → General → Red → Estado de red).") }
            else { errorText = nil }
            searchingTVs = false
        }
    }

    private func create() {
        errorText = nil
        switch type {
        case .airConditioner:
            let range = minTemp...maxTemp
            let device = Device(name: finalName, roomID: roomID, kind: .airConditioner,
                                transport: .broadlink(bridgeID: bridgeID), isFavorite: true, temperatureRange: range)
            finish(device, .learn(device, LearningSlot.airConditioner(modes: orderedModes, range: range)))
        case .television where tvByNetwork:
            createNetworkTV()
        case .webhook:
            let device = Device(name: finalName, symbol: "link", roomID: roomID, kind: .generic,
                                transport: .webhook(actions: []), isFavorite: true)
            finish(device, .editWebhook(device))
        default:
            let device = Device(name: finalName, roomID: roomID, kind: type.kind,
                                transport: .broadlink(bridgeID: bridgeID), isFavorite: true)
            finish(device, .learn(device, device.learningSlots))
        }
    }

    private func createNetworkTV() {
        let host = tvHost.trimmingCharacters(in: .whitespaces)
        creating = true
        Task {
            let probe = SamsungTVClient(deviceID: UUID(), host: host)
            let info = try? await probe.info()
            creating = false
            if info == nil {
                errorText = String(localized: "La TV no respondió en \(host). Encendela y revisá que esté en la misma red.")
                return
            }
            let name = self.name.trimmingCharacters(in: .whitespaces).isEmpty ? (info?.name ?? type.defaultName) : finalName
            let device = Device(name: name, roomID: roomID, kind: .television,
                                transport: .samsungTizen(host: host, macAddress: info?.wifiMac, fallbackBridgeID: tvFallbackBridge),
                                isFavorite: true)
            finish(device, .pairTV(device))
        }
    }

    private func finish(_ device: Device, _ next: AddDeviceNextStep) {
        model.store.upsert(device)
        dismiss()
        onCreated(next)
    }
}
