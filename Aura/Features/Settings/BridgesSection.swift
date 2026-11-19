import AppKit
import SwiftUI

/// Ajustes → Puentes: descubrir, agregar por IP, probar, redescubrir y olvidar Broadlinks.
struct BridgesSection: View {
    @Environment(AppModel.self) private var model
    @State private var showingDiscovery = false
    @State private var status: [UUID: BridgeStatus] = [:]
    @State private var showingNetworkHelp = false

    enum BridgeStatus: Equatable {
        case testing
        case ok
        case failed(String)
    }

    var body: some View {
        SettingsSection(title: String(localized: "Puentes"), symbol: "dot.radiowaves.left.and.right") {
            if model.store.bridges.isEmpty {
                Text("No hay ningún Broadlink configurado.")
                    .auraText(Typography.callout, Theme.Palette.textSecondary)
            }
            ForEach(model.store.bridges) { bridge in
                bridgeRow(bridge)
                Divider().overlay(Theme.Palette.border)
            }
            HStack {
                PrimaryButton(title: String(localized: "Buscar Broadlink"), symbol: "magnifyingglass") { showingDiscovery = true }
                    .disabled(model.settings.demoMode)
                Spacer()
                Button("Permiso de Red Local…") { showingNetworkHelp = true }.buttonStyle(SecondaryButtonStyle())
            }
            if model.settings.demoMode {
                Label("En modo demo los puentes son simulados. Desactivalo para buscar tu Broadlink real.", systemImage: "info.circle")
                    .auraText(Typography.label, Theme.Palette.accent)
            }
        }
        .sheet(isPresented: $showingDiscovery) {
            DiscoverySheet().environment(model)
        }
        .sheet(isPresented: $showingNetworkHelp) {
            LocalNetworkHelpView()
        }
    }

