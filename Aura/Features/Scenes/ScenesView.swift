import SwiftUI

/// Hoja de edición abierta: escena nueva o existente.
enum SceneEditTarget: Identifiable {
    case new
    case existing(HomeScene)

    var id: String {
        switch self {
        case .new: "new"
        case .existing(let scene): scene.id.uuidString
        }
    }
}

struct ScenesView: View {
    @Environment(AppModel.self) private var model
    @State private var editing: SceneEditTarget?
    private let columns = [GridItem(.adaptive(minimum: 300, maximum: 420), spacing: Theme.Spacing.md)]

    var body: some View {
        PageScroll(title: String(localized: "Escenas"),
                   subtitle: String(localized: "Una escena ejecuta varios comandos en orden, con demoras entre pasos.")) {
            HStack {
                Spacer()
                PrimaryButton(title: String(localized: "Nueva escena"), symbol: "plus") { editing = .new }
                    .disabled(model.store.devices.isEmpty)
            }
            if model.store.scenes.isEmpty {
                EmptyStateView(symbol: "sparkles", title: String(localized: "Sin escenas"),
                               message: String(localized: "Creá una escena, por ejemplo «Cine»: apagar luces, prender la TV y bajar el aire."))
            } else {
                LazyVGrid(columns: columns, spacing: Theme.Spacing.md) {
                    ForEach(model.store.scenes) { scene in
                        SceneCard(scene: scene) { editing = .existing(scene) }
                    }
                }
            }
        }
        .sheet(item: $editing) { target in
            switch target {
            case .new: SceneEditorSheet(scene: nil).environment(model)
            case .existing(let scene): SceneEditorSheet(scene: scene).environment(model)
            }
        }
    }
}

struct SceneCard: View {
    @Environment(AppModel.self) private var model
    let scene: HomeScene
    var onEdit: (() -> Void)?

    private var running: Bool { model.runningScene == scene.id }

    var body: some View {
        Card(isActive: running) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack {
                    Image(systemName: scene.symbol)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).fill(Theme.brandGradient))
                    VStack(alignment: .leading) {
                        Text(scene.name).auraText(Typography.headline)
                        Text("\(scene.steps.count) pasos").auraText(Typography.label, Theme.Palette.textSecondary)
                    }
                    Spacer()
                    if let onEdit {
                        IconButton(symbol: "pencil", label: String(localized: "Editar escena"), size: 30, action: onEdit)
                    }
                    PrimaryButton(title: String(localized: "Ejecutar"), symbol: "play.fill", isLoading: running) {
                        model.run(scene)
                    }
                    .disabled(model.runningScene != nil && !running)
                }
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(scene.steps.enumerated()), id: \.element.id) { index, step in
                        HStack(spacing: Theme.Spacing.xs) {
                            Text("\(index + 1)")
                                .font(Typography.caption.monospacedDigit())
                                .foregroundStyle(Theme.Palette.textTertiary)
                                .frame(width: 16)
                            if let device = model.store.device(step.deviceID) {
                                Image(systemName: device.symbol).foregroundStyle(Theme.Palette.accent).frame(width: 18)
                                Text(step.command.summary(for: device))
                                    .auraText(Typography.callout, Theme.Palette.textSecondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if step.delayAfter > 0 {
                                Text(String(format: "%.1f s", step.delayAfter))
                                    .font(Typography.caption.monospacedDigit())
                                    .foregroundStyle(Theme.Palette.textTertiary)
                            }
                        }
                    }
                }
            }
        }
    }
}

