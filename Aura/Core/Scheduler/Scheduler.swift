import Foundation
import UserNotifications

/// Ejecuta automatizaciones y temporizadores mientras la app esté abierta
/// (ventana o solo barra de menú). Duerme hasta el próximo evento, como mucho 30 s,
/// para reaccionar a cambios de hora, de huso o a ediciones.
@MainActor
final class Scheduler {
    typealias Perform = @MainActor (AutomationAction, _ label: String) async -> Bool

    private let store: AppStore
    private let perform: Perform
    private var loop: Task<Void, Never>?
    private let now: @Sendable () -> Date

    init(store: AppStore, now: @escaping @Sendable () -> Date = { Date() }, perform: @escaping Perform) {
        self.store = store
        self.now = now
        self.perform = perform
    }

    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let wait = await self.tick()
                try? await Task.sleep(for: .seconds(wait))
            }
        }
    }

    func stop() {
        loop?.cancel()
        loop = nil
    }

    /// Ejecuta lo vencido y devuelve cuántos segundos dormir.
    @discardableResult
    func tick() async -> Double {
        let current = now()
        for timer in store.timers where timer.fireDate <= current {
            store.removeTimer(timer.id)
            Log.scheduler.info("Temporizador: \(timer.label, privacy: .public)")
            let ok = await perform(timer.action, timer.label)
            if !ok { notifyFailure(timer.label) }
        }
        for automation in store.automations where automation.isEnabled {
            // Debió correr entre la última corrida (o hace 2 min) y ahora.
            let since = automation.lastRun ?? current.addingTimeInterval(-120)
            guard let due = automation.nextFire(after: since), due <= current else { continue }
            var updated = automation
            updated.lastRun = current
            store.upsert(updated)
            // Si la app estuvo cerrada mucho tiempo, no ejecutamos acciones viejas.
            guard current.timeIntervalSince(due) < 120 else { continue }
            Log.scheduler.info("Automatización: \(automation.name, privacy: .public)")
            let ok = await perform(automation.action, automation.name)
            if !ok { notifyFailure(automation.name) }
        }
        return nextWait(from: current)
    }

    func nextWait(from current: Date) -> Double {
        var candidates = store.timers.map(\.fireDate)
        candidates += store.automations.filter(\.isEnabled).compactMap { $0.nextFire(after: current) }
        guard let next = candidates.min() else { return 30 }
        return min(max(next.timeIntervalSince(current), 0.5), 30)
    }

    // MARK: - Notificaciones (solo errores en segundo plano)

    static func requestNotificationPermission() {
        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        }
    }

    private func notifyFailure(_ label: String) {
        let content = UNMutableNotificationContent()
        content.title = String(localized: "No se pudo ejecutar «\(label)»")
        content.body = String(localized: "Revisá que el dispositivo esté conectado.")
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
