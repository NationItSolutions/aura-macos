import Carbon.HIToolbox
import XCTest
@testable import Aura

/// Isla, atajos y acciones rápidas.
final class ExperienceTests: XCTestCase {
    func testShortcutDisplay() {
        XCTAssertEqual(KeyShortcut.defaultIsland.displayString, "⌥⌘" + String(localized: "Espacio"))
        XCTAssertEqual(KeyShortcut.scene(0)?.displayString, "⌃⌥1")
        XCTAssertNil(KeyShortcut.scene(9))
    }

    func testShortcutCodableRoundTrip() throws {
        let data = try JSONEncoder().encode(KeyShortcut.defaultWindow)
        XCTAssertEqual(try JSONDecoder().decode(KeyShortcut.self, from: data), .defaultWindow)
    }

    @MainActor
    func testIslandGeometry() {
        let pill = IslandModel.Geometry.none
        XCTAssertEqual(pill.size(for: .compact), IslandModel.Geometry.pillSize)
        XCTAssertEqual(pill.topInset, 0)
        let notch = IslandModel.Geometry(notchWidth: 200, notchHeight: 32)
        XCTAssertEqual(notch.size(for: .compact).width, 200 + IslandModel.Geometry.wing * 2)
        XCTAssertEqual(notch.size(for: .expanded), CGSize(width: 560, height: 262))
        XCTAssertGreaterThan(notch.size(for: .activity(CommandFeedback(title: "x", isError: false, symbol: "bolt"))).height, 32)
    }

    @MainActor
    func testStepTemperatureSkipsToRecorded() async throws {
        let model = AppModel(settings: AppSettings(defaults: try XCTUnwrap(UserDefaults(suiteName: "aura.tests.\(UUID())"))),
                             storeFile: nil)
        model.setDemoMode(true)
        let ac = Device(name: "Aire", kind: .airConditioner, transport: .broadlink(bridgeID: nil),
                        codes: ["cool_20": "x", "cool_24": "x"], temperatureRange: 17...26)
        model.store.upsert(ac)
        model.syncState(ac) { $0.ac = ACSettings(mode: .cool, temperature: 20) }
        XCTAssertTrue(await model.setTemperature(ac, to: 24))
        XCTAssertEqual(model.store.state(for: ac.id).ac?.temperature, 24)
        XCTAssertFalse(await model.setTemperature(ac, to: 31))
    }
}
