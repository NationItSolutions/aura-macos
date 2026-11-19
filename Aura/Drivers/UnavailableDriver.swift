import Foundation

/// Driver de un transporte que todavía no está implementado en esta versión.
/// Falla de forma explícita con un mensaje claro en vez de simular éxito.
struct UnavailableDriver: DeviceDriver {
    let transport: TransportKind
    let capabilities: Set<Capability>

    var isReachable: Bool { false }
    func connect() async throws { throw DriverError.transportUnavailable(transport) }
    func disconnect() async {}
    func send(_ command: Command) async throws { throw DriverError.transportUnavailable(transport) }
}
