import XCTest
@testable import Aura

/// Broadlink simulado: descifra cada pedido con su clave y responde como el firmware real.
actor FakeBroadlink: UDPTransport {
    let family: BroadlinkFamily
    var sessionKey: [UInt8] = Array(0..<16).map { UInt8($0 * 7 & 0xFF) }
    var sessionID: UInt32 = 0x1234
    var authenticated = false
    var locked = false
    /// Respuestas vacías (-10) antes de entregar el código aprendido.
    var emptyChecksBeforeData = 2
    var learnedCode: [UInt8] = [0x26, 0x00, 0x04, 0x00, 0x11, 0x22, 0x33, 0x44]
    /// Fuerza un error -7 (clave vencida) en el próximo comando.
    var expireNextCommand = false
    var unreachable = false
    var frequencyChecksBeforeFound = 1
    private(set) var receivedCommands: [UInt32] = []
    private(set) var sentCodes: [[UInt8]] = []
    private(set) var authCount = 0

    init(family: BroadlinkFamily) { self.family = family }

    func configure(_ change: @Sendable (isolated FakeBroadlink) -> Void) { change(self) }

    func request(_ packet: [UInt8], host: String, port: UInt16, timeout: Duration, retryInterval: Duration) async throws -> [UInt8] {
        if unreachable { throw BroadlinkError.timeout }
        let type = packet.readLE(UInt16.self, at: 0x26)
        let encrypted = Array(packet[0x38...])
        if type == 0x65 {
            authCount += 1
            if locked { return try response(error: -1, plain: [], key: BroadlinkProtocol.initialKey) }
            _ = try BroadlinkCrypto.decrypt(encrypted, key: BroadlinkProtocol.initialKey, iv: BroadlinkProtocol.iv)
            authenticated = true
            return try response(plain: [UInt8].le(sessionID) + sessionKey, key: BroadlinkProtocol.initialKey)
        }
        let payload = try BroadlinkCrypto.decrypt(encrypted, key: sessionKey, iv: BroadlinkProtocol.iv)
        guard authenticated, packet.readLE(UInt32.self, at: 0x30) == sessionID else {
            return try response(error: -4012, plain: [], key: sessionKey)
        }
        if expireNextCommand {
            expireNextCommand = false
            authenticated = false
            return try response(error: -7, plain: [], key: sessionKey)
        }
        let offset = family.usesLengthPrefix ? 2 : 0
        let command = payload.readLE(UInt32.self, at: offset)
        receivedCommands.append(command)
        var data: [UInt8] = []
        switch command {
        case 0x02:
            let length = family.usesLengthPrefix ? Int(payload.readLE(UInt16.self, at: 0)) - 4 : payload.count - 4
            sentCodes.append(Array(payload[(offset + 4)..<(offset + 4 + length)]))
        case 0x04:
            if emptyChecksBeforeData > 0 {
                emptyChecksBeforeData -= 1
                return try response(error: -10, plain: wrap(0x04, []), key: sessionKey)
            }
            data = learnedCode
        case 0x1A:
            if frequencyChecksBeforeFound > 0 {
                frequencyChecksBeforeFound -= 1
                data = [0] + [UInt8].le(UInt32(0))
            } else {
                data = [1] + [UInt8].le(UInt32(433_920))
            }
        default:
            break
        }
        return try response(plain: wrap(command, data), key: sessionKey)
    }

    private func wrap(_ command: UInt32, _ data: [UInt8]) -> [UInt8] {
        let body = [UInt8].le(command) + data
        return family.usesLengthPrefix ? [UInt8].le(UInt16(data.count + 4)) + body : body
    }

    private func response(error: Int16 = 0, plain: [UInt8], key: [UInt8]) throws -> [UInt8] {
        var packet = [UInt8](repeating: 0, count: 0x38)
        packet.replaceSubrange(0..<8, with: BroadlinkProtocol.magic)
        packet.writeLE(error, at: 0x22)
        packet += try BroadlinkCrypto.encrypt(BroadlinkCrypto.zeroPadded(plain), key: key, iv: BroadlinkProtocol.iv)
        packet.writeLE(BroadlinkProtocol.checksum(packet), at: 0x20)
        return packet
    }
}

final class BroadlinkClientTests: XCTestCase {
    private let mac: [UInt8] = [0xA0, 0x43, 0xB0, 0x12, 0x34, 0x56]

