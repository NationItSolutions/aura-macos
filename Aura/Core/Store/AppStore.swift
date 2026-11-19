import Foundation
import Observation

/// Fuente de verdad de la app. En modo demo trabaja en memoria y no toca el disco.
@MainActor
@Observable
final class AppStore {
    private(set) var snapshot: StoreSnapshot
    private(set) var isDemo: Bool
    private(set) var lastSaveError: String?

    @ObservationIgnored private let file: StoreFile?
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init(file: StoreFile?, demo: Bool) {
        self.file = file
        self.isDemo = demo
        self.snapshot = demo ? DemoData.snapshot() : Self.loadSnapshot(from: file)
    }

    private static func loadSnapshot(from file: StoreFile?) -> StoreSnapshot {
        guard let file else { return StoreSnapshot() }
        do {
            return try file.load() ?? StoreSnapshot()
        } catch {
            Log.store.error("No se pudo leer el store: \(error.localizedDescription, privacy: .public)")
            return StoreSnapshot()
        }
    }

    /// Cambia entre datos reales y datos de demostración.
    func setDemo(_ demo: Bool) {
        guard demo != isDemo else { return }
        flush()
        isDemo = demo
        snapshot = demo ? DemoData.snapshot() : Self.loadSnapshot(from: file)
    }

    // MARK: - Lectura

    var devices: [Device] { snapshot.devices.sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) } }
    var rooms: [Room] { snapshot.rooms.sorted { ($0.sortOrder, $0.name) < ($1.sortOrder, $1.name) } }
    var scenes: [HomeScene] { snapshot.scenes }
    var bridges: [Bridge] { snapshot.bridges }
    var automations: [Automation] { snapshot.automations.sorted { ($0.hour, $0.minute) < ($1.hour, $1.minute) } }
    var timers: [SleepTimer] { snapshot.timers.sorted { $0.fireDate < $1.fireDate } }
    func scene(_ id: UUID) -> HomeScene? { snapshot.scenes.first { $0.id == id } }
    func timers(for deviceID: UUID) -> [SleepTimer] { timers.filter { $0.deviceID == deviceID } }

    func device(_ id: UUID) -> Device? { snapshot.devices.first { $0.id == id } }
    func room(_ id: UUID?) -> Room? { id.flatMap { id in snapshot.rooms.first { $0.id == id } } }
    func bridge(_ id: UUID?) -> Bridge? { id.flatMap { id in snapshot.bridges.first { $0.id == id } } }
    func state(for id: UUID) -> DeviceState { snapshot.states[id] ?? DeviceState() }
    func devices(in room: Room) -> [Device] { devices.filter { $0.roomID == room.id } }

    // MARK: - Escritura

    func upsert(_ device: Device) {
        if let index = snapshot.devices.firstIndex(where: { $0.id == device.id }) {
            snapshot.devices[index] = device
        } else {
            var device = device
            device.sortOrder = (snapshot.devices.map(\.sortOrder).max() ?? -1) + 1
            snapshot.devices.append(device)
        }
        scheduleSave()
    }

    func removeDevice(_ id: UUID) {
        snapshot.devices.removeAll { $0.id == id }
        snapshot.states[id] = nil
        for index in snapshot.scenes.indices {
            snapshot.scenes[index].steps.removeAll { $0.deviceID == id }
        }
        snapshot.timers.removeAll { $0.deviceID == id }
        snapshot.automations.removeAll {
            if case .command(let deviceID, _) = $0.action { return deviceID == id }
            return false
        }
        scheduleSave()
    }

    func upsert(_ room: Room) {
        if let index = snapshot.rooms.firstIndex(where: { $0.id == room.id }) {
            snapshot.rooms[index] = room
        } else {
            var room = room
            room.sortOrder = (snapshot.rooms.map(\.sortOrder).max() ?? -1) + 1
            snapshot.rooms.append(room)
        }
        scheduleSave()
    }

    /// Elimina la habitación. Sus dispositivos quedan "Sin habitación".
    func removeRoom(_ id: UUID) {
        snapshot.rooms.removeAll { $0.id == id }
        for index in snapshot.devices.indices where snapshot.devices[index].roomID == id {
            snapshot.devices[index].roomID = nil
        }
        scheduleSave()
    }

    /// Mueve un dispositivo a otra habitación (o a ninguna).
    func move(deviceID: UUID, to roomID: UUID?) {
        guard let index = snapshot.devices.firstIndex(where: { $0.id == deviceID }) else { return }
        snapshot.devices[index].roomID = roomID
        scheduleSave()
    }

    func upsert(_ bridge: Bridge) {
        if let index = snapshot.bridges.firstIndex(where: { $0.id == bridge.id }) {
            snapshot.bridges[index] = bridge
        } else {
            snapshot.bridges.append(bridge)
        }
        scheduleSave()
    }

    func removeBridge(_ id: UUID) {
        snapshot.bridges.removeAll { $0.id == id }
        for index in snapshot.devices.indices where snapshot.devices[index].transport.bridgeID == id {
            if case .broadlink = snapshot.devices[index].transport {
                snapshot.devices[index].transport = .broadlink(bridgeID: nil)
            }
        }
        scheduleSave()
    }

    func upsert(_ scene: HomeScene) {
        if let index = snapshot.scenes.firstIndex(where: { $0.id == scene.id }) {
            snapshot.scenes[index] = scene
        } else {
            snapshot.scenes.append(scene)
        }
        scheduleSave()
    }

    func updateState(for id: UUID, _ change: (inout DeviceState) -> Void) {
        var state = snapshot.states[id] ?? DeviceState()
        change(&state)
        snapshot.states[id] = state
        scheduleSave()
    }

    func removeScene(_ id: UUID) {
        snapshot.scenes.removeAll { $0.id == id }
        snapshot.automations.removeAll { $0.action == .scene(id) }
        scheduleSave()
    }

    func moveScenes(from source: IndexSet, to destination: Int) {
        snapshot.scenes.move(fromOffsets: source, toOffset: destination)
        scheduleSave()
    }

    func upsert(_ automation: Automation) {
        if let index = snapshot.automations.firstIndex(where: { $0.id == automation.id }) {
            snapshot.automations[index] = automation
        } else {
            snapshot.automations.append(automation)
        }
        scheduleSave()
    }

    func removeAutomation(_ id: UUID) {
        snapshot.automations.removeAll { $0.id == id }
        scheduleSave()
    }

    func addTimer(_ timer: SleepTimer) {
        // Un solo temporizador por dispositivo: el nuevo reemplaza al anterior.
        if let deviceID = timer.deviceID {
            snapshot.timers.removeAll { $0.deviceID == deviceID }
        }
        snapshot.timers.append(timer)
        scheduleSave()
    }

    func removeTimer(_ id: UUID) {
        snapshot.timers.removeAll { $0.id == id }
        scheduleSave()
    }

    func replaceAll(with snapshot: StoreSnapshot) {
        self.snapshot = snapshot
        scheduleSave()
    }

    // MARK: - Persistencia

    /// Guarda con una pequeña demora para agrupar cambios seguidos.
    private func scheduleSave() {
        guard !isDemo, file != nil else { return }
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    /// Escribe ya mismo a disco (también al salir de la app).
    func flush() {
        saveTask?.cancel()
        saveTask = nil
        guard !isDemo, let file else { return }
        let snapshot = self.snapshot
        do {
            try file.save(snapshot)
            lastSaveError = nil
        } catch {
            lastSaveError = error.localizedDescription
            Log.store.error("No se pudo guardar el store: \(error.localizedDescription, privacy: .public)")
        }
    }
}
