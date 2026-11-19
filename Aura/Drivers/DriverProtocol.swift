import Foundation

/// Contrato de todos los drivers. La UI nunca habla con un driver directo:
/// todo pasa por `CommandBus`.
protocol DeviceDriver: Sendable {
    var capabilities: Set<Capability> { get }
    /// Tiempo máximo para conectar (algunos drivers redescubren la red).
    var connectTimeout: Duration { get }
    var isReachable: Bool { get async }
    func connect() async throws
    func disconnect() async
    func send(_ command: Command) async throws
}

extension DeviceDriver {
    var connectTimeout: Duration { .seconds(3) }
}

/// Errores comunes a todos los drivers.
enum DriverError: UserFacingError, Equatable {
    case unsupported(String)
    case missingCode(String)
    case missingBridge
    case transportUnavailable(TransportKind)
    case unreachable

    var userMessage: String {
        switch self {
        case .unsupported(let what):
            String(localized: "Este dispositivo no admite \(what)")
        case .missingCode(let name):
            String(localized: "Falta grabar el código \"\(name)\"")
        case .missingBridge:
            String(localized: "No hay un Broadlink asignado a este dispositivo")
        case .transportUnavailable(let kind):
            String(localized: "\(kind.displayName) todavía no está disponible en esta versión")
        case .unreachable:
            String(localized: "No se pudo conectar con el dispositivo")
        }
    }
}
