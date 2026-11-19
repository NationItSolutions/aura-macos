import SwiftUI

/// Panel de la barra de menús: favoritos con controles rápidos y escenas.
struct MenuBarContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.xs) {
                AuraLogo(size: 22)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Aura").font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.Palette.textPrimary)
                    Text(model.summaryLine).font(Typography.caption).foregroundStyle(Theme.Palette.textSecondary)
                }
                Spacer()
                if model.settings.demoMode {
                    Text("DEMO").font(.system(size: 9, weight: .bold)).foregroundStyle(Theme.Palette.warning)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Theme.Palette.warning.opacity(0.15)))
                }
            }

            if model.quickDevices.isEmpty {
                Text("Agregá dispositivos desde la ventana de Aura.")
                    .font(Typography.callout).foregroundStyle(Theme.Palette.textTertiary)
            } else {
                VStack(spacing: 4) {
                    ForEach(model.quickDevices.prefix(8)) { MenuBarDeviceRow(device: $0) }
                }
            }

            if !model.quickScenes.isEmpty {
                Divider().overlay(Theme.Palette.border)
                Text("Escenas").font(Typography.caption).foregroundStyle(Theme.Palette.textSecondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 6)], spacing: 6) {
                    ForEach(model.quickScenes.prefix(6)) { scene in
                        Button { model.run(scene) } label: {
                            HStack(spacing: 6) {
                                if model.runningScene == scene.id {
                                    ProgressView().controlSize(.mini)
                                } else {
                                    Image(systemName: scene.symbol).foregroundStyle(Theme.Palette.accent)
                                }
                                Text(scene.name).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.Palette.textPrimary)
                            .padding(.horizontal, 10)
                            .frame(height: 30)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.Palette.surfaceElevated))
                        }
                        .buttonStyle(.plain)
                        .disabled(model.runningScene != nil)
                    }
                }
            }

            Divider().overlay(Theme.Palette.border)
            HStack {
                Button {
                    MainWindow.show(openWindow: openWindow)
                } label: {
                    Label("Abrir Aura", systemImage: "macwindow")
                }
                Spacer()
                Button {
                    NSApp.terminate(nil)
                } label: {
                    Label("Salir", systemImage: "power")
                }
                .keyboardShortcut("q")
            }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(Theme.Palette.textSecondary)
        }
        .padding(Theme.Spacing.md)
        .frame(width: 320)
        .background(Theme.Palette.surface)
        .preferredColorScheme(.dark)
    }
}

private struct MenuBarDeviceRow: View {
    @Environment(AppModel.self) private var model
    let device: Device

    private var state: DeviceState { model.store.state(for: device.id) }

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            DeviceIcon(device: device, isOn: state.isOn, size: 28)
            VStack(alignment: .leading, spacing: 0) {
                Text(device.name).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.Palette.textPrimary)
                    .lineLimit(1)
                Text(detail).font(Typography.caption).foregroundStyle(Theme.Palette.textTertiary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if device.kind == .airConditioner {
                smallButton("minus") { model.stepTemperature(device, by: -1) }
                smallButton("plus") { model.stepTemperature(device, by: 1) }
            } else if device.kind == .television {
                smallButton("speaker.minus.fill") { model.send(.tvKey(.volumeDown), toDeviceID: device.id) }
                smallButton("speaker.plus.fill") { model.send(.tvKey(.volumeUp), toDeviceID: device.id) }
            }
            Toggle("", isOn: Binding { state.isOn } set: { model.send(.power($0), toDeviceID: device.id) })
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .disabled(model.bus.isBusy(device.id))
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.Palette.surfaceElevated.opacity(0.6)))
    }

    private var detail: String {
        if device.kind == .airConditioner {
            let settings = model.acSettings(for: device)
            return settings.mode.usesTemperature ? "\(settings.mode.displayName) · \(settings.temperature) °C" : settings.mode.displayName
        }
        return state.isOn ? String(localized: "Encendido") : String(localized: "Apagado")
    }

    private func smallButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 10, weight: .bold))
                .frame(width: 22, height: 22)
                .background(Circle().fill(Theme.Palette.surface))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.Palette.textPrimary)
    }
}

/// Abrir/traer la ventana principal también desde el modo "solo barra de menús".
enum MainWindow {
    @MainActor
    static func show(openWindow: OpenWindowAction) {
        if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("main") == true && $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
        }
        NSApp.activate()
    }
}
