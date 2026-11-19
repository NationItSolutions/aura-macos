import AppKit
import ServiceManagement
import SwiftUI

/// Isla, barra de menús, atajos e inicio con la sesión.
struct ExperienceSections: View {
    @Environment(AppModel.self) private var model
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var loginError: String?
    @Binding var showingOnboarding: Bool

    var body: some View {
        @Bindable var settings = model.settings

        SettingsSection(title: String(localized: "Dynamic Island"), symbol: "capsule.fill") {
            Toggle("Mostrar la isla en el notch", isOn: $settings.islandEnabled)
                .onChange(of: settings.islandEnabled) { _, _ in model.applyIslandSettings() }
            Toggle("Ocultar con apps en pantalla completa", isOn: $settings.islandHideInFullscreen)
                .onChange(of: settings.islandHideInFullscreen) { _, _ in model.island?.refresh() }
                .disabled(!settings.islandEnabled)
            Picker("Pantalla", selection: $settings.islandScreen) {
                ForEach(IslandScreen.allCases) { Text($0.title).tag($0) }
            }
            .onChange(of: settings.islandScreen) { _, _ in model.island?.refresh() }
            .disabled(!settings.islandEnabled)
            Text("Pasá el mouse sobre el notch para abrirla. En Macs sin notch se muestra como una píldora arriba al centro.")
                .auraText(Typography.label, Theme.Palette.textTertiary)
        }

        SettingsSection(title: String(localized: "Barra de menús"), symbol: "menubar.rectangle") {
            Toggle("Mostrar Aura en la barra de menús", isOn: $settings.menuBarEnabled)
                .onChange(of: settings.menuBarEnabled) { _, _ in model.applyActivationPolicy() }
            Toggle(isOn: $settings.menuBarOnly) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Solo en la barra de menús")
                    Text("Sin ícono en el Dock. La ventana se abre desde la barra de menús o con el atajo.")
                        .auraText(Typography.label, Theme.Palette.textSecondary)
                }
            }
            .onChange(of: settings.menuBarOnly) { _, _ in model.applyActivationPolicy() }
            .disabled(!settings.menuBarEnabled)
        }

        SettingsSection(title: String(localized: "Atajos de teclado globales"), symbol: "command") {
            Toggle("Activar atajos globales", isOn: $settings.hotkeysEnabled)
                .onChange(of: settings.hotkeysEnabled) { _, _ in model.applyHotKeys() }
            SettingsRow(title: String(localized: "Abrir o cerrar la isla"), detail: "") {
                ShortcutRecorder(shortcut: $settings.islandShortcut) { model.applyHotKeys() }
            }
            SettingsRow(title: String(localized: "Abrir la ventana de Aura"), detail: "") {
                ShortcutRecorder(shortcut: $settings.windowShortcut) { model.applyHotKeys() }
            }
            Toggle("⌃⌥1…9 ejecutan las escenas favoritas, en orden", isOn: $settings.sceneShortcutsEnabled)
                .onChange(of: settings.sceneShortcutsEnabled) { _, _ in model.applyHotKeys() }
            Text("Funcionan con Aura en segundo plano y no necesitan permisos de Accesibilidad.")
                .auraText(Typography.label, Theme.Palette.textTertiary)
        }

        SettingsSection(title: String(localized: "Inicio"), symbol: "power.circle") {
            Toggle("Abrir Aura al iniciar sesión", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in
                    do {
                        try LoginItem.set(enabled)
                        loginError = nil
                    } catch {
                        loginError = String(localized: "macOS no permitió cambiarlo. Revisalo en Ajustes del Sistema → General → Ítems de inicio.")
                        launchAtLogin = LoginItem.isEnabled
                    }
                }
            if let loginError {
                Label(loginError, systemImage: "exclamationmark.triangle.fill").auraText(Typography.label, Theme.Palette.warning)
            }
            SettingsRow(title: String(localized: "Asistente de configuración"),
                        detail: String(localized: "Volver a recorrer los pasos: red local, Broadlink, códigos y TV.")) {
                Button("Abrir asistente") { showingOnboarding = true }.buttonStyle(SecondaryButtonStyle())
            }
        }
        .onAppear { launchAtLogin = LoginItem.isEnabled }
    }
}

/// Ítem de inicio con SMAppService (macOS 13+).
enum LoginItem {
    @MainActor
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    @MainActor
    static func set(_ enabled: Bool) throws {
        if enabled {
            if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
        } else if SMAppService.mainApp.status == .enabled {
            try SMAppService.mainApp.unregister()
        }
    }
}

/// Grabador de atajos: clic, apretar la combinación (con ⌘, ⌥ o ⌃) o Esc para cancelar.
struct ShortcutRecorder: View {
    @Binding var shortcut: KeyShortcut
    var onChange: () -> Void
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            recording ? stop() : start()
        } label: {
            Text(recording ? String(localized: "Apretá el atajo…") : shortcut.displayString)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .frame(minWidth: 110)
        }
        .buttonStyle(SecondaryButtonStyle())
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        // Mientras se graba, los atajos globales no deben dispararse.
        HotKeyCenter.shared.unregisterAll()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated {
                if event.keyCode == 53 {
                    stop()
                } else if let new = KeyShortcut(event: event) {
                    shortcut = new
                    stop()
                } else {
                    NSSound.beep()
                }
            }
            return nil
        }
    }

    private func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording {
            recording = false
            onChange()
        }
    }
}
