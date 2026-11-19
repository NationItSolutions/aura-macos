import SwiftUI

struct RoomsView: View {
    @Environment(AppModel.self) private var model
    @State private var editing: RoomEditTarget?
    private let columns = [GridItem(.adaptive(minimum: 250, maximum: 360), spacing: Theme.Spacing.md)]

    var body: some View {
        PageScroll(title: String(localized: "Habitaciones"),
                   subtitle: String(localized: "Arrastrá una tarjeta a otra habitación para moverla.")) {
            HStack {
                Spacer()
                PrimaryButton(title: String(localized: "Nueva habitación"), symbol: "plus") { editing = .new }
            }
            if model.store.rooms.isEmpty {
                EmptyStateView(symbol: "square.split.bottomrightquarter", title: String(localized: "Sin habitaciones"),
                               message: String(localized: "Creá una habitación con «Nueva habitación» para agrupar tus dispositivos."))
            }
            ForEach(model.store.rooms) { room in
                RoomSection(room: room, devices: model.store.devices(in: room), columns: columns) {
                    editing = .existing(room)
                }
            }
            let unassigned = model.store.devices.filter { $0.roomID == nil }
            if !unassigned.isEmpty {
                RoomSection(room: nil, devices: unassigned, columns: columns, onEdit: nil)
            }
        }
        .sheet(item: $editing) { target in
            RoomEditorSheet(room: target.room).environment(model)
        }
    }
}

enum RoomEditTarget: Identifiable {
    case new
    case existing(Room)

    var id: String {
        switch self {
        case .new: "new"
        case .existing(let room): room.id.uuidString
        }
    }

    var room: Room? {
        if case .existing(let room) = self { return room }
        return nil
    }
}

/// Una habitación con sus tarjetas. Acepta soltar dispositivos para moverlos acá.
private struct RoomSection: View {
    @Environment(AppModel.self) private var model
    let room: Room?
    let devices: [Device]
    let columns: [GridItem]
    let onEdit: (() -> Void)?
    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: room?.symbol ?? "tray").foregroundStyle(Theme.Palette.accent)
                Text(room?.name ?? String(localized: "Sin habitación")).auraText(Typography.headline)
                Text("\(devices.count)").auraText(Typography.label, Theme.Palette.textTertiary)
                if let onEdit {
                    IconButton(symbol: "pencil", label: String(localized: "Editar habitación"), size: 26, action: onEdit)
                }
                Spacer()
            }
            Group {
                if devices.isEmpty {
                    Text("Sin dispositivos. Soltá una tarjeta acá o elegí la habitación desde la ficha del dispositivo.")
                        .auraText(Typography.callout, Theme.Palette.textTertiary)
                        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                } else {
                    LazyVGrid(columns: columns, spacing: Theme.Spacing.md) {
                        ForEach(devices) { device in
                            DeviceCard(device: device)
                                .draggable(device.id.uuidString)
                        }
                    }
                }
            }
            .padding(Theme.Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .strokeBorder(Theme.Palette.primary.opacity(isTargeted ? 0.8 : 0), lineWidth: 1.5)
            )
            .dropDestination(for: String.self) { items, _ in
                guard let first = items.first, let id = UUID(uuidString: first) else { return false }
                model.store.move(deviceID: id, to: room?.id)
                return true
            } isTargeted: { isTargeted = $0 }
        }
    }
}

/// Contenedor de página con título grande y scroll.
struct PageScroll<Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(title).auraText(Typography.display)
                    if let subtitle {
                        Text(subtitle).auraText(Typography.body, Theme.Palette.textSecondary)
                    }
                }
                content
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.top, Theme.Spacing.xl)
            .padding(.bottom, 96)
            .frame(maxWidth: 1280, alignment: .leading)
        }
        .scrollIndicators(.never)
    }
}
