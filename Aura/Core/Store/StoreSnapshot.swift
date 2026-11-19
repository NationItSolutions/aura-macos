import Foundation

/// Todo lo que se persiste en disco, en un solo documento versionado.
struct StoreSnapshot: Codable, Sendable, Equatable {
    static let currentVersion = 1

    var version: Int = StoreSnapshot.currentVersion
    var bridges: [Bridge] = []
    var rooms: [Room] = []
    var devices: [Device] = []
    var scenes: [HomeScene] = []
    var states: [UUID: DeviceState] = [:]
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
