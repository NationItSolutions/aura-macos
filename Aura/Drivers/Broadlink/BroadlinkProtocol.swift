import Foundation

/// Estado de la sesión con un Broadlink: clave AES, ID de sesión y contador de paquetes.
struct BroadlinkSession: Sendable, Equatable {
    var key: [UInt8]
    var id: UInt32
    var count: UInt16
    let deviceType: UInt16
    /// MAC en orden natural (como se muestra al usuario).
    let mac: [UInt8]

    init(deviceType: UInt16, mac: [UInt8], count: UInt16 = UInt16.random(in: 0x8000...0xFFFF)) {
        self.key = BroadlinkProtocol.initialKey
        self.id = 0
        self.count = count
        self.deviceType = deviceType
        self.mac = mac
    }

    /// Vuelve a la clave inicial antes de autenticar.
    mutating func reset() {
        key = BroadlinkProtocol.initialKey
        id = 0
    }
}

/// Un Broadlink encontrado en la red.
struct DiscoveredBroadlink: Sendable, Hashable, Identifiable {
    var host: String
    var deviceType: UInt16
    var mac: [UInt8]
    var name: String
    var isLocked: Bool

    var id: String { formatMAC(mac) }
    var family: BroadlinkFamily? { BroadlinkFamily(deviceType: deviceType) }
    var modelName: String { BroadlinkFamily.modelName(for: deviceType) ?? "Broadlink 0x\(String(deviceType, radix: 16))" }
}

/// Fecha empaquetada en el paquete de descubrimiento.
struct BroadlinkDate: Sendable, Equatable {
    var utcOffsetHours: Int32
    var year: Int
    var month: Int
    var day: Int
    var hour: Int
    var minute: Int
    /// 1 = lunes … 7 = domingo.
    var isoWeekday: Int

    init(utcOffsetHours: Int32, year: Int, month: Int, day: Int, hour: Int, minute: Int, isoWeekday: Int) {
        self.utcOffsetHours = utcOffsetHours
        self.year = year
        self.month = month
        self.day = day
        self.hour = hour
        self.minute = minute
        self.isoWeekday = isoWeekday
    }

    init(_ date: Date, timeZone: TimeZone = .current) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: date)
        let weekday = parts.weekday ?? 1 // 1 = domingo en Calendar
        self.init(
            utcOffsetHours: Int32(timeZone.secondsFromGMT(for: date) / 3600),
            year: parts.year ?? 2000, month: parts.month ?? 1, day: parts.day ?? 1,
            hour: parts.hour ?? 0, minute: parts.minute ?? 0,
            isoWeekday: weekday == 1 ? 7 : weekday - 1
        )
    }

    var packed: [UInt8] {
        var data = [UInt8](repeating: 0, count: 12)
        data.writeLE(utcOffsetHours, at: 0)
        data.writeLE(UInt16(truncatingIfNeeded: year), at: 4)
        data[6] = UInt8(truncatingIfNeeded: minute)
        data[7] = UInt8(truncatingIfNeeded: hour)
        data[8] = UInt8(truncatingIfNeeded: year % 100)
        data[9] = UInt8(truncatingIfNeeded: isoWeekday)
        data[10] = UInt8(truncatingIfNeeded: day)
        data[11] = UInt8(truncatingIfNeeded: month)
        return data
    }
}

/// Protocolo local de Broadlink, portado de python-broadlink 0.19.0
/// (`broadlink/device.py` y `broadlink/remote.py`). Funciones puras: sin red.
enum BroadlinkProtocol {
    static let port: UInt16 = 80
    static let initialKey: [UInt8] = [0x09, 0x76, 0x28, 0x34, 0x3F, 0xE9, 0x9E, 0x23,
                                      0x76, 0x5C, 0x15, 0x13, 0xAC, 0xCF, 0x8B, 0x02]
    static let iv: [UInt8] = [0x56, 0x2E, 0x17, 0x99, 0x6D, 0x09, 0x3D, 0x28,
                              0xDD, 0xB3, 0xBA, 0x69, 0x5A, 0x2E, 0x6F, 0x58]
    static let magic: [UInt8] = [0x5A, 0xA5, 0xAA, 0x55, 0x5A, 0xA5, 0xAA, 0x55]

