import Foundation

struct SceneStep: Codable, Sendable, Hashable, Identifiable {
    var id: UUID
    var deviceID: UUID
    var command: Command
    /// Demora después de este paso, en segundos.
    var delayAfter: Double

    init(id: UUID = UUID(), deviceID: UUID, command: Command, delayAfter: Double = 0) {
        self.id = id
        self.deviceID = deviceID
        self.command = command
        self.delayAfter = delayAfter
    }
}

/// Lista ordenada de comandos con demora opcional entre pasos.
struct HomeScene: Codable, Sendable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var symbol: String
    var steps: [SceneStep]
    var isFavorite: Bool

    init(id: UUID = UUID(), name: String, symbol: String, steps: [SceneStep] = [], isFavorite: Bool = true) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.steps = steps
        self.isFavorite = isFavorite
    }
}
