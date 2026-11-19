import SwiftUI
import UniformTypeIdentifiers

/// Control IR genérico: grilla de botones grabados, editable (nombre, ícono, color,
/// orden con drag & drop) y con asistente para sumar botones.
struct GenericRemoteView: View {
    @Environment(AppModel.self) private var model
    let device: Device
    @State private var editing = false
    @State private var editingButton: CustomButton?
    @State private var learningSlot: LearningSlot?
    @State private var showingNewButton = false
    @State private var showingWebhook = false

    private var webhookActions: [WebhookAction]? {
        if case .webhook(let actions) = device.transport { return actions }
        return nil
    }

    private var hasPower: Bool {
        if let webhookActions { return webhookActions.contains { $0.role != .button } }
        return device.codes["power_on"] != nil || device.codes["power_off"] != nil
    }

    private var state: DeviceState { model.store.state(for: device.id) }
    private let columns = [GridItem(.adaptive(minimum: 110), spacing: Theme.Spacing.xs)]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            if hasPower {
                HStack(spacing: Theme.Spacing.md) {
                    IconButton(symbol: "power", label: String(localized: "Encender o apagar"), size: 56,
                               isActive: state.isOn, isLoading: model.bus.isBusy(device.id)) {
                        model.togglePower(device)
                    }
                    Text(state.isOn ? String(localized: "Encendido") : String(localized: "Apagado"))
                        .auraText(Typography.headline)
                }
            }
            Card {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    HStack {
                        Text("Botones").auraText(Typography.label, Theme.Palette.textSecondary)
                        Spacer()
                        if webhookActions != nil {
                            Button { showingWebhook = true } label: { Label("Configurar acciones", systemImage: "slider.horizontal.3") }
                                .buttonStyle(SecondaryButtonStyle())
                        } else {
                            Button { showingNewButton = true } label: { Label("Agregar", systemImage: "plus") }
                                .buttonStyle(SecondaryButtonStyle())
                        }
                        Button { withAnimation(Theme.Motion.spring) { editing.toggle() } } label: {
                            Label(editing ? "Listo" : "Editar", systemImage: editing ? "checkmark" : "pencil")
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .disabled(device.buttons.isEmpty)
                    }
                    if device.buttons.isEmpty {
                        Text(webhookActions != nil
                             ? String(localized: "Agregá acciones de tipo «Botón» en «Configurar acciones».")
                             : String(localized: "Este control todavía no tiene botones. Tocá «Agregar» para grabar el primero."))
                            .auraText(Typography.callout, Theme.Palette.textTertiary)
                    } else {
                        LazyVGrid(columns: columns, spacing: Theme.Spacing.xs) {
                            ForEach(device.buttons) { button in
                                buttonTile(button)
                            }
                        }
                    }
                    if editing {
                        Text("Arrastrá para reordenar. Tocá un botón para editarlo.")
                            .auraText(Typography.caption, Theme.Palette.textTertiary)
                    }
                }
            }
        }
        .sheet(isPresented: $showingWebhook) {
            WebhookActionsSheet(deviceID: device.id).environment(model)
        }
        .sheet(item: $editingButton) { button in
            EditButtonSheet(device: device, button: button) { learningSlot = $0 }
                .environment(model)
        }
        .sheet(item: $learningSlot) { slot in
            LearningWizardSheet(model: model, deviceID: device.id, slots: [slot], allowsCustom: false)
                .environment(model)
        }
        .sheet(isPresented: $showingNewButton) {
            CustomButtonSheet(confirmTitle: String(localized: "Grabar")) { name, symbol, tint in
                // Espera a que cierre esta hoja antes de abrir el asistente.
                let slot = LearningSlot.custom(name: name, symbol: symbol, tint: tint)
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(350))
                    learningSlot = slot
                }
            }
        }
    }

    @ViewBuilder
    private func buttonTile(_ button: CustomButton) -> some View {
        let recorded = webhookActions != nil || device.codes[button.codeName] != nil
        TileButton(symbol: button.symbol, title: button.name, tint: button.tint.color) {
            if editing, webhookActions == nil {
                editingButton = button
            } else {
                model.send(.button(button.codeName), toDeviceID: device.id)
            }
        }
        .overlay(alignment: .topTrailing) {
            if editing {
                Image(systemName: "pencil.circle.fill")
                    .foregroundStyle(Theme.Palette.accent)
                    .padding(6)
            } else if !recorded {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(Theme.Palette.warning)
                    .padding(6)
                    .help(Text("Sin código grabado"))
            }
        }
        .rotationEffect(.degrees(editing ? 1.2 : 0))
        .draggable(button.id.uuidString) {
            Label(button.name, systemImage: button.symbol).padding(8)
        }
        .dropDestination(for: String.self) { items, _ in
            guard editing, let raw = items.first, let sourceID = UUID(uuidString: raw) else { return false }
            move(sourceID, before: button.id)
            return true
        }
    }

    private func move(_ sourceID: UUID, before targetID: UUID) {
        guard sourceID != targetID, var updated = model.store.device(device.id),
              let from = updated.buttons.firstIndex(where: { $0.id == sourceID }),
              let to = updated.buttons.firstIndex(where: { $0.id == targetID }) else { return }
        let item = updated.buttons.remove(at: from)
        updated.buttons.insert(item, at: to)
        withAnimation(Theme.Motion.spring) { model.store.upsert(updated) }
    }
}

/// Editar un botón: nombre, ícono, color, volver a grabar o eliminar.
private struct EditButtonSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let device: Device
    let button: CustomButton
    let onRelearn: (LearningSlot) -> Void

    var body: some View {
        VStack(spacing: 0) {
            CustomButtonSheet(initialName: button.name, initialSymbol: button.symbol, initialTint: button.tint,
                              confirmTitle: String(localized: "Guardar")) { name, symbol, tint in
                update { $0.name = name; $0.symbol = symbol; $0.tint = tint }
            }
            HStack {
                Button("Eliminar botón", role: .destructive) {
                    guard var updated = model.store.device(device.id) else { return }
                    updated.buttons.removeAll { $0.id == button.id }
                    updated.codes[button.codeName] = nil
                    model.store.upsert(updated)
                    dismiss()
                }
                .buttonStyle(SecondaryButtonStyle())
                Spacer()
                Button {
                    let slot = LearningSlot(codeName: button.codeName, title: button.name, symbol: button.symbol)
                    dismiss()
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(350))
                        onRelearn(slot)
                    }
                } label: {
                    Label("Volver a grabar", systemImage: "dot.radiowaves.left.and.right")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            .padding([.horizontal, .bottom], Theme.Spacing.lg)
        }
        .background(Theme.Palette.surfaceElevated)
    }

    private func update(_ change: (inout CustomButton) -> Void) {
        guard var updated = model.store.device(device.id),
              let index = updated.buttons.firstIndex(where: { $0.id == button.id }) else { return }
        change(&updated.buttons[index])
        model.store.upsert(updated)
    }
}
