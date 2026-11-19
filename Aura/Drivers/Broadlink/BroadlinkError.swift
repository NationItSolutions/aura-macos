import Foundation

/// Errores del driver Broadlink con mensajes en español para el usuario.
enum BroadlinkError: UserFacingError, Equatable {
    case timeout
    case locked
    case localNetworkDenied
    case authenticationFailed
    case deviceError(Int16)
    case invalidResponse
    case unsupportedDevice(UInt16)
    case notFound
    case learningTimedOut
    case rfNotSupported
    case invalidCode
    case missingIdentity

    var userMessage: String {
        switch self {
        case .timeout:
            String(localized: "El Broadlink no respondió. Revisá que esté encendido y en la misma red.")
        case .locked:
            String(localized: "El Broadlink está bloqueado. En la app Broadlink abrí el dispositivo, entrá a Propiedades y desactivá \"Bloquear dispositivo\".")
        case .localNetworkDenied:
            String(localized: "macOS no deja que Aura use la red local. Habilitalo en Ajustes del Sistema → Privacidad y seguridad → Red local.")
        case .authenticationFailed:
            String(localized: "El Broadlink rechazó la conexión. Si está bloqueado, desbloquealo desde la app Broadlink.")
        case .deviceError(let code):
            Self.message(for: code)
        case .invalidResponse:
            String(localized: "El Broadlink envió una respuesta inválida.")
        case .unsupportedDevice(let type):
            String(localized: "Este modelo de Broadlink (0x\(String(type, radix: 16, uppercase: true))) no es un control remoto compatible.")
        case .notFound:
            String(localized: "No se encontró el Broadlink en la red. Puede que haya cambiado de IP o esté apagado.")
        case .learningTimedOut:
            String(localized: "No se recibió ninguna señal. Apuntá el control al Broadlink y probá de nuevo.")
        case .rfNotSupported:
            String(localized: "Este Broadlink no tiene radio RF (hace falta un RM4 Pro).")
        case .invalidCode:
            String(localized: "El código grabado está dañado. Volvé a grabarlo.")
        case .missingIdentity:
            String(localized: "Falta identificar el Broadlink. Redescubrilo desde Ajustes → Puentes.")
        }
    }

    /// Códigos de error del firmware (python-broadlink, exceptions.py).
    static func message(for code: Int16) -> String {
        switch code {
        case -1: String(localized: "Falló la autenticación con el Broadlink.")
        case -2: String(localized: "El Broadlink cerró la sesión.")
        case -3: String(localized: "El Broadlink está desconectado.")
        case -4: String(localized: "El Broadlink no admite este comando.")
        case -5: String(localized: "La memoria del Broadlink está llena.")
        case -6: String(localized: "El Broadlink recibió datos con estructura inválida.")
        case -7: String(localized: "La clave de sesión del Broadlink venció.")
        case -8: String(localized: "El Broadlink no pudo enviar la señal.")
        case -9: String(localized: "El Broadlink no pudo escribir los datos.")
        case -10: String(localized: "El Broadlink no tiene datos para leer.")
        default: String(localized: "El Broadlink devolvió el error \(code).")
        }
    }

    /// Errores que se resuelven volviendo a autenticar.
    var requiresReauthentication: Bool {
        switch self {
        case .deviceError(let code): code == -2 || code == -7 || code == -4012
        default: false
        }
    }
}
