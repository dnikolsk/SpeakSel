import AppKit
import Combine
import Foundation
import ServiceManagement
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var settings = SettingsStore()
    @Published var voices: [ElevenLabsVoice] = []
    @Published var isSpeaking = false
    @Published var isSynthesizing = false
    @Published var accessibilityTrusted = false
    @Published var apiKeyDraft = ""
    @Published var statusText = "Select text, then press the speak hotkey."
    @Published var isLoadingVoices = false
    @Published var voicesError: String?

    private let client = ElevenLabsClient()
    private let player = SpeechPlayer()
    private var speakTask: Task<Void, Never>?
    private var speakGeneration = 0
    private var settingsController: NSWindowController?
    private var settingsWindowDelegate = SettingsWindowDelegate()
    private var accessibilityTimer: Timer?
    private var started = false
    private var cancellables = Set<AnyCancellable>()

    private init() {
        settings.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    var menuBarShowsSlash: Bool {
        !hasAPIKey || !accessibilityTrusted
    }

    var hasAPIKey: Bool {
        !apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var storedAPIKey: String {
        apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func start() {
        guard !started else { return }
        started = true

        apiKeyDraft = KeychainStore.load() ?? ""
        voices = settings.cachedVoices()
        SelectionCapture.startMonitoring()
        refreshAccessibility()
        HotkeyManager.shared.onSpeak = { [weak self] in
            Task { @MainActor in
                self?.handleHotkey()
            }
        }
        HotkeyManager.shared.onStop = { [weak self] in
            Task { @MainActor in
                self?.handleStopHotkey()
            }
        }
        registerHotkey()
        applyLaunchAtLogin()

        accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshAccessibility()
            }
        }

        if hasAPIKey {
            Task { await refreshVoices() }
        }

        if !hasAPIKey || !accessibilityTrusted {
            openSettings()
            if !accessibilityTrusted {
                AccessibilitySupport.requestTrust()
                AccessibilitySupport.openSystemSettings()
            }
        }
    }

    func handleHotkey() {
        if isSpeaking || isSynthesizing {
            stopSpeaking()
            return
        }
        speakSelection()
    }

    func handleStopHotkey() {
        guard isSpeaking || isSynthesizing else { return }
        stopSpeaking()
    }

    func speakSelection() {
        do {
            let text = try SelectionCapture.selectedText()
            speak(text: text)
        } catch {
            statusText = error.localizedDescription
            HUD.show(error.localizedDescription)
            if error as? SelectionCaptureError == .accessibilityDenied {
                AccessibilitySupport.requestTrust()
                openSettings()
            }
        }
    }

    func speak(text: String) {
        let apiKey = storedAPIKey
        guard !apiKey.isEmpty else {
            statusText = ElevenLabsError.missingAPIKey.localizedDescription
            HUD.show(statusText)
            openSettings()
            return
        }

        let chunks = TextChunker.chunks(from: text)
        guard !chunks.isEmpty else {
            statusText = SelectionCaptureError.empty.localizedDescription
            HUD.show(statusText)
            return
        }

        speakTask?.cancel()
        player.stop()
        speakGeneration += 1
        let generation = speakGeneration

        let voiceId = settings.voiceId
        let modelId = settings.model.rawValue
        let speed = settings.speed

        isSynthesizing = true
        isSpeaking = true
        statusText = "Reading…"
        HUD.show("Reading…")

        speakTask = Task { [weak self] in
            guard let self else { return }
            defer {
                Task { @MainActor in
                    guard self.speakGeneration == generation else { return }
                    self.isSynthesizing = false
                    self.isSpeaking = false
                    if self.statusText == "Reading…" || self.statusText.hasPrefix("Reading ") {
                        self.statusText = "Select text, then press the speak hotkey."
                    }
                }
            }

            do {
                for (index, chunk) in chunks.enumerated() {
                    try Task.checkCancellation()
                    guard generation == self.speakGeneration else { return }
                    await MainActor.run {
                        self.isSynthesizing = true
                        if chunks.count > 1 {
                            self.statusText = "Reading \(index + 1)/\(chunks.count)…"
                        }
                    }
                    let previous = index > 0 ? String(chunks[index - 1].suffix(280)) : nil
                    let request = TTSRequest(
                        text: chunk,
                        voiceId: voiceId,
                        modelId: modelId,
                        speed: speed,
                        previousText: previous
                    )
                    let audio = try await self.client.synthesize(request, apiKey: apiKey)
                    try Task.checkCancellation()
                    guard generation == self.speakGeneration else { return }
                    await MainActor.run {
                        self.isSynthesizing = false
                        self.isSpeaking = true
                    }
                    do {
                        try await self.player.playAndWait(audio)
                    } catch is CancellationError {
                        return
                    }
                }
                await MainActor.run {
                    guard generation == self.speakGeneration else { return }
                    self.statusText = "Done"
                    HUD.show("Done")
                }
            } catch is CancellationError {
                return
            } catch {
                await MainActor.run {
                    guard generation == self.speakGeneration else { return }
                    self.statusText = error.localizedDescription
                    HUD.show(error.localizedDescription)
                }
            }
        }
    }

    func stopSpeaking() {
        speakGeneration += 1
        speakTask?.cancel()
        speakTask = nil
        player.stop()
        isSpeaking = false
        isSynthesizing = false
        statusText = "Stopped"
        HUD.show("Stopped")
    }

    func saveAPIKey() {
        let trimmed = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        apiKeyDraft = trimmed
        if trimmed.isEmpty {
            KeychainStore.delete()
        } else {
            _ = KeychainStore.save(trimmed)
        }
        objectWillChange.send()
    }

    func refreshVoices() async {
        let apiKey = storedAPIKey
        guard !apiKey.isEmpty else { return }
        isLoadingVoices = true
        voicesError = nil
        defer { isLoadingVoices = false }
        do {
            let loaded = try await client.listVoices(apiKey: apiKey)
            voices = loaded
            settings.cacheVoices(loaded)
            if !loaded.contains(where: { $0.voiceId == settings.voiceId }), let first = loaded.first {
                settings.voiceId = first.voiceId
                settings.voiceName = first.name
            }
        } catch {
            voicesError = error.localizedDescription
        }
    }

    func playTestPhrase() {
        speak(text: "Hello. SpeakSel is ready to read anything you highlight.")
    }

    func registerHotkey() {
        HotkeyManager.shared.register(speak: settings.hotkey, stop: settings.stopHotkey)
    }

    func refreshAccessibility() {
        accessibilityTrusted = AccessibilitySupport.isTrusted(prompt: false)
    }

    func requestAccessibility() {
        // Accessory (no Dock icon) apps otherwise fail to show the TCC prompt.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        AccessibilitySupport.requestTrust()
        AccessibilitySupport.openSystemSettings()
        refreshAccessibility()
    }

    func applyLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if settings.launchAtLogin {
                if service.status != .enabled {
                    try service.register()
                }
            } else if service.status == .enabled {
                try service.unregister()
            }
        } catch {
            statusText = "Could not update Login Items: \(error.localizedDescription)"
        }
    }

    func openSettings() {
        // Accessory apps otherwise fail to order a window in front of Terminal/Xcode.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let window = settingsController?.window {
            window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            window.makeKeyAndOrderFront(nil)
            return
        }

        let view = SettingsView()
            .environmentObject(self)
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "SpeakSel"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 460, height: 620))
        window.center()
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.delegate = settingsWindowDelegate
        let controller = NSWindowController(window: window)
        settingsController = controller
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    func quit() {
        accessibilityTimer?.invalidate()
        accessibilityTimer = nil
        stopSpeaking()
        HotkeyManager.shared.unregister()
        NSApp.terminate(nil)
    }
}

private final class SettingsWindowDelegate: NSObject, NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
