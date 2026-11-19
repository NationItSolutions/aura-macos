import Foundation

/// Driver simulado con latencia, para el modo demo y los tests.
actor MockDriver: DeviceDriver {
    struct Configuration: Sendable {
        var latency: ClosedRange<Double> = 0.12...0.35
        /// Probabilidad de fallo por envío (0 = nunca).
        var failureRate: Double = 0
        /// Si es `true`, valida que exista un código grabado para comandos IR.
        var requiresCodes: Bool = false
    }

    nonisolated let capabilities: Set<Capability>
    private let device: Device
    private let configuration: Configuration
    private(set) var connected = false
    private(set) var sent: [Command] = []

    init(device: Device, configuration: Configuration = Configuration()) {
        self.device = device
        self.capabilities = device.capabilities
        self.configuration = configuration
    }

    var isReachable: Bool { connected }

    func connect() async throws {
        try await simulateLatency()
        connected = true
    }

    func disconnect() async {
        connected = false
    }

    func send(_ command: Command) async throws {
        if !connected { try await connect() }
        try await simulateLatency()
        if configuration.failureRate > 0, Double.random(in: 0..<1) < configuration.failureRate {
            throw DriverError.unreachable
        }
        if configuration.requiresCodes, let name = IRCodeResolver.codeName(for: command, device: device),
           device.codes[name] == nil {
            throw DriverError.missingCode(name)
        }
        sent.append(command)
    }

    private func simulateLatency() async throws {
        let seconds = Double.random(in: configuration.latency)
        try await Task.sleep(for: .milliseconds(Int(seconds * 1000)))
    }
}
