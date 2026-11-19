import SwiftUI

/// Tarjeta de dispositivo con control rápido (power + valor principal).
struct DeviceCard: View {
    @Environment(AppModel.self) private var model
    let device: Device

    private var state: DeviceState { model.store.state(for: device.id) }
    private var busy: Bool { model.bus.isBusy(device.id) }

    var body: some View {
        Card(isActive: state.isOn) {
            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                HStack(alignment: .top) {
                    DeviceIcon(device: device, isOn: state.isOn)
                    Spacer()
                    if device.capabilities.contains(.power) || device.kind == .television {
                        IconButton(symbol: "power", label: String(localized: "Encender o apagar \(device.name)"),
                                   size: 34, isActive: state.isOn, isLoading: busy) {
                            model.togglePower(device)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name).auraText(Typography.headline).lineLimit(1)
                    Text(subtitle).auraText(Typography.callout, Theme.Palette.textSecondary).lineLimit(1)
                }
                quickControl
                    .frame(height: 34)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        .onTapGesture { model.open(device) }
        .hoverLift()
        .animation(Theme.Motion.spring, value: state.isOn)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(device.name)
        .accessibilityHint(Text("Abre el control completo"))
        .accessibilityAction(named: Text("Abrir")) { model.open(device) }
    }

    private var subtitle: String {
        let room = model.store.room(device.roomID)?.name ?? device.kind.displayName
        let status = state.isOn ? String(localized: "Encendido") : String(localized: "Apagado")
        return "\(room) · \(status)"
    }

    @ViewBuilder
    private var quickControl: some View {
        switch device.kind {
        case .airConditioner:
            ACQuickControl(device: device, state: state)
        case .light:
            LightQuickControl(device: device, state: state)
        case .television:
            HStack(spacing: Theme.Spacing.xs) {
                IconButton(symbol: "speaker.minus.fill", label: String(localized: "Bajar volumen"), size: 34) {
                    model.send(.tvKey(.volumeDown), toDeviceID: device.id)
                }
                IconButton(symbol: "speaker.plus.fill", label: String(localized: "Subir volumen"), size: 34) {
                    model.send(.tvKey(.volumeUp), toDeviceID: device.id)
                }
                IconButton(symbol: state.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                           label: String(localized: "Silencio"), size: 34, isActive: state.isMuted) {
                    model.send(.tvKey(.mute), toDeviceID: device.id)
                }
                Spacer()
            }
        case .fan, .generic:
            HStack(spacing: Theme.Spacing.xs) {
                ForEach(device.buttons.prefix(3)) { button in
                    IconButton(symbol: button.symbol, label: button.name, size: 34) {
                        model.send(.button(button.codeName), toDeviceID: device.id)
                    }
                }
                Spacer()
            }
        }
    }
}

struct DeviceIcon: View {
    let device: Device
    var isOn: Bool
    var size: CGFloat = 44

    private var tint: Color {
        guard isOn else { return Theme.Palette.textTertiary }
        return switch device.kind {
        case .light: Theme.Palette.accent
        case .airConditioner: Theme.Palette.primary
        default: Theme.Palette.primaryHover
        }
    }

    var body: some View {
        Image(systemName: device.symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(isOn ? Color.white : Theme.Palette.textSecondary)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .fill(isOn ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(Theme.Palette.surfaceElevated))
            )
            .shadow(color: isOn ? tint.opacity(0.45) : .clear, radius: 10)
            .accessibilityHidden(true)
    }
}

/// Aire en la tarjeta: − temperatura +.
struct ACQuickControl: View {
    @Environment(AppModel.self) private var model
    let device: Device
    let state: DeviceState

    private var settings: ACSettings { state.ac ?? ACSettings() }

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            IconButton(symbol: "minus", label: String(localized: "Bajar temperatura"), size: 34) { change(-1) }
                .disabled(next(-1) == nil)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("\(settings.temperature)").font(Typography.value(26))
                    .contentTransition(.numericText(value: Double(settings.temperature)))
                Text("°C").font(Typography.label).foregroundStyle(Theme.Palette.textSecondary)
            }
            .foregroundStyle(state.isOn ? Theme.Palette.textPrimary : Theme.Palette.textTertiary)
            .frame(minWidth: 56)
            IconButton(symbol: "plus", label: String(localized: "Subir temperatura"), size: 34) { change(+1) }
                .disabled(next(+1) == nil)
            Spacer()
            Image(systemName: settings.mode.symbol)
                .foregroundStyle(settings.mode == .heat ? Theme.Palette.warning : Theme.Palette.accent)
                .help(settings.mode.displayName)
        }
        .animation(Theme.Motion.quick, value: settings.temperature)
    }

    /// Próxima temperatura grabada en esa dirección.
    private func next(_ delta: Int) -> Int? {
        var candidate = settings.temperature + delta
        while device.temperatureRange.contains(candidate) {
            var probe = settings
            probe.temperature = candidate
            if device.hasCode(for: probe) { return candidate }
            candidate += delta
        }
        return nil
    }

    private func change(_ delta: Int) {
        guard let temperature = next(delta) else { return }
        var new = settings
        new.temperature = temperature
        model.send(.setAC(new), toDeviceID: device.id)
    }
}

/// LED en la tarjeta: hasta 6 colores grabados.
struct LightQuickControl: View {
    @Environment(AppModel.self) private var model
    let device: Device
    let state: DeviceState

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(device.recordedColors.prefix(6), id: \.self) { color in
                ColorSwatch(name: color, isSelected: state.ledColor == color && state.isOn, size: 26) {
                    model.send(.color(color), toDeviceID: device.id)
                }
            }
            Spacer()
        }
    }
}

struct ColorSwatch: View {
    let name: String
    var isSelected: Bool
    var size: CGFloat = 30
    let action: () -> Void

    private var color: Color {
        LEDPalette.hex(for: name).map { Color(rgb: $0) } ?? Theme.Palette.textSecondary
    }

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: size, height: size)
                .overlay(Circle().strokeBorder(Color.white.opacity(isSelected ? 0.95 : 0.12), lineWidth: isSelected ? 2.5 : 1))
                .shadow(color: color.opacity(isSelected ? 0.8 : 0.3), radius: isSelected ? 10 : 4)
                .scaleEffect(isSelected ? 1.08 : 1)
        }
        .buttonStyle(.plain)
        .animation(Theme.Motion.quick, value: isSelected)
        .accessibilityLabel(LEDPalette.displayName(for: name))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .help(LEDPalette.displayName(for: name))
    }
}
