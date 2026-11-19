import AppKit
import Foundation
import Observation

/// Punto de encuentro entre la UI, el store y el bus de comandos.
@MainActor
@Observable
final class AppModel {
    let settings: AppSettings
    let store: AppStore
    let bus: CommandBus
    @ObservationIgnored let drivers: DriverRegistry
    @ObservationIgnored private(set) var scheduler: Scheduler!

    private(set) var runningScene: UUID?
    /// Ficha de dispositivo abierta en la ventana principal.
    var presentedDevice: DeviceRef?

    struct DeviceRef: Identifiable, Hashable {
        let id: UUID
    }

    func open(_ device: Device) {
        presentedDevice = DeviceRef(id: device.id)
    }

    convenience init() {
        self.init(settings: AppSettings(), storeFile: try? StoreFile.default())
    }

    init(settings: AppSettings, storeFile: StoreFile?) {
        self.settings = settings
        let store = AppStore(file: storeFile, demo: settings.demoMode)
        let drivers = DriverRegistry(demoMode: settings.demoMode, broadlink: BroadlinkHub(store: store))
        self.drivers = drivers
        self.store = store
        self.bus = CommandBus { device in drivers.driver(for: device) }
        self.scheduler = Scheduler(store: store) { [weak self] action, _ in
            guard let self else { return false }
            return await self.perform(action)
        }
    }

    /// Arranca lo que corre en segundo plano (una sola vez, al abrir la app).
    func startServices() {
        scheduler.start()
        if !store.automations.isEmpty { Scheduler.requestNotificationPermission() }
    }

    func setDemoMode(_ demo: Bool) {
        settings.demoMode = demo
        drivers.setDemoMode(demo)
        store.setDemo(demo)
    }

    /// Envía un comando y, si sale bien, actualiza el estado asumido.
    @discardableResult
    func send(_ command: Command, to device: Device, feedback: Bool = true) async -> Bool {
        if settings.hapticsEnabled {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        let result = await bus.send(command, to: device, publishFeedback: feedback)
        if case .success = result {
            store.updateState(for: device.id) { $0.apply(command) }
            return true
        }
        return false
    }

    func send(_ command: Command, toDeviceID id: UUID) {
        guard let device = store.device(id) else { return }
        Task { await send(command, to: device) }
    }

    func togglePower(_ device: Device) {
        let isOn = store.state(for: device.id).isOn
        Task { await send(.power(!isOn), to: device) }
    }

    /// Corrige el estado asumido a mano, sin enviar comandos.
    func syncState(_ device: Device, _ change: (inout DeviceState) -> Void) {
        store.updateState(for: device.id, change)
    }

    /// Ejecuta una escena paso a paso respetando las demoras.
    func run(_ scene: HomeScene) {
        Task { await runScene(scene) }
    }

    /// Ejecuta una escena y devuelve `true` si todos los pasos salieron bien.
    @discardableResult
    func runScene(_ scene: HomeScene) async -> Bool {
        guard runningScene == nil else { return false }
        runningScene = scene.id
        defer { runningScene = nil }
        var failures: [String] = []
        for step in scene.steps {
            guard let device = store.device(step.deviceID) else { continue }
            let ok = await send(step.command, to: device, feedback: false)
            if !ok { failures.append(device.name) }
            if step.delayAfter > 0 {
                try? await Task.sleep(for: .milliseconds(Int(step.delayAfter * 1000)))
            }
        }
        if failures.isEmpty {
            bus.publish(CommandFeedback(title: String(localized: "\(scene.name) ✓"), isError: false, symbol: scene.symbol))
            return true
        }
        let list = failures.joined(separator: ", ")
        bus.publish(CommandFeedback(title: scene.name, message: String(localized: "Falló: \(list)"),
                                    isError: true, symbol: "exclamationmark.triangle.fill"))
        return false
    }

    /// Ejecuta la acción de una automatización o temporizador.
    func perform(_ action: AutomationAction) async -> Bool {
        switch action {
        case .command(let deviceID, let command):
            guard let device = store.device(deviceID) else { return false }
            return await send(command, to: device)
        case .scene(let sceneID):
            guard let scene = store.scene(sceneID) else { return false }
            return await runScene(scene)
        }
    }

    /// Temporizador rápido: apagar un dispositivo en `minutes` minutos.
    func scheduleOff(_ device: Device, inMinutes minutes: Int) {
        let timer = SleepTimer(fireDate: Date().addingTimeInterval(Double(minutes) * 60),
                               action: .command(deviceID: device.id, command: .power(false)),
                               label: String(localized: "Apagar \(device.name)"))
        store.addTimer(timer)
        bus.publish(CommandFeedback(title: String(localized: "\(device.name) se apaga en \(minutes) min"),
                                    isError: false, symbol: "timer"))
    }

    // MARK: - TV Samsung

    func isTVPaired(_ device: Device) -> Bool {
        if settings.demoMode { return false }
        return KeychainStore.get(account: KeychainStore.tvTokenAccount(device.id)) != nil
    }

    /// Abre el canal con permiso de emparejar: la TV muestra "Permitir" y se guarda el token.
    func pairTV(_ device: Device) async throws {
        if settings.demoMode {
            try await Task.sleep(for: .seconds(1.5))
            return
        }
        guard case .samsungTizen(let host, _, _) = device.transport else { throw SamsungTVError.invalidHost }
        let client = drivers.tvClient(for: device.id, host: host)
        try await client.connect(allowPairing: true, timeout: .seconds(30))
        bus.publish(CommandFeedback(title: String(localized: "\(device.name) emparejada"), isError: false, symbol: "tv"))
    }

    func forgetTVPairing(_ device: Device) {
        drivers.forgetTV(device.id)
    }

    // MARK: - Resúmenes para el dashboard

    var devicesOn: [Device] { store.devices.filter { store.state(for: $0.id).isOn } }

    var summaryLine: String {
        let onCount = devicesOn.count
        var parts: [String] = []
        switch onCount {
        case 0: parts.append(String(localized: "Todo apagado"))
        case 1: parts.append(String(localized: "1 dispositivo encendido"))
        default: parts.append(String(localized: "\(onCount) dispositivos encendidos"))
        }
        if let ac = store.devices.first(where: { $0.kind == .airConditioner }) {
            let state = store.state(for: ac.id)
            if state.isOn, let settings = state.ac, settings.mode.usesTemperature {
                parts.append(String(localized: "Aire en \(settings.temperature) °C"))
            }
        }
        return parts.joined(separator: " · ")
    }

    var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        let first = NSFullUserName().split(separator: " ").first.map(String.init) ?? ""
        let base: String
        switch hour {
        case 5..<12: base = String(localized: "Buen día")
        case 12..<20: base = String(localized: "Buenas tardes")
        default: base = String(localized: "Buenas noches")
        }
        return first.isEmpty ? base : "\(base), \(first)"
    }
}
