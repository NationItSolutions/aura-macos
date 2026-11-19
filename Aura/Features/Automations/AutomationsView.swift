import SwiftUI

/// Automatizaciones por horario y temporizadores activos.
/// Corren mientras Aura esté abierta, aunque sea solo en la barra de menús.
struct AutomationsView: View {
    @Environment(AppModel.self) private var model
    @State private var editing: AutomationEditTarget?

    var body: some View {
        PageScroll(title: String(localized: "Automatizaciones"),
                   subtitle: String(localized: "Acciones por horario y temporizadores rápidos.")) {
            HStack {
                Label("Corren mientras Aura esté abierta, incluso solo en la barra de menús.", systemImage: "info.circle")
                    .auraText(Typography.label, Theme.Palette.textTertiary)
                Spacer()
                PrimaryButton(title: String(localized: "Nueva automatización"), symbol: "plus") { editing = .new }
                    .disabled(model.store.devices.isEmpty && model.store.scenes.isEmpty)
            }

            if !model.store.timers.isEmpty {
                SectionHeader(title: String(localized: "Temporizadores"))
                VStack(spacing: Theme.Spacing.xs) {
                    ForEach(model.store.timers) { timer in TimerRow(timer: timer) }
                }
            }

            SectionHeader(title: String(localized: "Por horario"))
            if model.store.automations.isEmpty {
                EmptyStateView(symbol: "clock.arrow.2.circlepath", title: String(localized: "Todavía no hay automatizaciones"),
                               message: String(localized: "Por ejemplo: prender el aire a las 18:30 de lunes a viernes, o la escena «Dormir» a las 23:00."))
            } else {
                VStack(spacing: Theme.Spacing.xs) {
                    ForEach(model.store.automations) { automation in
                        AutomationRow(automation: automation) { editing = .existing(automation) }
                    }
                }
            }
        }
        .sheet(item: $editing) { target in
            switch target {
            case .new: AutomationEditorSheet(automation: nil).environment(model)
            case .existing(let automation): AutomationEditorSheet(automation: automation).environment(model)
            }
        }
    }
}

enum AutomationEditTarget: Identifiable {
    case new
    case existing(Automation)

    var id: String {
        switch self {
        case .new: "new"
        case .existing(let automation): automation.id.uuidString
        }
    }
}

extension AppModel {
    /// Texto de la acción ("Aire · Frío 23 °C", "Escena Cine").
    func describe(_ action: AutomationAction) -> String {
        switch action {
        case .command(let deviceID, let command):
            guard let device = store.device(deviceID) else { return String(localized: "Dispositivo eliminado") }
            return command.summary(for: device)
        case .scene(let id):
            return store.scene(id).map { String(localized: "Escena \($0.name)") } ?? String(localized: "Escena eliminada")
        }
    }
}

private struct TimerRow: View {
    @Environment(AppModel.self) private var model
    let timer: SleepTimer

    var body: some View {
        Card {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "timer").foregroundStyle(Theme.Palette.accent).frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(timer.label).auraText(Typography.headline)
                    Text(model.describe(timer.action)).auraText(Typography.label, Theme.Palette.textSecondary)
                }
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(SleepTimerCard.remaining(until: timer.fireDate, now: context.date))
                        .font(.system(size: 20, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Theme.Palette.textPrimary)
                }
                Button("Cancelar") { model.store.removeTimer(timer.id) }.buttonStyle(SecondaryButtonStyle())
            }
        }
    }
}

private struct AutomationRow: View {
    @Environment(AppModel.self) private var model
    let automation: Automation
    let onEdit: () -> Void

