import Foundation

/// Driver de dispositivos IR/RF que pasan por un Broadlink.
struct BroadlinkDriver: DeviceDriver {
    let device: Device
    let bridgeID: UUID
    let hub: BroadlinkHub

    var capabilities: Set<Capability> { device.capabilities }
    /// Conectar puede incluir un redescubrimiento por broadcast.
    var connectTimeout: Duration { .seconds(6) }

    var isReachable: Bool {
        get async {
            guard let client = await hub.existingClient(bridgeID) else { return false }
            return await client.isAuthenticated
        }
    }

    func connect() async throws {
        let client = try await hub.client(for: bridgeID)
        do {
            try await client.authenticate()
        } catch BroadlinkError.timeout {
            // Puede que el router le haya dado otra IP: lo buscamos por MAC.
            guard try await hub.rediscover(bridgeID: bridgeID) else { throw BroadlinkError.notFound }
            try await client.authenticate()
        }
    }

    func disconnect() async {
        await hub.existingClient(bridgeID)?.invalidate()
    }

    func send(_ command: Command) async throws {
        guard let name = IRCodeResolver.codeName(for: command, device: device) else {
            throw DriverError.unsupported(String(localized: "este comando"))
        }
        guard let base64 = device.codes[name] else { throw DriverError.missingCode(name) }
        guard let code = Data(base64Encoded: base64), !code.isEmpty else { throw BroadlinkError.invalidCode }
        let client = try await hub.client(for: bridgeID)
        try await client.send(code: code)
    }
}

/// Graba y prueba códigos. Lo usa el asistente de aprendizaje.
protocol CodeLearner: Sendable {
    var supportsRadio: Bool { get async }
    func learn(_ kind: SignalKind, timeout: Duration, onPhase: @escaping @Sendable (LearningPhase) -> Void) async throws -> Data
    func test(_ code: Data) async throws
    func cancel() async
}

struct BroadlinkLearner: CodeLearner {
    let client: BroadlinkClient

    var supportsRadio: Bool {
        get async { client.family.supportsRF }
    }

    func learn(_ kind: SignalKind, timeout: Duration, onPhase: @escaping @Sendable (LearningPhase) -> Void) async throws -> Data {
        switch kind {
        case .infrared:
            onPhase(.listening)
            return try await client.learnInfrared(timeout: timeout)
        case .radio:
            return try await client.learnRadio(timeout: timeout, onPhase: onPhase)
        }
    }

    func test(_ code: Data) async throws {
        try await client.send(code: code)
    }

    func cancel() async {
        await client.cancelLearning()
    }
}

/// Aprendizaje simulado para el modo demo: "recibe" un código a los pocos segundos.
struct MockLearner: CodeLearner {
    var delay: Duration = .milliseconds(2200)

    var supportsRadio: Bool { get async { true } }

    func learn(_ kind: SignalKind, timeout: Duration, onPhase: @escaping @Sendable (LearningPhase) -> Void) async throws -> Data {
        if kind == .radio {
            onPhase(.sweeping)
            try await Task.sleep(for: delay)
            onPhase(.frequencyFound(433.92))
        } else {
            onPhase(.listening)
        }
        try await Task.sleep(for: delay)
        let pulses = (0..<34).flatMap { index in index == 0 ? [9000, 4500] : [560, Bool.random() ? 1690 : 560] }
        return Data(BroadlinkProtocol.pulsesToPacket(pulses + [560, 40000]))
    }

    func test(_ code: Data) async throws {
        try await Task.sleep(for: .milliseconds(200))
    }

    func cancel() async {}
}
