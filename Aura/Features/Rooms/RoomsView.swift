import SwiftUI

struct RoomsView: View {
    @Environment(AppModel.self) private var model
    private let columns = [GridItem(.adaptive(minimum: 250, maximum: 360), spacing: Theme.Spacing.md)]

    var body: some View {
        PageScroll(title: String(localized: "Habitaciones")) {
            if model.store.rooms.isEmpty {
                EmptyStateView(symbol: "square.split.bottomrightquarter", title: String(localized: "Sin habitaciones"),
                               message: String(localized: "Las habitaciones agrupan tus dispositivos."))
            }
            ForEach(model.store.rooms) { room in
                let devices = model.store.devices(in: room)
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    HStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: room.symbol).foregroundStyle(Theme.Palette.accent)
                        Text(room.name).auraText(Typography.headline)
                        Text("\(devices.count)").auraText(Typography.label, Theme.Palette.textTertiary)
                    }
                    if devices.isEmpty {
                        Text("Sin dispositivos").auraText(Typography.callout, Theme.Palette.textTertiary)
                    } else {
                        LazyVGrid(columns: columns, spacing: Theme.Spacing.md) {
                            ForEach(devices) { DeviceCard(device: $0) }
                        }
                    }
                }
            }
            let unassigned = model.store.devices.filter { $0.roomID == nil }
            if !unassigned.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Sin habitación").auraText(Typography.headline)
                    LazyVGrid(columns: columns, spacing: Theme.Spacing.md) {
                        ForEach(unassigned) { DeviceCard(device: $0) }
                    }
                }
            }
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
