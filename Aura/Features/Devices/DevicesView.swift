import SwiftUI

struct DevicesView: View {
    @Environment(AppModel.self) private var model
    @State private var filter: DeviceKind?
    private let columns = [GridItem(.adaptive(minimum: 250, maximum: 360), spacing: Theme.Spacing.md)]

    private var kinds: [DeviceKind] {
        DeviceKind.allCases.filter { kind in model.store.devices.contains { $0.kind == kind } }
    }

    private var filtered: [Device] {
        guard let filter else { return model.store.devices }
        return model.store.devices.filter { $0.kind == filter }
    }

    var body: some View {
        PageScroll(title: String(localized: "Dispositivos"),
                   subtitle: String(localized: "\(model.store.devices.count) dispositivos")) {
            HStack(spacing: Theme.Spacing.xs) {
                Chip(title: String(localized: "Todos"), isSelected: filter == nil) { filter = nil }
                ForEach(kinds) { kind in
                    Chip(title: kind.displayName, symbol: kind.defaultSymbol, isSelected: filter == kind) { filter = kind }
                }
            }
            if filtered.isEmpty {
                EmptyStateView(symbol: "square.grid.2x2", title: String(localized: "Sin dispositivos"),
                               message: String(localized: "Importá tus códigos desde Ajustes."))
            } else {
                LazyVGrid(columns: columns, spacing: Theme.Spacing.md) {
                    ForEach(filtered) { DeviceCard(device: $0) }
                }
            }
        }
    }
}
