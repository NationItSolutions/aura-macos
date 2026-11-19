import Foundation

/// Nombres conocidos de códigos de LED y su color de muestra.
enum LEDPalette {
    static let brightnessSteps = 5

    /// Códigos reservados que no son colores.
    static let reservedCodeNames: Set<String> = ["power_on", "power_off", "brightness_up", "brightness_down"]

    /// Orden de presentación de los colores conocidos.
    static let order = [
        "white", "red", "orange", "yellow", "green", "cyan", "blue", "purple", "pink",
        "branco", "vermelho", "laranja", "amarelo", "verde", "ciano", "azul", "roxo", "rosa",
    ]

    /// Color RGB de muestra (hex) para un nombre de código. Reconoce inglés, portugués y español.
    static func hex(for name: String) -> UInt32? {
        let key = name.lowercased().folding(options: .diacriticInsensitive, locale: nil)
        switch key {
        case "white", "branco", "blanco": return 0xF4F7FF
        case "red", "vermelho", "rojo": return 0xFF3B4E
        case "orange", "laranja", "naranja": return 0xFF8A2B
        case "yellow", "amarelo", "amarillo": return 0xFFD43B
        case "green", "verde": return 0x34D399
        case "cyan", "ciano", "cian": return 0x38BDF8
        case "blue", "azul": return 0x2F7BFF
        case "purple", "roxo", "violeta", "morado": return 0x9B5CFF
        case "pink", "rosa": return 0xFF5CC8
        default: return nil
        }
    }

    static func displayName(for name: String) -> String {
        let key = name.lowercased().folding(options: .diacriticInsensitive, locale: nil)
        switch key {
        case "white", "branco", "blanco": return String(localized: "Blanco")
        case "red", "vermelho", "rojo": return String(localized: "Rojo")
        case "orange", "laranja", "naranja": return String(localized: "Naranja")
        case "yellow", "amarelo", "amarillo": return String(localized: "Amarillo")
        case "green", "verde": return String(localized: "Verde")
        case "cyan", "ciano", "cian": return String(localized: "Cian")
        case "blue", "azul": return String(localized: "Azul")
        case "purple", "roxo", "violeta", "morado": return String(localized: "Violeta")
        case "pink", "rosa": return String(localized: "Rosa")
        default: return name.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}
