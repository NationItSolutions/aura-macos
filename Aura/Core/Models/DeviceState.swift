import Foundation

/// Último estado enviado por la app. El IR es de una sola vía, así que es un
/// "estado asumido": si alguien usa el control físico, el usuario puede sincronizarlo a mano.
struct DeviceState: Codable, Sendable, Hashable {
    var isOn: Bool = false
    var ac: ACSettings?
    var ledColor: String?
    var brightnessLevel: Int?
    var isMuted: Bool = false
    var lastUpdated: Date?

    /// Aplica un comando exitoso al estado asumido.
    mutating func apply(_ command: Command, now: Date = .now) {
        switch command {
        case .power(let on):
            isOn = on
        case .setAC(let settings):
            ac = settings
            isOn = true
        case .tvKey(let key):
            switch key {
            case .power: isOn.toggle()
            case .mute: isMuted.toggle()
            case .volumeUp, .volumeDown: isMuted = false
            default: break
            }
        case .launchApp:
            isOn = true
        case .brightness(let step):
            let current = brightnessLevel ?? LEDPalette.brightnessSteps
            let next = step == .up ? current + 1 : current - 1
            brightnessLevel = min(max(next, 1), LEDPalette.brightnessSteps)
            isOn = true
        case .color(let color):
            ledColor = color
            isOn = true
        case .button(let name):
            // El botón Swing del aire alterna la oscilación.
            if name == "swing", var settings = ac {
                settings.swing.toggle()
                ac = settings
            }
        }
        lastUpdated = now
    }
}
