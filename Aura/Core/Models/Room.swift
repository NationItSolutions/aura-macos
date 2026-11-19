import Foundation

struct Room: Codable, Sendable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var symbol: String
    var sortOrder: Int

    init(id: UUID = UUID(), name: String, symbol: String = "square.split.bottomrightquarter", sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.sortOrder = sortOrder
    }
}