    enum PacketType: UInt16 {
        case auth = 0x65
        case command = 0x6A
    }

    /// Comandos de control remoto (remote.py).
    enum RemoteCommand: UInt32 {
        case sendData = 0x02
        case enterLearning = 0x03
        case checkData = 0x04
        case sweepFrequency = 0x19
        case checkFrequency = 0x1A
        case findRFPacket = 0x1B
        case cancelSweep = 0x1E
    }

    /// Suma de bytes + 0xBEAF, truncada a 16 bits.
    static func checksum<S: Sequence>(_ bytes: S) -> UInt16 where S.Element == UInt8 {
        var sum: UInt32 = 0xBEAF
        for byte in bytes { sum &+= UInt32(byte) }
        return UInt16(truncatingIfNeeded: sum)
    }

    // MARK: - Descubrimiento

    /// Paquete "hello" de descubrimiento (`scan()` en device.py).
    static func helloPacket(date: BroadlinkDate, localIP: [UInt8] = [0, 0, 0, 0], localPort: UInt16 = 0) -> [UInt8] {
        var packet = [UInt8](repeating: 0, count: 0x30)
        packet.replaceSubrange(0x08..<0x14, with: date.packed)
        packet.replaceSubrange(0x18..<0x1C, with: localIP.reversed())
        packet.writeLE(localPort, at: 0x1C)
        packet[0x26] = 6
        packet.writeLE(checksum(packet), at: 0x20)
        return packet
    }

    static func parseHello(_ response: [UInt8], host: String) -> DiscoveredBroadlink? {
        guard response.count >= 0x80 else { return nil }
        let deviceType = response.readLE(UInt16.self, at: 0x34)
        let mac = Array(response[0x3A..<0x40].reversed())
        let nameBytes = response[0x40...].prefix { $0 != 0 }
        let name = String(decoding: nameBytes, as: UTF8.self)
        return DiscoveredBroadlink(host: host, deviceType: deviceType, mac: mac, name: name, isLocked: response[0x7F] != 0)
    }

    // MARK: - Paquetes cifrados

    /// Arma un paquete cifrado (`send_packet()`): incrementa el contador de la sesión.
    static func packet(type: PacketType, payload: [UInt8], session: inout BroadlinkSession) throws -> [UInt8] {
        session.count = (session.count &+ 1) | 0x8000
        var packet = [UInt8](repeating: 0, count: 0x38)
        packet.replaceSubrange(0x00..<0x08, with: magic)
        packet.writeLE(session.deviceType, at: 0x24)
        packet.writeLE(type.rawValue, at: 0x26)
        packet.writeLE(session.count, at: 0x28)
        packet.replaceSubrange(0x2A..<0x30, with: session.mac.reversed())
        packet.writeLE(session.id, at: 0x30)
        packet.writeLE(checksum(payload), at: 0x34)
        packet += try BroadlinkCrypto.encrypt(BroadlinkCrypto.zeroPadded(payload), key: session.key, iv: iv)
        packet.writeLE(checksum(packet), at: 0x20)
        return packet
    }

    /// Valida una respuesta, verifica el código de error y devuelve el payload descifrado.
    static func decodeResponse(_ response: [UInt8], key: [UInt8]) throws -> [UInt8] {
        guard response.count >= 0x30 else { throw BroadlinkError.invalidResponse }
        let nominal = response.readLE(UInt16.self, at: 0x20)
        let real = checksum(response) &- UInt16(response[0x20]) &- UInt16(response[0x21])
        guard nominal == real else { throw BroadlinkError.invalidResponse }
        let error = response.readLE(Int16.self, at: 0x22)
        if error != 0 { throw BroadlinkError.deviceError(error) }
        guard response.count > 0x38 else { return [] }
        let encrypted = Array(response[0x38...])
        guard encrypted.count.isMultiple(of: 16) else { throw BroadlinkError.invalidResponse }
        return try BroadlinkCrypto.decrypt(encrypted, key: key, iv: iv)
    }

