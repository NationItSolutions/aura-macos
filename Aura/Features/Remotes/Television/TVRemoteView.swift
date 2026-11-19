import SwiftUI

/// Control remoto visual estilo Apple TV Remote.
/// Atajos: flechas = D-pad, Enter = OK, Esc = volver, +/− = volumen.
struct TVRemoteView: View {
    @Environment(AppModel.self) private var model
    let device: Device
    @State private var showNumpad = false
    @FocusState private var focused: Bool

    private var state: DeviceState { model.store.state(for: device.id) }

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            controls
            apps
        }
        .focusable()
        .focused($focused)
        .focusEffectDisabled()
        .onAppear { focused = true }
        .onKeyPress(.upArrow) { key(.up); return .handled }
        .onKeyPress(.downArrow) { key(.down); return .handled }
        .onKeyPress(.leftArrow) { key(.left); return .handled }
        .onKeyPress(.rightArrow) { key(.right); return .handled }
        .onKeyPress(.return) { key(.enter); return .handled }
        .onKeyPress(.escape) { key(.back); return .handled }
        .onKeyPress(characters: CharacterSet(charactersIn: "+=")) { _ in key(.volumeUp); return .handled }
        .onKeyPress(characters: CharacterSet(charactersIn: "-_")) { _ in key(.volumeDown); return .handled }
    }

    private var controls: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.lg) {
            VStack(spacing: Theme.Spacing.lg) {
                HStack(spacing: Theme.Spacing.md) {
                    IconButton(symbol: "power", label: String(localized: "Encender o apagar"), size: 48,
                               isActive: state.isOn, isLoading: model.bus.isBusy(device.id)) {
                        model.togglePower(device)
                    }
                    IconButton(symbol: "rectangle.on.rectangle", label: String(localized: "Fuente"), size: 48) { key(.source) }
                    IconButton(symbol: "house.fill", label: String(localized: "Inicio"), size: 48) { key(.home) }
                }
                DPad { key($0) }
                HStack(spacing: Theme.Spacing.md) {
                    IconButton(symbol: "arrow.uturn.backward", label: String(localized: "Volver"), size: 48) { key(.back) }
                    IconButton(symbol: "playpause.fill", label: String(localized: "Reproducir o pausar"), size: 48) { key(.play) }
                    IconButton(symbol: "number", label: String(localized: "Teclado numérico"), size: 48, isActive: showNumpad) {
                        withAnimation(Theme.Motion.spring) { showNumpad.toggle() }
                    }
                }
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: Theme.Spacing.md) {
                HStack(spacing: Theme.Spacing.md) {
                    RockerButton(topSymbol: "plus", bottomSymbol: "minus", label: String(localized: "Volumen"),
                                 onTop: { key(.volumeUp) }, onBottom: { key(.volumeDown) })
                    RockerButton(topSymbol: "chevron.up", bottomSymbol: "chevron.down", label: String(localized: "Canal"),
                                 onTop: { key(.channelUp) }, onBottom: { key(.channelDown) })
                }
                IconButton(symbol: state.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                           label: String(localized: "Silencio"), size: 44, isActive: state.isMuted) { key(.mute) }
                if showNumpad {
                    NumberPad { digit in if let key = TVKey.digit(digit) { self.key(key) } }
                        .transition(.opacity.combined(with: .scale(scale: 0.95)))
                }
            }
            .frame(width: 210)
        }
    }

    private var apps: some View {
        Card {
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Apps").auraText(Typography.label, Theme.Palette.textSecondary)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: Theme.Spacing.xs)], spacing: Theme.Spacing.xs) {
                    ForEach(device.tvApps) { app in
                        TileButton(symbol: app.symbol, title: app.name, tint: Theme.Palette.accent) {
                            model.send(.launchApp(app), toDeviceID: device.id)
                        }
                    }
                }
            }
        }
    }

    private func key(_ key: TVKey) {
        model.send(.tvKey(key), toDeviceID: device.id)
    }
}

/// D-pad circular con botón OK al centro.
struct DPad: View {
    let onKey: (TVKey) -> Void
    var size: CGFloat = 200

    var body: some View {
        ZStack {
            Circle()
                .fill(Theme.Palette.surface)
                .overlay(Circle().strokeBorder(Theme.Palette.border))
            ForEach([(TVKey.up, "chevron.up", 0.0), (.right, "chevron.right", 90.0),
                     (.down, "chevron.down", 180.0), (.left, "chevron.left", 270.0)], id: \.0) { item in
                Button { onKey(item.0) } label: {
                    Image(systemName: item.1)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Theme.Palette.textSecondary)
                        .frame(width: 56, height: 56)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressScaleStyle())
                .offset(x: sin(item.2 * .pi / 180) * size * 0.36, y: -cos(item.2 * .pi / 180) * size * 0.36)
                .accessibilityLabel(item.0.displayName)
            }
            Button { onKey(.enter) } label: {
                Text("OK")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: size * 0.38, height: size * 0.38)
                    .background(Circle().fill(Theme.brandGradient))
                    .shadow(color: Theme.Palette.primaryGlow, radius: 14)
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel(Text("OK"))
        }
        .frame(width: size, height: size)
    }
}

struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(Theme.Motion.quick, value: configuration.isPressed)
    }
}

/// Botón basculante vertical (volumen / canal).
struct RockerButton: View {
    let topSymbol: String
    let bottomSymbol: String
    let label: String
    let onTop: () -> Void
    let onBottom: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onTop) {
                Image(systemName: topSymbol).frame(width: 64, height: 60).contentShape(Rectangle())
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel(Text("\(label) +"))
            Text(label).font(Typography.caption).foregroundStyle(Theme.Palette.textTertiary)
            Button(action: onBottom) {
                Image(systemName: bottomSymbol).frame(width: 64, height: 60).contentShape(Rectangle())
            }
            .buttonStyle(PressScaleStyle())
            .accessibilityLabel(Text("\(label) −"))
        }
        .font(.system(size: 18, weight: .bold))
        .foregroundStyle(Theme.Palette.textPrimary)
        .background(Capsule().fill(Theme.Palette.surface))
        .overlay(Capsule().strokeBorder(Theme.Palette.border))
    }
}

struct NumberPad: View {
    let onDigit: (Int) -> Void

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(52), spacing: 8), count: 3), spacing: 8) {
            ForEach([1, 2, 3, 4, 5, 6, 7, 8, 9, -1, 0, -2], id: \.self) { digit in
                if digit >= 0 {
                    Button { onDigit(digit) } label: {
                        Text("\(digit)")
                            .font(.system(size: 17, weight: .medium, design: .rounded))
                            .frame(width: 52, height: 40)
                    }
                    .buttonStyle(TileButtonStyle(isActive: false, tint: Theme.Palette.textPrimary))
                    .foregroundStyle(Theme.Palette.textPrimary)
                } else {
                    Color.clear.frame(width: 52, height: 40)
                }
            }
        }
    }
}
