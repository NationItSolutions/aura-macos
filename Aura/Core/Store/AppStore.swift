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
        scheduleSave()
    }

    func upsert(_ room: Room) {
        if let index = snapshot.rooms.firstIndex(where: { $0.id == room.id }) {
            snapshot.rooms[index] = room
        } else {
            snapshot.rooms.append(room)
        }
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
