import Foundation

/// Botón personalizado de un control genérico o de efectos.
struct CustomButton: Codable, Sendable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var symbol: String
    /// Nombre del código grabado en `Device.codes`.
    var codeName: String
    var tint: ButtonTint

    init(id: UUID = UUID(), name: String, symbol: String, codeName: String, tint: ButtonTint = .neutral) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.codeName = codeName
        self.tint = tint
    }
}

enum ButtonTint: String, Codable, Sendable, CaseIterable, Hashable {
    case neutral, blue, cyan, green, amber, red
}

struct Device: Codable, Sendable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var symbol: String
    var roomID: UUID?
    var kind: DeviceKind
    var transport: TransportConfig
    /// Códigos grabados: nombre → paquete IR crudo de Broadlink en base64.
    var codes: [String: String]
    var buttons: [CustomButton]
    var isFavorite: Bool
    var sortOrder: Int
    /// Rango de temperatura configurable para aires.
    var temperatureRange: ClosedRange<Int>
    /// Apps de TV editables.
    var tvApps: [TVApp]

    init(
        id: UUID = UUID(),
        name: String,
        symbol: String? = nil,
        roomID: UUID? = nil,
        kind: DeviceKind,
        transport: TransportConfig,
        codes: [String: String] = [:],
        buttons: [CustomButton] = [],
        isFavorite: Bool = false,
        sortOrder: Int = 0,
        temperatureRange: ClosedRange<Int> = ACSettings.defaultRange,
        tvApps: [TVApp] = []
    ) {
        self.id = id
        self.name = name
        self.symbol = symbol ?? kind.defaultSymbol
        self.roomID = roomID
        self.kind = kind
        self.transport = transport
        self.codes = codes
        self.buttons = buttons
        self.isFavorite = isFavorite
        self.sortOrder = sortOrder
        self.temperatureRange = temperatureRange
        self.tvApps = tvApps.isEmpty && kind == .television ? TVApp.defaults : tvApps
    }

    var capabilities: Set<Capability> { kind.capabilities }

    /// Colores grabados (para LEDs), en el orden de la paleta conocida y luego alfabético.
    var recordedColors: [String] {
        let known = LEDPalette.order.filter { codes[$0] != nil }
        let reserved = Set(LEDPalette.order).union(LEDPalette.reservedCodeNames)
        let others = codes.keys.filter { !reserved.contains($0) && !$0.hasPrefix("effect_") }.sorted()
        return known + others
    }

    /// Botones del asistente para este dispositivo: sugeridos + personalizados existentes.
    var learningSlots: [LearningSlot] {
        var slots: [LearningSlot]
        if kind == .airConditioner {
            // Frío siempre, más los modos que ya tengan algún código grabado.
            let modes = ACMode.allCases.filter { mode in
                mode == .cool || codes.keys.contains { $0 == mode.rawValue || $0.hasPrefix("\(mode.rawValue)_") }
            }
            slots = LearningSlot.airConditioner(modes: modes, range: temperatureRange)
        } else {
            slots = LearningSlot.presets(for: kind)
        }
        let known = Set(slots.map(\.codeName))
        for button in buttons where !known.contains(button.codeName) {
            slots.append(LearningSlot(codeName: button.codeName, title: button.name, symbol: button.symbol))
        }
        return slots
    }

    /// ¿Hay un código grabado para esta combinación de aire?
    func hasCode(for settings: ACSettings) -> Bool {
        codes[settings.codeName] != nil || codes[settings.codeNameIgnoringFan] != nil
    }

    /// Temperaturas grabadas para un modo dado.
    func recordedTemperatures(for mode: ACMode) -> [Int] {
        temperatureRange.filter { codes["\(mode.rawValue)_\($0)"] != nil }
    }
}
