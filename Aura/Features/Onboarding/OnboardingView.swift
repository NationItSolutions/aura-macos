import SwiftUI

/// Asistente inicial: bienvenida → red local → Broadlink → códigos → TV → listo. Cada paso se puede saltear.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    enum Step: Int, CaseIterable {
        case welcome, network, broadlink, codes, tv, done

        var title: String {
            switch self {
            case .welcome: String(localized: "Bienvenido a Aura")
            case .network: String(localized: "Red local")
            case .broadlink: String(localized: "Tu Broadlink")
            case .codes: String(localized: "Códigos guardados")
            case .tv: String(localized: "Smart TV")
            case .done: String(localized: "¡Todo listo!")
            }
        }

        var symbol: String {
            switch self {
            case .welcome: "sparkles"
            case .network: "wifi"
            case .broadlink: "dot.radiowaves.left.and.right"
            case .codes: "doc.badge.arrow.up"
            case .tv: "tv"
            case .done: "checkmark.seal.fill"
            }
        }
    }

    @State private var step: Step = .welcome
    @State private var showingDiscovery = false
    @State private var importResult: String?
    @State private var importError: String?
    @State private var foundTVs: [String] = []
    @State private var searchingTVs = false
    @State private var tvMessage: String?
    @State private var pairingTV: Device?

    var body: some View {
        VStack(spacing: 0) {
            progress
            VStack(spacing: Theme.Spacing.lg) {
                Image(systemName: step.symbol)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 76, height: 76)
                    .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Theme.brandGradient))
                    .shadow(color: Theme.Palette.primaryGlow, radius: 20)
                Text(step.title).auraText(Typography.title)
                content
                    .frame(maxWidth: 460)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(Theme.Spacing.xl)
            .id(step)
            .transition(.opacity.combined(with: .move(edge: .trailing)))
            footer
        }
        .frame(width: 640, height: 560)
        .background(Theme.Palette.surfaceElevated)
        .animation(Theme.Motion.spring, value: step)
        .sheet(isPresented: $showingDiscovery) { DiscoverySheet().environment(model) }
        .sheet(item: $pairingTV) { TVPairingSheet(deviceID: $0.id).environment(model) }
    }

    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(Step.allCases, id: \.self) { item in
                Capsule()
                    .fill(item.rawValue <= step.rawValue ? Theme.Palette.primary : Theme.Palette.border)
                    .frame(height: 4)
            }
        }
        .padding([.horizontal, .top], Theme.Spacing.lg)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .welcome:
            paragraph("Aura controla tu aire, tu TV y tus luces desde la Mac: con la isla en el notch, la barra de menús, atajos de teclado y Siri.")
            paragraph("Vamos a configurar todo en un par de minutos. Podés saltear cualquier paso y hacerlo después desde Ajustes.")
        case .network:
            paragraph("Aura habla con tus equipos por la red local, sin nube. macOS te va a pedir permiso de «Red local»: tocá Permitir.")
            LocalNetworkHelpView(compact: true)
        case .broadlink:
            paragraph("El Broadlink RM4 Mini es el que manda las señales infrarrojas al aire, las luces y la TV. Tiene que estar configurado con la app Broadlink y en la misma Wi-Fi.")
            HStack {
                Label("\(model.store.bridges.count) puentes configurados", systemImage: "checkmark.circle.fill")
                    .auraText(Typography.callout, model.store.bridges.isEmpty ? Theme.Palette.textTertiary : Theme.Palette.success)
                Spacer()
                PrimaryButton(title: String(localized: "Buscar Broadlink"), symbol: "magnifyingglass") {
                    if model.settings.demoMode { model.setDemoMode(false) }
                    showingDiscovery = true
                }
            }
        case .codes:
            paragraph("Si ya grabaste códigos con el prototipo en Python, importá el archivo codigos.json y Aura crea el aire y las luces con todo lo grabado.")
            HStack {
                if let importResult {
                    Label(importResult, systemImage: "checkmark.circle.fill").auraText(Typography.label, Theme.Palette.success)
                } else if let importError {
                    Label(importError, systemImage: "exclamationmark.triangle.fill").auraText(Typography.label, Theme.Palette.danger)
                }
                Spacer()
                PrimaryButton(title: String(localized: "Elegir codigos.json…"), symbol: "doc") { importCodes() }
            }
            paragraph("¿No tenés el archivo? Salteá este paso: después agregás cada equipo en Dispositivos y Aura te guía para grabar los botones.")
        case .tv:
            paragraph("Si tenés una Smart TV Samsung (2016 o más nueva), Aura la controla por la red: volumen, apps y encendido. La TV tiene que estar prendida.")
            HStack {
                Button {
                    searchTVs()
                } label: {
                    if searchingTVs { ProgressView().controlSize(.small) } else { Label("Buscar TV", systemImage: "magnifyingglass") }
                }
                .buttonStyle(SecondaryButtonStyle())
                ForEach(foundTVs, id: \.self) { host in
                    Button { addTV(host) } label: { Label(host, systemImage: "tv") }
                        .buttonStyle(PrimaryButtonStyle())
                }
                Spacer()
            }
            if let tvMessage {
                Text(tvMessage).auraText(Typography.label, Theme.Palette.textSecondary)
            }
        case .done:
            paragraph("Pasá el mouse por el notch para abrir la isla, o usá ⌥⌘Espacio. También podés decir «Oye Siri, ejecutar Cine en Aura».")
            if model.settings.demoMode {
                Label("Al terminar se desactiva el modo demo.", systemImage: "info.circle")
                    .auraText(Typography.label, Theme.Palette.accent)
            }
        }
    }

    private func paragraph(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .auraText(Typography.body, Theme.Palette.textSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var footer: some View {
        HStack {
            if step != .welcome && step != .done {
                Button("Atrás") { go(-1) }.buttonStyle(SecondaryButtonStyle())
            }
            Spacer()
            if step == .done {
                PrimaryButton(title: String(localized: "Empezar"), symbol: "arrow.right") { finish() }
                    .keyboardShortcut(.defaultAction)
            } else {
                if step != .welcome {
                    Button("Saltear") { go(1) }.buttonStyle(SecondaryButtonStyle())
                }
                PrimaryButton(title: String(localized: "Continuar"), symbol: "arrow.right") { go(1) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Spacing.lg)
    }

    private func go(_ delta: Int) {
        if let next = Step(rawValue: step.rawValue + delta) { step = next }
    }

    private func finish() {
        if model.settings.demoMode { model.setDemoMode(false) }
        model.settings.onboardingCompleted = true
        model.applyHotKeys()
        dismiss()
    }

    private func importCodes() {
        let panel = LegacyCodesImporter.openPanel()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            importResult = try model.importLegacyCodes(from: url)
            importError = nil
        } catch {
            importError = error.displayMessage
        }
    }

    private func searchTVs() {
        searchingTVs = true
        tvMessage = nil
        Task {
            foundTVs = await LocalUDP.discoverSamsungTVs()
            if foundTVs.isEmpty {
                tvMessage = String(localized: "No apareció ninguna. Prendé la TV o agregala con su IP desde Dispositivos.")
            }
            searchingTVs = false
        }
    }

    private func addTV(_ host: String) {
        tvMessage = String(localized: "Conectando con \(host)…")
        Task {
            let info = try? await SamsungTVClient(deviceID: UUID(), host: host).info()
            guard let info else {
                tvMessage = String(localized: "La TV no respondió en \(host).")
                return
            }
            if model.settings.demoMode { model.setDemoMode(false) }
            let device = Device(name: info.name, roomID: model.store.rooms.first?.id, kind: .television,
                                transport: .samsungTizen(host: host, macAddress: info.wifiMac,
                                                         fallbackBridgeID: model.store.bridges.first?.id),
                                isFavorite: true)
            model.store.upsert(device)
            tvMessage = String(localized: "\(info.name) agregada.")
            pairingTV = device
        }
    }
}