    var body: some View {
        Card {
            HStack(spacing: Theme.Spacing.md) {
                Text(automation.timeText)
                    .font(.system(size: 28, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(automation.isEnabled ? Theme.Palette.textPrimary : Theme.Palette.textTertiary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(automation.name).auraText(Typography.headline)
                    Text("\(automation.daysSummary) · \(model.describe(automation.action))")
                        .auraText(Typography.label, Theme.Palette.textSecondary)
                        .lineLimit(1)
                    if automation.isEnabled, let next = automation.nextFire(after: .now) {
                        Text("Próxima: \(next.formatted(.relative(presentation: .named)))")
                            .auraText(Typography.caption, Theme.Palette.textTertiary)
                    }
                }
                Spacer()
                IconButton(symbol: "pencil", label: String(localized: "Editar"), size: 30, action: onEdit)
                Toggle("", isOn: Binding {
                    automation.isEnabled
                } set: { enabled in
                    var updated = automation
                    updated.isEnabled = enabled
                    // Al reactivar no se ejecuta lo que "se perdió" mientras estuvo apagada.
                    if enabled { updated.lastRun = .now }
                    model.store.upsert(updated)
                })
                .toggleStyle(.switch)
                .labelsHidden()
            }
        }
    }
}

/// Crear o editar una automatización.
struct AutomationEditorSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let automation: Automation?

    enum Target: String { case device, scene }

    @State private var name = ""
    @State private var time = Calendar.current.date(bySettingHour: 18, minute: 30, second: 0, of: .now) ?? .now
    @State private var weekdays: Set<Weekday> = []
    @State private var target: Target = .device
    @State private var deviceID = UUID()
    @State private var command: Command = .power(true)
    @State private var sceneID: UUID?
    @State private var confirmingDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text(automation == nil ? "Nueva automatización" : "Editar automatización").auraText(Typography.title)
            Form {
                TextField("Nombre", text: $name, prompt: Text(defaultName))
                DatePicker("Hora", selection: $time, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.field)
            }
            .formStyle(.columns)

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Días").auraText(Typography.label, Theme.Palette.textSecondary)
                HStack(spacing: 6) {
                    ForEach(Weekday.mondayFirst) { day in
                        Chip(title: day.shortName, isSelected: weekdays.contains(day)) {
                            if weekdays.contains(day) { weekdays.remove(day) } else { weekdays.insert(day) }
                        }
                    }
                    Spacer()
                    Text(Automation(name: "", hour: 0, minute: 0, weekdays: weekdays, action: .scene(UUID())).daysSummary)
                        .auraText(Typography.caption, Theme.Palette.textTertiary)
                }
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text("Acción").auraText(Typography.label, Theme.Palette.textSecondary)
                Picker("Acción", selection: $target) {
                    Text("Dispositivo").tag(Target.device)
                    Text("Escena").tag(Target.scene)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 260)
                switch target {
                case .device:
                    if model.store.devices.isEmpty {
                        Text("No hay dispositivos.").auraText(Typography.callout, Theme.Palette.textTertiary)
                    } else {
                        CommandEditor(deviceID: $deviceID, command: $command)
                    }
                case .scene:
                    Picker("Escena", selection: $sceneID) {
                        Text("Elegí una escena").tag(UUID?.none)
                        ForEach(model.store.scenes) { Label($0.name, systemImage: $0.symbol).tag(UUID?.some($0.id)) }
                    }
                    .labelsHidden()
                    .frame(width: 260)
                }
            }

            HStack {
                if automation != nil {
                    Button("Eliminar", role: .destructive) { confirmingDelete = true }.buttonStyle(SecondaryButtonStyle())
                }
                Spacer()
                Button("Cancelar") { dismiss() }.buttonStyle(SecondaryButtonStyle()).keyboardShortcut(.cancelAction)
                PrimaryButton(title: String(localized: "Guardar"), symbol: "checkmark") { save() }
                    .disabled(action == nil)
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(width: 640)
        .background(Theme.Palette.surfaceElevated)
        .onAppear(perform: load)
        .confirmationDialog("¿Eliminar esta automatización?", isPresented: $confirmingDelete) {
            Button("Eliminar", role: .destructive) {
                if let automation { model.store.removeAutomation(automation.id) }
                dismiss()
            }
        }
    }

    private var action: AutomationAction? {
        switch target {
        case .device: model.store.device(deviceID) == nil ? nil : .command(deviceID: deviceID, command: command)
        case .scene: sceneID.map { .scene($0) }
        }
    }

    private var defaultName: String {
        action.map { model.describe($0) } ?? String(localized: "Automatización")
    }

    private func load() {
        if let automation {
            name = automation.name
            time = Calendar.current.date(bySettingHour: automation.hour, minute: automation.minute, second: 0, of: .now) ?? .now
            weekdays = automation.weekdays
            switch automation.action {
            case .command(let id, let cmd):
                target = .device; deviceID = id; command = cmd
            case .scene(let id):
                target = .scene; sceneID = id
            }
        } else if let device = model.store.devices.first {
            deviceID = device.id
            command = CommandChoice.available(for: device).first?.defaultCommand(for: device) ?? .power(true)
            sceneID = model.store.scenes.first?.id
        } else {
            target = .scene
            sceneID = model.store.scenes.first?.id
        }
    }

    private func save() {
        guard let action else { return }
        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        var updated = automation ?? Automation(name: "", hour: 0, minute: 0, action: action)
        updated.name = trimmed.isEmpty ? defaultName : trimmed
        updated.hour = parts.hour ?? 0
        updated.minute = parts.minute ?? 0
        updated.weekdays = weekdays
        updated.action = action
        // Desde ahora: no dispara por un horario que ya pasó.
        updated.lastRun = .now
        model.store.upsert(updated)
        Scheduler.requestNotificationPermission()
        dismiss()
    }
}
