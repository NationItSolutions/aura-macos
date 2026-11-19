import Foundation

/// Error con un mensaje en español listo para mostrar al usuario.
protocol UserFacingError: Error, Sendable {
    var userMessage: String { get }
}

extension Error {
    /// Mensaje para la UI: usa `userMessage` si existe, si no un texto genérico.
    var displayMessage: String {
        if let facing = self as? any UserFacingError { return facing.userMessage }
        if self is CancellationError { return String(localized: "Operación cancelada") }
        return String(localized: "Ocurrió un error inesperado")
    }
}

struct TimeoutError: UserFacingError, Equatable {
    var userMessage: String { String(localized: "El dispositivo no respondió a tiempo") }
}

/// Ejecuta `operation` con un límite de tiempo. Si se pasa, lanza `TimeoutError`.
func withTimeout<T: Sendable>(
    _ duration: Duration,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: duration)
            throw TimeoutError()
        }
        defer { group.cancelAll() }
        guard let result = try await group.next() else { throw TimeoutError() }
        return result
    }
}
