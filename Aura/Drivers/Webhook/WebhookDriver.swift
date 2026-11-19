import Foundation

enum WebhookError: UserFacingError, Equatable {
    case invalidURL(String)
    case httpStatus(Int)
    case unreachable

    var userMessage: String {
        switch self {
        case .invalidURL(let name): String(localized: "La URL de «\(name)» no es válida")
        case .httpStatus(let code): String(localized: "El servidor respondió con error \(code)")
        case .unreachable: String(localized: "No se pudo conectar con el servidor del webhook")
        }
    }
}

/// Dispositivo que se controla con pedidos HTTP configurables por botón.
struct WebhookDriver: DeviceDriver {
    let device: Device

    var capabilities: Set<Capability> { device.capabilities }
    var isReachable: Bool { true }
    func connect() async throws {}
    func disconnect() async {}

    private var actions: [WebhookAction] {
        if case .webhook(let actions) = device.transport { return actions }
        return []
    }

    func send(_ command: Command) async throws {
        let action: WebhookAction?
        switch command {
        case .power(let on):
            action = actions.first { $0.role == (on ? .powerOn : .powerOff) }
        case .button(let idOrName):
            action = actions.first { $0.id.uuidString == idOrName || $0.name == idOrName }
        default:
            action = nil
        }
        guard let action else { throw DriverError.unsupported(String(localized: "este comando")) }
        guard let request = action.request() else { throw WebhookError.invalidURL(action.name) }
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                throw WebhookError.httpStatus(http.statusCode)
            }
        } catch let error as WebhookError {
            throw error
        } catch {
            throw WebhookError.unreachable
        }
    }
}
