import SwiftUI

/// Emparejamiento con una Smart TV Samsung: la TV muestra "Permitir" y Aura guarda el token en el Llavero.
struct TVPairingSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let deviceID: UUID

    enum Phase: Equatable {
        case idle, waiting, paired, failed(String)
    }

    @State private var phase: Phase = .idle
    @State private var pulse = false

    private var device: Device? { model.store.device(deviceID) }

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            hero
            VStack(spacing: Theme.Spacing.xs) {
                Text(title).auraText(Typography.title)
                Text(message)
                    .auraText(Typography.callout, Theme.Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if model.settings.demoMode {
                Label("Modo demo: el emparejamiento se simula.", systemImage: "sparkles")
                    .auraText(Typography.label, Theme.Palette.warning)
            }
            HStack {
                Button(phase == .paired ? "Cerrar" : "Más tarde") { dismiss() }
                    .buttonStyle(SecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Spacer()
                switch phase {
                case .paired:
                    PrimaryButton(title: String(localized: "Listo"), symbol: "checkmark") { dismiss() }
                case .waiting:
                    PrimaryButton(title: String(localized: "Esperando a la TV…"), isLoading: true) {}
                        .disabled(true)
                default:
                    PrimaryButton(title: phase == .idle ? String(localized: "Emparejar") : String(localized: "Reintentar"),
                                  symbol: "link") { pair() }
                }
            }
        }
        .padding(Theme.Spacing.xl)
        .frame(width: 460)
        .background(Theme.Palette.surfaceElevated)
        .onAppear {
            if let device, model.isTVPaired(device) { phase = .paired } else { pair() }
        }
    }

    private var hero: some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.35), lineWidth: 2)
                .frame(width: 120, height: 120)
                .scaleEffect(pulse ? 1.15 : 0.9)
                .opacity(pulse ? 0 : 1)
            Circle()
                .fill(tint.opacity(0.15))
                .frame(width: 96, height: 96)
            Image(systemName: heroSymbol)
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(height: 130)
        .onChange(of: phase) { _, newValue in
            pulse = false
            if newValue == .waiting {
                withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { pulse = true }
            }
        }
    }

    private var tint: Color {
        switch phase {
        case .paired: Theme.Palette.success
        case .failed: Theme.Palette.danger
        default: Theme.Palette.accent
        }
    }

    private var heroSymbol: String {
        switch phase {
        case .paired: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        default: "tv"
        }
    }

    private var title: String {
        switch phase {
        case .idle: String(localized: "Emparejar TV")
        case .waiting: String(localized: "Aceptá Aura en la TV")
        case .paired: String(localized: "¡TV emparejada!")
        case .failed: String(localized: "No se pudo emparejar")
        }
    }

    private var message: String {
        switch phase {
        case .idle:
            String(localized: "Encendé la TV. Aura le va a pedir permiso para controlarla.")
        case .waiting:
            String(localized: "En la pantalla de la TV apareció un aviso: elegí «Permitir» con el control remoto. Tenés 30 segundos.")
        case .paired:
            String(localized: "Ya podés usar volumen, D-pad y apps desde Aura, la isla y la barra de menús.")
        case .failed(let reason):
            reason
        }
    }

    private func pair() {
        guard let device else { return }
        phase = .waiting
        Task {
            do {
                try await model.pairTV(device)
                phase = .paired
            } catch {
                phase = .failed(error.displayMessage)
            }
        }
    }
}
