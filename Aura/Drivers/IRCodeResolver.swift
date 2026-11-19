import Foundation

/// Traduce un comando de alto nivel al nombre del código IR grabado.
/// Lo usan el driver Broadlink (M2) y el mock cuando valida códigos.
enum IRCodeResolver {
    static func codeName(for command: Command, device: Device) -> String? {
        switch (device.kind, command) {
        case (.airConditioner, .power(let on)):
            return on ? "on" : "off"
        case (.airConditioner, .setAC(let settings)):
            if device.codes[settings.codeName] != nil { return settings.codeName }
            return settings.codeNameIgnoringFan
        case (.light, .power(let on)):
            return on ? "power_on" : "power_off"
        case (.light, .brightness(let step)):
            return step == .up ? "brightness_up" : "brightness_down"
        case (.light, .color(let name)):
            return name
        case (.television, .power):
            return TVKey.power.rawValue.lowercased()
        case (.television, .tvKey(let key)):
            return key.rawValue.lowercased()
        case (_, .power(let on)):
            return on ? "power_on" : "power_off"
        case (_, .button(let name)):
            return name
        default:
            return nil
        }
    }
}
