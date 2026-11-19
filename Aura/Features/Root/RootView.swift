import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case home, rooms, devices, scenes, automations, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: String(localized: "Inicio")
        case .rooms: String(localized: "Habitaciones")
        case .devices: String(localized: "Dispositivos")
        case .scenes: String(localized: "Escenas")
        case .automations: String(localized: "Automatizaciones")
        case .settings: String(localized: "Ajustes")
        }
    }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .rooms: "square.split.bottomrightquarter.fill"
        case .devices: "square.grid.2x2.fill"
        case .scenes: "sparkles"
        case .automations: "clock.arrow.2.circlepath"
        case .settings: "gearshape.fill"
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var selection: SidebarItem? = .home

    var body: some View {
        NavigationSplitView {
            Sidebar(selection: $selection)
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 260)
        } detail: {
            ZStack(alignment: .bottom) {
                Theme.Palette.background.ignoresSafeArea()
                content
                FeedbackToast()
                    .padding(.bottom, Theme.Spacing.lg)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(item: Bindable(model).presentedDevice) { ref in
            DeviceDetailSheet(deviceID: ref.id)
                .environment(model)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch selection ?? .home {
        case .home: DashboardView()
        case .rooms: RoomsView()
        case .devices: DevicesView()
        case .scenes: ScenesView()
        case .automations: AutomationsView()
        case .settings: SettingsView()
        }
    }
}

struct Sidebar: View {
    @Environment(AppModel.self) private var model
    @Binding var selection: SidebarItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: Theme.Spacing.sm) {
                AuraLogo(size: 30)
                Text("Aura").font(.system(size: 20, weight: .semibold)).foregroundStyle(Theme.Palette.textPrimary)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.xl)
            .padding(.bottom, Theme.Spacing.md)

            List(selection: $selection) {
                ForEach(SidebarItem.allCases) { item in
                    Label(item.title, systemImage: item.symbol)
                        .font(.system(size: 14, weight: .medium))
                        .padding(.vertical, 4)
                        .tag(item)
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)

            Spacer(minLength: 0)

            if model.settings.demoMode {
                Button {
                    selection = .settings
                } label: {
                    HStack(spacing: Theme.Spacing.xs) {
                        Image(systemName: "sparkles.tv.fill")
                        Text("Modo demo activo")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .bold))
                    }
                    .font(Typography.label)
                    .foregroundStyle(Theme.Palette.accent)
                    .padding(.horizontal, Theme.Spacing.sm)
                    .padding(.vertical, Theme.Spacing.xs)
                    .background(Capsule().fill(Theme.Palette.accent.opacity(0.12)))
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(String(localized: "Los dispositivos son simulados. Abrí Ajustes para importar tus códigos o desactivar el modo demo."))
                .accessibilityHint(Text("Abre Ajustes"))
                .padding(Theme.Spacing.md)
            }
        }
        .background(.ultraThinMaterial)
        .background(Theme.Palette.background.opacity(0.6))
    }
}

/// Logo provisorio: onda/señal sobre casa, con el gradiente de marca.
struct AuraLogo: View {
    var size: CGFloat = 28

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(Theme.brandGradient)
            Image(systemName: "dot.radiowaves.up.forward")
                .font(.system(size: size * 0.5, weight: .bold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: Theme.Palette.primaryGlow, radius: 8)
        .accessibilityHidden(true)
    }
}
