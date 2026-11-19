import Foundation

enum TransportKind: String, Codable, Sendable, CaseIterable, Hashable {
    case broadlinkIR
    case broadlinkRF
    case samsungTizen
    case webhook

    var displayName: String {
        switch self {
        case .broadlinkIR: String(localized: "Broadlink · IR")
        case .broadlinkRF: String(localized: "Broadlink · RF")
        case .samsungTizen: String(localized: "Samsung Tizen")
        case .webhook: String(localized: "Webhook HTTP")
        }
    }
}

/// Configuración específica del transporte. Nada de IPs ni MACs hardcodeadas:
/// todo se descubre o lo ingresa el usuario.
enum TransportConfig: Codable, Sendable, Hashable {
    case broadlink(bridgeID: UUID?)
    case samsungTizen(host: String, macAddress: String?, fallbackBridgeID: UUID?)
    /// Botones HTTP (Home Assistant, Shelly, Tasmota, n8n…).
    case webhook(actions: [WebhookAction])

    var kind: TransportKind {
        switch self {
        case .broadlink: .broadlinkIR
        case .samsungTizen: .samsungTizen
        case .webhook: .webhook
        }
    }

    var bridgeID: UUID? {
        switch self {
        case .broadlink(let id): id
        case .samsungTizen(_, _, let fallback): fallback
        case .webhook: nil
        }
    }
}

/// Un puente Broadlink (RM4 Mini, RM4 Pro, ...).
struct Bridge: Codable, Sendable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var host: String
    var macAddress: String?
    /// Código de tipo de dispositivo reportado por el Broadlink (define la familia RM / RM4).
    var deviceType: UInt16?

    init(id: UUID = UUID(), name: String, host: String, macAddress: String? = nil, deviceType: UInt16? = nil) {
        self.id = id
        self.name = name
        self.host = host
        self.macAddress = macAddress
        self.deviceType = deviceType
    }
}

/// Un botón de un dispositivo webhook: método, URL, cabeceras y cuerpo configurables.
struct WebhookAction: Codable, Sendable, Hashable, Identifiable {
    enum Method: String, Codable, Sendable, CaseIterable, Hashable {
        case get = "GET", post = "POST", put = "PUT"
    }

    var id: UUID
    var name: String
    var symbol: String
    var method: Method
    var url: String
    var headers: [String: String]
    var body: String
    /// Acción de encendido/apagado (para el botón de power y las escenas).
    var role: Role

    enum Role: String, Codable, Sendable, CaseIterable, Hashable {
        case button, powerOn, powerOff
    }

    init(id: UUID = UUID(), name: String, symbol: String = "bolt.fill", method: Method = .post, url: String = "",
         headers: [String: String] = [:], body: String = "", role: Role = .button) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
        self.role = role
    }

    /// URL válida http(s).
    var resolvedURL: URL? {
        guard let url = URL(string: url.trimmingCharacters(in: .whitespaces)),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https", url.host != nil else { return nil }
        return url
    }

    func request(timeout: TimeInterval = 3) -> URLRequest? {
        guard let url = resolvedURL else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.timeoutInterval = timeout
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        if method != .get, !body.isEmpty {
            request.httpBody = Data(body.utf8)
            if request.value(forHTTPHeaderField: "Content-Type") == nil {
                let trimmed = body.trimmingCharacters(in: .whitespaces)
                let isJSON = trimmed.hasPrefix("{") || trimmed.hasPrefix("[")
                request.setValue(isJSON ? "application/json" : "text/plain", forHTTPHeaderField: "Content-Type")
            }
        }
        return request
    }
}
