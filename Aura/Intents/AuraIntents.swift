import AppIntents
import Foundation

// MARK: - Entidades

struct DeviceEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Dispositivo")
    static let defaultQuery = DeviceEntityQuery()

    let id: UUID
    let name: String
    let symbol: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", image: .init(systemName: symbol))
    }

    init(_ device: Device) {
        id = device.id
        name = device.name
        symbol = device.symbol
    }
}

struct DeviceEntityQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [DeviceEntity] {
        identifiers.compactMap { AppModel.shared.store.device($0) }.map(DeviceEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [DeviceEntity] {
        AppModel.shared.store.devices.map(DeviceEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [DeviceEntity] {
        AppModel.shared.store.devices
            .filter { $0.name.localizedCaseInsensitiveContains(string) }
            .map(DeviceEntity.init)
    }
}

struct SceneEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Escena")
    static let defaultQuery = SceneEntityQuery()

    let id: UUID
    let name: String
    let symbol: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", image: .init(systemName: symbol))
    }

    init(_ scene: HomeScene) {
        id = scene.id
        name = scene.name
        symbol = scene.symbol
    }
}

struct SceneEntityQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [SceneEntity] {
        identifiers.compactMap { AppModel.shared.store.scene($0) }.map(SceneEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [SceneEntity] {
        AppModel.shared.store.scenes.map(SceneEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [SceneEntity] {
        AppModel.shared.store.scenes
            .filter { $0.name.localizedCaseInsensitiveContains(string) }
            .map(SceneEntity.init)
    }
}

// MARK: - Errores

enum AuraIntentError: Error, CustomLocalizedStringResourceConvertible {
    case deviceNotFound
    case sceneNotFound
    case notAirConditioner
    case temperatureOutOfRange(Int, Int)
    case buttonNotFound(String)
    case commandFailed

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .deviceNotFound: "No encontré ese dispositivo en Aura."
        case .sceneNotFound: "No encontré esa escena en Aura."
        case .notAirConditioner: "Ese dispositivo no es un aire acondicionado."
        case .temperatureOutOfRange(let low, let high): "La temperatura tiene que estar entre \(low) y \(high) °C."
        case .buttonNotFound(let name): "Ese dispositivo no tiene un botón «\(name)»."
        case .commandFailed: "No se pudo enviar el comando. Revisá que el dispositivo esté conectado."
        }
    }
}

// MARK: - Intents

struct PowerDeviceIntent: AppIntent {
    static let title: LocalizedStringResource = "Encender o apagar un dispositivo"
    static let description = IntentDescription("Enciende o apaga un dispositivo de Aura.")

    @Parameter(title: "Dispositivo")
    var device: DeviceEntity

    @Parameter(title: "Encender", default: true)
    var turnOn: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Poner \(\.$device) encendido: \(\.$turnOn)")
    }

    init() {}

    init(device: DeviceEntity, turnOn: Bool) {
        self.device = device
        self.turnOn = turnOn
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = AppModel.shared
        guard let target = model.store.device(device.id) else { throw AuraIntentError.deviceNotFound }
        guard await model.send(.power(turnOn), to: target) else { throw AuraIntentError.commandFailed }
        return .result(dialog: turnOn ? "Listo, encendí \(target.name)." : "Listo, apagué \(target.name).")
    }
}

struct TurnOnDeviceIntent: AppIntent {
    static let title: LocalizedStringResource = "Encender un dispositivo"

    @Parameter(title: "Dispositivo")
    var device: DeviceEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await PowerDeviceIntent(device: device, turnOn: true).perform()
    }
}

struct TurnOffDeviceIntent: AppIntent {
    static let title: LocalizedStringResource = "Apagar un dispositivo"

    @Parameter(title: "Dispositivo")
    var device: DeviceEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await PowerDeviceIntent(device: device, turnOn: false).perform()
    }
}

struct SetACTemperatureIntent: AppIntent {
    static let title: LocalizedStringResource = "Poner el aire a una temperatura"
    static let description = IntentDescription("Ajusta la temperatura de un aire acondicionado.")

