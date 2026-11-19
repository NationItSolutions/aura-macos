import Foundation

/// Qué hace una automatización o un temporizador.
enum AutomationAction: Codable, Sendable, Hashable {
    case command(deviceID: UUID, command: Command)
    case scene(UUID)
}

/// Día de la semana con la numeración de `Calendar` (1 = domingo … 7 = sábado).
enum Weekday: Int, Codable, Sendable, CaseIterable, Hashable, Identifiable, Comparable {
    case sunday = 1, monday, tuesday, wednesday, thursday, friday, saturday

    var id: Int { rawValue }

    /// Orden de lunes a domingo para la UI.
    static let mondayFirst: [Weekday] = [.monday, .tuesday, .wednesday, .thursday, .friday, .saturday, .sunday]

    var shortName: String {
        switch self {
        case .monday: String(localized: "Lu")
        case .tuesday: String(localized: "Ma")
        case .wednesday: String(localized: "Mi")
        case .thursday: String(localized: "Ju")
        case .friday: String(localized: "Vi")
        case .saturday: String(localized: "Sá")
        case .sunday: String(localized: "Do")
        }
    }

    static func < (lhs: Weekday, rhs: Weekday) -> Bool {
        (mondayFirst.firstIndex(of: lhs) ?? 0) < (mondayFirst.firstIndex(of: rhs) ?? 0)
    }
}

/// Automatización por horario: a una hora local, los días elegidos.
struct Automation: Codable, Sendable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var isEnabled: Bool
    var hour: Int
    var minute: Int
    /// Vacío = todos los días.
    var weekdays: Set<Weekday>
    var action: AutomationAction
    var lastRun: Date?

    init(id: UUID = UUID(), name: String, isEnabled: Bool = true, hour: Int, minute: Int,
         weekdays: Set<Weekday> = [], action: AutomationAction, lastRun: Date? = nil) {
        self.id = id
        self.name = name
        self.isEnabled = isEnabled
        self.hour = hour
        self.minute = minute
        self.weekdays = weekdays
        self.action = action
        self.lastRun = lastRun
    }

    /// Próxima ejecución estrictamente posterior a `date`, en la zona horaria del calendario.
    /// Se calcula con componentes de calendario, así que respeta cambios de horario y de huso.
    func nextFire(after date: Date, calendar: Calendar = .current) -> Date? {
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        components.second = 0
        var cursor = date
        // Como mucho 8 candidatos: alcanza para encontrar el próximo día habilitado.
        for _ in 0..<8 {
            guard let candidate = calendar.nextDate(after: cursor, matching: components,
                                                    matchingPolicy: .nextTime, repeatedTimePolicy: .first,
                                                    direction: .forward) else { return nil }
            let weekday = calendar.component(.weekday, from: candidate)
            if weekdays.isEmpty || weekdays.contains(where: { $0.rawValue == weekday }) {
                return candidate
            }
            cursor = candidate
        }
        return nil
    }

    /// "Todos los días", "Lu a Vi", "Sá, Do"…
    var daysSummary: String {
        if weekdays.isEmpty || weekdays.count == 7 { return String(localized: "Todos los días") }
        let workdays: Set<Weekday> = [.monday, .tuesday, .wednesday, .thursday, .friday]
        if weekdays == workdays { return String(localized: "Lunes a viernes") }
        if weekdays == [.saturday, .sunday] { return String(localized: "Fines de semana") }
        return weekdays.sorted().map(\.shortName).joined(separator: ", ")
    }

    var timeText: String { String(format: "%02d:%02d", hour, minute) }
}

/// Temporizador de una sola vez ("apagar el aire en 60 min").
struct SleepTimer: Codable, Sendable, Hashable, Identifiable {
    var id: UUID
    var fireDate: Date
    var action: AutomationAction
    var label: String

    init(id: UUID = UUID(), fireDate: Date, action: AutomationAction, label: String) {
        self.id = id
        self.fireDate = fireDate
        self.action = action
        self.label = label
    }

    var deviceID: UUID? {
        if case .command(let id, _) = action { return id }
        return nil
    }
}
