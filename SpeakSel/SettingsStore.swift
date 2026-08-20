import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    private enum Keys {
        static let voiceId = "speaksel.voiceId"
        static let voiceName = "speaksel.voiceName"
        static let model = "speaksel.model"
        static let speed = "speaksel.speed"
        static let hotkeyKeyCode = "speaksel.hotkeyKeyCode"
        static let hotkeyModifiers = "speaksel.hotkeyModifiers"
        static let launchAtLogin = "speaksel.launchAtLogin"
        static let cachedVoices = "speaksel.cachedVoices"
    }

    @Published var voiceId: String {
        didSet { UserDefaults.standard.set(voiceId, forKey: Keys.voiceId) }
    }

    @Published var voiceName: String {
        didSet { UserDefaults.standard.set(voiceName, forKey: Keys.voiceName) }
    }

    @Published var model: TTSModel {
        didSet { UserDefaults.standard.set(model.rawValue, forKey: Keys.model) }
    }

    @Published var speed: Double {
        didSet { UserDefaults.standard.set(speed, forKey: Keys.speed) }
    }

    @Published var hotkey: HotkeyCombo {
        didSet {
            UserDefaults.standard.set(Int(hotkey.keyCode), forKey: Keys.hotkeyKeyCode)
            UserDefaults.standard.set(Int(hotkey.carbonModifiers), forKey: Keys.hotkeyModifiers)
        }
    }

    @Published var launchAtLogin: Bool {
        didSet { UserDefaults.standard.set(launchAtLogin, forKey: Keys.launchAtLogin) }
    }

    init(defaults: UserDefaults = .standard) {
        voiceId = defaults.string(forKey: Keys.voiceId) ?? ElevenLabsClient.defaultVoiceId
        voiceName = defaults.string(forKey: Keys.voiceName) ?? ElevenLabsClient.defaultVoiceName
        if let raw = defaults.string(forKey: Keys.model), let parsed = TTSModel(rawValue: raw) {
            model = parsed
        } else {
            model = .flash
        }
        let storedSpeed = defaults.object(forKey: Keys.speed) as? Double ?? 1.0
        speed = min(1.2, max(0.7, storedSpeed))
        if defaults.object(forKey: Keys.hotkeyKeyCode) != nil {
            hotkey = HotkeyCombo(
                keyCode: UInt32(defaults.integer(forKey: Keys.hotkeyKeyCode)),
                carbonModifiers: UInt32(defaults.integer(forKey: Keys.hotkeyModifiers))
            )
        } else {
            hotkey = .default
        }
        launchAtLogin = defaults.bool(forKey: Keys.launchAtLogin)
    }

    func cacheVoices(_ voices: [ElevenLabsVoice]) {
        if let data = try? JSONEncoder().encode(voices) {
            UserDefaults.standard.set(data, forKey: Keys.cachedVoices)
        }
    }

    func cachedVoices() -> [ElevenLabsVoice] {
        guard let data = UserDefaults.standard.data(forKey: Keys.cachedVoices) else { return [] }
        return (try? JSONDecoder().decode([ElevenLabsVoice].self, from: data)) ?? []
    }
}
