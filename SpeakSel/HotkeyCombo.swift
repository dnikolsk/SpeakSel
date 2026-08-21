import Foundation

/// Carbon modifier bits and virtual key codes, kept as numeric constants so
/// display/parsing logic can be tested without linking Carbon.
enum CarbonHotkey {
    static let command: UInt32 = 256      // cmdKey
    static let shift: UInt32 = 512        // shiftKey
    static let option: UInt32 = 2048      // optionKey
    static let control: UInt32 = 4096     // controlKey

    static let keyANSI_C: UInt32 = 0x08
    static let keyANSI_R: UInt32 = 0x0F
    static let keyANSI_S: UInt32 = 0x01
    static let keySpace: UInt32 = 0x31
}

struct HotkeyCombo: Equatable, Codable, Hashable {
    var keyCode: UInt32
    var carbonModifiers: UInt32

    static let `default` = HotkeyCombo(
        keyCode: CarbonHotkey.keyANSI_R,
        carbonModifiers: CarbonHotkey.control | CarbonHotkey.option
    )

    static let defaultStop = HotkeyCombo(
        keyCode: CarbonHotkey.keyANSI_S,
        carbonModifiers: CarbonHotkey.control | CarbonHotkey.option
    )

    var displayString: String {
        var parts: [String] = []
        if carbonModifiers & CarbonHotkey.control != 0 { parts.append("⌃") }
        if carbonModifiers & CarbonHotkey.option != 0 { parts.append("⌥") }
        if carbonModifiers & CarbonHotkey.shift != 0 { parts.append("⇧") }
        if carbonModifiers & CarbonHotkey.command != 0 { parts.append("⌘") }
        parts.append(Self.keyName(for: keyCode))
        return parts.joined()
    }

    var hasModifier: Bool {
        carbonModifiers & (CarbonHotkey.control | CarbonHotkey.option | CarbonHotkey.shift | CarbonHotkey.command) != 0
    }

    static func keyName(for keyCode: UInt32) -> String {
        let names: [UInt32: String] = [
            0x00: "A", 0x01: "S", 0x02: "D", 0x03: "F", 0x04: "H", 0x05: "G",
            0x06: "Z", 0x07: "X", 0x08: "C", 0x09: "V", 0x0B: "B", 0x0C: "Q",
            0x0D: "W", 0x0E: "E", 0x0F: "R", 0x10: "Y", 0x11: "T",
            0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4", 0x16: "6", 0x17: "5",
            0x18: "=", 0x19: "9", 0x1A: "7", 0x1B: "-", 0x1C: "8", 0x1D: "0",
            0x1E: "]", 0x1F: "O", 0x20: "U", 0x21: "[", 0x22: "I", 0x23: "P",
            0x25: "L", 0x26: "J", 0x27: "'", 0x28: "K", 0x29: ";",
            0x2A: "\\", 0x2B: ",", 0x2C: "/", 0x2D: "N", 0x2E: "M", 0x2F: ".",
            0x24: "↩", 0x30: "⇥", 0x31: "Space", 0x33: "⌫", 0x35: "⎋",
            0x7A: "F1", 0x78: "F2", 0x63: "F3", 0x76: "F4",
            0x60: "F5", 0x61: "F6", 0x62: "F7", 0x64: "F8",
            0x65: "F9", 0x6D: "F10", 0x67: "F11", 0x6F: "F12",
            0x7B: "←", 0x7C: "→", 0x7D: "↓", 0x7E: "↑"
        ]
        return names[keyCode] ?? "Key \(keyCode)"
    }

    static func carbonModifiers(command: Bool, shift: Bool, option: Bool, control: Bool) -> UInt32 {
        var mods: UInt32 = 0
        if command { mods |= CarbonHotkey.command }
        if shift { mods |= CarbonHotkey.shift }
        if option { mods |= CarbonHotkey.option }
        if control { mods |= CarbonHotkey.control }
        return mods
    }
}

enum TTSModel: String, CaseIterable, Identifiable, Codable {
    case flash = "eleven_flash_v2_5"
    case turbo = "eleven_turbo_v2_5"
    case multilingual = "eleven_multilingual_v2"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .flash: return "Flash (fastest)"
        case .turbo: return "Turbo (balanced)"
        case .multilingual: return "Multilingual v2 (highest quality)"
        }
    }
}
