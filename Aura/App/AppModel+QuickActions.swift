import AppKit
import Foundation
import UniformTypeIdentifiers

/// Acciones rápidas compartidas por la isla, la barra de menús y Atajos/Siri.
extension AppModel {
    /// Dispositivos para accesos rápidos: favoritos primero; si no hay, todos.
    var quickDevices: [Device] {
        let favorites = store.devices.filter(\.isFavorite)
        return favorites.isEmpty ? store.devices : favorites
    }

    var quickScenes: [HomeScene] {
        let favorites = store.scenes.filter(\.isFavorite)
        return favorites.isEmpty ? store.scenes : favorites
    }

    /// Ajustes actuales del aire (o los de por defecto dentro del rango del equipo).
    func acSettings(for device: Device) -> ACSettings {
        var settings = store.state(for: device.id).ac ?? ACSettings()
        settings.temperature = min(max(settings.temperature, device.temperatureRange.lowerBound), device.temperatureRange.upperBound)
        return settings
    }

    /// Sube o baja la temperatura saltando a la próxima temperatura grabada.
    func stepTemperature(_ device: Device, by delta: Int) {
        var settings = acSettings(for: device)
        guard settings.mode.usesTemperature else { return }
        let recorded = device.recordedTemperatures(for: settings.mode)
        let candidates = recorded.isEmpty ? Array(device.temperatureRange) : recorded
        let next = delta > 0
            ? candidates.first { $0 > settings.temperature }
            : candidates.last { $0 < settings.temperature }
        guard let next else { return }
        settings.temperature = next
        Task { await send(.setAC(settings), to: device) }
    }

    /// Fija una temperatura exacta (Siri/Atajos). Devuelve `false` si está fuera de rango.
    func setTemperature(_ device: Device, to temperature: Int) async -> Bool {
        guard device.temperatureRange.contains(temperature) else { return false }
        var settings = acSettings(for: device)
        if !settings.mode.usesTemperature { settings.mode = .cool }
        settings.temperature = temperature
        return await send(.setAC(settings), to: device)
    }
}

// MARK: - Importación del prototipo

extension AppModel {
    /// Importa codigos.json y devuelve un resumen para mostrar.
    func importLegacyCodes(from url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        let result = try LegacyCodesImporter.parse(data)
        if settings.demoMode { setDemoMode(false) }
        let summary = store.apply(result)
        var detail = String(localized: "Aire: \(summary.acCodes) códigos · LED: \(summary.ledCodes) códigos.")
        if !summary.warnings.isEmpty {
            detail += "\n\n" + summary.warnings.joined(separator: "\n")
        }
        return detail
    }
}

extension LegacyCodesImporter {
    /// Panel para elegir codigos.json (el sandbox exige que lo elija el usuario).
    @MainActor
    static func openPanel() -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.showsHiddenFiles = true
        panel.canChooseDirectories = false
        panel.directoryURL = defaultURL.deletingLastPathComponent()
        panel.message = String(localized: "Elegí el archivo codigos.json del prototipo")
        return panel
    }
}
