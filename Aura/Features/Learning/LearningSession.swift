import Foundation
import Observation

/// Estado del asistente de aprendizaje. Guarda cada código apenas se graba.
@MainActor
@Observable
final class LearningSession {
    enum Stage: Equatable {
        case ready
        case listening
        case captured
        case failed(String)
        case finished
    }

    let deviceID: UUID
    private(set) var slots: [LearningSlot]
    private(set) var index = 0
    private(set) var stage: Stage = .ready
    private(set) var phase: LearningPhase = .listening
    private(set) var remaining = 30
    private(set) var isTesting = false
    private(set) var testResult: String?
    private(set) var recorded: Set<String> = []
    private(set) var skipped: Set<String> = []
    var signalKind: SignalKind = .infrared
    private(set) var supportsRadio = false

    let listenSeconds = 30

    @ObservationIgnored private let model: AppModel
    @ObservationIgnored private var learner: (any CodeLearner)?
    @ObservationIgnored private var learnTask: Task<Void, Never>?
    @ObservationIgnored private var countdownTask: Task<Void, Never>?
    @ObservationIgnored private var lastCode: Data?

    init(model: AppModel, deviceID: UUID, slots: [LearningSlot]) {
        self.model = model
        self.deviceID = deviceID
        self.slots = slots
        if let device = model.store.device(deviceID) {
            recorded = Set(slots.map(\.codeName).filter { device.codes[$0] != nil })
        }
    }

    var current: LearningSlot? { slots.indices.contains(index) ? slots[index] : nil }
    var progress: Double { slots.isEmpty ? 1 : Double(index) / Double(slots.count) }

    func select(_ slot: LearningSlot) {
        guard let position = slots.firstIndex(of: slot) else { return }
        cancelListening()
        index = position
        stage = .ready
    }

    func append(_ slot: LearningSlot) {
        slots.append(slot)
        cancelListening()
        index = slots.count - 1
        stage = .ready
    }

    /// Prepara el aprendizaje (crea el cliente del puente).
    func prepare() async {
        guard learner == nil else { return }
        do {
            let bridgeID = model.store.device(deviceID)?.transport.bridgeID
            let learner = try await model.drivers.learner(for: bridgeID)
            self.learner = learner
            supportsRadio = await learner.supportsRadio
        } catch {
            stage = .failed(error.displayMessage)
        }
    }

    func startListening() {
        guard current != nil else { return }
        cancelListening()
        stage = .listening
        phase = signalKind == .radio ? .sweeping : .listening
        remaining = listenSeconds
        testResult = nil
        let kind = signalKind
        let seconds = listenSeconds

        countdownTask = Task { [weak self] in
            while let self, self.remaining > 0, self.stage == .listening {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self.remaining -= 1
            }
        }
        learnTask = Task { [weak self] in
            guard let self else { return }
            if self.learner == nil { await self.prepare() }
            guard let learner = self.learner else { return }
            do {
                let code = try await learner.learn(kind, timeout: .seconds(seconds)) { phase in
                    Task { @MainActor in self.phase = phase }
                }
                guard !Task.isCancelled else { return }
                self.store(code)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                self.stage = .failed(error.displayMessage)
            }
            self.countdownTask?.cancel()
        }
    }

    /// Guarda el código en el dispositivo apenas llega.
    private func store(_ code: Data) {
        guard let slot = current, var device = model.store.device(deviceID) else { return }
        device.codes[slot.codeName] = code.base64EncodedString()
        if let button = slot.customButton, !device.buttons.contains(where: { $0.codeName == button.codeName }) {
            device.buttons.append(button)
        }
        model.store.upsert(device)
        lastCode = code
        recorded.insert(slot.codeName)
        skipped.remove(slot.codeName)
        stage = .captured
        Log.broadlink.info("Código grabado: \(slot.codeName, privacy: .public)")
    }

    /// Reenvía el código recién grabado para comprobar que funciona.
    func test() {
        guard let code = lastCode ?? currentStoredCode, let learner else { return }
        isTesting = true
        testResult = nil
        Task {
            do {
                try await learner.test(code)
                testResult = String(localized: "Enviado. ¿Reaccionó el equipo?")
            } catch {
                testResult = error.displayMessage
            }
            isTesting = false
        }
    }

    private var currentStoredCode: Data? {
        guard let slot = current, let base64 = model.store.device(deviceID)?.codes[slot.codeName] else { return nil }
        return Data(base64Encoded: base64)
    }

    func retry() {
        startListening()
    }

    func skip() {
        if let slot = current, !recorded.contains(slot.codeName) { skipped.insert(slot.codeName) }
        advance()
    }

    func next() {
        advance()
    }

    private func advance() {
        cancelListening()
        lastCode = nil
        testResult = nil
        // Siguiente botón sin grabar; si no hay, termina.
        if let nextIndex = slots.indices.first(where: { $0 > index && !recorded.contains(slots[$0].codeName) }) {
            index = nextIndex
            stage = .ready
        } else {
            index = slots.count
            stage = .finished
        }
    }

    func cancelListening() {
        let wasListening = stage == .listening
        learnTask?.cancel()
        countdownTask?.cancel()
        learnTask = nil
        countdownTask = nil
        if wasListening {
            stage = .ready
            if let learner { Task { await learner.cancel() } }
        }
    }
}
