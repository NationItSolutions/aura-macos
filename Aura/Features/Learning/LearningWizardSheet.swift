import SwiftUI

/// Asistente de aprendizaje: lista de botones a la izquierda, paso actual a la derecha.
struct LearningWizardSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var session: LearningSession
    @State private var showingCustom = false
    private let allowsCustom: Bool

    init(model: AppModel, deviceID: UUID, slots: [LearningSlot], startAt: LearningSlot? = nil, allowsCustom: Bool = true) {
        let session = LearningSession(model: model, deviceID: deviceID, slots: slots)
        if let startAt { session.select(startAt) }
        _session = State(initialValue: session)
        self.allowsCustom = allowsCustom
    }

    private var device: Device? { model.store.device(session.deviceID) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.Palette.border)
            HStack(spacing: 0) {
                slotList
                    .frame(width: 230)
                    .background(Theme.Palette.surface.opacity(0.6))
                Divider().overlay(Theme.Palette.border)
                stepView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(Theme.Spacing.lg)
            }
        }
        .frame(width: 760, height: 540)
        .background(Theme.Palette.surfaceElevated)
        .task { await session.prepare() }
        .onDisappear { session.cancelListening() }
        .sheet(isPresented: $showingCustom) {
            CustomButtonSheet { name, symbol, tint in
                session.append(.custom(name: name, symbol: symbol, tint: tint))
            }
        }
    }

    private var header: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.brandGradient))
            VStack(alignment: .leading, spacing: 2) {
                Text("Grabar códigos").auraText(Typography.headline)
                Text(device?.name ?? "").auraText(Typography.label, Theme.Palette.textSecondary)
            }
            Spacer()
            if session.supportsRadio {
                Picker("Señal", selection: $session.signalKind) {
                    Text("Infrarrojo").tag(SignalKind.infrared)
                    Text("RF 433 MHz").tag(SignalKind.radio)
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
                .disabled(session.stage == .listening)
            }
            Button("Listo") { dismiss() }.buttonStyle(SecondaryButtonStyle())
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.md)
    }

    private var slotList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(session.slots) { slot in
                        Button { session.select(slot) } label: {
                            HStack(spacing: Theme.Spacing.xs) {
                                statusIcon(for: slot)
                                Text(slot.title).font(Typography.callout).lineLimit(1)
                                Spacer()
                            }
                            .padding(.horizontal, Theme.Spacing.sm)
                            .frame(height: 32)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(session.current == slot ? Theme.Palette.primary.opacity(0.18) : .clear)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.Palette.textPrimary)
                    }
                }
                .padding(Theme.Spacing.xs)
            }
            if allowsCustom {
                Divider().overlay(Theme.Palette.border)
                Button { showingCustom = true } label: {
                    Label("Agregar botón", systemImage: "plus.circle.fill")
                        .font(Typography.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Theme.Spacing.sm)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.Palette.accent)
            }
        }
    }

    @ViewBuilder
    private func statusIcon(for slot: LearningSlot) -> some View {
        if session.recorded.contains(slot.codeName) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.Palette.success)
        } else if session.skipped.contains(slot.codeName) {
            Image(systemName: "forward.circle").foregroundStyle(Theme.Palette.textTertiary)
        } else {
            Image(systemName: "circle").foregroundStyle(Theme.Palette.textTertiary)
        }
    }

    @ViewBuilder
    private var stepView: some View {
        switch session.stage {
        case .finished:
            FinishedStep(recorded: session.recorded.count, total: session.slots.count) { dismiss() }
        default:
            if let slot = session.current {
                SlotStep(session: session, slot: slot)
            } else {
                FinishedStep(recorded: session.recorded.count, total: session.slots.count) { dismiss() }
            }
        }
    }
}

/// Paso de un botón: instrucción, escucha con cuenta regresiva, prueba.
private struct SlotStep: View {
    let session: LearningSession
    let slot: LearningSlot

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer(minLength: 0)
            ListeningIndicator(stage: session.stage, phase: session.phase,
                               remaining: session.remaining, total: session.listenSeconds, symbol: slot.symbol)
            VStack(spacing: Theme.Spacing.xs) {
                Text(slot.title).auraText(Typography.title)
                Text(message).auraText(Typography.body, Theme.Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
                    .fixedSize(horizontal: false, vertical: true)
                if let result = session.testResult {
                    Text(result).auraText(Typography.label, Theme.Palette.accent)
                }
            }
            actions
            Spacer(minLength: 0)
        }
        .animation(Theme.Motion.spring, value: session.stage)
    }

    private var message: String {
        switch session.stage {
        case .ready:
            if session.recorded.contains(slot.codeName) {
                return String(localized: "Este botón ya está grabado. Podés probarlo o grabarlo de nuevo.")
            }
            return slot.instruction
        case .listening:
            switch session.phase {
            case .sweeping:
                return String(localized: "Mantené apretado «\(slot.title)» hasta que Aura encuentre la frecuencia.")
            case .frequencyFound(let mhz):
                let value = String(format: "%.2f", mhz)
                return String(localized: "Frecuencia encontrada (\(value) MHz). Soltá y apretá «\(slot.title)» una vez.")
            case .listening:
                return slot.instruction
            }
        case .captured:
            return String(localized: "¡Listo! El código quedó guardado. Probalo para confirmar que el equipo responde.")
        case .failed(let reason):
            return reason
        case .finished:
            return ""
        }
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: Theme.Spacing.sm) {
            switch session.stage {
            case .ready:
                if session.recorded.contains(slot.codeName) {
                    Button("Probar") { session.test() }.buttonStyle(SecondaryButtonStyle()).disabled(session.isTesting)
                }
                Button("Omitir") { session.skip() }.buttonStyle(SecondaryButtonStyle())
                PrimaryButton(title: String(localized: "Empezar a escuchar"), symbol: "dot.radiowaves.left.and.right") {
                    session.startListening()
                }
            case .listening:
                Button("Cancelar") { session.cancelListening() }.buttonStyle(SecondaryButtonStyle())
            case .captured:
                Button("Reintentar") { session.retry() }.buttonStyle(SecondaryButtonStyle())
                Button("Probar") { session.test() }.buttonStyle(SecondaryButtonStyle()).disabled(session.isTesting)
                PrimaryButton(title: String(localized: "Siguiente"), symbol: "arrow.right") { session.next() }
            case .failed:
                Button("Omitir") { session.skip() }.buttonStyle(SecondaryButtonStyle())
                PrimaryButton(title: String(localized: "Reintentar"), symbol: "arrow.clockwise") { session.retry() }
            case .finished:
                EmptyView()
            }
        }
    }
}

