import SwiftUI
import XCTest
@testable import Aura

final class ModelTests: XCTestCase {
    func testACCodeNames() {
        XCTAssertEqual(ACSettings(mode: .cool, temperature: 23).codeName, "cool_23")
        XCTAssertEqual(ACSettings(mode: .heat, temperature: 25, fan: .high).codeName, "heat_25_high")
        XCTAssertEqual(ACSettings(mode: .fan, temperature: 25).codeName, "fan")
        XCTAssertEqual(ACSettings(mode: .heat, temperature: 25, fan: .high).codeNameIgnoringFan, "heat_25")
    }

    func testDeviceHasCodeFallsBackIgnoringFan() {
        let device = Device(name: "Aire", kind: .airConditioner, transport: .broadlink(bridgeID: nil),
                            codes: ["cool_23": "x"])
        XCTAssertTrue(device.hasCode(for: ACSettings(mode: .cool, temperature: 23, fan: .high)))
        XCTAssertFalse(device.hasCode(for: ACSettings(mode: .cool, temperature: 24)))
        XCTAssertEqual(device.recordedTemperatures(for: .cool), [23])
    }

    func testStateApply() {
        var state = DeviceState()
        state.apply(.setAC(ACSettings(mode: .cool, temperature: 21)))
        XCTAssertTrue(state.isOn)
        XCTAssertEqual(state.ac?.temperature, 21)
        state.apply(.power(false))
        XCTAssertFalse(state.isOn)
        state.apply(.brightness(.down))
        XCTAssertEqual(state.brightnessLevel, LEDPalette.brightnessSteps - 1)
        for _ in 0..<10 { state.apply(.brightness(.down)) }
        XCTAssertEqual(state.brightnessLevel, 1)
        state.apply(.color("azul"))
        XCTAssertEqual(state.ledColor, "azul")
    }

    func testRecordedColorsOrderAndFiltering() {
        let device = Device(name: "LED", kind: .light, transport: .broadlink(bridgeID: nil), codes: [
            "power_on": "x", "brightness_up": "x", "zz_custom": "x", "blue": "x", "red": "x", "effect_flash": "x",
        ])
        XCTAssertEqual(device.recordedColors, ["red", "blue", "zz_custom"])
    }

    func testIRCodeResolver() {
        let ac = Device(name: "Aire", kind: .airConditioner, transport: .broadlink(bridgeID: nil), codes: ["cool_22": "x"])
        XCTAssertEqual(IRCodeResolver.codeName(for: .power(false), device: ac), "off")
        XCTAssertEqual(IRCodeResolver.codeName(for: .setAC(ACSettings(mode: .cool, temperature: 22, fan: .low)), device: ac), "cool_22")
        let led = Device(name: "LED", kind: .light, transport: .broadlink(bridgeID: nil))
        XCTAssertEqual(IRCodeResolver.codeName(for: .brightness(.up), device: led), "brightness_up")
    }

    func testCommandCodableRoundTrip() throws {
        let commands: [Command] = [.power(true), .setAC(ACSettings(mode: .heat, temperature: 25, fan: .high, swing: true)),
                                   .tvKey(.volumeUp), .launchApp(TVApp.defaults[0]), .brightness(.down),
                                   .color("blue"), .button("effect_flash")]
        let data = try JSONEncoder().encode(commands)
        XCTAssertEqual(try JSONDecoder().decode([Command].self, from: data), commands)
    }

    func testColorHex() {
        XCTAssertNotNil(Color(hex: "#2F7BFF"))
        XCTAssertNotNil(Color(hex: "FFFFFF14"))
        XCTAssertNil(Color(hex: "#12345"))
        XCTAssertNil(Color(hex: "#GGGGGG"))
    }
}

@MainActor
final class StoreTests: XCTestCase {
    func testSnapshotPersistsAndReloads() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("aura-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let file = StoreFile(url: url)

        let store = AppStore(file: file, demo: false)
        let device = Device(name: "Aire", kind: .airConditioner, transport: .broadlink(bridgeID: nil), codes: ["on": "x"])
        store.upsert(device)
        store.updateState(for: device.id) { $0.apply(.setAC(ACSettings(mode: .cool, temperature: 24))) }
        store.flush()

        let reloaded = AppStore(file: file, demo: false)
        XCTAssertEqual(reloaded.devices.count, 1)
        XCTAssertEqual(reloaded.state(for: device.id).ac?.temperature, 24)
    }

    func testDemoModeNeverWritesToDisk() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("aura-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = AppStore(file: StoreFile(url: url), demo: true)
        XCTAssertFalse(store.devices.isEmpty)
        store.upsert(Device(name: "X", kind: .generic, transport: .webhook))
        store.flush()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testRemovingDeviceCleansScenes() {
        let store = AppStore(file: nil, demo: true)
        let ac = try? XCTUnwrap(store.devices.first { $0.kind == .airConditioner })
        guard let ac else { return XCTFail("La demo debe tener un aire") }
        store.removeDevice(ac.id)
        XCTAssertFalse(store.scenes.flatMap(\.steps).contains { $0.deviceID == ac.id })
    }

    func testDemoDataIsConsistent() {
        let snapshot = DemoData.snapshot()
        let ids = Set(snapshot.devices.map(\.id))
        for scene in snapshot.scenes {
            for step in scene.steps { XCTAssertTrue(ids.contains(step.deviceID)) }
        }
        let ac = snapshot.devices.first { $0.kind == .airConditioner }
        XCTAssertEqual(ac?.recordedTemperatures(for: .cool), Array(17...28))
    }
}
