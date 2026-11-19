import SwiftUI

struct ScenesView: View {
    @Environment(AppModel.self) private var model
    private let columns = [GridItem(.adaptive(minimum: 300, maximum: 420), spacing: Theme.Spacing.md)]

    var body: some View {
        PageScroll(title: String(localized: "Escenas"),
                   subtitle: String(localized: "Una escena ejecuta varios comandos en orden, con demoras entre pasos.")) {
            if model.store.scenes.isEmpty {
                EmptyStateView(symbol: "sparkles", title: String(localized: "Sin escenas"),
                               message: String(localized: "Todavía no creaste ninguna escena."))
            } else {
                LazyVGrid(columns: columns, spacing: Theme.Spacing.md) {
                    ForEach(model.store.scenes) { SceneCard(scene: $0) }
                }
            }
        }
    }
}

struct SceneCard: View {
    @Environment(AppModel.self) private var model
    let scene: HomeScene

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
