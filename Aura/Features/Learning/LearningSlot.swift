import Foundation

/// Un código a grabar en el asistente.
struct LearningSlot: Identifiable, Hashable, Sendable {
    var id: String { codeName }
    var codeName: String
    var title: String
    var symbol: String
    /// Si es un botón personalizado nuevo, se agrega a `Device.buttons` al grabarlo.
    var customButton: CustomButton?

    var instruction: String {
        String(localized: "Apuntá el control al Broadlink y apretá «\(title)».")
    }

    /// Botones sugeridos según el tipo de dispositivo.
    static func presets(for kind: DeviceKind) -> [LearningSlot] {
        switch kind {
        case .light:
            var slots = [
                LearningSlot(codeName: "power_on", title: String(localized: "Encender"), symbol: "power"),
                LearningSlot(codeName: "power_off", title: String(localized: "Apagar"), symbol: "poweroff"),
                LearningSlot(codeName: "brightness_up", title: String(localized: "Brillo +"), symbol: "sun.max.fill"),
                LearningSlot(codeName: "brightness_down", title: String(localized: "Brillo −"), symbol: "sun.min"),
            ]
            for color in ["white", "red", "orange", "yellow", "green", "cyan", "blue", "purple", "pink"] {
                slots.append(LearningSlot(codeName: color, title: LEDPalette.displayName(for: color), symbol: "circle.fill"))
            }
            return slots
        case .fan, .generic:
            return [
                LearningSlot(codeName: "power_on", title: String(localized: "Encender"), symbol: "power"),
                LearningSlot(codeName: "power_off", title: String(localized: "Apagar"), symbol: "poweroff"),
            ]
        case .airConditioner:
            return [
                LearningSlot(codeName: "on", title: String(localized: "Encender"), symbol: "power"),
                LearningSlot(codeName: "off", title: String(localized: "Apagar"), symbol: "poweroff"),
            ]
        case .television:
            return [TVKey.power, .volumeUp, .volumeDown, .mute, .channelUp, .channelDown, .up, .down, .left, .right,
                    .enter, .back, .home, .source].map {
                LearningSlot(codeName: $0.rawValue.lowercased(), title: $0.displayName, symbol: "av.remote")
            }
        }
    }

    /// Botón personalizado nuevo con un nombre de código único.
    static func custom(name: String, symbol: String, tint: ButtonTint) -> LearningSlot {
        let codeName = "btn_" + UUID().uuidString.prefix(8).lowercased()
        let button = CustomButton(name: name, symbol: symbol, codeName: codeName, tint: tint)
        return LearningSlot(codeName: codeName, title: name, symbol: symbol, customButton: button)
    }
}

/// Símbolos sugeridos para botones personalizados.
enum ButtonSymbols {
    static let all = [
        "power", "poweroff", "plus", "minus", "chevron.up", "chevron.down", "chevron.left", "chevron.right",
        "play.fill", "pause.fill", "stop.fill", "forward.fill", "backward.fill", "speaker.wave.2.fill",
        "speaker.slash.fill", "sun.max.fill", "sun.min", "moon.fill", "bolt.fill", "sparkles", "wind",
        "fan.fill", "timer", "clock", "arrow.left.and.right", "arrow.up.and.down", "repeat", "shuffle",
        "light.beacon.max.fill", "circle.lefthalf.filled", "water.waves", "flame.fill", "snowflake",
        "gauge.with.dots.needle.67percent", "number", "star.fill", "heart.fill", "music.note", "mic.fill",
        "tv", "hifispeaker.fill", "lightbulb.fill", "lamp.desk.fill", "projector.fill", "gamecontroller.fill",
    ]
}
