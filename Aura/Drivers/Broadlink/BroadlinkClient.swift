import Foundation

/// Tipo de señal a grabar.
enum SignalKind: String, Codable, Sendable, Hashable {
    case infrared
    case radio
}

/// Fases del aprendizaje, para mostrar en el asistente.
enum LearningPhase: Sendable, Equatable {
    case listening
    /// RF: buscando la frecuencia (mantener apretado el botón).
    case sweeping
    /// RF: frecuencia encontrada, ahora apretar el botón una vez.
    case frequencyFound(Double)
}

/// Cliente de un Broadlink: autenticación, envío y aprendizaje.
/// Es un actor: serializa los pedidos y protege la sesión (clave, ID, contador).
actor BroadlinkClient {
    private(set) var host: String
    nonisolated let family: BroadlinkFamily
    private var session: BroadlinkSession
    private(set) var isAuthenticated = false
    private let transport: any UDPTransport
    /// Cola interna: un pedido a la vez (varios dispositivos comparten el mismo puente).
    private var queueTail: Task<Void, Never>?

    var requestTimeout: Duration = .seconds(2)
    var retryInterval: Duration = .milliseconds(500)
    var pollInterval: Duration = .seconds(1)

    init(host: String, mac: [UInt8], deviceType: UInt16, transport: any UDPTransport = NWUDPTransport(),
         initialCount: UInt16 = UInt16.random(in: 0x8000...0xFFFF)) throws {
        guard let family = BroadlinkFamily(deviceType: deviceType) else {
            throw BroadlinkError.unsupportedDevice(deviceType)
        }
        self.host = host
        self.family = family
        self.transport = transport
        self.session = BroadlinkSession(deviceType: deviceType, mac: mac, count: initialCount)
    }

    var mac: [UInt8] { session.mac }

    func updateHost(_ host: String) {
        guard host != self.host else { return }
        self.host = host
        isAuthenticated = false
    }

    func invalidate() {
        isAuthenticated = false
    }

    func setPollInterval(_ interval: Duration) {
        pollInterval = interval
    }

    // MARK: - Autenticación

    func authenticate() async throws {
        try await enqueue { client in try await client.performAuthenticate() }
    }

    private func performAuthenticate() async throws {
        session.reset()
        let packet = try BroadlinkProtocol.packet(type: .auth, payload: BroadlinkProtocol.authPayload, session: &session)
        let response = try await transport.request(packet, host: host, port: BroadlinkProtocol.port,
                                                   timeout: requestTimeout, retryInterval: retryInterval)
        let payload: [UInt8]
        do {
            payload = try BroadlinkProtocol.decodeResponse(response, key: session.key)
        } catch BroadlinkError.deviceError(let code) where code == -1 {
            throw BroadlinkError.locked
        }
        let (id, key) = try BroadlinkProtocol.parseAuth(payload)
        session.id = id
        session.key = key
        isAuthenticated = true
        Log.broadlink.info("Autenticado con \(self.host, privacy: .public)")
    }

    // MARK: - Comandos

    /// Envía un comando de control remoto. Autentica si hace falta y reintenta una vez
    /// si la sesión venció.
    @discardableResult
    func remote(_ command: BroadlinkProtocol.RemoteCommand, data: [UInt8] = []) async throws -> [UInt8] {
        try await enqueue { client in try await client.performRemote(command, data: data) }
    }

    private func performRemote(_ command: BroadlinkProtocol.RemoteCommand, data: [UInt8]) async throws -> [UInt8] {
        if !isAuthenticated { try await performAuthenticate() }
        do {
            return try await rawRemote(command, data: data)
        } catch let error as BroadlinkError where error.requiresReauthentication {
            try await performAuthenticate()
            return try await rawRemote(command, data: data)
        }
    }

    /// Ejecuta `operation` después de que terminen los pedidos anteriores.
    private func enqueue<T: Sendable>(
        _ operation: @escaping @Sendable (isolated BroadlinkClient) async throws -> T
    ) async throws -> T {
        let previous = queueTail
        let task = Task { () async throws -> T in
            await previous?.value
            return try await operation(self)
        }
        queueTail = Task { _ = try? await task.value }
        return try await task.value
    }

    private func rawRemote(_ command: BroadlinkProtocol.RemoteCommand, data: [UInt8]) async throws -> [UInt8] {
        let payload = BroadlinkProtocol.remotePayload(command, data: data, family: family)
        let packet = try BroadlinkProtocol.packet(type: .command, payload: payload, session: &session)
        let response = try await transport.request(packet, host: host, port: BroadlinkProtocol.port,
                                                   timeout: requestTimeout, retryInterval: retryInterval)
        let decrypted = try BroadlinkProtocol.decodeResponse(response, key: session.key)
        return BroadlinkProtocol.remoteResponseData(decrypted, family: family)
    }

    /// Reproduce un código IR o RF grabado.
    func send(code: Data) async throws {
        guard !code.isEmpty else { throw BroadlinkError.invalidCode }
        try await remote(.sendData, data: [UInt8](code))
    }

    // MARK: - Aprendizaje

    /// Graba un código IR: entra en modo aprendizaje y consulta cada segundo hasta recibir datos.
    func learnInfrared(timeout: Duration = .seconds(30)) async throws -> Data {
        try await remote(.enterLearning)
        return try await pollLearnedData(until: ContinuousClock.now + timeout)
    }

    /// Graba un código RF (solo RM Pro / RM4 Pro): barrido de frecuencia y luego captura.
    func learnRadio(
        timeout: Duration = .seconds(30),
        onPhase: @escaping @Sendable (LearningPhase) -> Void
    ) async throws -> Data {
        guard family.supportsRF else { throw BroadlinkError.rfNotSupported }
        let deadline = ContinuousClock.now + timeout
        onPhase(.sweeping)
        try await remote(.sweepFrequency)
        var frequency: Double?
        do {
            while ContinuousClock.now < deadline {
                try await Task.sleep(for: pollInterval)
                let result = try BroadlinkProtocol.parseFrequency(try await remote(.checkFrequency))
                if result.found {
                    frequency = result.megahertz
                    break
                }
            }
        } catch {
            _ = try? await remote(.cancelSweep)
            throw error
        }
        guard let frequency else {
            _ = try? await remote(.cancelSweep)
            throw BroadlinkError.learningTimedOut
        }
        onPhase(.frequencyFound(frequency))
        try await remote(.findRFPacket, data: BroadlinkProtocol.rfFrequencyData(frequency))
        return try await pollLearnedData(until: deadline)
    }

    /// Cancela un barrido RF en curso (no-op en IR).
    func cancelLearning() async {
        if family.supportsRF { _ = try? await remote(.cancelSweep) }
    }

    private func pollLearnedData(until deadline: ContinuousClock.Instant) async throws -> Data {
        while ContinuousClock.now < deadline {
            try await Task.sleep(for: pollInterval)
            do {
                let data = try await remote(.checkData)
                if !data.isEmpty { return Data(data) }
            } catch BroadlinkError.deviceError(let code) where code == -10 || code == -5 {
                continue // Todavía no hay datos.
            }
        }
        throw BroadlinkError.learningTimedOut
    }
}
