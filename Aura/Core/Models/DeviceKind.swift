import Foundation

enum DeviceKind: String, Codable, Sendable, CaseIterable, Hashable, Identifiable {
    case airConditioner
    case television
    case light
    case fan
    case generic

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .airConditioner: String(localized: "Aire acondicionado")
        case .television: String(localized: "Televisor")
        case .light: String(localized: "Luces LED")
        case .fan: String(localized: "Ventilador")
        case .generic: String(localized: "Control IR genérico")
        }
    }

    var defaultSymbol: String {
        switch self {
        case .airConditioner: "air.conditioner.horizontal.fill"
        case .television: "tv.fill"
        case .light: "lightbulb.led.fill"
        case .fan: "fan.fill"
        case .generic: "av.remote.fill"
        }
    }

    var capabilities: Set<Capability> {
        switch self {
        case .airConditioner: [.power, .temperature, .mode, .fanSpeed, .swing]
        case .television: [.power, .volume, .channel, .navigation, .input, .apps]
        case .light: [.power, .color, .brightness, .customButtons]
        case .fan: [.power, .customButtons]
        case .generic: [.customButtons]
        }
    }
}