/// Crear o editar una escena: nombre, ícono y pasos con demora.
struct SceneEditorSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let scene: HomeScene?

    @State private var name = ""
    @State private var symbol = "sparkles"
    @State private var isFavorite = true
    @State private var steps: [SceneStep] = []
    @State private var confirmingDelete = false

    static let symbols = ["sparkles", "film.fill", "moon.stars.fill", "sun.max.fill", "bed.double.fill", "house.fill",
                          "figure.walk", "gamecontroller.fill", "book.fill", "cup.and.saucer.fill", "party.popper.fill",
                          "snowflake", "flame.fill", "power", "music.note", "briefcase.fill"]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text(scene == nil ? "Nueva escena" : "Editar escena").auraText(Typography.title)
            HStack(spacing: Theme.Spacing.md) {
                TextField("Nombre", text: $name, prompt: Text("p. ej. Cine"))
                    .textFieldStyle(.roundedBorder)
                Toggle("Favorita", isOn: $isFavorite)
                    .help(Text("Las favoritas aparecen en la isla y en la barra de menús"))
            }
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(34), spacing: 6), count: 16), spacing: 6) {
                ForEach(Self.symbols, id: \.self) { candidate in
                    IconButton(symbol: candidate, label: candidate, size: 32, isActive: symbol == candidate) { symbol = candidate }
                }
            }

            Text("Pasos").auraText(Typography.label, Theme.Palette.textSecondary)
            ScrollView {
                VStack(spacing: Theme.Spacing.xs) {
                    ForEach($steps) { $step in
                        stepRow($step)
                    }
                    if steps.isEmpty {
                        Text("Agregá el primer paso.").auraText(Typography.callout, Theme.Palette.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(minHeight: 180, maxHeight: 300)
            Button { addStep() } label: { Label("Agregar paso", systemImage: "plus") }
                .buttonStyle(SecondaryButtonStyle())

            HStack {
                if scene != nil {
                    Button("Eliminar", role: .destructive) { confirmingDelete = true }
                        .buttonStyle(SecondaryButtonStyle())
                }
                Spacer()
                Button("Cancelar") { dismiss() }.buttonStyle(SecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                PrimaryButton(title: String(localized: "Guardar"), symbol: "checkmark") { save() }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || steps.isEmpty)
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(width: 780)
        .background(Theme.Palette.surfaceElevated)
        .onAppear(perform: load)
        .confirmationDialog("¿Eliminar esta escena?", isPresented: $confirmingDelete) {
            Button("Eliminar", role: .destructive) {
                if let scene { model.store.removeScene(scene.id) }
                dismiss()
            }
        } message: {
            Text("También se borran las automatizaciones que la ejecutan.")
        }
    }

    private func stepRow(_ step: Binding<SceneStep>) -> some View {
        let index = steps.firstIndex { $0.id == step.wrappedValue.id } ?? 0
        return HStack(spacing: Theme.Spacing.xs) {
            Text("\(index + 1)")
                .font(Typography.caption.monospacedDigit())
                .foregroundStyle(Theme.Palette.textTertiary)
                .frame(width: 16)
            CommandEditor(deviceID: step.deviceID, command: step.command)
            Spacer(minLength: 0)
            Stepper(value: step.delayAfter, in: 0...60, step: 0.5) {
                Text(String(format: String(localized: "+%.1f s"), step.wrappedValue.delayAfter))
                    .font(Typography.caption.monospacedDigit())
                    .foregroundStyle(Theme.Palette.textSecondary)
            }
            .fixedSize()
            .help(Text("Demora después de este paso"))
            IconButton(symbol: "arrow.up", label: String(localized: "Subir"), size: 24) { move(index, by: -1) }
                .disabled(index == 0)
            IconButton(symbol: "trash", label: String(localized: "Quitar paso"), size: 24) {
                steps.removeAll { $0.id == step.wrappedValue.id }
            }
        }
        .padding(Theme.Spacing.xs)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous).fill(Theme.Palette.surface))
    }

    private func move(_ index: Int, by offset: Int) {
        let target = index + offset
        guard steps.indices.contains(index), steps.indices.contains(target) else { return }
        steps.swapAt(index, target)
    }

    private func addStep() {
        guard let device = steps.last.flatMap({ model.store.device($0.deviceID) }) ?? model.store.devices.first else { return }
        let command = CommandChoice.available(for: device).first?.defaultCommand(for: device) ?? .power(true)
        steps.append(SceneStep(deviceID: device.id, command: command, delayAfter: 0.5))
    }

    private func load() {
        guard let scene else { addStep(); return }
        name = scene.name
        symbol = scene.symbol
        isFavorite = scene.isFavorite
        steps = scene.steps
    }

    private func save() {
        var updated = scene ?? HomeScene(name: name, symbol: symbol)
        updated.name = name.trimmingCharacters(in: .whitespaces)
        updated.symbol = symbol
        updated.isFavorite = isFavorite
        updated.steps = steps
        model.store.upsert(updated)
        dismiss()
    }
}
