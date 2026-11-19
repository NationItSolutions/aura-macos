import XCTest
@testable import Aura

/// Compara byte a byte contra los vectores generados con python-broadlink
/// (scripts/gen_broadlink_vectors.py). Sin estos tests en verde el driver no está terminado.
final class BroadlinkProtocolTests: XCTestCase {
    private func bytes(_ hex: String, file: StaticString = #filePath, line: UInt = #line) -> [UInt8] {
        guard let data = Data(hex: hex) else {
            XCTFail("Hex inválido", file: file, line: line)
            return []
        }
        return [UInt8](data)
    }

    private var mac: [UInt8] { bytes(BroadlinkVectors.mac) }

    private func session(deviceType: UInt16, authenticated: Bool) -> BroadlinkSession {
        var session = BroadlinkSession(deviceType: deviceType, mac: mac, count: BroadlinkVectors.count)
        if authenticated {
            session.id = BroadlinkVectors.sessionID
            session.key = bytes(BroadlinkVectors.sessionKey)
        }
        return session
    }

    private func assertHex(_ actual: [UInt8], _ expected: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(Data(actual).hexString, expected, file: file, line: line)
    }

    // MARK: - Constantes y checksum

    func testConstantsMatchReference() {
        XCTAssertEqual(BroadlinkProtocol.initialKey, bytes(BroadlinkVectors.initKey))
        XCTAssertEqual(BroadlinkProtocol.iv, bytes(BroadlinkVectors.iv))
    }

    func testChecksum() {
        let value = BroadlinkProtocol.checksum(bytes(BroadlinkVectors.checksumInput))
        assertHex([UInt8].le(value), BroadlinkVectors.checksumValue)
    }

    func testAESRoundTrip() throws {
        let plain = BroadlinkCrypto.zeroPadded(Array("Aura Broadlink".utf8))
        let key = bytes(BroadlinkVectors.sessionKey)
        let encrypted = try BroadlinkCrypto.encrypt(plain, key: key, iv: BroadlinkProtocol.iv)
        XCTAssertNotEqual(encrypted, plain)
        XCTAssertEqual(try BroadlinkCrypto.decrypt(encrypted, key: key, iv: BroadlinkProtocol.iv), plain)
        XCTAssertThrowsError(try BroadlinkCrypto.encrypt([1, 2, 3], key: key, iv: BroadlinkProtocol.iv))
    }

    // MARK: - Descubrimiento

    func testHelloPacket() {
        let d = BroadlinkVectors.helloDate
        let date = BroadlinkDate(utcOffsetHours: Int32(d.utcOffsetHours), year: d.year, month: d.month, day: d.day,
                                 hour: d.hour, minute: d.minute, isoWeekday: 4) // 19/11/2026 es jueves
        let ip = BroadlinkVectors.localIP.split(separator: ".").compactMap { UInt8($0) }
        let packet = BroadlinkProtocol.helloPacket(date: date, localIP: ip, localPort: BroadlinkVectors.localPort)
        assertHex(packet, BroadlinkVectors.helloRequest)
    }

