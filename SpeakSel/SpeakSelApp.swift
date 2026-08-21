import SwiftUI
import AppKit

@main
struct SpeakSelApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @ObservedObject private var model = AppModel.shared

    var body: some Scene {
        MenuBarExtra {
            Button("Speak Selection") {
                model.speakSelection()
            }
            Button("Stop", action: model.stopSpeaking)
                .disabled(!model.isSpeaking && !model.isSynthesizing)
            Divider()
            Button("Settings…") {
                model.openSettings()
            }
            Divider()
            Button("Quit SpeakSel") {
                model.quit()
            }
        } label: {
            if model.menuBarShowsSlash {
                Image(systemName: "speaker.slash")
            } else {
                Image("MenuBarIcon")
                    .renderingMode(.template)
            }
        }
        .menuBarExtraStyle(.menu)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hosted unit tests launch SpeakSel.app; don't open Settings or TCC prompts.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return
        }
        NSApp.setActivationPolicy(.accessory)
        AppModel.shared.start()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppModel.shared.openSettings()
        return true
    }
}
