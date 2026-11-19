import XCTest
@testable import Aura

final class LegacyCodesImporterTests: XCTestCase {
    private let code = "JgBQAAABKZIUERQRFDYUERQRFBEUERQRFDYUNhQ="

    private func data(_ json: String) -> Data { Data(json.utf8) }

    func testFullFileMapsNames() throws {
        let json = """
        { "ip": "192.168.1.50",
          "codigos": { "off": "\(code)", "on": "\(code)", "frio_18": "\(code)", "frio_23": "\(code)" },
          "led": { "ligar": "\(code)", "desligar": "\(code)", "brilho_mais": "\(code)",
                   "brilho_menos": "\(code)", "azul": "\(code)", "vermelho": "\(code)" } }
        """
        let result = try LegacyCodesImporter.parse(data(json))
        XCTAssertEqual(result.bridgeHost, "192.168.1.50")
        XCTAssertEqual(Set(result.acCodes.keys), ["off", "on", "cool_18", "cool_23"])
        XCTAssertEqual(Set(result.ledCodes.keys),
                       ["power_on", "power_off", "brightness_up", "brightness_down", "azul", "vermelho"])
        XCTAssertTrue(result.warnings.isEmpty)
    }

    func testPartialFileWithOnlyLED() throws {
        let result = try LegacyCodesImporter.parse(data(#"{ "led": { "ligar": "\#(code)" } }"#))
        XCTAssertNil(result.bridgeHost)
        XCTAssertTrue(result.acCodes.isEmpty)
        XCTAssertEqual(result.ledCodes["power_on"], code)
    }

    func testCorruptEntriesAreSkippedWithWarning() throws {
        let json = #"{ "codigos": { "on": "\#(code)", "off": "", "frio_20": "@@no-base64@@", "frio_21": 42 } }"#
        let result = try LegacyCodesImporter.parse(data(json))
        XCTAssertEqual(Set(result.acCodes.keys), ["on"])
        XCTAssertEqual(result.warnings.count, 3)
    }

    func testInvalidIPIsIgnored() throws {
        let result = try LegacyCodesImporter.parse(data(#"{ "ip": "192.168.1.300", "codigos": { "on": "\#(code)" } }"#))
        XCTAssertNil(result.bridgeHost)
        XCTAssertEqual(result.warnings.count, 1)
    }

    func testWrongSectionTypeIsSkipped() throws {
        let result = try LegacyCodesImporter.parse(data(#"{ "codigos": ["a", "b"], "led": { "azul": "\#(code)" } }"#))
        XCTAssertTrue(result.acCodes.isEmpty)
        XCTAssertEqual(result.ledCodes.count, 1)
        XCTAssertEqual(result.warnings.count, 1)
    }

    func testInvalidJSONThrows() {
        XCTAssertThrowsError(try LegacyCodesImporter.parse(data("{ esto no es json"))) { error in
            XCTAssertEqual(error as? LegacyCodesImporter.ImportError, .invalidJSON)
        }
    }

    func testTruncatedFileThrows() {
        XCTAssertThrowsError(try LegacyCodesImporter.parse(data(#"{ "codigos": { "on": "\#(code)""#)))
    }

    func testNonObjectRootThrows() {
        XCTAssertThrowsError(try LegacyCodesImporter.parse(data("[1, 2, 3]"))) { error in
            XCTAssertEqual(error as? LegacyCodesImporter.ImportError, .notAnObject)
        }
    }

    func testEmptyObjectThrowsNothingToImport() {
        XCTAssertThrowsError(try LegacyCodesImporter.parse(data("{}"))) { error in
            XCTAssertEqual(error as? LegacyCodesImporter.ImportError, .nothingToImport)
        }
    }

    func testNameMapping() {
        XCTAssertEqual(LegacyCodesImporter.mapACName("frio_23"), "cool_23")
        XCTAssertEqual(LegacyCodesImporter.mapACName("FRIO_16"), "cool_16")
        XCTAssertEqual(LegacyCodesImporter.mapACName("frio_x"), "frio_x")
        XCTAssertEqual(LegacyCodesImporter.mapLEDName("brilho_mais"), "brightness_up")
        XCTAssertEqual(LegacyCodesImporter.mapLEDName("azul"), "azul")
    }

    @MainActor
    func testApplyCreatesBridgeACAndLED() throws {
        let store = AppStore(file: nil, demo: false)
        let result = LegacyCodesImporter.Result(
            bridgeHost: "192.168.1.50",
            acCodes: ["on": code, "cool_23": code],
            ledCodes: ["power_on": code, "azul": code],
            warnings: []
        )
        let summary = store.apply(result)
        XCTAssertEqual(summary.acCodes, 2)
        XCTAssertEqual(store.bridges.count, 1)
        XCTAssertEqual(store.bridges.first?.host, "192.168.1.50")
        let ac = try XCTUnwrap(store.devices.first { $0.kind == .airConditioner })
        XCTAssertEqual(ac.codes.count, 2)
        XCTAssertEqual(ac.transport.bridgeID, store.bridges.first?.id)
        let led = try XCTUnwrap(store.devices.first { $0.kind == .light })
        XCTAssertEqual(led.recordedColors, ["azul"])

        // Reimportar fusiona sin duplicar dispositivos.
        store.apply(LegacyCodesImporter.Result(bridgeHost: nil, acCodes: ["off": code], ledCodes: [:], warnings: []))
        XCTAssertEqual(store.devices.filter { $0.kind == .airConditioner }.count, 1)
        XCTAssertEqual(store.devices.first { $0.kind == .airConditioner }?.codes.count, 3)
    }
}
