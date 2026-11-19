import Foundation
import Observation

/// Preferencias del usuario (UserDefaults). Los datos de dispositivos van en `AppStore`.
@MainActor
@Observable
final class AppSettings {
    @ObservationIgnored private let defaults: UserDefaults

    var demoMode: Bool { didSet { defaults.set(demoMode, forKey: Keys.demoMode) } }
    var soundsEnabled: Bool { didSet { defaults.set(soundsEnabled, forKey: Keys.sounds) } }
    var hapticsEnabled: Bool { didSet { defaults.set(hapticsEnabled, forKey: Keys.haptics) } }

    private enum Keys {
        static let demoMode = "demoMode"
        static let sounds = "soundsEnabled"
        static let haptics = "hapticsEnabled"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Hasta completar el onboarding (M6) la app arranca en modo demo.
        defaults.register(defaults: [Keys.demoMode: true, Keys.sounds: false, Keys.haptics: true])
        demoMode = defaults.bool(forKey: Keys.demoMode)
        soundsEnabled = defaults.bool(forKey: Keys.sounds)
        hapticsEnabled = defaults.bool(forKey: Keys.haptics)
    }
}
