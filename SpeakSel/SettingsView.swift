import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var revealKey = false

    var body: some View {
        Form {
            Section("ElevenLabs") {
                if revealKey {
                    TextField("API key", text: $model.apiKeyDraft)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: model.apiKeyDraft) { _, _ in model.saveAPIKey() }
                } else {
                    SecureField("API key", text: $model.apiKeyDraft)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: model.apiKeyDraft) { _, _ in model.saveAPIKey() }
                }
                Toggle("Show key", isOn: $revealKey)
                Link("Get an API key", destination: URL(string: "https://elevenlabs.io/app/settings/api-keys")!)
            }

            Section("Voice") {
                Picker("Voice", selection: voiceBinding) {
                    if model.voices.isEmpty {
                        Text(model.settings.voiceName).tag(model.settings.voiceId)
                    }
                    ForEach(model.voices) { voice in
                        Text(voiceLabel(voice)).tag(voice.voiceId)
                    }
                }
                Picker("Model", selection: $model.settings.model) {
                    ForEach(TTSModel.allCases) { item in
                        Text(item.title).tag(item)
                    }
                }
                HStack {
                    Text("Speed")
                    Slider(value: $model.settings.speed, in: 0.7...1.2, step: 0.05)
                    Text(String(format: "%.2f×", model.settings.speed))
                        .monospacedDigit()
                        .frame(width: 52, alignment: .trailing)
                }
                HStack {
                    Button("Refresh voices") {
                        Task { await model.refreshVoices() }
                    }
                    .disabled(!model.hasAPIKey || model.isLoadingVoices)
                    if model.isLoadingVoices {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                if let voicesError = model.voicesError {
                    Text(voicesError)
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }

            Section("Hotkeys") {
                LabeledContent("Speak") {
                    HotkeyRecorder(combo: $model.settings.hotkey)
                }
                .onChange(of: model.settings.hotkey) { _, _ in
                    model.registerHotkey()
                }
                LabeledContent("Stop") {
                    HotkeyRecorder(combo: $model.settings.stopHotkey)
                }
                .onChange(of: model.settings.stopHotkey) { _, _ in
                    model.registerHotkey()
                }
                Text("Select text, then press \(model.settings.hotkey.displayString) to read. Press \(model.settings.stopHotkey.displayString) to stop. The speak key also stops if something is already playing.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }

            Section("Permissions") {
                LabeledContent("Accessibility") {
                    Text(model.accessibilityTrusted ? "Granted" : "Required")
                        .foregroundStyle(model.accessibilityTrusted ? .green : .orange)
                }
                Button("Open Accessibility settings") {
                    model.requestAccessibility()
                }
                Text("SpeakSel needs Accessibility so it can read highlighted text in Terminal, browsers, and other apps.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }

            Section("General") {
                Toggle("Launch at login", isOn: $model.settings.launchAtLogin)
                    .onChange(of: model.settings.launchAtLogin) { _, _ in
                        model.applyLaunchAtLogin()
                    }
                LabeledContent("Status") {
                    Text(model.statusText)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Button("Test voice") {
                    model.playTestPhrase()
                }
                .disabled(!model.hasAPIKey || model.isSpeaking || model.isSynthesizing)
                if model.isSpeaking || model.isSynthesizing {
                    Button("Stop", role: .destructive) {
                        model.stopSpeaking()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 420, idealWidth: 460)
        .onAppear {
            model.refreshAccessibility()
            if model.voices.isEmpty, model.hasAPIKey {
                Task { await model.refreshVoices() }
            }
        }
    }

    private var voiceBinding: Binding<String> {
        Binding(
            get: { model.settings.voiceId },
            set: { newId in
                model.settings.voiceId = newId
                if let voice = model.voices.first(where: { $0.voiceId == newId }) {
                    model.settings.voiceName = voice.name
                }
            }
        )
    }

    private func voiceLabel(_ voice: ElevenLabsVoice) -> String {
        if let category = voice.category, !category.isEmpty, category != "premade" {
            return "\(voice.name) (\(category))"
        }
        return voice.name
    }
}

struct HotkeyRecorder: View {
    @Binding var combo: HotkeyCombo
    @State private var recording = false

    var body: some View {
        HStack {
            Text(recording ? "Press a shortcut…" : combo.displayString)
                .font(.body.monospaced())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(recording ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            Button(recording ? "Cancel" : "Change") {
                recording.toggle()
            }
            KeyCatcher(isRecording: $recording, combo: $combo)
                .frame(width: 1, height: 1)
        }
    }
}

private struct KeyCatcher: NSViewRepresentable {
    @Binding var isRecording: Bool
    @Binding var combo: HotkeyCombo

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        view.onCombo = { recorded in
            combo = recorded
            isRecording = false
        }
        view.onCancel = {
            isRecording = false
        }
        return view
    }

    func updateNSView(_ nsView: RecorderView, context: Context) {
        nsView.onCombo = { recorded in
            combo = recorded
            isRecording = false
        }
        nsView.onCancel = {
            isRecording = false
        }
        nsView.recording = isRecording
        if isRecording {
            DispatchQueue.main.async {
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }

    final class RecorderView: NSView {
        var recording = false
        var onCombo: ((HotkeyCombo) -> Void)?
        var onCancel: (() -> Void)?

        override var acceptsFirstResponder: Bool { true }

        override func keyDown(with event: NSEvent) {
            guard recording else {
                super.keyDown(with: event)
                return
            }
            if event.keyCode == 53 {
                onCancel?()
                return
            }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let carbon = HotkeyCombo.carbonModifiers(
                command: flags.contains(.command),
                shift: flags.contains(.shift),
                option: flags.contains(.option),
                control: flags.contains(.control)
            )
            let recorded = HotkeyCombo(keyCode: UInt32(event.keyCode), carbonModifiers: carbon)
            guard recorded.hasModifier else { return }
            onCombo?(recorded)
        }
    }
}
