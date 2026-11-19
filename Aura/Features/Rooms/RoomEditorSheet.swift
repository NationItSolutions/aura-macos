import SwiftUI

/// Crear o editar una habitación: nombre e ícono. Desde acá también se elimina.
struct RoomEditorSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let room: Room?
    var onSaved: (Room) -> Void = { _ in }

    @State private var name = ""
    @State private var symbol = RoomSymbols.all[0]
    @State private var confirmDelete = false

    private let columns = Array(repeating: GridItem(.fixed(44), spacing: Theme.Spacing.xs), count: 8)

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text(room == nil ? "Nueva habitación" : "Editar habitación").auraText(Typography.title)

            TextField("Nombre", text: $name, prompt: Text("Living, Dormitorio, Oficina…"))
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)

            Text("Ícono").auraText(Typography.label, Theme.Palette.textSecondary)
            LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.Spacing.xs) {
                ForEach(RoomSymbols.all, id: \.self) { candidate in
                    IconButton(symbol: candidate, label: candidate, size: 40, isActive: symbol == candidate) {
                        symbol = candidate
                    }
                }
            }

            HStack {
                if room != nil {
                    Button("Eliminar", role: .destructive) { confirmDelete = true }
                        .buttonStyle(SecondaryButtonStyle())
                }
                Spacer()
                Button("Cancelar") { dismiss() }.buttonStyle(SecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                PrimaryButton(title: String(localized: "Guardar"), symbol: "checkmark") { save() }
                    .disabled(trimmedName.isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(width: 460)
        .background(Theme.Palette.surfaceElevated)
        .onAppear {
            if let room {
                name = room.name
                symbol = room.symbol
            }
        }
        .confirmationDialog("¿Eliminar esta habitación?", isPresented: $confirmDelete) {
            Button("Eliminar", role: .destructive) {
                if let room { model.store.removeRoom(room.id) }
                dismiss()
            }
        } message: {
            Text("Los dispositivos no se borran: quedan sin habitación.")
        }
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func save() {
        guard !trimmedName.isEmpty else { return }
        var updated = room ?? Room(name: trimmedName)
        updated.name = trimmedName
        updated.symbol = symbol
        model.store.upsert(updated)
        let saved = model.store.room(updated.id) ?? updated
        dismiss()
        onSaved(saved)
    }
}

enum RoomSymbols {
    static let all = [
        "sofa.fill", "bed.double.fill", "fork.knife", "desktopcomputer", "shower.fill", "tv.fill",
        "figure.and.child.holdinghands", "washer.fill", "car.fill", "tree.fill", "dumbbell.fill", "gamecontroller.fill",
        "books.vertical.fill", "stairs", "door.left.hand.open", "square.split.bottomrightquarter",
    ]
}
