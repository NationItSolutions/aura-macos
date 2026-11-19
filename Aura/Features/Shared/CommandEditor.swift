import SwiftUI

/// Tipos de comando que se pueden elegir en escenas y automatizaciones.
enum CommandChoice: String, CaseIterable, Identifiable {
    case powerOn, powerOff, ac, tvKey, tvApp, color, brightnessUp, brightnessDown, button

    var id: String { rawValue }

    var title: String {
        switch self {
        case .powerOn: String(localized: "Encender")
        case .powerOff: String(localized: "Apagar")
        case .ac: String(localized: "Ajustar aire")
        case .tvKey: String(localized: "Tecla de TV")
        case .tvApp: String(localized: "Abrir app")
        case .color: String(localized: "Color")
        case .brightnessUp: String(localized: "Brillo +")
        case .brightnessDown: String(localized: "Brillo −")
        case .button: String(localized: "Botón")
        }
    }

    static func available(for device: Device) -> [CommandChoice] {
        var result: [CommandChoice] = []
        if device.capabilities.contains(.power) || hasPowerAction(device) { result += [.powerOn, .powerOff] }
        switch device.kind {
        case .airConditioner: result.append(.ac)
        case .television: result += [.tvKey, .tvApp]
        case .light:
            if !device.recordedColors.isEmpty { result.append(.color) }
            result += [.brightnessUp, .brightnessDown]
        case .fan, .generic: break
        }
        if !device.buttons.isEmpty { result.append(.button) }
        return result
    }

    private static func hasPowerAction(_ device: Device) -> Bool {
        if case .webhook(let actions) = device.transport { return actions.contains { $0.role != .button } }
        return device.codes["power_on"] != nil || device.codes["power_off"] != nil
    }

    init(_ command: Command) {
        switch command {
        case .power(let on): self = on ? .powerOn : .powerOff
        case .setAC: self = .ac
        case .tvKey: self = .tvKey
        case .launchApp: self = .tvApp
        case .color: self = .color
        case .brightness(let step): self = step == .up ? .brightnessUp : .brightnessDown
        case .button: self = .button
        }
    }

    /// Comando por defecto al cambiar de tipo.
    func defaultCommand(for device: Device) -> Command {
        switch self {
        case .powerOn: .power(true)
        case .powerOff: .power(false)
        case .ac: .setAC(ACSettings(temperature: min(max(23, device.temperatureRange.lowerBound), device.temperatureRange.upperBound)))
        case .tvKey: .tvKey(.volumeUp)
        case .tvApp: device.tvApps.first.map { .launchApp($0) } ?? .tvKey(.home)
        case .color: .color(device.recordedColors.first ?? "white")
        case .brightnessUp: .brightness(.up)
        case .brightnessDown: .brightness(.down)
        case .button: .button(device.buttons.first?.codeName ?? "")
        }
    }
}

/// Selector de dispositivo + comando, compacto para listas.
struct CommandEditor: View {
    @Environment(AppModel.self) private var model
    @Binding var deviceID: UUID
    @Binding var command: Command

    private var device: Device? { model.store.device(deviceID) }

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Picker("Dispositivo", selection: $deviceID) {
                ForEach(model.store.devices) { Label($0.name, systemImage: $0.symbol).tag($0.id) }
            }
            .labelsHidden()
            .frame(width: 170)
            .onChange(of: deviceID) { _, _ in
                guard let device else { return }
                let choices = CommandChoice.available(for: device)
                if !choices.contains(CommandChoice(command)), let first = choices.first {
                    command = first.defaultCommand(for: device)
                }
            }
            if let device {
                Picker("Acción", selection: choiceBinding(device)) {
                    ForEach(CommandChoice.available(for: device)) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .frame(width: 130)
                detail(device)
            }
        }
    }

    private func choiceBinding(_ device: Device) -> Binding<CommandChoice> {
        Binding { CommandChoice(command) } set: { command = $0.defaultCommand(for: device) }
    }

    @ViewBuilder
    private func detail(_ device: Device) -> some View {
        switch command {
        case .setAC(let settings):
            Picker("Modo", selection: Binding { settings.mode } set: { var s = settings; s.mode = $0; command = .setAC(s) }) {
                ForEach(ACMode.allCases) { Text($0.displayName).tag($0) }
            }
            .labelsHidden().frame(width: 110)
            if settings.mode.usesTemperature {
                Stepper("\(settings.temperature) °C",
                        value: Binding { settings.temperature } set: { var s = settings; s.temperature = $0; command = .setAC(s) },
                        in: device.temperatureRange)
                    .fixedSize()
            }
        case .tvKey(let key):
            Picker("Tecla", selection: Binding { key } set: { command = .tvKey($0) }) {
                ForEach(TVKey.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            .labelsHidden().frame(width: 140)
        case .launchApp(let app):
            Picker("App", selection: Binding { app } set: { command = .launchApp($0) }) {
                ForEach(device.tvApps) { Text($0.name).tag($0) }
            }
            .labelsHidden().frame(width: 130)
        case .color(let color):
            Picker("Color", selection: Binding { color } set: { command = .color($0) }) {
                ForEach(device.recordedColors, id: \.self) { Text(LEDPalette.displayName(for: $0)).tag($0) }
            }
            .labelsHidden().frame(width: 130)
        case .button(let name):
            Picker("Botón", selection: Binding { name } set: { command = .button($0) }) {
                ForEach(device.buttons) { Text($0.name).tag($0.codeName) }
            }
            .labelsHidden().frame(width: 140)
        default:
            EmptyView()
        }
    }
}
