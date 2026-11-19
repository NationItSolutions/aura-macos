import Foundation

/// Crea el driver de cada dispositivo. En modo demo devuelve mocks.
/// No cachea: los drivers son livianos y el estado de conexión vive en `BroadlinkHub`,
/// así cada envío usa los códigos más recientes del dispositivo.
@MainActor
final class DriverRegistry {
    private(set) var demoMode: Bool
    let broadlink: BroadlinkHub
    /// Un cliente por TV (mantiene el WebSocket abierto entre comandos).
    private var tvClients: [UUID: SamsungTVClient] = [:]

    init(demoMode: Bool, broadlink: BroadlinkHub) {
        self.demoMode = demoMode
        self.broadlink = broadlink
    }

    func setDemoMode(_ demo: Bool) {
        demoMode = demo
    }

    func driver(for device: Device) -> any DeviceDriver {
        if demoMode {
            return MockDriver(device: device)
        }
        switch device.transport {
        case .broadlink(let bridgeID):
            guard let bridgeID else { return MissingBridgeDriver(capabilities: device.capabilities) }
            return BroadlinkDriver(device: device, bridgeID: bridgeID, hub: broadlink)
        case .samsungTizen(let host, let mac, let fallbackBridgeID):
            let fallback: (any DeviceDriver)? = fallbackBridgeID.map {
                BroadlinkDriver(device: device, bridgeID: $0, hub: broadlink)
            }
            return SamsungTVDriver(device: device, client: tvClient(for: device.id, host: host),
                                   macAddress: mac, fallback: fallback)
        case .webhook:
            return WebhookDriver(device: device)
        }
    }

    func tvClient(for deviceID: UUID, host: String) -> SamsungTVClient {
        if let client = tvClients[deviceID] {
            Task { await client.updateHost(host) }
            return client
        }
        let client = SamsungTVClient(deviceID: deviceID, host: host)
        tvClients[deviceID] = client
        return client
    }

    func forgetTV(_ deviceID: UUID) {
        if let client = tvClients.removeValue(forKey: deviceID) {
            Task { await client.forgetPairing() }
        } else {
            KeychainStore.delete(account: KeychainStore.tvTokenAccount(deviceID))
        }
    }

    /// Aprendizaje de códigos para un puente.
    func learner(for bridgeID: UUID?) async throws -> any CodeLearner {
        if demoMode { return MockLearner() }
        guard let bridgeID else { throw DriverError.missingBridge }
        return BroadlinkLearner(client: try await broadlink.client(for: bridgeID))
    }
}

/// Dispositivo IR sin puente asignado.
struct MissingBridgeDriver: DeviceDriver {
    let capabilities: Set<Capability>
    var isReachable: Bool { false }
    func connect() async throws { throw DriverError.missingBridge }
    func disconnect() async {}
    func send(_ command: Command) async throws { throw DriverError.missingBridge }
}
