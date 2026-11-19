import Foundation

enum ACMode: String, Codable, Sendable, CaseIterable, Hashable, Identifiable {
    case cool, heat, fan, dry, auto

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cool: String(localized: "Frío")
        case .heat: String(localized: "Calor")
        case .fan: String(localized: "Ventilación")
        case .dry: String(localized: "Deshumidificar")
        case .auto: String(localized: "Automático")
        }
    }

    var symbol: String {
        switch self {
        case .cool: "snowflake"
        case .heat: "sun.max.fill"
        case .fan: "wind"
        case .dry: "drop.fill"
        case .auto: "arrow.triangle.2.circlepath"
        }
    }

    /// Modos en los que la temperatura forma parte del código IR.
    var usesTemperature: Bool { self != .fan }
}

enum FanSpeed: String, Codable, Sendable, CaseIterable, Hashable, Identifiable {
    case auto, low, medium, high

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: String(localized: "Auto")
        case .low: String(localized: "Baja")
        case .medium: String(localized: "Media")
        case .high: String(localized: "Alta")
        }
    }
}

/// Estado completo de un aire acondicionado. Los controles IR de aire son "con estado":
/// cada código representa una combinación modo + temperatura (+ ventilador).
struct ACSettings: Codable, Sendable, Hashable {
    var mode: ACMode
    var temperature: Int
    var fan: FanSpeed
    var swing: Bool

    init(mode: ACMode = .cool, temperature: Int = 23, fan: FanSpeed = .auto, swing: Bool = false) {
        self.mode = mode
        self.temperature = temperature
        self.fan = fan
        self.swing = swing
    }

    /// Nombre estructurado del código: `<modo>_<temp>[_<ventilador>]`, p. ej. `cool_23`, `heat_25_high`.
    var codeName: String {
        var parts = [mode.rawValue]
        if mode.usesTemperature { parts.append(String(temperature)) }
        if fan != .auto { parts.append(fan.rawValue) }
        return parts.joined(separator: "_")
    }

    /// Variante sin ventilador, usada como respaldo si no se grabó la combinación exacta.
    var codeNameIgnoringFan: String {
        mode.usesTemperature ? "\(mode.rawValue)_\(temperature)" : mode.rawValue
    }

    static let defaultRange: ClosedRange<Int> = 16...30
}