    private func bridgeRow(_ bridge: Bridge) -> some View {
        HStack(alignment: .center, spacing: Theme.Spacing.md) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .foregroundStyle(Theme.Palette.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(bridge.name).auraText(Typography.body)
                Text(details(bridge))
                    .font(Typography.label.monospacedDigit())
                    .foregroundStyle(Theme.Palette.textSecondary)
                    .textSelection(.enabled)
                if case .failed(let message) = status[bridge.id] {
                    Text(message).auraText(Typography.label, Theme.Palette.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            statusPill(bridge)
            Menu {
                Button("Probar conexión") { test(bridge) }
                Button("Redescubrir por MAC") { rediscover(bridge) }
                Divider()
                Button("Olvidar este puente", role: .destructive) {
                    model.drivers.broadlink.forget(bridge.id)
                    model.store.removeBridge(bridge.id)
                }
            } label: {
                Image(systemName: "ellipsis.circle").font(.system(size: 16))
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .disabled(model.settings.demoMode)
        }
    }

    private func details(_ bridge: Bridge) -> String {
        var parts = [bridge.host]
        if let mac = bridge.macAddress { parts.append(mac) }
        if let type = bridge.deviceType { parts.append(BroadlinkFamily.modelName(for: type) ?? String(format: "0x%04X", type)) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private func statusPill(_ bridge: Bridge) -> some View {
        if model.settings.demoMode {
            StatusPill(title: String(localized: "Demo"), status: .demo)
        } else {
            switch status[bridge.id] {
            case .testing: StatusPill(title: String(localized: "Probando…"), status: .connecting)
            case .ok: StatusPill(title: String(localized: "Conectado"), status: .online)
            case .failed: StatusPill(title: String(localized: "Sin conexión"), status: .offline)
            case nil: StatusPill(title: String(localized: "Sin probar"), status: .connecting)
            }
        }
    }

    private func test(_ bridge: Bridge) {
        status[bridge.id] = .testing
        Task {
            do {
                try await model.drivers.broadlink.testConnection(bridgeID: bridge.id)
                status[bridge.id] = .ok
            } catch {
                status[bridge.id] = .failed(error.displayMessage)
                if (error as? BroadlinkError) == .localNetworkDenied { showingNetworkHelp = true }
            }
        }
    }

    private func rediscover(_ bridge: Bridge) {
        status[bridge.id] = .testing
        Task {
            do {
                if try await model.drivers.broadlink.rediscover(bridgeID: bridge.id) {
                    try await model.drivers.broadlink.testConnection(bridgeID: bridge.id)
                    status[bridge.id] = .ok
                } else {
                    status[bridge.id] = .failed(BroadlinkError.notFound.userMessage)
                }
            } catch {
                status[bridge.id] = .failed(error.displayMessage)
                if (error as? BroadlinkError) == .localNetworkDenied { showingNetworkHelp = true }
            }
        }
    }
}

/// Busca Broadlinks por broadcast o por IP y permite agregarlos.
struct DiscoverySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var results: [DiscoveredBroadlink] = []
    @State private var searching = false
    @State private var error: BroadlinkError?
    @State private var otherError: String?
    @State private var manualIP = ""
    @State private var added: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack {
                Text("Buscar Broadlink").auraText(Typography.title)
                Spacer()
                if searching { ProgressView().controlSize(.small) }
            }
            Text("Aura busca en tu red local. El Broadlink tiene que estar configurado con la app Broadlink y en la misma Wi-Fi que esta Mac.")
                .auraText(Typography.callout, Theme.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if error == .localNetworkDenied {
                LocalNetworkHelpView(compact: true)
            } else if let message = error?.userMessage ?? otherError {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .auraText(Typography.label, Theme.Palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Card(padding: Theme.Spacing.sm) {
                if results.isEmpty {
                    Text(searching ? "Buscando…" : "No se encontró ningún Broadlink todavía.")
                        .auraText(Typography.callout, Theme.Palette.textTertiary)
                        .frame(maxWidth: .infinity, minHeight: 80)
                } else {
                    VStack(spacing: Theme.Spacing.xs) {
                        ForEach(results) { result in resultRow(result) }
                    }
                }
            }

            HStack(spacing: Theme.Spacing.xs) {
                TextField("IP manual (p. ej. 192.168.1.50)", text: $manualIP)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 240)
                    .onSubmit(probe)
                Button("Probar IP") { probe() }.buttonStyle(SecondaryButtonStyle())
                    .disabled(manualIP.isEmpty || searching)
                Spacer()
                Button("Cerrar") { dismiss() }.buttonStyle(SecondaryButtonStyle())
                PrimaryButton(title: String(localized: "Buscar de nuevo"), symbol: "arrow.clockwise", isLoading: searching) { scan() }
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(width: 600)
        .background(Theme.Palette.surfaceElevated)
        .task { scan() }
    }

    private func resultRow(_ result: DiscoveredBroadlink) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "dot.radiowaves.left.and.right").foregroundStyle(Theme.Palette.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(result.name.isEmpty ? result.modelName : "\(result.name) · \(result.modelName)").auraText(Typography.body)
                Text("\(result.host) · \(formatMAC(result.mac))")
                    .font(Typography.label.monospacedDigit()).foregroundStyle(Theme.Palette.textSecondary)
                if result.isLocked {
                    Text(BroadlinkError.locked.userMessage).auraText(Typography.label, Theme.Palette.warning)
                        .fixedSize(horizontal: false, vertical: true)
                } else if result.family == nil {
                    Text(BroadlinkError.unsupportedDevice(result.deviceType).userMessage)
                        .auraText(Typography.label, Theme.Palette.warning)
                }
            }
            Spacer()
            if added.contains(result.id) {
                Label("Agregado", systemImage: "checkmark.circle.fill").auraText(Typography.label, Theme.Palette.success)
            } else {
                Button("Agregar") {
                    model.drivers.broadlink.add(result)
                    added.insert(result.id)
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(result.isLocked || result.family == nil)
            }
        }
        .padding(Theme.Spacing.xs)
    }

    private func scan() {
        guard !searching else { return }
        searching = true
        error = nil
        otherError = nil
        Task {
            defer { searching = false }
            do {
                let found = try await model.drivers.broadlink.discover()
                merge(found)
            } catch let failure as BroadlinkError {
                error = failure
            } catch {
                otherError = error.displayMessage
            }
        }
    }

    private func probe() {
        let host = manualIP.trimmingCharacters(in: .whitespaces)
        guard !host.isEmpty, !searching else { return }
        searching = true
        error = nil
        otherError = nil
        Task {
            defer { searching = false }
            do {
                merge([try await model.drivers.broadlink.probe(host: host)])
            } catch let failure as BroadlinkError {
                error = failure
            } catch {
                otherError = error.displayMessage
            }
        }
    }

    private func merge(_ found: [DiscoveredBroadlink]) {
        for item in found where !results.contains(where: { $0.mac == item.mac }) {
            results.append(item)
        }
    }
}

/// Explica cómo habilitar el permiso de Red Local de macOS.
struct LocalNetworkHelpView: View {
    var compact = false
    @Environment(\.dismiss) private var dismiss

    private static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork")

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "network.badge.shield.half.filled")
                    .font(.system(size: compact ? 20 : 30))
                    .foregroundStyle(Theme.Palette.warning)
                Text("Aura necesita acceso a la red local").auraText(compact ? Typography.body : Typography.headline)
            }
            Text("Para hablar con el Broadlink y la TV, macOS tiene que permitir que Aura use tu red local.")
                .auraText(Typography.callout, Theme.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 4) {
                Text("1. Abrí Ajustes del Sistema → Privacidad y seguridad → Red local.")
                Text("2. Activá el interruptor de Aura.")
                Text("3. Volvé a Aura y probá de nuevo.")
            }
            .auraText(Typography.callout)
            HStack {
                Button("Abrir Ajustes del Sistema") {
                    if let url = Self.settingsURL { NSWorkspace.shared.open(url) }
                }
                .buttonStyle(SecondaryButtonStyle())
                if !compact {
                    Spacer()
                    PrimaryButton(title: String(localized: "Entendido")) { dismiss() }
                }
            }
        }
        .padding(compact ? Theme.Spacing.sm : Theme.Spacing.lg)
        .frame(width: compact ? nil : 460)
        .background(compact ? AnyShapeStyle(Theme.Palette.warning.opacity(0.08)) : AnyShapeStyle(Theme.Palette.surfaceElevated))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.control))
    }
}
