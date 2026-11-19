import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var importMessage: ImportMessage?
    @State private var confirmErase = false

    struct ImportMessage: Identifiable {
        let id = UUID()
        var title: String
        var detail: String
    }

    var body: some View {
        @Bindable var settings = model.settings
        PageScroll(title: String(localized: "Ajustes")) {
            SettingsSection(title: String(localized: "General"), symbol: "gearshape") {
                Toggle("Feedback háptico en el trackpad", isOn: $settings.hapticsEnabled)
                Toggle("Sonidos", isOn: $settings.soundsEnabled)
            }

            SettingsSection(title: String(localized: "Puentes"), symbol: "dot.radiowaves.left.and.right") {
                if model.store.bridges.isEmpty {
                    Text("No hay ningún Broadlink configurado. El descubrimiento automático llega con el driver Broadlink.")
                        .auraText(Typography.callout, Theme.Palette.textSecondary)
                } else {
                    ForEach(model.store.bridges) { bridge in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(bridge.name).auraText(Typography.body)
                                Text([bridge.host, bridge.macAddress].compactMap { $0 }.joined(separator: " · "))
                                    .font(Typography.label.monospacedDigit())
                                    .foregroundStyle(Theme.Palette.textSecondary)
                            }
                            Spacer()
                            StatusPill(title: model.settings.demoMode ? String(localized: "Demo") : String(localized: "Sin conexión"),
                                       status: model.settings.demoMode ? .demo : .offline)
                        }
                    }
                }
            }

            SettingsSection(title: String(localized: "Importar y exportar"), symbol: "square.and.arrow.down.on.square") {
                SettingsRow(title: String(localized: "Importar codigos.json del prototipo"),
                            detail: String(localized: "Trae los códigos grabados con python-broadlink (~/.ar-mac/codigos.json).")) {
                    Button("Elegir archivo…") { importLegacy() }.buttonStyle(SecondaryButtonStyle())
                }
                SettingsRow(title: String(localized: "Exportar configuración"),
                            detail: String(localized: "Guarda dispositivos, escenas y códigos en un JSON.")) {
                    Button("Exportar…") { exportConfig() }.buttonStyle(SecondaryButtonStyle())
                }
                SettingsRow(title: String(localized: "Importar configuración"),
                            detail: String(localized: "Reemplaza la configuración actual por la de un JSON exportado.")) {
                    Button("Importar…") { importConfig() }.buttonStyle(SecondaryButtonStyle())
                }
                if model.settings.demoMode {
                    Label("Desactivá el modo demo para importar sobre tus datos reales.", systemImage: "info.circle")
                        .auraText(Typography.label, Theme.Palette.accent)
                }
            }

            SettingsSection(title: String(localized: "Avanzado"), symbol: "wrench.and.screwdriver") {
                Toggle(isOn: Binding(get: { model.settings.demoMode }, set: { model.setDemoMode($0) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Modo demo")
                        Text("Reemplaza los drivers por simulaciones con latencia para revisar la app sin dispositivos. No modifica tus datos.")
                            .auraText(Typography.label, Theme.Palette.textSecondary)
                    }
                }
                SettingsRow(title: String(localized: "Logs"),
                            detail: String(localized: "En Terminal: log stream --predicate 'subsystem == \"com.nationit.aura\"'")) {
                    EmptyView()
                }
                SettingsRow(title: String(localized: "Borrar datos"),
                            detail: String(localized: "Elimina dispositivos, escenas y códigos guardados.")) {
                    Button("Borrar…", role: .destructive) { confirmErase = true }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(model.settings.demoMode)
                }
            }
        }
        .alert(item: $importMessage) { message in
            Alert(title: Text(message.title), message: Text(message.detail))
        }
        .confirmationDialog("¿Borrar todos los datos?", isPresented: $confirmErase) {
            Button("Borrar todo", role: .destructive) { model.store.replaceAll(with: StoreSnapshot()) }
        } message: {
            Text("Esta acción no se puede deshacer. Exportá la configuración antes si querés conservarla.")
        }
    }

    // MARK: - Acciones

    private func importLegacy() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.showsHiddenFiles = true
        panel.canChooseDirectories = false
        panel.directoryURL = LegacyCodesImporter.defaultURL.deletingLastPathComponent()
        panel.message = String(localized: "Elegí el archivo codigos.json del prototipo")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let result = try LegacyCodesImporter.parse(data)
            if model.settings.demoMode { model.setDemoMode(false) }
            let summary = model.store.apply(result)
            var detail = String(localized: "Aire: \(summary.acCodes) códigos · LED: \(summary.ledCodes) códigos.")
            if !summary.warnings.isEmpty {
                detail += "\n\n" + summary.warnings.joined(separator: "\n")
            }
            importMessage = ImportMessage(title: String(localized: "Importación completa"), detail: detail)
        } catch {
            importMessage = ImportMessage(title: String(localized: "No se pudo importar"), detail: error.displayMessage)
        }
    }

    private func exportConfig() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "aura-config.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try StoreFile(url: url).save(model.store.snapshot)
        } catch {
            importMessage = ImportMessage(title: String(localized: "No se pudo exportar"), detail: error.localizedDescription)
        }
    }

    private func importConfig() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            guard let snapshot = try StoreFile(url: url).load() else { return }
            if model.settings.demoMode { model.setDemoMode(false) }
            model.store.replaceAll(with: snapshot)
            importMessage = ImportMessage(title: String(localized: "Configuración importada"),
                                          detail: String(localized: "\(snapshot.devices.count) dispositivos y \(snapshot.scenes.count) escenas."))
        } catch {
            importMessage = ImportMessage(title: String(localized: "No se pudo importar"),
                                          detail: String(localized: "El archivo no es una configuración válida de Aura."))
        }
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Label(title, systemImage: symbol)
                .auraText(Typography.headline)
            Card {
                VStack(alignment: .leading, spacing: Theme.Spacing.md) { content }
                    .toggleStyle(.switch)
                    .tint(Theme.Palette.primary)
            }
        }
        .frame(maxWidth: 720, alignment: .leading)
    }
}

struct SettingsRow<Trailing: View>: View {
    let title: String
    let detail: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).auraText(Typography.body)
                Text(detail).auraText(Typography.label, Theme.Palette.textSecondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            trailing
        }
    }
}
