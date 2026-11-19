import Foundation

enum TransportKind: String, Codable, Sendable, CaseIterable, Hashable {
    case broadlinkIR
    case broadlinkRF
    case samsungTizen
    case webhook

    var displayName: String {
        switch self {
        case .broadlinkIR: String(localized: "Broadlink · IR")
        case .broadlinkRF: String(localized: "Broadlink · RF")
        case .samsungTizen: String(localized: "Samsung Tizen")
        case .webhook: String(localized: "Webhook HTTP")
        }
    }
}

/// Configuración específica del transporte. Nada de IPs ni MACs hardcodeadas:
/// todo se descubre o lo ingresa el usuario.
enum TransportConfig: Codable, Sendable, Hashable {
    case broadlink(bridgeID: UUID?)
    case samsungTizen(host: String, macAddress: String?, fallbackBridgeID: UUID?)
    case webhook

    var kind: TransportKind {
        switch self {
        case .broadlink: .broadlinkIR
        case .samsungTizen: .samsungTizen
        case .webhook: .webhook
        }
    }

    var bridgeID: UUID? {
        switch self {
        case .broadlink(let id): id
        case .samsungTizen(_, _, let fallback): fallback
        case .webhook: nil
        }
    }
}

/// Un puente Broadlink (RM4 Mini, RM4 Pro, ...).
struct Bridge: Codable, Sendable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var host: String
    var macAddress: String?
    /// Código de tipo de dispositivo reportado por el Broadlink (define la familia RM / RM4).
    var deviceType: UInt16?

    init(id: UUID = UUID(), name: String, host: String, macAddress: String? = nil, deviceType: UInt16? = nil) {
        self.id = id
        self.name = name
        self.host = host
        self.macAddress = macAddress
        self.deviceType = deviceType
    }
}
