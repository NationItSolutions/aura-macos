import Foundation

/// Importa el `codigos.json` del prototipo en Python (`~/.ar-mac/codigos.json`).
///
/// Formato esperado:
/// ```json
/// { "ip": "192.168.x.x",
///   "codigos": { "off": "<base64>", "on": "<base64>", "frio_18": "<base64>" },
///   "led":     { "ligar": "<base64>", "azul": "<base64>" } }
/// ```
/// Es tolerante: secciones faltantes o entradas inválidas se omiten con un aviso.
enum LegacyCodesImporter {

    struct Result: Sendable, Equatable {
        var bridgeHost: String?
        var acCodes: [String: String]
        var ledCodes: [String: String]
        var warnings: [String]

        var isEmpty: Bool { bridgeHost == nil && acCodes.isEmpty && ledCodes.isEmpty }
    }

    enum ImportError: UserFacingError, Equatable {
        case unreadable
        case invalidJSON
        case notAnObject
        case nothingToImport

        var userMessage: String {
            switch self {
            case .unreadable: String(localized: "No se pudo leer el archivo.")
            case .invalidJSON: String(localized: "El archivo no es un JSON válido.")
            case .notAnObject: String(localized: "El archivo no tiene el formato de codigos.json.")
            case .nothingToImport: String(localized: "El archivo no tiene códigos para importar.")
            }
        }
    }

    /// Ruta del archivo del prototipo en la carpeta personal real del usuario
    /// (fuera del contenedor del sandbox).
    static var defaultURL: URL {
        URL(fileURLWithPath: realHomeDirectory, isDirectory: true)
            .appendingPathComponent(".ar-mac", isDirectory: true)
            .appendingPathComponent("codigos.json")
    }

    static var realHomeDirectory: String {
        if let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir {
            return String(cString: dir)
        }
        return NSHomeDirectory()
    }

    static func parse(_ data: Data) throws -> Result {
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw ImportError.invalidJSON
        }
        guard let root = object as? [String: Any] else { throw ImportError.notAnObject }

        var warnings: [String] = []
        var host: String?
        if let ip = root["ip"] as? String {
            let trimmed = ip.trimmingCharacters(in: .whitespacesAndNewlines)
            if isValidIPv4(trimmed) {
                host = trimmed
            } else {
                warnings.append(String(localized: "La IP \"\(trimmed)\" no es válida y se ignoró."))
            }
        }

        let ac = section(root["codigos"], name: "codigos", mapper: mapACName, warnings: &warnings)
        let led = section(root["led"], name: "led", mapper: mapLEDName, warnings: &warnings)

        let result = Result(bridgeHost: host, acCodes: ac, ledCodes: led, warnings: warnings)
        if result.acCodes.isEmpty && result.ledCodes.isEmpty && result.bridgeHost == nil {
            throw ImportError.nothingToImport
        }
        return result
    }

    private static func section(
        _ value: Any?,
        name: String,
        mapper: (String) -> String,
        warnings: inout [String]
    ) -> [String: String] {
        guard let value else { return [:] }
        guard let dict = value as? [String: Any] else {
            warnings.append(String(localized: "La sección \"\(name)\" no tiene el formato esperado y se omitió."))
            return [:]
        }
        var codes: [String: String] = [:]
        for key in dict.keys.sorted() {
            guard let raw = dict[key] as? String, isValidPacket(raw) else {
                warnings.append(String(localized: "El código \"\(key)\" de \"\(name)\" está vacío o dañado y se omitió."))
                continue
            }
            let mapped = mapper(key)
            if codes[mapped] != nil {
                warnings.append(String(localized: "El código \"\(key)\" se repite como \"\(mapped)\"; se usó el primero."))
                continue
            }
            codes[mapped] = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return codes
    }

    /// `off` → off, `on` → on, `frio_<t>` → `cool_<t>`. Lo demás conserva su nombre.
    static func mapACName(_ key: String) -> String {
        let lower = key.lowercased()
        if lower.hasPrefix("frio_"), let temp = Int(lower.dropFirst("frio_".count)) {
            return "cool_\(temp)"
        }
        return lower
    }

    /// `ligar` → power_on, `desligar` → power_off, `brilho_mais` → brightness_up,
    /// `brilho_menos` → brightness_down. Los colores conservan su nombre.
    static func mapLEDName(_ key: String) -> String {
        switch key.lowercased() {
        case "ligar": "power_on"
        case "desligar": "power_off"
        case "brilho_mais": "brightness_up"
        case "brilho_menos": "brightness_down"
        default: key.lowercased()
        }
    }

    /// Un paquete válido es base64 decodificable y no vacío.
    static func isValidPacket(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = Data(base64Encoded: trimmed) else { return false }
        return !data.isEmpty
    }

    static func isValidIPv4(_ value: String) -> Bool {
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return false }
        return parts.allSatisfy { part in
            guard !part.isEmpty, part.count <= 3, let number = Int(part) else { return false }
            return (0...255).contains(number)
        }
    }
}

extension AppStore {
    struct ImportSummary: Sendable, Equatable {
        var acCodes: Int
        var ledCodes: Int
        var warnings: [String]
    }

    /// Aplica un resultado de importación: crea o actualiza el puente, el aire y los LED.
    @discardableResult
    func apply(_ result: LegacyCodesImporter.Result) -> ImportSummary {
        var bridgeID = bridges.first?.id
        if let host = result.bridgeHost {
            if var bridge = bridges.first(where: { $0.host == host }) ?? bridges.first {
                bridge.host = host
                upsert(bridge)
                bridgeID = bridge.id
            } else {
                let bridge = Bridge(name: "Broadlink RM4 Mini", host: host)
                upsert(bridge)
                bridgeID = bridge.id
            }
        }

        if !result.acCodes.isEmpty {
            var ac = devices.first { $0.kind == .airConditioner }
                ?? Device(name: String(localized: "Aire"), kind: .airConditioner,
                          transport: .broadlink(bridgeID: bridgeID), isFavorite: true)
            ac.codes.merge(result.acCodes) { _, new in new }
            if ac.transport.bridgeID == nil { ac.transport = .broadlink(bridgeID: bridgeID) }
            upsert(ac)
        }

        if !result.ledCodes.isEmpty {
            var led = devices.first { $0.kind == .light }
                ?? Device(name: String(localized: "LED"), kind: .light,
                          transport: .broadlink(bridgeID: bridgeID), isFavorite: true)
            led.codes.merge(result.ledCodes) { _, new in new }
            if led.transport.bridgeID == nil { led.transport = .broadlink(bridgeID: bridgeID) }
            upsert(led)
        }

        return ImportSummary(acCodes: result.acCodes.count, ledCodes: result.ledCodes.count, warnings: result.warnings)
    }
}
