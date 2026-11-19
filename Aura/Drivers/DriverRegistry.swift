import Foundation

/// Crea y cachea un driver por dispositivo. En modo demo devuelve mocks.
@MainActor
final class DriverRegistry {
    private var drivers: [UUID: any DeviceDriver] = [:]
    private(set) var demoMode: Bool

    init(demoMode: Bool) {
        self.demoMode = demoMode
    }

    func setDemoMode(_ demo: Bool) {
        guard demo != demoMode else { return }
        demoMode = demo
        let old = Array(drivers.values)
        drivers.removeAll()
        Task { for driver in old { await driver.disconnect() } }
    }

    /// Descarta el driver cacheado (por ejemplo, si cambió la configuración del dispositivo).
    func invalidate(_ deviceID: UUID) {
        if let driver = drivers.removeValue(forKey: deviceID) {
            Task { await driver.disconnect() }
        }
    }

    func driver(for device: Device) -> any DeviceDriver {
        if let cached = drivers[device.id] { return cached }
        let driver = makeDriver(for: device)
        drivers[device.id] = driver
        return driver
    }

    private func makeDriver(for device: Device) -> any DeviceDriver {
        if demoMode {
            return MockDriver(device: device)
        }
        return UnavailableDriver(transport: device.transport.kind, capabilities: device.capabilities)
    }
}