    // MARK: - Autenticación

    static var authPayload: [UInt8] {
        var payload = [UInt8](repeating: 0, count: 0x50)
        payload.replaceSubrange(0x04..<0x14, with: [UInt8](repeating: 0x31, count: 16))
        payload[0x1E] = 0x01
        payload[0x2D] = 0x01
        payload.replaceSubrange(0x30..<0x36, with: Array("Test 1".utf8))
        return payload
    }

    /// Extrae el ID de sesión y la clave nueva de la respuesta de autenticación.
    static func parseAuth(_ payload: [UInt8]) throws -> (id: UInt32, key: [UInt8]) {
        guard payload.count >= 0x14 else { throw BroadlinkError.invalidResponse }
        return (payload.readLE(UInt32.self, at: 0), Array(payload[0x04..<0x14]))
    }

    // MARK: - Control remoto

    /// Payload de un comando de control remoto según la familia.
    static func remotePayload(_ command: RemoteCommand, data: [UInt8] = [], family: BroadlinkFamily) -> [UInt8] {
        let body = [UInt8].le(command.rawValue) + data
        guard family.usesLengthPrefix else { return body }
        return [UInt8].le(UInt16(truncatingIfNeeded: data.count + 4)) + body
    }

    /// Datos útiles de la respuesta a un comando de control remoto.
    static func remoteResponseData(_ payload: [UInt8], family: BroadlinkFamily) -> [UInt8] {
        if family.usesLengthPrefix {
            guard payload.count >= 2 else { return [] }
            let length = Int(payload.readLE(UInt16.self, at: 0))
            let end = min(length + 2, payload.count)
            guard end > 6 else { return [] }
            return Array(payload[6..<end])
        }
        guard payload.count > 4 else { return [] }
        return Array(payload[4...])
    }

    /// Frecuencia en la respuesta de `check_frequency`: (encontrada, MHz).
    static func parseFrequency(_ data: [UInt8]) throws -> (found: Bool, megahertz: Double) {
        guard data.count >= 5 else { throw BroadlinkError.invalidResponse }
        return (data[0] != 0, Double(data.readLE(UInt32.self, at: 1)) / 1000)
    }

    /// Datos de `find_rf_packet`: frecuencia en kHz (u32 LE), o vacío para barrido.
    static func rfFrequencyData(_ megahertz: Double?) -> [UInt8] {
        guard let megahertz else { return [] }
        return [UInt8].le(UInt32(megahertz * 1000))
    }

    // MARK: - Pulsos

    /// Convierte duraciones en microsegundos a un paquete IR de Broadlink (`pulses_to_data`).
    static func pulsesToPacket(_ pulses: [Int], tick: Double = 32.84) -> [UInt8] {
        var result: [UInt8] = [0x26, 0, 0, 0]
        for pulse in pulses {
            let ticks = Int((Double(pulse) / tick).rounded(.down))
            let (div, mod) = ticks.quotientAndRemainder(dividingBy: 256)
            if div != 0 {
                result.append(0)
                result.append(UInt8(truncatingIfNeeded: div))
            }
            result.append(UInt8(truncatingIfNeeded: mod))
        }
        let length = result.count - 4
        result[2] = UInt8(truncatingIfNeeded: length & 0xFF)
        result[3] = UInt8(truncatingIfNeeded: length >> 8)
        return result
    }

    /// Convierte un paquete IR en duraciones en microsegundos (`data_to_pulses`).
    static func packetToPulses(_ data: [UInt8], tick: Double = 32.84) throws -> [Int] {
        guard data.count >= 4 else { throw BroadlinkError.invalidCode }
        var result: [Int] = []
        var index = 4
        let end = min(256 * Int(data[3]) + Int(data[2]) + 4, data.count)
        while index < end {
            var chunk = Int(data[index])
            index += 1
            if chunk == 0 {
                guard index + 1 < data.count else { throw BroadlinkError.invalidCode }
                chunk = 256 * Int(data[index]) + Int(data[index + 1])
                index += 2
            }
            result.append(Int(Double(chunk) * tick))
        }
        return result
    }
}
