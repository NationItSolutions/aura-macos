import Foundation

/// Administra los clientes Broadlink (uno por puente), el descubrimiento y el
/// redescubrimiento por MAC cuando el router cambia la IP (DHCP).
@MainActor
final class BroadlinkHub {
    typealias Scanner = @Sendable (_ timeout: Duration, _ address: String) async throws -> [DiscoveredBroadlink]

    private let store: AppStore
    private var clients: [UUID: BroadlinkClient] = [:]
    private let transport: any UDPTransport
    private let scanner: Scanner

    init(
        store: AppStore,
        transport: any UDPTransport = NWUDPTransport(),
        scanner: @escaping Scanner = { timeout, address in try await BroadlinkScanner.scan(timeout: timeout, address: address) }
    ) {
        self.store = store
        self.transport = transport
        self.scanner = scanner
    }

    /// Cliente ya creado para un puente (sin tocar la red).
    func existingClient(_ bridgeID: UUID) -> BroadlinkClient? { clients[bridgeID] }

    /// Devuelve el cliente del puente. Si al puente le falta la MAC o el tipo (por ejemplo,
    /// vino del codigos.json con solo la IP), primero lo identifica con un "hello" directo.
    func client(for bridgeID: UUID) async throws -> BroadlinkClient {
        guard var bridge = store.bridge(bridgeID) else { throw DriverError.missingBridge }
        if let client = clients[bridgeID] {
            await client.updateHost(bridge.host)
            return client
        }
        if bridge.macAddress == nil || bridge.deviceType == nil {
            guard let found = try await scanner(.seconds(2), bridge.host).first else { throw BroadlinkError.notFound }
            if found.isLocked { throw BroadlinkError.locked }
            bridge.macAddress = formatMAC(found.mac)
            bridge.deviceType = found.deviceType
            store.upsert(bridge)
        }
        if let client = clients[bridgeID] { return client }
        guard let macString = bridge.macAddress, let mac = parseMAC(macString), let deviceType = bridge.deviceType else {
            throw BroadlinkError.missingIdentity
        }
        let client = try BroadlinkClient(host: bridge.host, mac: mac, deviceType: deviceType, transport: transport)
        clients[bridgeID] = client
        return client
    }

    /// Busca el puente por su MAC en toda la red. Si cambió de IP, la actualiza.
    /// Devuelve `true` si lo encontró.
    func rediscover(bridgeID: UUID) async throws -> Bool {
        guard var bridge = store.bridge(bridgeID), let macString = bridge.macAddress, let mac = parseMAC(macString) else {
            return false
        }
        let found = try await scanner(.seconds(2), "255.255.255.255")
        guard let match = found.first(where: { $0.mac == mac }) else { return false }
        if match.isLocked { throw BroadlinkError.locked }
        if match.host != bridge.host {
            Log.broadlink.info("El Broadlink cambió de IP: \(bridge.host, privacy: .public) → \(match.host, privacy: .public)")
            bridge.host = match.host
            store.upsert(bridge)
            await clients[bridgeID]?.updateHost(match.host)
        }
        return true
    }

    /// Descubre los Broadlink de la red por broadcast.
    func discover(timeout: Duration = .seconds(3)) async throws -> [DiscoveredBroadlink] {
        try await scanner(timeout, "255.255.255.255")
    }

    /// Identifica un Broadlink por IP directa (para redes que bloquean el broadcast).
    func probe(host: String) async throws -> DiscoveredBroadlink {
        guard LegacyCodesImporter.isValidIPv4(host) else { throw BroadlinkError.notFound }
        guard let found = try await scanner(.seconds(3), host).first else { throw BroadlinkError.notFound }
        return found
    }

    /// Guarda (o actualiza, si ya existe la misma MAC o IP) un puente descubierto.
    @discardableResult
    func add(_ discovered: DiscoveredBroadlink) -> Bridge {
        let mac = formatMAC(discovered.mac)
        var bridge = store.bridges.first { $0.macAddress.flatMap(parseMAC) == discovered.mac }
            ?? store.bridges.first { $0.host == discovered.host }
            ?? Bridge(name: discovered.name.isEmpty ? discovered.modelName : discovered.name, host: discovered.host)
        bridge.host = discovered.host
        bridge.macAddress = mac
        bridge.deviceType = discovered.deviceType
        store.upsert(bridge)
        clients[bridge.id] = nil
        return bridge
    }

    /// Prueba la conexión autenticando contra el puente.
    func testConnection(bridgeID: UUID) async throws {
        let client = try await client(for: bridgeID)
        do {
            try await client.authenticate()
        } catch BroadlinkError.timeout {
            guard try await rediscover(bridgeID: bridgeID) else { throw BroadlinkError.notFound }
            try await client.authenticate()
        }
    }

    func forget(_ bridgeID: UUID) {
        clients[bridgeID] = nil
    }
}
