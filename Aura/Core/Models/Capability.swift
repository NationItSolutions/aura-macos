import Foundation

/// Lo que un dispositivo sabe hacer. La UI decide qué controles mostrar en base a esto.
enum Capability: String, Codable, Sendable, CaseIterable, Hashable {
    case power
    case temperature
    case mode
    case fanSpeed
    case swing
    case volume
    case channel
    case navigation
    case input
    case apps
    case color
    case brightness
    case customButtons
}