    @Parameter(title: "Aire")
    var device: DeviceEntity

    @Parameter(title: "Temperatura", inclusiveRange: (16, 30))
    var temperature: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Poner \(\.$device) a \(\.$temperature) °C")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = AppModel.shared
        guard let target = model.store.device(device.id) else { throw AuraIntentError.deviceNotFound }
        guard target.kind == .airConditioner else { throw AuraIntentError.notAirConditioner }
        guard target.temperatureRange.contains(temperature) else {
            throw AuraIntentError.temperatureOutOfRange(target.temperatureRange.lowerBound, target.temperatureRange.upperBound)
        }
        guard await model.setTemperature(target, to: temperature) else { throw AuraIntentError.commandFailed }
        return .result(dialog: "\(target.name) a \(temperature) °C.")
    }
}

struct RunSceneIntent: AppIntent {
    static let title: LocalizedStringResource = "Ejecutar una escena"
    static let description = IntentDescription("Ejecuta una escena de Aura.")

    @Parameter(title: "Escena")
    var scene: SceneEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Ejecutar \(\.$scene)")
    }

    init() {}

    init(scene: SceneEntity) {
        self.scene = scene
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = AppModel.shared
        guard let target = model.store.scene(scene.id) else { throw AuraIntentError.sceneNotFound }
        guard await model.runScene(target) else { throw AuraIntentError.commandFailed }
        return .result(dialog: "Escena \(target.name) lista.")
    }
}

struct SendButtonIntent: AppIntent {
    static let title: LocalizedStringResource = "Apretar un botón"
    static let description = IntentDescription("Envía un botón grabado de un control (por nombre).")

    @Parameter(title: "Dispositivo")
    var device: DeviceEntity

    @Parameter(title: "Botón")
    var button: String

    static var parameterSummary: some ParameterSummary {
        Summary("Apretar \(\.$button) en \(\.$device)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let model = AppModel.shared
        guard let target = model.store.device(device.id) else { throw AuraIntentError.deviceNotFound }
        let match = target.buttons.first { $0.name.localizedCaseInsensitiveCompare(button) == .orderedSame }
        let codeName = match?.codeName ?? (target.codes[button] != nil ? button : nil)
        guard let codeName else { throw AuraIntentError.buttonNotFound(button) }
        guard await model.send(.button(codeName), to: target) else { throw AuraIntentError.commandFailed }
        return .result(dialog: "Listo.")
    }
}

struct ToggleIslandIntent: AppIntent {
    static let title: LocalizedStringResource = "Abrir la isla de Aura"
    static let description = IntentDescription("Abre o cierra los controles en el notch.")

    @MainActor
    func perform() async throws -> some IntentResult {
        AppModel.shared.island?.toggle()
        return .result()
    }
}

// MARK: - Frases para Siri y Spotlight

struct AuraShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: RunSceneIntent(), phrases: [
            "Ejecutar \(\.$scene) en \(.applicationName)",
            "Activar \(\.$scene) con \(.applicationName)",
            "\(.applicationName) escena \(\.$scene)",
        ], shortTitle: "Ejecutar escena", systemImageName: "sparkles")
        AppShortcut(intent: TurnOnDeviceIntent(), phrases: [
            "Encender \(\.$device) con \(.applicationName)",
            "Prender \(\.$device) con \(.applicationName)",
        ], shortTitle: "Encender", systemImageName: "power")
        AppShortcut(intent: TurnOffDeviceIntent(), phrases: [
            "Apagar \(\.$device) con \(.applicationName)",
        ], shortTitle: "Apagar", systemImageName: "poweroff")
        AppShortcut(intent: SetACTemperatureIntent(), phrases: [
            "Cambiar la temperatura de \(\.$device) con \(.applicationName)",
            "Ajustar \(\.$device) con \(.applicationName)",
        ], shortTitle: "Temperatura del aire", systemImageName: "thermometer.medium")
        AppShortcut(intent: ToggleIslandIntent(), phrases: [
            "Abrir la isla de \(.applicationName)",
        ], shortTitle: "Abrir la isla", systemImageName: "capsule.fill")
    }
}