    private func makeClient(_ fake: FakeBroadlink, deviceType: UInt16 = 0x6539) async throws -> BroadlinkClient {
        let client = try BroadlinkClient(host: "192.0.2.10", mac: mac, deviceType: deviceType, transport: fake)
        await client.setPollInterval(.milliseconds(10))
        return client
    }

    func testAuthenticateAndSend() async throws {
        let fake = FakeBroadlink(family: .rm4Mini)
        let client = try await makeClient(fake)
        let code = Data([0x26, 0x00, 0x02, 0x00, 0xAA, 0xBB])
        try await client.send(code: code)
        let authenticated = await client.isAuthenticated
        let sent = await fake.sentCodes
        XCTAssertTrue(authenticated)
        XCTAssertEqual(sent, [[UInt8](code)])
    }

    func testClassicFamilySend() async throws {
        let fake = FakeBroadlink(family: .rmMini)
        let client = try await makeClient(fake, deviceType: 0x2737)
        try await client.send(code: Data([0x26, 0x00, 0x01, 0x00, 0x7F]))
        let sent = await fake.sentCodes
        XCTAssertEqual(sent.first?.prefix(5).map { $0 }, [0x26, 0x00, 0x01, 0x00, 0x7F])
    }

    func testLearnInfraredPollsUntilData() async throws {
        let fake = FakeBroadlink(family: .rm4Mini)
        let client = try await makeClient(fake)
        let learned = try await client.learnInfrared(timeout: .seconds(5))
        let expected = await fake.learnedCode
        let commands = await fake.receivedCommands
        XCTAssertEqual([UInt8](learned), expected)
        XCTAssertEqual(commands.first, 0x03)
        XCTAssertEqual(commands.filter { $0 == 0x04 }.count, 3) // dos respuestas vacías (-10) y la buena
    }

    func testLearnTimesOut() async throws {
        let fake = FakeBroadlink(family: .rm4Mini)
        await fake.configure { $0.emptyChecksBeforeData = 10_000 }
        let client = try await makeClient(fake)
        do {
            _ = try await client.learnInfrared(timeout: .milliseconds(150))
            XCTFail("Debía vencer")
        } catch {
            XCTAssertEqual(error as? BroadlinkError, .learningTimedOut)
        }
    }

    func testReauthenticatesWhenKeyExpires() async throws {
        let fake = FakeBroadlink(family: .rm4Mini)
        let client = try await makeClient(fake)
        try await client.authenticate()
        await fake.configure { $0.expireNextCommand = true }
        try await client.send(code: Data([0x26, 0x00, 0x01, 0x00, 0x01]))
        let auths = await fake.authCount
        let sent = await fake.sentCodes
        XCTAssertEqual(auths, 2)
        XCTAssertEqual(sent.count, 1)
    }

    func testLockedDevice() async throws {
        let fake = FakeBroadlink(family: .rm4Mini)
        await fake.configure { $0.locked = true }
        let client = try await makeClient(fake)
        do {
            try await client.authenticate()
            XCTFail("Debía fallar")
        } catch {
            XCTAssertEqual(error as? BroadlinkError, .locked)
            XCTAssertTrue(error.displayMessage.contains("Bloquear dispositivo"))
        }
    }

    func testLearnRadio() async throws {
        let fake = FakeBroadlink(family: .rm4Pro)
        await fake.configure { $0.emptyChecksBeforeData = 0 }
        let client = try await makeClient(fake, deviceType: 0x520B)
        let phases = PhaseRecorder()
        let code = try await client.learnRadio(timeout: .seconds(5)) { phase in phases.append(phase) }
        XCTAssertFalse(code.isEmpty)
        XCTAssertEqual(phases.values, [.sweeping, .frequencyFound(433.92)])
        let commands = await fake.receivedCommands
        XCTAssertEqual(Array(commands.prefix(2)), [0x19, 0x1A])
        XCTAssertTrue(commands.contains(0x1B))
    }

    func testRadioRequiresPro() async throws {
        let client = try await makeClient(FakeBroadlink(family: .rm4Mini))
        do {
            _ = try await client.learnRadio(timeout: .seconds(1)) { _ in }
            XCTFail("Debía fallar")
        } catch {
            XCTAssertEqual(error as? BroadlinkError, .rfNotSupported)
        }
    }

    func testUnsupportedDeviceType() {
        XCTAssertThrowsError(try BroadlinkClient(host: "x", mac: mac, deviceType: 0x2711, transport: FakeBroadlink(family: .rm4Mini)))
    }

