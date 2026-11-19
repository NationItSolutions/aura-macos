import Foundation

enum SamsungTVError: UserFacingError, Equatable {
    case invalidHost
    case unreachable
    case timeout
    case denied
    case notPaired
    case tokenRejected
    case wakeFailed
    case appLaunchFailed(String)
    case localNetworkDenied

    var userMessage: String {
        switch self {
        case .invalidHost:
            String(localized: "La IP de la TV no es válida")
        case .unreachable:
            String(localized: "La TV no responde en la red. ¿Está encendida y en la misma Wi‑Fi?")
        case .timeout:
            String(localized: "La TV no respondió a tiempo")
        case .denied:
            String(localized: "La TV rechazó la conexión. Aceptá «Aura» en el aviso de la TV o habilitalo en Configuración → General → Administrador de dispositivos externos")
        case .notPaired:
            String(localized: "La TV todavía no está emparejada. Abrí su ficha y tocá «Emparejar»")
        case .tokenRejected:
            String(localized: "La TV olvidó el emparejamiento. Volvé a emparejarla")
        case .wakeFailed:
            String(localized: "No se pudo encender la TV por red. Activá «Encender con dispositivo móvil» en la TV o grabá el botón de encendido por IR")
        case .appLaunchFailed(let name):
            String(localized: "No se pudo abrir \(name) en la TV")
        case .localNetworkDenied:
            String(localized: "macOS bloqueó el acceso a la red local. Habilitalo en Ajustes del Sistema → Privacidad y seguridad → Red local")
        }
    }
}