    func testBroadlinkDateFromFoundationDate() throws {
        let timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: -3 * 3600))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 15, minute: 30)))
        let packed = BroadlinkDate(date, timeZone: timeZone)
        XCTAssertEqual(packed, BroadlinkDate(utcOffsetHours: -3, year: 2026, month: 11, day: 19, hour: 15, minute: 30, isoWeekday: 4))
    }

    func testParseHello() throws {
        let device = try XCTUnwrap(BroadlinkProtocol.parseHello(bytes(BroadlinkVectors.helloResponse), host: "192.0.2.10"))
        XCTAssertEqual(device.deviceType, 0x6539)
        XCTAssertEqual(device.mac, mac)
        XCTAssertEqual(device.name, "RM4 mini")
        XCTAssertFalse(device.isLocked)
        XCTAssertEqual(device.family, .rm4Mini)
        let locked = try XCTUnwrap(BroadlinkProtocol.parseHello(bytes(BroadlinkVectors.helloResponseLocked), host: "x"))
        XCTAssertTrue(locked.isLocked)
        XCTAssertNil(BroadlinkProtocol.parseHello([0, 1, 2], host: "x"))
    }

    // MARK: - Autenticación

    func testAuthPacket() throws {
        var session = session(deviceType: 0x6539, authenticated: false)
        let packet = try BroadlinkProtocol.packet(type: .auth, payload: BroadlinkProtocol.authPayload, session: &session)
        assertHex(packet, BroadlinkVectors.authRequest)
        XCTAssertEqual(session.count, (BroadlinkVectors.count &+ 1) | 0x8000)
    }

    func testAuthResponse() throws {
        let payload = try BroadlinkProtocol.decodeResponse(bytes(BroadlinkVectors.authResponse), key: BroadlinkProtocol.initialKey)
        let (id, key) = try BroadlinkProtocol.parseAuth(payload)
        XCTAssertEqual(id, BroadlinkVectors.sessionID)
        XCTAssertEqual(key, bytes(BroadlinkVectors.sessionKey))
    }

    // MARK: - RM4 (prefijo de longitud)

    func testRM4SendData() throws {
        var session = session(deviceType: 0x6539, authenticated: true)
        let payload = BroadlinkProtocol.remotePayload(.sendData, data: bytes(BroadlinkVectors.irCode), family: .rm4Mini)
        assertHex(try BroadlinkProtocol.packet(type: .command, payload: payload, session: &session), BroadlinkVectors.rm4SendData)
    }

    func testRM4EnterLearning() throws {
        var session = session(deviceType: 0x6539, authenticated: true)
        let payload = BroadlinkProtocol.remotePayload(.enterLearning, family: .rm4Mini)
        assertHex(try BroadlinkProtocol.packet(type: .command, payload: payload, session: &session), BroadlinkVectors.rm4EnterLearning)
    }

    func testRM4CheckData() throws {
        var session = session(deviceType: 0x6539, authenticated: true)
        let payload = BroadlinkProtocol.remotePayload(.checkData, family: .rm4Mini)
        assertHex(try BroadlinkProtocol.packet(type: .command, payload: payload, session: &session), BroadlinkVectors.rm4CheckData)

        let decrypted = try BroadlinkProtocol.decodeResponse(bytes(BroadlinkVectors.rm4CheckDataResponse), key: session.key)
        XCTAssertEqual(BroadlinkProtocol.remoteResponseData(decrypted, family: .rm4Mini), bytes(BroadlinkVectors.irCode))
    }

    func testRM4CheckDataEmptyIsReadError() {
        XCTAssertThrowsError(try BroadlinkProtocol.decodeResponse(bytes(BroadlinkVectors.rm4CheckDataEmptyResponse),
                                                                  key: bytes(BroadlinkVectors.sessionKey))) { error in
            XCTAssertEqual(error as? BroadlinkError, .deviceError(-10))
        }
    }

    // MARK: - RM mini 3 clásico

    func testRMSendData() throws {
        var session = session(deviceType: 0x2737, authenticated: true)
        let payload = BroadlinkProtocol.remotePayload(.sendData, data: bytes(BroadlinkVectors.irCode), family: .rmMini)
        assertHex(try BroadlinkProtocol.packet(type: .command, payload: payload, session: &session), BroadlinkVectors.rmSendData)
    }

    func testRMCheckData() throws {
        var session = session(deviceType: 0x2737, authenticated: true)
        let payload = BroadlinkProtocol.remotePayload(.checkData, family: .rmMini)
        assertHex(try BroadlinkProtocol.packet(type: .command, payload: payload, session: &session), BroadlinkVectors.rmCheckData)
        let decrypted = try BroadlinkProtocol.decodeResponse(bytes(BroadlinkVectors.rmCheckDataResponse), key: session.key)
        let data = BroadlinkProtocol.remoteResponseData(decrypted, family: .rmMini)
        let code = bytes(BroadlinkVectors.irCode)
        // Igual que python-broadlink: la familia clásica devuelve también el relleno AES.
        XCTAssertEqual(Array(data.prefix(code.count)), code)
        XCTAssertTrue(data.dropFirst(code.count).allSatisfy { $0 == 0 })
    }

    // MARK: - RF (RM4 pro)

    func testRM4ProRF() throws {
        var s = session(deviceType: 0x520B, authenticated: true)
        assertHex(try BroadlinkProtocol.packet(type: .command, payload: BroadlinkProtocol.remotePayload(.sweepFrequency, family: .rm4Pro), session: &s),
                  BroadlinkVectors.rm4ProSweep)

        s = session(deviceType: 0x520B, authenticated: true)
        assertHex(try BroadlinkProtocol.packet(type: .command, payload: BroadlinkProtocol.remotePayload(.checkFrequency, family: .rm4Pro), session: &s),
                  BroadlinkVectors.rm4ProCheckFrequency)
        let decrypted = try BroadlinkProtocol.decodeResponse(bytes(BroadlinkVectors.rm4ProCheckFrequencyResponse), key: s.key)
        let frequency = try BroadlinkProtocol.parseFrequency(BroadlinkProtocol.remoteResponseData(decrypted, family: .rm4Pro))
        XCTAssertTrue(frequency.found)
        XCTAssertEqual(frequency.megahertz, 433.92, accuracy: 0.0001)

        s = session(deviceType: 0x520B, authenticated: true)
        let find = BroadlinkProtocol.remotePayload(.findRFPacket, data: BroadlinkProtocol.rfFrequencyData(433.92), family: .rm4Pro)
        assertHex(try BroadlinkProtocol.packet(type: .command, payload: find, session: &s), BroadlinkVectors.rm4ProFindRF)

        s = session(deviceType: 0x520B, authenticated: true)
        assertHex(try BroadlinkProtocol.packet(type: .command, payload: BroadlinkProtocol.remotePayload(.cancelSweep, family: .rm4Pro), session: &s),
                  BroadlinkVectors.rm4ProCancelSweep)

        s = session(deviceType: 0x520B, authenticated: true)
        let rf = BroadlinkProtocol.remotePayload(.sendData, data: bytes(BroadlinkVectors.rfCode), family: .rm4Pro)
        assertHex(try BroadlinkProtocol.packet(type: .command, payload: rf, session: &s), BroadlinkVectors.rm4ProSendRF)
    }

    // MARK: - Errores y validación

    func testDeviceErrorIsReported() {
        XCTAssertThrowsError(try BroadlinkProtocol.decodeResponse(bytes(BroadlinkVectors.errorResponse),
                                                                  key: bytes(BroadlinkVectors.sessionKey))) { error in
            XCTAssertEqual(error as? BroadlinkError, .deviceError(-7))
            XCTAssertTrue((error as? BroadlinkError)?.requiresReauthentication ?? false)
        }
    }

    func testCorruptChecksumIsRejected() {
        var response = bytes(BroadlinkVectors.authResponse)
        response[0x40] ^= 0xFF
        XCTAssertThrowsError(try BroadlinkProtocol.decodeResponse(response, key: BroadlinkProtocol.initialKey)) { error in
            XCTAssertEqual(error as? BroadlinkError, .invalidResponse)
        }
        XCTAssertThrowsError(try BroadlinkProtocol.decodeResponse([0, 1, 2], key: BroadlinkProtocol.initialKey))
    }

    func testFamilies() {
        XCTAssertEqual(BroadlinkFamily(deviceType: 0x6539), .rm4Mini)
        XCTAssertEqual(BroadlinkFamily(deviceType: 0x520B), .rm4Pro)
        XCTAssertEqual(BroadlinkFamily(deviceType: 0x2737), .rmMini)
        XCTAssertEqual(BroadlinkFamily(deviceType: 0x5F36), .rmMiniB)
        XCTAssertNil(BroadlinkFamily(deviceType: 0x2711)) // SP2: no es un control remoto
        XCTAssertTrue(BroadlinkFamily.rm4Mini.usesLengthPrefix)
        XCTAssertFalse(BroadlinkFamily.rmPro.usesLengthPrefix)
        XCTAssertTrue(BroadlinkFamily.rm4Pro.supportsRF)
        XCTAssertFalse(BroadlinkFamily.rm4Mini.supportsRF)
    }

    // MARK: - Pulsos

    func testPulsesToPacket() throws {
        let packet = BroadlinkProtocol.pulsesToPacket(BroadlinkVectors.pulses)
        assertHex(packet, BroadlinkVectors.pulsesPacket)
        let back = try BroadlinkProtocol.packetToPulses(packet)
        XCTAssertEqual(back.count, BroadlinkVectors.pulses.count)
        for (a, b) in zip(back, BroadlinkVectors.pulses) { XCTAssertLessThan(abs(a - b), 40) }
    }

    func testMACHelpers() {
        XCTAssertEqual(formatMAC(mac), "A0:43:B0:12:34:56")
        XCTAssertEqual(parseMAC("a0:43:b0:12:34:56"), mac)
        XCTAssertEqual(parseMAC("A043B0123456"), mac)
        XCTAssertNil(parseMAC("A0:43"))
    }
}