    func testConcurrentRequestsShareSessionSafely() async throws {
        let fake = FakeBroadlink(family: .rm4Mini)
        let client = try await makeClient(fake)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<8 {
                group.addTask { try await client.send(code: Data([0x26, 0x00, 0x01, 0x00, UInt8(index)])) }
            }
            try await group.waitForAll()
        }
        let sent = await fake.sentCodes
        let auths = await fake.authCount
        XCTAssertEqual(sent.count, 8)
        XCTAssertEqual(auths, 1)
    }
}

/// Junta valores desde closures @Sendable.
final class PhaseRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [LearningPhase] = []
    func append(_ phase: LearningPhase) { lock.withLock { storage.append(phase) } }
    var values: [LearningPhase] { lock.withLock { storage } }
}

@MainActor
final class BroadlinkHubTests: XCTestCase {
    private let mac: [UInt8] = [0xA0, 0x43, 0xB0, 0x12, 0x34, 0x56]

    func testIdentifiesBridgeImportedWithOnlyIP() async throws {
        let store = AppStore(file: nil, demo: false)
        let bridge = Bridge(name: "Broadlink", host: "192.0.2.10")
        store.upsert(bridge)
        let mac = self.mac
        let hub = BroadlinkHub(store: store, transport: FakeBroadlink(family: .rm4Mini)) { _, address in
            [DiscoveredBroadlink(host: address, deviceType: 0x6539, mac: mac, name: "RM4 mini", isLocked: false)]
        }
        _ = try await hub.client(for: bridge.id)
        XCTAssertEqual(store.bridge(bridge.id)?.macAddress, "A0:43:B0:12:34:56")
        XCTAssertEqual(store.bridge(bridge.id)?.deviceType, 0x6539)
    }

    func testRediscoverUpdatesIPByMAC() async throws {
        let store = AppStore(file: nil, demo: false)
        let bridge = Bridge(name: "Broadlink", host: "192.0.2.10", macAddress: "A0:43:B0:12:34:56", deviceType: 0x6539)
        store.upsert(bridge)
        let mac = self.mac
        let hub = BroadlinkHub(store: store, transport: FakeBroadlink(family: .rm4Mini)) { _, _ in
            [DiscoveredBroadlink(host: "192.0.2.99", deviceType: 0x6539, mac: mac, name: "RM4 mini", isLocked: false),
             DiscoveredBroadlink(host: "192.0.2.50", deviceType: 0x6539, mac: [1, 2, 3, 4, 5, 6], name: "Otro", isLocked: false)]
        }
        let client = try await hub.client(for: bridge.id)
        let found = try await hub.rediscover(bridgeID: bridge.id)
        XCTAssertTrue(found)
        XCTAssertEqual(store.bridge(bridge.id)?.host, "192.0.2.99")
        let host = await client.host
        XCTAssertEqual(host, "192.0.2.99")
    }

    func testLockedBridgeIsReportedOnIdentify() async {
        let store = AppStore(file: nil, demo: false)
        let bridge = Bridge(name: "Broadlink", host: "192.0.2.10")
        store.upsert(bridge)
        let mac = self.mac
        let hub = BroadlinkHub(store: store, transport: FakeBroadlink(family: .rm4Mini)) { _, address in
            [DiscoveredBroadlink(host: address, deviceType: 0x6539, mac: mac, name: "RM4 mini", isLocked: true)]
        }
        do {
            _ = try await hub.client(for: bridge.id)
            XCTFail("Debía fallar")
        } catch {
            XCTAssertEqual(error as? BroadlinkError, .locked)
        }
    }

    func testDriverSendsRecordedCode() async throws {
        let store = AppStore(file: nil, demo: false)
        let bridge = Bridge(name: "Broadlink", host: "192.0.2.10", macAddress: "A0:43:B0:12:34:56", deviceType: 0x6539)
        store.upsert(bridge)
        let fake = FakeBroadlink(family: .rm4Mini)
        let hub = BroadlinkHub(store: store, transport: fake) { _, _ in [] }
        let code = Data([0x26, 0x00, 0x02, 0x00, 0x10, 0x20])
        let led = Device(name: "LED", kind: .light, transport: .broadlink(bridgeID: bridge.id),
                         codes: ["power_on": code.base64EncodedString()])
        let driver = BroadlinkDriver(device: led, bridgeID: bridge.id, hub: hub)
        try await driver.send(.power(true))
        let sent = await fake.sentCodes
        XCTAssertEqual(sent, [[UInt8](code)])

        do {
            try await driver.send(.power(false))
            XCTFail("Debía faltar el código")
        } catch {
            XCTAssertEqual(error as? DriverError, .missingCode("power_off"))
        }
    }
}
