import Foundation

/// TV Samsung por red, con respaldo IR por Broadlink si la red falla y hay códigos grabados.
struct SamsungTVDriver: DeviceDriver {
    let device: Device
    let client: SamsungTVClient
    let macAddress: String?
    /// Driver IR de respaldo (Broadlink) si la TV tiene un puente asignado.
    let fallback: (any DeviceDriver)?

    var capabilities: Set<Capability> { device.capabilities }
    var connectTimeout: Duration { .seconds(4) }

    var isReachable: Bool {
        get async { await client.isConnected }
    }

    func connect() async throws {
        try await client.connect()
    }

    func disconnect() async {
        await client.disconnect()
    }

    func send(_ command: Command) async throws {
        switch command {
        case .power(true):
            try await powerOn()
        case .power(false):
            try await withFallback(command) { try await client.send(.power) }
        case .tvKey(.power):
            if (try? await client.info(timeout: .seconds(2)))?.isOn == true {
                try await withFallback(command) { try await client.send(.power) }
            } else {
                try await powerOn()
            }
        case .tvKey(let key):
            try await withFallback(command) { try await client.send(key) }
        case .launchApp(let app):
            try await client.launch(app)
        case .button(let name):
            // Botones personalizados de la TV: van por IR.
            guard let fallback else { throw DriverError.unsupported(name) }
            try await fallback.send(command)
        default:
            throw DriverError.unsupported(String(localized: "este comando"))
        }
    }

    /// Wake-on-LAN y espera a que la TV responda; si no, KEY_POWER por IR.
    private func powerOn() async throws {
        if let info = try? await client.info(timeout: .seconds(1)), info.isOn {
            return
        }
        if let macAddress, let mac = parseMAC(macAddress), await LocalUDP.wake(mac: mac) {
            for _ in 0..<12 {
                try await Task.sleep(for: .milliseconds(500))
                if let info = try? await client.info(timeout: .seconds(1)), info.isOn { return }
            }
        }
        if let fallback, device.codes["key_power"] != nil {
            Log.tv.info("Wake-on-LAN sin respuesta: KEY_POWER por IR")
            try await fallback.send(.tvKey(.power))
            return
        }
        throw SamsungTVError.wakeFailed
    }

    private func withFallback(_ command: Command, _ network: () async throws -> Void) async throws {
        do {
            try await network()
        } catch {
            guard let fallback, let name = IRCodeResolver.codeName(for: command, device: device),
                  device.codes[name] != nil else { throw error }
            Log.tv.info("La TV no respondió por red: \(name, privacy: .public) por IR")
            try await fallback.send(command)
        }
    }
}