/// Animación de "escuchando…" con anillo de cuenta regresiva.
struct ListeningIndicator: View {
    let stage: LearningSession.Stage
    let phase: LearningPhase
    let remaining: Int
    let total: Int
    let symbol: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    private var tint: Color {
        switch stage {
        case .captured: Theme.Palette.success
        case .failed: Theme.Palette.danger
        default: Theme.Palette.primary
        }
    }

    var body: some View {
        ZStack {
            if stage == .listening && !reduceMotion {
                ForEach(0..<3) { ring in
                    Circle()
                        .stroke(Theme.Palette.primary.opacity(0.35), lineWidth: 2)
                        .scaleEffect(pulse ? 1.6 + Double(ring) * 0.25 : 0.9)
                        .opacity(pulse ? 0 : 0.8)
                        .animation(.easeOut(duration: 1.8).repeatForever(autoreverses: false).delay(Double(ring) * 0.45), value: pulse)
                }
            }
            Circle().fill(tint.opacity(0.12))
            Circle()
                .trim(from: 0, to: stage == .listening ? CGFloat(remaining) / CGFloat(max(total, 1)) : 1)
                .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: remaining)
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(tint)
                    .symbolEffect(.pulse, isActive: stage == .listening && !reduceMotion)
                if stage == .listening {
                    Text("\(remaining) s").font(Typography.label.monospacedDigit()).foregroundStyle(Theme.Palette.textSecondary)
                }
            }
        }
        .frame(width: 130, height: 130)
        .onAppear { pulse = true }
        .accessibilityElement()
        .accessibilityLabel(Text(accessibilityText))
    }

    private var icon: String {
        switch stage {
        case .captured: "checkmark"
        case .failed: "exclamationmark.triangle.fill"
        case .listening: phase == .sweeping ? "antenna.radiowaves.left.and.right" : "dot.radiowaves.left.and.right"
        default: symbol
        }
    }

    private var accessibilityText: String {
        switch stage {
        case .listening: String(localized: "Escuchando, quedan \(remaining) segundos")
        case .captured: String(localized: "Código grabado")
        case .failed: String(localized: "Error")
        default: String(localized: "Listo para grabar")
        }
    }
}

private struct FinishedStep: View {
    let recorded: Int
    let total: Int
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 54))
                .foregroundStyle(Theme.brandGradient)
            Text("¡Terminaste!").auraText(Typography.title)
            Text("Grabaste \(recorded) de \(total) botones. Podés volver a este asistente cuando quieras para completar los que faltan.")
                .auraText(Typography.body, Theme.Palette.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            PrimaryButton(title: String(localized: "Cerrar"), action: onClose)
        }
    }
}

/// Crear un botón personalizado: nombre, ícono y color.
struct CustomButtonSheet: View {
    @Environment(\.dismiss) private var dismiss
    var initialName = ""
    var initialSymbol = "circle.fill"
    var initialTint: ButtonTint = .blue
    var confirmTitle = String(localized: "Agregar")
    let onSave: (String, String, ButtonTint) -> Void

    @State private var name = ""
    @State private var symbol = "circle.fill"
    @State private var tint: ButtonTint = .blue

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Botón").auraText(Typography.headline)
            TextField("Nombre (p. ej. Velocidad)", text: $name)
                .textFieldStyle(.roundedBorder)
            Text("Ícono").auraText(Typography.label, Theme.Palette.textSecondary)
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(36), spacing: 6), count: 9), spacing: 6) {
                    ForEach(ButtonSymbols.all, id: \.self) { candidate in
                        Button { symbol = candidate } label: {
                            Image(systemName: candidate)
                                .frame(width: 36, height: 36)
                                .background(RoundedRectangle(cornerRadius: 8)
                                    .fill(symbol == candidate ? Theme.Palette.primary : Theme.Palette.surface))
                                .foregroundStyle(symbol == candidate ? Color.white : Theme.Palette.textPrimary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(candidate)
                    }
                }
            }
            .frame(height: 170)
            Text("Color").auraText(Typography.label, Theme.Palette.textSecondary)
            HStack(spacing: Theme.Spacing.xs) {
                ForEach(ButtonTint.allCases, id: \.self) { candidate in
                    Button { tint = candidate } label: {
                        Circle().fill(candidate.color).frame(width: 24, height: 24)
                            .overlay(Circle().strokeBorder(.white, lineWidth: tint == candidate ? 2 : 0))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(candidate.rawValue)
                }
            }
            HStack {
                Spacer()
                Button("Cancelar") { dismiss() }.buttonStyle(SecondaryButtonStyle())
                PrimaryButton(title: confirmTitle) {
                    onSave(name.trimmingCharacters(in: .whitespaces), symbol, tint)
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(width: 420)
        .background(Theme.Palette.surfaceElevated)
        .onAppear {
            name = initialName
            symbol = initialSymbol
            tint = initialTint
        }
    }
}
