import AppKit
import Carbon.HIToolbox

/// Atajo de teclado global: código de tecla virtual + modificadores de Carbon.
struct KeyShortcut: Codable, Sendable, Hashable {
    var keyCode: UInt32
    var carbonModifiers: UInt32

    /// ⌥⌘Espacio: abre o cierra la isla.
    static let defaultIsland = KeyShortcut(keyCode: UInt32(kVK_Space), carbonModifiers: UInt32(optionKey | cmdKey))
    /// ⌥⌘A: abre la ventana principal.
    static let defaultWindow = KeyShortcut(keyCode: UInt32(kVK_ANSI_A), carbonModifiers: UInt32(optionKey | cmdKey))

    /// ⌃⌥1…9 para las escenas favoritas.
    static func scene(_ index: Int) -> KeyShortcut? {
        let codes = [kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9]
        guard codes.indices.contains(index) else { return nil }
        return KeyShortcut(keyCode: UInt32(codes[index]), carbonModifiers: UInt32(controlKey | optionKey))
    }

    init(keyCode: UInt32, carbonModifiers: UInt32) {
        self.keyCode = keyCode
        self.carbonModifiers = carbonModifiers
    }

    /// Desde un evento de teclado. Exige al menos ⌘, ⌥ o ⌃ para no robar teclas comunes.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: UInt32 = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        guard modifiers != 0 else { return nil }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        self.init(keyCode: UInt32(event.keyCode), carbonModifiers: modifiers)
    }

    /// "⌥⌘Espacio"
    var displayString: String {
        var text = ""
        if carbonModifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if carbonModifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if carbonModifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if carbonModifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + Self.keyName(keyCode)
    }

    static func keyName(_ code: UInt32) -> String {
        let special: [Int: String] = [
            kVK_Space: String(localized: "Espacio"), kVK_Return: "↩", kVK_Escape: "⎋", kVK_Tab: "⇥",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        ]
        if let name = special[Int(code)] { return name }
        let letters: [Int: String] = [
            kVK_ANSI_A: "A", kVK_ANSI_B: "B", kVK_ANSI_C: "C", kVK_ANSI_D: "D", kVK_ANSI_E: "E", kVK_ANSI_F: "F",
            kVK_ANSI_G: "G", kVK_ANSI_H: "H", kVK_ANSI_I: "I", kVK_ANSI_J: "J", kVK_ANSI_K: "K", kVK_ANSI_L: "L",
            kVK_ANSI_M: "M", kVK_ANSI_N: "N", kVK_ANSI_O: "O", kVK_ANSI_P: "P", kVK_ANSI_Q: "Q", kVK_ANSI_R: "R",
            kVK_ANSI_S: "S", kVK_ANSI_T: "T", kVK_ANSI_U: "U", kVK_ANSI_V: "V", kVK_ANSI_W: "W", kVK_ANSI_X: "X",
            kVK_ANSI_Y: "Y", kVK_ANSI_Z: "Z", kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
            kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9",
        ]
        return letters[Int(code)] ?? "#\(code)"
    }
}

/// Atajos globales con `RegisterEventHotKey` de Carbon: funcionan con la app en segundo plano
/// y no necesitan permiso de Accesibilidad.
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var eventHandler: EventHandlerRef?
    private var nextID: UInt32 = 1
    private static let signature: OSType = 0x4155_5241 // "AURA"

    /// Registra un atajo. Devuelve `false` si el sistema u otra app ya lo usa.
    @discardableResult
    func register(_ shortcut: KeyShortcut, action: @escaping () -> Void) -> Bool {
        installHandlerIfNeeded()
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        let status = RegisterEventHotKey(shortcut.keyCode, shortcut.carbonModifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            Log.app.error("No se pudo registrar el atajo \(shortcut.displayString, privacy: .public): \(status)")
            return false
        }
        refs[id] = ref
        handlers[id] = action
        return true
    }

    func unregisterAll() {
        for ref in refs.values { UnregisterEventHotKey(ref) }
        refs.removeAll()
        handlers.removeAll()
    }

    fileprivate func fire(_ id: UInt32) {
        handlers[id]?()
    }

    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            let result = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard result == noErr else { return result }
            let id = hotKeyID.id
            Task { @MainActor in HotKeyCenter.shared.fire(id) }
            return noErr
        }, 1, &spec, nil, &eventHandler)
        if status != noErr { Log.app.error("No se pudo instalar el manejador de atajos: \(status)") }
    }
}
