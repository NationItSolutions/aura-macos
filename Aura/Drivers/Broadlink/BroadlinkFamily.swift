import Foundation

/// Familia de control remoto Broadlink. Define el formato del payload de comandos.
/// Tabla tomada de python-broadlink 0.19.0 (`broadlink/__init__.py`, SUPPORTED_TYPES).
enum BroadlinkFamily: String, Codable, Sendable, Hashable {
    /// RM mini 3 (firmware viejo): payload = comando (u32 LE) + datos.
    case rmMini
    /// RM pro / pro+ / plus: igual que rmMini, con RF.
    case rmPro
    /// RM mini 3 (firmware nuevo): payload con prefijo de longitud (u16 LE).
    case rmMiniB
    /// RM4 mini / RM4C mini / RM4 TV mate: con prefijo de longitud.
    case rm4Mini
    /// RM4 pro / RM4C pro: con prefijo de longitud y RF.
    case rm4Pro

    init?(deviceType: UInt16) {
        guard let entry = Self.table[deviceType] else { return nil }
        self = entry.family
    }

    /// RM4 y RM mini 3 nuevo anteponen la longitud del payload.
    var usesLengthPrefix: Bool {
        switch self {
        case .rmMiniB, .rm4Mini, .rm4Pro: true
        case .rmMini, .rmPro: false
        }
    }

    /// Modelos con radio de 433/315 MHz.
    var supportsRF: Bool {
        switch self {
        case .rmPro, .rm4Pro: true
        case .rmMini, .rmMiniB, .rm4Mini: false
        }
    }

    static func modelName(for deviceType: UInt16) -> String? {
        table[deviceType]?.model
    }

    private static let table: [UInt16: (family: BroadlinkFamily, model: String)] = [
        // rmmini
        0x2737: (.rmMini, "RM mini 3"), 0x278F: (.rmMini, "RM mini"), 0x27B7: (.rmMini, "RM mini 3"),
        0x27C2: (.rmMini, "RM mini 3"), 0x27C7: (.rmMini, "RM mini 3"), 0x27CC: (.rmMini, "RM mini 3"),
        0x27CD: (.rmMini, "RM mini 3"), 0x27D0: (.rmMini, "RM mini 3"), 0x27D1: (.rmMini, "RM mini 3"),
        0x27D3: (.rmMini, "RM mini 3"), 0x27DC: (.rmMini, "RM mini 3"), 0x27DE: (.rmMini, "RM mini 3"),
        // rmpro
        0x2712: (.rmPro, "RM pro/pro+"), 0x272A: (.rmPro, "RM pro"), 0x273D: (.rmPro, "RM pro"),
        0x277C: (.rmPro, "RM home"), 0x2783: (.rmPro, "RM home"), 0x2787: (.rmPro, "RM pro"),
        0x278B: (.rmPro, "RM plus"), 0x2797: (.rmPro, "RM pro+"), 0x279D: (.rmPro, "RM pro+"),
        0x27A1: (.rmPro, "RM plus"), 0x27A6: (.rmPro, "RM plus"), 0x27A9: (.rmPro, "RM pro+"),
        0x27C3: (.rmPro, "RM pro+"),
        // rmminib
        0x5F36: (.rmMiniB, "RM mini 3"), 0x6507: (.rmMiniB, "RM mini 3"), 0x6508: (.rmMiniB, "RM mini 3"),
        // rm4mini
        0x51DA: (.rm4Mini, "RM4 mini"), 0x5209: (.rm4Mini, "RM4 TV mate"), 0x520C: (.rm4Mini, "RM4 mini"),
        0x520D: (.rm4Mini, "RM4C mini"), 0x5211: (.rm4Mini, "RM4C mate"), 0x5212: (.rm4Mini, "RM4 TV mate"),
        0x5216: (.rm4Mini, "RM4 mini"), 0x521C: (.rm4Mini, "RM4 mini"), 0x6070: (.rm4Mini, "RM4C mini"),
        0x610E: (.rm4Mini, "RM4 mini"), 0x610F: (.rm4Mini, "RM4C mini"), 0x62BC: (.rm4Mini, "RM4 mini"),
        0x62BE: (.rm4Mini, "RM4C mini"), 0x6364: (.rm4Mini, "RM4S"), 0x648D: (.rm4Mini, "RM4 mini"),
        0x6539: (.rm4Mini, "RM4C mini"), 0x653A: (.rm4Mini, "RM4 mini"),
        // rm4pro
        0x520B: (.rm4Pro, "RM4 pro"), 0x5213: (.rm4Pro, "RM4 pro"), 0x5218: (.rm4Pro, "RM4C pro"),
        0x6026: (.rm4Pro, "RM4 pro"), 0x6184: (.rm4Pro, "RM4C pro"), 0x61A2: (.rm4Pro, "RM4 pro"),
        0x649B: (.rm4Pro, "RM4 pro"), 0x653C: (.rm4Pro, "RM4 pro"),
    ]
}
