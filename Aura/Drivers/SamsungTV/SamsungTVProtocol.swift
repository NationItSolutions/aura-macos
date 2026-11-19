import Foundation

/// Mensajes y formatos del control remoto de las Smart TV Samsung (Tizen, 2016+).
/// Todo es puro para poder probarlo sin red.
enum SamsungTVProtocol {
    static let appName = "Aura"
    static let remotePort = 8002
    static let restPort = 8001
    static let ssdpTarget = "urn:samsung.com:device:RemoteControlReceiver:1"

    /// wss://<ip>:8002/api/v2/channels/samsung.remote.control?name=<base64("Aura")>[&token=<token>]
    static func remoteURL(host: String, token: String?) -> URL? {
        var components = URLComponents()
        components.scheme = "wss"
        components.host = host
        components.port = remotePort
        components.path = "/api/v2/channels/samsung.remote.control"
        var items = [URLQueryItem(name: "name", value: Data(appName.utf8).base64EncodedString())]
        if let token, !token.isEmpty { items.append(URLQueryItem(name: "token", value: token)) }
        components.queryItems = items
        return components.url
    }

    /// http://<ip>:8001/api/v2/
    static func infoURL(host: String) -> URL? {
        URL(string: "http://\(host):\(restPort)/api/v2/")
    }

    /// http://<ip>:8001/api/v2/applications/<appId>
    static func applicationURL(host: String, appID: String) -> URL? {
        guard appID.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "_" }) else { return nil }
        return URL(string: "http://\(host):\(restPort)/api/v2/applications/\(appID)")
    }

    /// {"method":"ms.remote.control","params":{"Cmd":"Click","DataOfCmd":"KEY_VOLUP","Option":"false","TypeOfRemote":"SendRemoteKey"}}
    static func keyMessage(_ key: TVKey) -> String {
        let payload = KeyPayload(method: "ms.remote.control",
                                 params: .init(Cmd: "Click", DataOfCmd: key.rawValue, Option: "false", TypeOfRemote: "SendRemoteKey"))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(payload) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    private struct KeyPayload: Encodable {
        struct Params: Encodable {
            // Los nombres de campo los define el protocolo de Samsung.
            // swiftlint:disable identifier_name
            let Cmd: String
            let DataOfCmd: String
            let Option: String
            let TypeOfRemote: String
            // swiftlint:enable identifier_name
        }
        let method: String
        let params: Params
    }

    /// Eventos del canal que nos importan.
    enum ChannelEvent: Equatable, Sendable {
        case connected(token: String?)
        case unauthorized
        case timeout
        case other(String)
    }

    static func parseEvent(_ text: String) -> ChannelEvent? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let event = object["event"] as? String else { return nil }
        switch event {
        case "ms.channel.connect":
            let payload = object["data"] as? [String: Any]
            let token: String?
            if let string = payload?["token"] as? String {
                token = string
            } else if let number = payload?["token"] as? NSNumber {
                token = number.stringValue
            } else {
                token = nil
            }
            return .connected(token: token)
        case "ms.channel.unauthorized":
            return .unauthorized
        case "ms.channel.timeOut":
            return .timeout
        default:
            return .other(event)
        }
    }

    /// Datos de GET /api/v2/.
    struct DeviceInfo: Equatable, Sendable {
        var name: String
        var modelName: String
        var wifiMac: String?
        var powerState: String?
        var tokenAuthSupported: Bool

        var isOn: Bool { powerState.map { $0.lowercased() == "on" } ?? true }
    }

    static func parseInfo(_ data: Data) -> DeviceInfo? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let device = object["device"] as? [String: Any] else { return nil }
        let rawName = (device["name"] as? String) ?? (object["name"] as? String) ?? "Samsung TV"
        let name = rawName.replacingOccurrences(of: "[TV] ", with: "")
        let mac = (device["wifiMac"] as? String).flatMap { parseMAC($0) != nil ? $0.lowercased() : nil }
        return DeviceInfo(
            name: name,
            modelName: (device["modelName"] as? String) ?? "",
            wifiMac: mac,
            powerState: device["PowerState"] as? String,
            tokenAuthSupported: (device["TokenAuthSupport"] as? String)?.lowercased() == "true"
        )
    }

    /// Paquete mágico de Wake-on-LAN: 6 × 0xFF + 16 × MAC.
    static func wakeOnLANPacket(mac: [UInt8]) -> [UInt8]? {
        guard mac.count == 6 else { return nil }
        return [UInt8](repeating: 0xFF, count: 6) + Array([[UInt8]](repeating: mac, count: 16).joined())
    }

    /// M-SEARCH de SSDP para encontrar TVs Samsung.
    static func ssdpSearch(mx: Int = 2) -> String {
        [
            "M-SEARCH * HTTP/1.1",
            "HOST: 239.255.255.250:1900",
            "MAN: \"ssdp:discover\"",
            "MX: \(mx)",
            "ST: \(ssdpTarget)",
            "", "",
        ].joined(separator: "\r\n")
    }

    /// Extrae el host de la cabecera LOCATION de una respuesta SSDP de Samsung.
    static func parseSSDPResponse(_ text: String) -> String? {
        let lines = text.components(separatedBy: "\r\n")
        guard lines.contains(where: { $0.lowercased().hasPrefix("st:") && $0.contains("samsung.com:device:RemoteControlReceiver") })
        else { return nil }
        guard let location = lines.first(where: { $0.lowercased().hasPrefix("location:") }) else { return nil }
        let value = location.dropFirst("location:".count).trimmingCharacters(in: .whitespaces)
        return URL(string: value)?.host
    }
}
