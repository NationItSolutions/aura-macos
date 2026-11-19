import Foundation
import Observation

/// Pantalla donde se muestra la isla.
enum IslandScreen: String, CaseIterable, Identifiable, Sendable {
    /// La pantalla con notch si hay una; si no, la principal.
    case notch
    /// La pantalla que tiene la barra de menús activa.
    case main

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notch: String(localized: "La del notch (o la principal)")
        case .main: String(localized: "La pantalla activa")
        }
    }
}

/// Preferencias del usuario (UserDefaults). Los datos de dispositivos van en `AppStore`.
@MainActor
@Observable
final class AppSettings {
    @ObservationIgnored private let defaults: UserDefaults

    var demoMode: Bool { didSet { defaults.set(demoMode, forKey: Keys.demoMode) } }
    var soundsEnabled: Bool { didSet { defaults.set(soundsEnabled, forKey: Keys.sounds) } }
    var hapticsEnabled: Bool { didSet { defaults.set(hapticsEnabled, forKey: Keys.haptics) } }
    var onboardingCompleted: Bool { didSet { defaults.set(onboardingCompleted, forKey: Keys.onboarding) } }

    // Isla
    var islandEnabled: Bool { didSet { defaults.set(islandEnabled, forKey: Keys.islandEnabled) } }
    var islandHideInFullscreen: Bool { didSet { defaults.set(islandHideInFullscreen, forKey: Keys.islandFullscreen) } }
    var islandScreen: IslandScreen { didSet { defaults.set(islandScreen.rawValue, forKey: Keys.islandScreen) } }

    // Barra de menús
    var menuBarEnabled: Bool { didSet { defaults.set(menuBarEnabled, forKey: Keys.menuBar) } }
    var menuBarOnly: Bool { didSet { defaults.set(menuBarOnly, forKey: Keys.menuBarOnly) } }

    // Atajos globales
    var hotkeysEnabled: Bool { didSet { defaults.set(hotkeysEnabled, forKey: Keys.hotkeys) } }
    var islandShortcut: KeyShortcut { didSet { save(islandShortcut, Keys.islandShortcut) } }
    var windowShortcut: KeyShortcut { didSet { save(windowShortcut, Keys.windowShortcut) } }
    /// Atajos para las escenas favoritas, en orden (⌃⌥1…9 por defecto).
    var sceneShortcutsEnabled: Bool { didSet { defaults.set(sceneShortcutsEnabled, forKey: Keys.sceneShortcuts) } }

    private enum Keys {
        static let demoMode = "demoMode"
        static let sounds = "soundsEnabled"
        static let haptics = "hapticsEnabled"
        static let onboarding = "onboardingCompleted"
        static let islandEnabled = "islandEnabled"
        static let islandFullscreen = "islandHideInFullscreen"
        static let islandScreen = "islandScreen"
        static let menuBar = "menuBarEnabled"
        static let menuBarOnly = "menuBarOnly"
        static let hotkeys = "hotkeysEnabled"
        static let islandShortcut = "islandShortcut"
        static let windowShortcut = "windowShortcut"
        static let sceneShortcuts = "sceneShortcutsEnabled"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Hasta completar el onboarding la app arranca en modo demo.
        defaults.register(defaults: [
            Keys.demoMode: true, Keys.sounds: false, Keys.haptics: true, Keys.onboarding: false,
            Keys.islandEnabled: true, Keys.islandFullscreen: true, Keys.islandScreen: IslandScreen.notch.rawValue,
            Keys.menuBar: true, Keys.menuBarOnly: false, Keys.hotkeys: true, Keys.sceneShortcuts: true,
        ])
        demoMode = defaults.bool(forKey: Keys.demoMode)
        soundsEnabled = defaults.bool(forKey: Keys.sounds)
        hapticsEnabled = defaults.bool(forKey: Keys.haptics)
        onboardingCompleted = defaults.bool(forKey: Keys.onboarding)
        islandEnabled = defaults.bool(forKey: Keys.islandEnabled)
        islandHideInFullscreen = defaults.bool(forKey: Keys.islandFullscreen)
        islandScreen = IslandScreen(rawValue: defaults.string(forKey: Keys.islandScreen) ?? "") ?? .notch
        menuBarEnabled = defaults.bool(forKey: Keys.menuBar)
        menuBarOnly = defaults.bool(forKey: Keys.menuBarOnly)
        hotkeysEnabled = defaults.bool(forKey: Keys.hotkeys)
        sceneShortcutsEnabled = defaults.bool(forKey: Keys.sceneShortcuts)
        islandShortcut = Self.load(defaults, Keys.islandShortcut) ?? .defaultIsland
        windowShortcut = Self.load(defaults, Keys.windowShortcut) ?? .defaultWindow
    }

    private func save(_ shortcut: KeyShortcut, _ key: String) {
        if let data = try? JSONEncoder().encode(shortcut) { defaults.set(data, forKey: key) }
    }

    private static func load(_ defaults: UserDefaults, _ key: String) -> KeyShortcut? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(KeyShortcut.self, from: $0) }
    }
}
