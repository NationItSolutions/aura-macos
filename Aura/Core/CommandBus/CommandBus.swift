import Foundation
import Observation

/// Resultado de un comando o escena, para el feedback visual (toast, isla, tarjeta).
struct CommandFeedback: Identifiable, Equatable, Sendable {
    let id = UUID()
    var deviceID: UUID?
    var title: String
    var message: String?
    var isError: Bool
    var symbol: String
    var date: Date = .now
}

/// Falla de un comando ya traducida a texto para la UI.
struct CommandFailure: Error, Equatable, Sendable {
    var message: String
}

/// Cola de comandos: serializa los envíos por dispositivo, aplica timeout,
/// reintenta una vez reconectando y publica el resultado.
@MainActor
@Observable
final class CommandBus {
    typealias DriverProvider = @MainActor (Device) -> any DeviceDriver

    private(set) var lastFeedback: CommandFeedback?
    private(set) var busyDevices: Set<UUID> = []

    @ObservationIgnored var timeout: Duration = .seconds(3)
    @ObservationIgnored private let driverProvider: DriverProvider
    @ObservationIgnored private var tails: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var pending: [UUID: Int] = [:]

    init(driverProvider: @escaping DriverProvider) {
        self.driverProvider = driverProvider
    }

    func isBusy(_ deviceID: UUID) -> Bool { busyDevices.contains(deviceID) }

    /// Envía un comando. Espera a que terminen los comandos anteriores del mismo dispositivo.
    @discardableResult
    func send(_ command: Command, to device: Device, publishFeedback: Bool = true) async -> Result<Void, CommandFailure> {
        let driver = driverProvider(device)
        let previous = tails[device.id]
        let timeout = self.timeout

        let task = Task { () -> Result<Void, CommandFailure> in
            await previous?.value
            return await Self.execute(command, on: driver, timeout: timeout)
        }
        tails[device.id] = Task { _ = await task.value }
        pending[device.id, default: 0] += 1
        busyDevices.insert(device.id)

        let result = await task.value

        let remaining = (pending[device.id] ?? 1) - 1
        if remaining <= 0 {
            pending[device.id] = nil
            tails[device.id] = nil
            busyDevices.remove(device.id)
        } else {
            pending[device.id] = remaining
        }

        switch result {
        case .success:
            Log.commandBus.debug("OK \(device.name, privacy: .public)")
            if publishFeedback {
                publish(CommandFeedback(deviceID: device.id, title: command.summary(for: device),
                                        isError: false, symbol: device.symbol))
            }
        case .failure(let failure):
            Log.commandBus.error("Error \(device.name, privacy: .public): \(failure.message, privacy: .public)")
            if publishFeedback {
                publish(CommandFeedback(deviceID: device.id, title: device.name, message: failure.message,
                                        isError: true, symbol: "exclamationmark.triangle.fill"))
            }
        }
        return result
    }

    func publish(_ feedback: CommandFeedback) {
        lastFeedback = feedback
    }

    /// Un intento + un reintento con reconexión.
    nonisolated static func execute(
        _ command: Command,
        on driver: any DeviceDriver,
        timeout: Duration
    ) async -> Result<Void, CommandFailure> {
        do {
            try await withTimeout(timeout) { try await driver.send(command) }
            return .success(())
        } catch {
            if error is CancellationError || !isRetryable(error) {
                return .failure(CommandFailure(message: error.displayMessage))
            }
            Log.commandBus.info("Reintentando tras: \(error.displayMessage, privacy: .public)")
            do {
                await driver.disconnect()
                try await withTimeout(driver.connectTimeout) { try await driver.connect() }
                try await withTimeout(timeout) { try await driver.send(command) }
                return .success(())
            } catch {
                return .failure(CommandFailure(message: error.displayMessage))
            }
        }
    }

    /// Errores de configuración (falta un código, transporte no disponible) no se reintentan.
    nonisolated static func isRetryable(_ error: any Error) -> Bool {
        if let driverError = error as? DriverError {
            switch driverError {
            case .unreachable: return true
            case .unsupported, .missingCode, .missingBridge, .transportUnavailable: return false
            }
        }
        if let broadlink = error as? BroadlinkError {
            switch broadlink {
            case .timeout, .deviceError, .invalidResponse, .notFound: return true
            case .locked, .localNetworkDenied, .authenticationFailed, .unsupportedDevice,
                 .learningTimedOut, .rfNotSupported, .invalidCode, .missingIdentity: return false
            }
        }
        return true
    }
}
