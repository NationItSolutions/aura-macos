import SwiftUI

/// Control completo del aire: dial, modo, ventilador y swing.
struct ACControlView: View {
    @Environment(AppModel.self) private var model
    let device: Device
    @State private var draft = ACSettings()

    private var state: DeviceState { model.store.state(for: device.id) }
    private var current: ACSettings { state.ac ?? ACSettings() }

    private var available: Set<Int> {
        Set(device.temperatureRange.filter { temp in
            var probe = draft
            probe.temperature = temp
            return device.hasCode(for: probe)
        })
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            HStack(alignment: .center, spacing: Theme.Spacing.xl) {
                Dial(
                    value: $draft.temperature,
                    range: device.temperatureRange,
                    available: draft.mode.usesTemperature ? available : [],
                    style: draft.mode == .heat ? .heat : (draft.mode == .cool ? .cool : .neutral),
                    isOn: state.isOn,
                    caption: state.isOn ? draft.mode.displayName : String(localized: "Apagado"),
                    diameter: 260
                ) { _ in apply() }
                .disabled(!draft.mode.usesTemperature)

                VStack(spacing: Theme.Spacing.md) {
                    IconButton(symbol: "power", label: String(localized: "Encender o apagar"), size: 64,
                               isActive: state.isOn, isLoading: model.bus.isBusy(device.id)) {
                        model.togglePower(device)
                    }
                    Text(state.isOn ? "Encendido" : "Apagado")
                        .auraText(Typography.label, Theme.Palette.textSecondary)
                }
            }

            Card {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Modo").auraText(Typography.label, Theme.Palette.textSecondary)
                    HStack(spacing: Theme.Spacing.xs) {
                        ForEach(ACMode.allCases) { mode in
                            TileButton(symbol: mode.symbol, title: mode.displayName,
                                       tint: mode == .heat ? Theme.Palette.warning : Theme.Palette.accent,
                                       isActive: draft.mode == mode) {
                                select(mode: mode)
                            }
                            .disabled(!hasAnyCode(for: mode))
                            .opacity(hasAnyCode(for: mode) ? 1 : 0.4)
                        }
                    }
                }
            }

            HStack(spacing: Theme.Spacing.md) {
                Card {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("Ventilador").auraText(Typography.label, Theme.Palette.textSecondary)
                        HStack(spacing: Theme.Spacing.xs) {
                            ForEach(FanSpeed.allCases) { fan in
                                Chip(title: fan.displayName, isSelected: draft.fan == fan) {
                                    draft.fan = fan
                                    apply()
                                }
                            }
                        }
                    }
                }
                Card {
                    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                        Text("Swing").auraText(Typography.label, Theme.Palette.textSecondary)
                        Chip(title: draft.swing ? String(localized: "Activado") : String(localized: "Desactivado"),
                             symbol: "arrow.up.and.down", isSelected: draft.swing) {
                            toggleSwing()
                        }
                        .disabled(device.codes["swing"] == nil)
                        .help(device.codes["swing"] == nil ? Text("Grabá el botón Swing desde «Grabar códigos».") : Text("Alternar oscilación"))
                    }
                }
                .frame(maxWidth: 180)
            }

            SleepTimerCard(device: device)

            if let missing = missingMessage {
                Label(missing, systemImage: "exclamationmark.circle")
                    .auraText(Typography.label, Theme.Palette.warning)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear { draft = current }
        .onChange(of: current) { _, newValue in draft = newValue }
    }

    private var missingMessage: String? {
        guard !device.hasCode(for: draft) else { return nil }
        return String(localized: "La combinación \"\(draft.codeName)\" no está grabada. Grabala desde el asistente de aprendizaje.")
    }

    private func hasAnyCode(for mode: ACMode) -> Bool {
        if !mode.usesTemperature { return device.codes.keys.contains { $0 == mode.rawValue || $0.hasPrefix("\(mode.rawValue)_") } }
        return !device.recordedTemperatures(for: mode).isEmpty
    }

    private func select(mode: ACMode) {
        draft.mode = mode
        if mode.usesTemperature {
            let temps = device.recordedTemperatures(for: mode)
            if !temps.contains(draft.temperature), let closest = temps.min(by: { abs($0 - draft.temperature) < abs($1 - draft.temperature) }) {
                draft.temperature = closest
            }
        }
        apply()
    }

    private func toggleSwing() {
        guard device.codes["swing"] != nil else { return }
        draft.swing.toggle()
        model.send(.button("swing"), toDeviceID: device.id)
    }

    private func apply() {
        let settings = draft
        guard device.hasCode(for: settings) else { return }
        model.send(.setAC(settings), toDeviceID: device.id)
    }
}

/// Temporizador de apagado: 30 / 60 / 90 / 120 min, con cuenta regresiva y cancelar.
struct SleepTimerCard: View {
    @Environment(AppModel.self) private var model
    let device: Device

    var body: some View {
        Card {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "timer").foregroundStyle(Theme.Palette.accent)
                if let timer = model.store.timers(for: device.id).first {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text("Se apaga en \(Self.remaining(until: timer.fireDate, now: context.date))")
                            .auraText(Typography.body)
                            .monospacedDigit()
                    }
                    Spacer()
                    Button("Cancelar") { model.store.removeTimer(timer.id) }.buttonStyle(SecondaryButtonStyle())
                } else {
                    Text("Apagar en").auraText(Typography.label, Theme.Palette.textSecondary)
                    ForEach([30, 60, 90, 120], id: \.self) { minutes in
                        Chip(title: "\(minutes) min", isSelected: false) { model.scheduleOff(device, inMinutes: minutes) }
                    }
                    Spacer()
                }
            }
        }
    }

    static func remaining(until date: Date, now: Date) -> String {
        let seconds = max(0, Int(date.timeIntervalSince(now)))
        return String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
    }
}
