import Foundation

/// Datos de demostración: una casa con aire, TV, LED y un ventilador genérico.
/// Los códigos son paquetes ficticios (solo sirven con los drivers mock).
enum DemoData {
    static func snapshot() -> StoreSnapshot {
        let bridge = Bridge(name: "Broadlink RM4 Mini", host: "192.0.2.10", macAddress: "00:00:5E:00:53:01", deviceType: 0x6539)
        let living = Room(name: String(localized: "Living"), symbol: "sofa.fill", sortOrder: 0)
        let bedroom = Room(name: String(localized: "Dormitorio"), symbol: "bed.double.fill", sortOrder: 1)
        let office = Room(name: String(localized: "Oficina"), symbol: "desktopcomputer", sortOrder: 2)

        var acCodes: [String: String] = ["on": fakeCode, "off": fakeCode]
        for temp in 17...28 { acCodes["cool_\(temp)"] = fakeCode }
        for temp in 20...26 { acCodes["heat_\(temp)"] = fakeCode }
        acCodes["fan"] = fakeCode
        acCodes["dry_24"] = fakeCode
        for temp in [22, 23, 24] { acCodes["cool_\(temp)_high"] = fakeCode }

        let ac = Device(name: String(localized: "Aire Carrier"), roomID: bedroom.id, kind: .airConditioner,
                        transport: .broadlink(bridgeID: bridge.id), codes: acCodes, isFavorite: true, sortOrder: 0)

        let tv = Device(name: String(localized: "TV Samsung"), roomID: living.id, kind: .television,
                        transport: .samsungTizen(host: "192.0.2.20", macAddress: "00:00:5E:00:53:02", fallbackBridgeID: bridge.id),
                        isFavorite: true, sortOrder: 1)

        var ledCodes: [String: String] = [
            "power_on": fakeCode, "power_off": fakeCode,
            "brightness_up": fakeCode, "brightness_down": fakeCode,
        ]
        for color in ["white", "red", "orange", "yellow", "green", "cyan", "blue", "purple", "pink"] {
            ledCodes[color] = fakeCode
        }
        for effect in ["flash", "fade", "strobe", "smooth"] { ledCodes["effect_\(effect)"] = fakeCode }
        let led = Device(
            name: String(localized: "LED del living"), roomID: living.id, kind: .light,
            transport: .broadlink(bridgeID: bridge.id), codes: ledCodes,
            buttons: [
                CustomButton(name: "Flash", symbol: "bolt.fill", codeName: "effect_flash", tint: .amber),
                CustomButton(name: "Fade", symbol: "circle.lefthalf.filled", codeName: "effect_fade", tint: .cyan),
                CustomButton(name: "Strobe", symbol: "light.beacon.max.fill", codeName: "effect_strobe", tint: .red),
                CustomButton(name: "Smooth", symbol: "water.waves", codeName: "effect_smooth", tint: .blue),
            ],
            isFavorite: true, sortOrder: 2
        )

        let fan = Device(
            name: String(localized: "Ventilador"), roomID: office.id, kind: .fan,
            transport: .broadlink(bridgeID: bridge.id),
            codes: ["power_on": fakeCode, "power_off": fakeCode, "speed": fakeCode, "oscillate": fakeCode, "timer": fakeCode],
            buttons: [
                CustomButton(name: String(localized: "Velocidad"), symbol: "gauge.with.dots.needle.67percent", codeName: "speed", tint: .blue),
                CustomButton(name: String(localized: "Oscilar"), symbol: "arrow.left.and.right", codeName: "oscillate", tint: .cyan),
                CustomButton(name: String(localized: "Timer"), symbol: "timer", codeName: "timer", tint: .neutral),
            ],
            sortOrder: 3
        )

        let cinema = HomeScene(name: String(localized: "Modo cine"), symbol: "film.fill", steps: [
            SceneStep(deviceID: tv.id, command: .power(true), delayAfter: 3),
            SceneStep(deviceID: led.id, command: .color("blue"), delayAfter: 0.3),
            SceneStep(deviceID: led.id, command: .brightness(.down), delayAfter: 0.3),
            SceneStep(deviceID: led.id, command: .brightness(.down), delayAfter: 0.3),
            SceneStep(deviceID: led.id, command: .brightness(.down), delayAfter: 0.3),
            SceneStep(deviceID: ac.id, command: .setAC(ACSettings(mode: .cool, temperature: 22))),
        ])
        let sleep = HomeScene(name: String(localized: "Dormir"), symbol: "moon.zzz.fill", steps: [
            SceneStep(deviceID: tv.id, command: .power(false)),
            SceneStep(deviceID: led.id, command: .power(false)),
            SceneStep(deviceID: ac.id, command: .setAC(ACSettings(mode: .cool, temperature: 24, fan: .auto))),
        ])
        let arrived = HomeScene(name: String(localized: "Llegué"), symbol: "house.fill", steps: [
            SceneStep(deviceID: led.id, command: .power(true), delayAfter: 0.3),
            SceneStep(deviceID: led.id, command: .color("white")),
            SceneStep(deviceID: ac.id, command: .setAC(ACSettings(mode: .cool, temperature: 23))),
        ])
        let leaving = HomeScene(name: String(localized: "Me voy"), symbol: "figure.walk.departure", steps: [
            SceneStep(deviceID: ac.id, command: .power(false)),
            SceneStep(deviceID: tv.id, command: .power(false)),
            SceneStep(deviceID: led.id, command: .power(false)),
            SceneStep(deviceID: fan.id, command: .power(false)),
        ])

        var states: [UUID: DeviceState] = [:]
        states[ac.id] = DeviceState(isOn: true, ac: ACSettings(mode: .cool, temperature: 23), lastUpdated: .now)
        states[led.id] = DeviceState(isOn: true, ledColor: "blue", brightnessLevel: 3, lastUpdated: .now)
        states[tv.id] = DeviceState(isOn: false)
        states[fan.id] = DeviceState(isOn: false)

        return StoreSnapshot(
            bridges: [bridge],
            rooms: [living, bedroom, office],
            devices: [ac, tv, led, fan],
            scenes: [cinema, sleep, arrived, leaving],
            states: states
        )
    }

    /// Paquete ficticio con forma de código Broadlink (no se envía a hardware real).
    private static let fakeCode = "JgBQAAABKZIUERQRFDYUERQRFBEUERQRFDYUNhQRFDYUNhQ2FDYUNhQRFBEUERQ2FBEUERQRFBEUNhQ2FDYUERQ2FDYUNhQ2FAAFGQABKUkUAA0FAAAAAAAAAAA="
}
