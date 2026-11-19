import AppKit
import Observation

/// Estado de la Dynamic Island emulada.
@MainActor
@Observable
final class IslandModel {
    enum Phase: Equatable {
        case compact
        case expanded
        case activity(CommandFeedback)
    }

    /// Geometría de la pantalla elegida.
    struct Geometry: Equatable {
        /// Ancho y alto del notch físico (0 si no hay).
        var notchWidth: CGFloat
        var notchHeight: CGFloat
        var hasNotch: Bool { notchWidth > 0 }

        static let none = Geometry(notchWidth: 0, notchHeight: 0)

        static let expandedSize = CGSize(width: 560, height: 230)
        static let pillSize = CGSize(width: 200, height: 32)
        /// Alas a cada lado del notch en modo compacto.
        static let wing: CGFloat = 64

        var compactSize: CGSize {
            hasNotch ? CGSize(width: notchWidth + Self.wing * 2, height: notchHeight) : Self.pillSize
        }

        var activitySize: CGSize {
            hasNotch ? CGSize(width: max(notchWidth + Self.wing * 2, 380), height: notchHeight + 40)
                     : CGSize(width: 340, height: 40)
        }

        func size(for phase: Phase) -> CGSize {
            switch phase {
            case .compact: compactSize
            case .expanded: CGSize(width: Self.expandedSize.width, height: Self.expandedSize.height + (hasNotch ? notchHeight : 0))
            case .activity: activitySize
            }
        }

        /// Margen superior del contenido para no quedar debajo de la cámara.
        var topInset: CGFloat { hasNotch ? notchHeight : 0 }
    }

    var phase: Phase = .compact
    var geometry: Geometry = .none
    /// Dispositivo elegido en las pestañas de la isla (nil = escenas).
    var selectedDeviceID: UUID?
    var showingScenes = false
}
