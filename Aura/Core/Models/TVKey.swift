import Foundation

/// Teclas del control remoto Samsung (valores de `DataOfCmd` del protocolo Tizen).
enum TVKey: String, Codable, Sendable, CaseIterable, Hashable {
    case power = "KEY_POWER"
    case volumeUp = "KEY_VOLUP"
    case volumeDown = "KEY_VOLDOWN"
    case mute = "KEY_MUTE"
    case channelUp = "KEY_CHUP"
    case channelDown = "KEY_CHDOWN"
    case up = "KEY_UP"
    case down = "KEY_DOWN"
    case left = "KEY_LEFT"
    case right = "KEY_RIGHT"
    case enter = "KEY_ENTER"
    case back = "KEY_RETURN"
    case home = "KEY_HOME"
    case source = "KEY_SOURCE"
    case play = "KEY_PLAY"
    case pause = "KEY_PAUSE"
    case num0 = "KEY_0", num1 = "KEY_1", num2 = "KEY_2", num3 = "KEY_3", num4 = "KEY_4"
    case num5 = "KEY_5", num6 = "KEY_6", num7 = "KEY_7", num8 = "KEY_8", num9 = "KEY_9"

    static func digit(_ value: Int) -> TVKey? {
        TVKey(rawValue: "KEY_\(value)")
    }

    var displayName: String {
        switch self {
        case .power: String(localized: "Encender/apagar")
        case .volumeUp: String(localized: "Subir volumen")
        case .volumeDown: String(localized: "Bajar volumen")
        case .mute: String(localized: "Silencio")
        case .channelUp: String(localized: "Canal siguiente")
        case .channelDown: String(localized: "Canal anterior")
        case .up: String(localized: "Arriba")
        case .down: String(localized: "Abajo")
        case .left: String(localized: "Izquierda")
        case .right: String(localized: "Derecha")
        case .enter: String(localized: "OK")
        case .back: String(localized: "Volver")
        case .home: String(localized: "Inicio")
        case .source: String(localized: "Fuente")
        case .play: String(localized: "Reproducir")
        case .pause: String(localized: "Pausa")
        default: rawValue.replacingOccurrences(of: "KEY_", with: "")
        }
    }
}

struct TVApp: Codable, Sendable, Hashable, Identifiable {
    var id: String          // appId de Tizen
    var name: String
    var symbol: String

    static let defaults: [TVApp] = [
        TVApp(id: "3201907018807", name: "Netflix", symbol: "play.rectangle.fill"),
        TVApp(id: "111299001912", name: "YouTube", symbol: "play.tv.fill"),
    ]
}
