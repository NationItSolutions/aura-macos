import Foundation

enum BrightnessStep: String, Codable, Sendable, Hashable {
    case up, down
}

/// Comando de alto nivel. La UI arma comandos; el driver los traduce a su transporte.
enum Command: Codable, Sendable, Hashable {
    case power(Bool)
    case setAC(ACSettings)
    case tvKey(TVKey)
    case launchApp(TVApp)
    case brightness(BrightnessStep)
    case color(String)
    /// Botón grabado por nombre (controles genéricos, efectos de LED, etc.).
    case button(String)

    /// Texto corto para el feedback ("Aire · 23 °C").
    func summary(for device: Device) -> String {
        let name = device.name
        switch self {
        case .power(let on):
            return on ? String(localized: "\(name) · Encendido") : String(localized: "\(name) · Apagado")
        case .setAC(let settings):
            if settings.mode.usesTemperature {
                return "\(name) · \(settings.mode.displayName) \(settings.temperature) °C"
            }
            return "\(name) · \(settings.mode.displayName)"
        case .tvKey(let key):
            return "\(name) · \(key.displayName)"
        case .launchApp(let app):
            return "\(name) · \(app.name)"
        case .brightness(let step):
            return step == .up ? String(localized: "\(name) · Brillo +") : String(localized: "\(name) · Brillo −")
        case .color(let color):
            return "\(name) · \(LEDPalette.displayName(for: color))"
        case .button(let button):
            return "\(name) · \(button)"
        }
    }
}
