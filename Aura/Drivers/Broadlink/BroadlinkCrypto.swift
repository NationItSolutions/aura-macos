import CommonCrypto
import Foundation

/// AES-128-CBC sin padding, como pide el protocolo Broadlink.
/// El llamador rellena con ceros hasta múltiplo de 16.
enum BroadlinkCrypto {
    static func encrypt(_ data: [UInt8], key: [UInt8], iv: [UInt8]) throws -> [UInt8] {
        try crypt(CCOperation(kCCEncrypt), data, key: key, iv: iv)
    }

    static func decrypt(_ data: [UInt8], key: [UInt8], iv: [UInt8]) throws -> [UInt8] {
        try crypt(CCOperation(kCCDecrypt), data, key: key, iv: iv)
    }

    /// Rellena con ceros hasta un múltiplo de 16 bytes.
    static func zeroPadded(_ data: [UInt8]) -> [UInt8] {
        let padding = (16 - data.count % 16) % 16
        return data + [UInt8](repeating: 0, count: padding)
    }

    private static func crypt(_ operation: CCOperation, _ data: [UInt8], key: [UInt8], iv: [UInt8]) throws -> [UInt8] {
        guard key.count == kCCKeySizeAES128, iv.count == kCCBlockSizeAES128,
              data.count.isMultiple(of: kCCBlockSizeAES128) else {
            throw BroadlinkError.invalidResponse
        }
        if data.isEmpty { return [] }
        let outputCount = data.count
        var output = [UInt8](repeating: 0, count: outputCount)
        var moved = 0
        let status = output.withUnsafeMutableBytes { outPtr in
            data.withUnsafeBytes { inPtr in
                key.withUnsafeBytes { keyPtr in
                    iv.withUnsafeBytes { ivPtr in
                        CCCrypt(operation, CCAlgorithm(kCCAlgorithmAES), CCOptions(0),
                                keyPtr.baseAddress, key.count, ivPtr.baseAddress,
                                inPtr.baseAddress, data.count,
                                outPtr.baseAddress, outputCount, &moved)
                    }
                }
            }
        }
        guard status == kCCSuccess, moved == data.count else { throw BroadlinkError.invalidResponse }
        return output
    }
}
