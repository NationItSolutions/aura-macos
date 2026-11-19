import SwiftUI

/// Contenido de la isla: compacta junto al notch, expandida con controles, o actividad tras un comando.
struct IslandView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let island: IslandModel

    private var size: CGSize { island.geometry.size(for: island.phase) }

    private var shape: UnevenRoundedRectangle {
        let bottom: CGFloat
        switch island.phase {
        case .expanded: bottom = Theme.Radius.island
        case .activity: bottom = 20
        case .compact: bottom = island.geometry.hasNotch ? 12 : 16
        }
        // Con notch la isla "sale" del borde: arriba sin redondeo. Sin notch es una píldora.
        let top: CGFloat = island.geometry.hasNotch ? 0 : bottom
        return UnevenRoundedRectangle(topLeadingRadius: top, bottomLeadingRadius: bottom,
                                      bottomTrailingRadius: bottom, topTrailingRadius: top, style: .continuous)
    }

    private var animation: Animation {
        reduceMotion ? .easeInOut(duration: 0.12) : .spring(response: 0.38, dampingFraction: 0.78)
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                shape.fill(Theme.Palette.islandBackground)
                content
                    .padding(.top, island.geometry.topInset)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }
            .frame(width: size.width, height: size.height)
            .clipShape(shape)
            .overlay(errorGlow)
            .shadow(color: .black.opacity(island.phase == .expanded ? 0.55 : 0), radius: 24, y: 10)
            .animation(animation, value: island.phase)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var errorGlow: some View {
        if case .activity(let feedback) = island.phase, feedback.isError {
            shape.strokeBorder(Theme.Palette.danger.opacity(0.8), lineWidth: 1.5)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch island.phase {
        case .compact: CompactIslandContent(geometry: island.geometry)
        case .activity(let feedback): ActivityIslandContent(feedback: feedback, geometry: island.geometry)
        case .expanded: ExpandedIslandContent(island: island)
        }
    }
}

// MARK: - Compacta

private struct CompactIslandContent: View {
    @Environment(AppModel.self) private var model
    let geometry: IslandModel.Geometry

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 4) {
                AuraLogo(size: 16)
                if model.devicesOn.count > 0 {
                    Text("\(model.devicesOn.count)")
                        .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(Theme.Palette.accent)
                }
            }
            .frame(width: geometry.hasNotch ? IslandModel.Geometry.wing : nil, alignment: .center)
            if geometry.hasNotch {
                Spacer(minLength: geometry.notchWidth)
            } else {
                Text("Aura").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 6)
                Spacer(minLength: 0)
            }
            trailing
                .frame(width: geometry.hasNotch ? IslandModel.Geometry.wing : nil, alignment: .center)
        }
        .padding(.horizontal, geometry.hasNotch ? 0 : 12)
        .frame(maxHeight: .infinity)
        .padding(.top, -geometry.topInset)
    }

    @ViewBuilder
    private var trailing: some View {
        if let ac = model.store.devices.first(where: { $0.kind == .airConditioner && model.store.state(for: $0.id).isOn }),
           let settings = model.store.state(for: ac.id).ac {
            HStack(spacing: 3) {
                Image(systemName: settings.mode.symbol).font(.system(size: 10, weight: .bold))
                if settings.mode.usesTemperature { Text("\(settings.temperature)°") }
            }
            .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
            .foregroundStyle(Theme.Palette.accent)
        } else if model.runningScene != nil {
            ProgressView().controlSize(.mini).tint(.white)
        } else {
            Circle().fill(model.devicesOn.isEmpty ? Theme.Palette.textTertiary : Theme.Palette.success)
                .frame(width: 6, height: 6)
        }
    }
}

// MARK: - Actividad

