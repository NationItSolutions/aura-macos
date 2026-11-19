import Foundation

extension Data {
    /// Crea `Data` desde un string hexadecimal ("a0b1..."). Devuelve `nil` si es inválido.
    init?(hex: String) {
        let clean = hex.filter { !$0.isWhitespace }
        guard clean.count.isMultiple(of: 2) else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(clean.count / 2)
        var index = clean.startIndex
        while index < clean.endIndex {
            let next = clean.index(index, offsetBy: 2)
            guard let byte = UInt8(clean[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }

    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}

extension Array where Element == UInt8 {
    /// Escribe un entero en little endian a partir de `offset`.
    mutating func writeLE<T: FixedWidthInteger>(_ value: T, at offset: Int) {
        let size = MemoryLayout<T>.size
        for index in 0..<size {
            self[offset + index] = UInt8(truncatingIfNeeded: value >> (8 * index))
        }
    }

    /// Lee un entero en little endian desde `offset`.
    func readLE<T: FixedWidthInteger>(_ type: T.Type, at offset: Int) -> T {
        var value: T = 0
        for index in 0..<MemoryLayout<T>.size {
            value |= T(truncatingIfNeeded: self[offset + index]) << (8 * index)
        }
        return value
    }

    static func le<T: FixedWidthInteger>(_ value: T) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: MemoryLayout<T>.size)
        bytes.writeLE(value, at: 0)
        return bytes
    }
}

/// Formatea una MAC en orden natural como "A0:43:B0:12:34:56".
func formatMAC(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02X", $0) }.joined(separator: ":")
}

/// Convierte "A0:43:B0:12:34:56" (o sin separadores) a bytes.
func parseMAC(_ string: String) -> [UInt8]? {
    let hex = string.filter(\.isHexDigit)
    guard hex.count == 12, let data = Data(hex: hex) else { return nil }
    return [UInt8](data)
}
