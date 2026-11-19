import os

/// Loggers por subsistema. Ver con: `log stream --predicate 'subsystem == "com.nationit.aura"'`.
enum Log {
    private static let subsystem = "com.nationit.aura"
    static let app = Logger(subsystem: subsystem, category: "app")
    static let store = Logger(subsystem: subsystem, category: "store")
    static let commandBus = Logger(subsystem: subsystem, category: "commandbus")
    static let broadlink = Logger(subsystem: subsystem, category: "broadlink")
    static let tv = Logger(subsystem: subsystem, category: "tv")
    static let island = Logger(subsystem: subsystem, category: "island")
    static let scheduler = Logger(subsystem: subsystem, category: "scheduler")
}