private struct ActivityIslandContent: View {
    let feedback: CommandFeedback
    let geometry: IslandModel.Geometry

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: feedback.isError ? "exclamationmark.triangle.fill" : feedback.symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(feedback.isError ? Theme.Palette.danger : Theme.Palette.accent)
                .symbolEffect(.bounce, value: feedback.id)
            VStack(alignment: .leading, spacing: 0) {
                Text(feedback.title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white).lineLimit(1)
                if let message = feedback.message {
                    Text(message).font(.system(size: 11, weight: .medium))
                        .foregroundStyle(feedback.isError ? Theme.Palette.danger : Theme.Palette.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if !feedback.isError {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.Palette.success)
            }
        }
        .padding(.horizontal, 16)
        .frame(maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Expandida

private struct ExpandedIslandContent: View {
    @Environment(AppModel.self) private var model
    @Bindable var island: IslandModel

    private var selectedDevice: Device? {
        guard !island.showingScenes else { return nil }
        let devices = model.quickDevices
        return devices.first { $0.id == island.selectedDeviceID } ?? devices.first
    }

    var body: some View {
        VStack(spacing: 10) {
            tabs
            Group {
                if island.showingScenes || model.quickDevices.isEmpty {
                    scenes
                } else if let device = selectedDevice {
                    IslandDeviceControls(device: device)
                        .id(device.id)
                        .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private var tabs: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                ForEach(model.quickDevices) { device in
                    tab(title: device.name, symbol: device.symbol,
                        isOn: model.store.state(for: device.id).isOn,
                        selected: !island.showingScenes && selectedDevice?.id == device.id) {
                        island.showingScenes = false
                        island.selectedDeviceID = device.id
                    }
                }
                if !model.quickScenes.isEmpty {
                    tab(title: String(localized: "Escenas"), symbol: "sparkles", isOn: false, selected: island.showingScenes) {
                        island.showingScenes = true
                    }
                }
            }
        }
        .scrollIndicators(.never)
    }

    private func tab(title: String, symbol: String, isOn: Bool, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isOn ? Theme.Palette.accent : Color.white.opacity(0.7))
                Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Capsule().fill(selected ? Color.white.opacity(0.16) : Color.white.opacity(0.05)))
        }
        .buttonStyle(.plain)
    }

    private var scenes: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
            ForEach(model.quickScenes) { scene in
                Button { model.run(scene) } label: {
                    HStack(spacing: 6) {
                        if model.runningScene == scene.id {
                            ProgressView().controlSize(.mini).tint(.white)
                        } else {
                            Image(systemName: scene.symbol).foregroundStyle(Theme.Palette.accent)
                        }
                        Text(scene.name).lineLimit(1)
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(PressScaleStyle())
                .disabled(model.runningScene != nil)
            }
        }
    }
}

/// Controles compactos por tipo de dispositivo.
struct IslandDeviceControls: View {
    @Environment(AppModel.self) private var model
    let device: Device

    private var state: DeviceState { model.store.state(for: device.id) }

    var body: some View {
        HStack(spacing: 16) {
            IslandRoundButton(symbol: "power", active: state.isOn, loading: model.bus.isBusy(device.id), size: 54) {
                model.togglePower(device)
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(device.name).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                specific
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var specific: some View {
        switch device.kind {
        case .airConditioner:
            let settings = model.acSettings(for: device)
            HStack(spacing: 10) {
                IslandRoundButton(symbol: "minus") { model.stepTemperature(device, by: -1) }
                VStack(spacing: 0) {
                    Text(settings.mode.usesTemperature ? "\(settings.temperature)°" : settings.mode.displayName)
                        .font(.system(size: 34, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(state.isOn ? .white : Theme.Palette.textTertiary)
                        .contentTransition(.numericText())
                    Label(settings.mode.displayName, systemImage: settings.mode.symbol)
                        .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.Palette.accent)
                }
                .frame(minWidth: 90)
                IslandRoundButton(symbol: "plus") { model.stepTemperature(device, by: 1) }
            }
        case .television:
            HStack(spacing: 8) {
                IslandRoundButton(symbol: "speaker.minus.fill") { key(.volumeDown) }
                IslandRoundButton(symbol: "speaker.plus.fill") { key(.volumeUp) }
                IslandRoundButton(symbol: state.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", active: state.isMuted) { key(.mute) }
                IslandRoundButton(symbol: "chevron.up") { key(.channelUp) }
                IslandRoundButton(symbol: "chevron.down") { key(.channelDown) }
                IslandRoundButton(symbol: "playpause.fill") { key(.play) }
                ForEach(device.tvApps.prefix(2)) { app in
                    IslandRoundButton(symbol: app.symbol) { model.send(.launchApp(app), toDeviceID: device.id) }
                        .help(app.name)
                }
            }
        case .light:
            HStack(spacing: 8) {
                IslandRoundButton(symbol: "sun.min") { model.send(.brightness(.down), toDeviceID: device.id) }
                IslandRoundButton(symbol: "sun.max.fill") { model.send(.brightness(.up), toDeviceID: device.id) }
                ForEach(device.recordedColors.prefix(7), id: \.self) { color in
                    ColorSwatch(name: color, isSelected: state.isOn && state.ledColor == color, size: 26) {
                        model.send(.color(color), toDeviceID: device.id)
                    }
                }
            }
        case .fan, .generic:
            HStack(spacing: 8) {
                ForEach(device.buttons.prefix(8)) { button in
                    IslandRoundButton(symbol: button.symbol) { model.send(.button(button.codeName), toDeviceID: device.id) }
                        .help(button.name)
                }
            }
        }
    }

    private func key(_ key: TVKey) {
        model.send(.tvKey(key), toDeviceID: device.id)
    }
}

struct IslandRoundButton: View {
    let symbol: String
    var active = false
    var loading = false
    var size: CGFloat = 36
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                if loading {
                    ProgressView().controlSize(.small).tint(.white)
                } else {
                    Image(systemName: symbol).font(.system(size: size * 0.38, weight: .semibold))
                }
            }
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(active ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(Color.white.opacity(0.1))))
            .shadow(color: active ? Theme.Palette.primaryGlow : .clear, radius: 10)
        }
        .buttonStyle(PressScaleStyle())
        .disabled(loading)
    }
}
