import SwiftUI

struct DashboardView: View {
    @Environment(AppModel.self) private var model

    private let columns = [GridItem(.adaptive(minimum: 250, maximum: 360), spacing: Theme.Spacing.md)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                header
                scenes
                devices
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.top, Theme.Spacing.xl)
            .padding(.bottom, 96)
            .frame(maxWidth: 1280, alignment: .leading)
        }
        .scrollIndicators(.never)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(model.greeting).auraText(Typography.display)
                Text(model.summaryLine).auraText(Typography.body, Theme.Palette.textSecondary)
                    .contentTransition(.opacity)
                    .animation(Theme.Motion.spring, value: model.summaryLine)
            }
            Spacer()
            ConnectionIndicators()
        }
    }

    @ViewBuilder
    private var scenes: some View {
        let favorites = model.store.scenes.filter(\.isFavorite)
        if !favorites.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                SectionHeader(title: String(localized: "Escenas"))
                ScrollView(.horizontal) {
                    HStack(spacing: Theme.Spacing.sm) {
                        ForEach(favorites) { scene in
                            Chip(title: scene.name, symbol: scene.symbol,
                                 isSelected: model.runningScene == scene.id,
                                 isLoading: model.runningScene == scene.id,
                                 large: true) {
                                model.run(scene)
                            }
                            .disabled(model.runningScene != nil && model.runningScene != scene.id)
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 2)
                }
                .scrollIndicators(.never)
            }
        }
    }

    @ViewBuilder
    private var devices: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader(title: String(localized: "Dispositivos"),
                          subtitle: String(localized: "Click en una tarjeta para abrir el control completo"))
            if model.store.devices.isEmpty {
                EmptyStateView(
                    symbol: "dot.radiowaves.left.and.right",
                    title: String(localized: "Todavía no hay dispositivos"),
                    message: String(localized: "Importá tu codigos.json desde Ajustes o activá el modo demo para explorar la app.")
                )
            } else {
                LazyVGrid(columns: columns, spacing: Theme.Spacing.md) {
                    ForEach(model.store.devices) { device in
                        DeviceCard(device: device)
                    }
                }
            }
        }
    }
}

/// Estado de conexión de los puentes y la TV.
struct ConnectionIndicators: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            if model.settings.demoMode {
                StatusPill(title: String(localized: "Demo"), status: .demo)
            }
            ForEach(model.store.bridges) { bridge in
                StatusPill(title: bridge.name, status: model.settings.demoMode ? .online : .offline)
            }
            ForEach(model.store.devices.filter { $0.transport.kind == .samsungTizen }) { tv in
                StatusPill(title: tv.name, status: model.settings.demoMode ? .online : .offline)
            }
        }
    }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        Card {
            VStack(spacing: Theme.Spacing.sm) {
                Image(systemName: symbol)
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(Theme.brandGradient)
                Text(title).auraText(Typography.headline)
                Text(message).auraText(Typography.callout, Theme.Palette.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.xl)
        }
    }
}
