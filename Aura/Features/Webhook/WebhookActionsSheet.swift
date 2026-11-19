import SwiftUI

/// Editor de las acciones HTTP de un dispositivo webhook.
/// Cada acción de tipo "botón" aparece como botón en el control; encender/apagar van al botón de power.
struct WebhookActionsSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let deviceID: UUID

    @State private var actions: [WebhookAction] = []
    @State private var selection: UUID?
    @State private var testing = false
    @State private var testResult: (ok: Bool, text: String)?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Acciones del webhook").auraText(Typography.headline)
                    Text(model.store.device(deviceID)?.name ?? "").auraText(Typography.label, Theme.Palette.textSecondary)
                }
                Spacer()
                Button("Cancelar") { dismiss() }.buttonStyle(SecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                PrimaryButton(title: String(localized: "Guardar"), symbol: "checkmark") { save() }
                    .disabled(!isValid)
            }
            .padding(Theme.Spacing.lg)
            Divider().overlay(Theme.Palette.border)
            HStack(spacing: 0) {
                list.frame(width: 220).background(Theme.Palette.surface.opacity(0.6))
                Divider().overlay(Theme.Palette.border)
                editor.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(Theme.Spacing.lg)
            }
        }
        .frame(width: 760, height: 520)
        .background(Theme.Palette.surfaceElevated)
        .onAppear(perform: load)
    }

    private var isValid: Bool {
        actions.allSatisfy { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty && $0.resolvedURL != nil }
    }

    // MARK: - Lista

    private var list: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            ScrollView {
                VStack(spacing: 4) {
                    ForEach(actions) { action in
                        Button { selection = action.id; testResult = nil } label: {
                            HStack(spacing: Theme.Spacing.xs) {
                                Image(systemName: action.symbol).frame(width: 18)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(action.name.isEmpty ? String(localized: "Sin nombre") : action.name)
                                        .auraText(Typography.callout)
                                    Text(roleTitle(action.role)).auraText(Typography.caption, Theme.Palette.textTertiary)
                                }
                                Spacer()
                                if action.resolvedURL == nil {
                                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Theme.Palette.warning)
                                }
                            }
                            .padding(.horizontal, Theme.Spacing.sm)
                            .padding(.vertical, 8)
                            .background(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                                .fill(selection == action.id ? Theme.Palette.primary.opacity(0.2) : .clear))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(Theme.Spacing.xs)
            }
            Button {
                let action = WebhookAction(name: String(localized: "Acción \(actions.count + 1)"))
                actions.append(action)
                selection = action.id
            } label: {
                Label("Agregar acción", systemImage: "plus")
            }
            .buttonStyle(SecondaryButtonStyle())
            .padding(Theme.Spacing.sm)
        }
    }

    // MARK: - Editor

    @ViewBuilder
    private var editor: some View {
        if let index = actions.firstIndex(where: { $0.id == selection }) {
            let binding = $actions[index]
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Form {
                    TextField("Nombre", text: binding.name)
                    Picker("Uso", selection: binding.role) {
                        ForEach(WebhookAction.Role.allCases, id: \.self) { Text(roleTitle($0)).tag($0) }
                    }
                    Picker("Ícono", selection: binding.symbol) {
                        ForEach(Self.symbols, id: \.self) { Label($0, systemImage: $0).labelStyle(.iconOnly).tag($0) }
                    }
                    Picker("Método", selection: binding.method) {
                        ForEach(WebhookAction.Method.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    TextField("URL", text: binding.url, prompt: Text("http://192.168.1.10:8123/api/webhook/luz"))
                    TextField("Encabezados", text: headersBinding(index), prompt: Text("Authorization: Bearer …"), axis: .vertical)
                        .lineLimit(1...3)
                    if binding.wrappedValue.method != .get {
                        TextField("Cuerpo", text: binding.body, prompt: Text("{\"state\": \"on\"}"), axis: .vertical)
                            .lineLimit(2...5)
                            .font(.system(.callout, design: .monospaced))
                    }
                }
                .formStyle(.columns)
                Text("Un encabezado por línea con el formato «Nombre: valor». Si el cuerpo empieza con { se envía como JSON.")
                    .auraText(Typography.caption, Theme.Palette.textTertiary)
                HStack {
                    Button {
                        test(actions[index])
                    } label: {
                        if testing { ProgressView().controlSize(.small) } else { Label("Probar", systemImage: "paperplane") }
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(testing || binding.wrappedValue.resolvedURL == nil)
                    if let testResult {
                        Label(testResult.text, systemImage: testResult.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                            .auraText(Typography.label, testResult.ok ? Theme.Palette.success : Theme.Palette.danger)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        actions.remove(at: index)
                        selection = actions.first?.id
                    } label: {
                        Label("Eliminar", systemImage: "trash")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                }
            }
        } else {
            EmptyStateView(symbol: "link", title: String(localized: "Sin acciones"),
                           message: String(localized: "Agregá una acción por cada cosa que quieras disparar: encender, apagar, una escena de Home Assistant…"))
        }
    }

    private func headersBinding(_ index: Int) -> Binding<String> {
        Binding {
            actions[index].headers.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
        } set: { text in
            actions[index].headers = Self.parseHeaders(text)
        }
    }

    nonisolated static func parseHeaders(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if !key.isEmpty { result[key] = value }
        }
        return result
    }

    private func roleTitle(_ role: WebhookAction.Role) -> String {
        switch role {
        case .button: String(localized: "Botón")
        case .powerOn: String(localized: "Encender")
        case .powerOff: String(localized: "Apagar")
        }
    }

    static let symbols = ["bolt.fill", "power", "lightbulb.fill", "lightbulb", "fan.fill", "lock.fill", "lock.open.fill",
                          "door.garage.closed", "blinds.horizontal.closed", "speaker.wave.2.fill", "play.fill",
                          "sparkles", "bell.fill", "house.fill", "moon.fill", "sun.max.fill"]

    // MARK: - Acciones

    private func load() {
        guard let device = model.store.device(deviceID), case .webhook(let saved) = device.transport else { return }
        actions = saved.isEmpty
            ? [WebhookAction(name: String(localized: "Encender"), symbol: "power", role: .powerOn),
               WebhookAction(name: String(localized: "Apagar"), symbol: "power", role: .powerOff)]
            : saved
        selection = actions.first?.id
    }

    private func test(_ action: WebhookAction) {
        guard let device = model.store.device(deviceID) else { return }
        var preview = device
        preview.transport = .webhook(actions: [action])
        testing = true
        testResult = nil
        Task {
            do {
                try await WebhookDriver(device: preview).send(.button(action.id.uuidString))
                testResult = (true, String(localized: "Respondió bien"))
            } catch {
                testResult = (false, error.displayMessage)
            }
            testing = false
        }
    }

    private func save() {
        guard var device = model.store.device(deviceID) else { return }
        device.transport = .webhook(actions: actions)
        device.buttons = Self.buttons(for: actions)
        model.store.upsert(device)
        dismiss()
    }

    /// Botones del control: uno por acción de tipo botón, apuntando al id de la acción.
    static func buttons(for actions: [WebhookAction]) -> [CustomButton] {
        actions.filter { $0.role == .button }.map {
            CustomButton(id: $0.id, name: $0.name, symbol: $0.symbol, codeName: $0.id.uuidString, tint: .blue)
        }
    }
}
