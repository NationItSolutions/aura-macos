import Foundation

/// Todo lo que se persiste en disco, en un solo documento versionado.
/// Los campos nuevos se decodifican con valor por defecto para leer archivos de versiones anteriores.
struct StoreSnapshot: Codable, Sendable, Equatable {
    static let currentVersion = 2

    var version: Int = StoreSnapshot.currentVersion
    var bridges: [Bridge] = []
    var rooms: [Room] = []
    var devices: [Device] = []
    var scenes: [HomeScene] = []
    var states: [UUID: DeviceState] = [:]
    var automations: [Automation] = []
    var timers: [SleepTimer] = []

    init(
        bridges: [Bridge] = [], rooms: [Room] = [], devices: [Device] = [], scenes: [HomeScene] = [],
        states: [UUID: DeviceState] = [:], automations: [Automation] = [], timers: [SleepTimer] = []
    ) {
        self.bridges = bridges
        self.rooms = rooms
        self.devices = devices
        self.scenes = scenes
        self.states = states
        self.automations = automations
        self.timers = timers
    }

    private enum CodingKeys: String, CodingKey {
        case version, bridges, rooms, devices, scenes, states, automations, timers
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        bridges = try container.decodeIfPresent([Bridge].self, forKey: .bridges) ?? []
        rooms = try container.decodeIfPresent([Room].self, forKey: .rooms) ?? []
        devices = try container.decodeIfPresent([Device].self, forKey: .devices) ?? []
        scenes = try container.decodeIfPresent([HomeScene].self, forKey: .scenes) ?? []
        states = try container.decodeIfPresent([UUID: DeviceState].self, forKey: .states) ?? [:]
        automations = try container.decodeIfPresent([Automation].self, forKey: .automations) ?? []
        timers = try container.decodeIfPresent([SleepTimer].self, forKey: .timers) ?? []
        version = StoreSnapshot.currentVersion
    }
}

/// Lee y escribe el snapshot como JSON en ~/Library/Application Support/Aura.
/// (Bajo sandbox, esa ruta vive dentro del contenedor de la app.)
struct StoreFile: Sendable {
    let url: URL

    static func `default`() throws -> StoreFile {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let folder = base.appendingPathComponent("Aura", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return StoreFile(url: folder.appendingPathComponent("store.json"))
    }

    func load() throws -> StoreSnapshot? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try Self.decoder.decode(StoreSnapshot.self, from: data)
    }

    func save(_ snapshot: StoreSnapshot) throws {
        let data = try Self.encoder.encode(snapshot)
        try data.write(to: url, options: [.atomic])
    }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
