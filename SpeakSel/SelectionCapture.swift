import AppKit
import ApplicationServices

enum SelectionCaptureError: LocalizedError, Equatable {
    case accessibilityDenied
    case secureField
    case empty

    var errorDescription: String? {
        switch self {
        case .accessibilityDenied:
            return "Grant SpeakSel Accessibility access to read highlighted text."
        case .secureField:
            return "Won’t read a password field."
        case .empty:
            return "No text selected."
        }
    }
}

enum SelectionCapture {
    static func selectedText() throws -> String {
        guard AccessibilitySupport.isTrusted(prompt: false) else {
            throw SelectionCaptureError.accessibilityDenied
        }

        if AccessibilitySupport.focusedElementIsSecureField() {
            throw SelectionCaptureError.secureField
        }

        if let ax = axSelectedText()?.trimmingCharacters(in: .whitespacesAndNewlines), !ax.isEmpty {
            return ax
        }

        if let copied = copySelectedText()?.trimmingCharacters(in: .whitespacesAndNewlines), !copied.isEmpty {
            return copied
        }

        throw SelectionCaptureError.empty
    }

    static func axSelectedText() -> String? {
        let systemWide = AXUIElementCreateSystemWide()

        var focused: CFTypeRef?
        let focusedStatus = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        )
        if focusedStatus == .success, let focused {
            if let text = selectedText(from: focused as! AXUIElement), !text.isEmpty {
                return text
            }
        }

        var app: CFTypeRef?
        let appStatus = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &app
        )
        if appStatus == .success, let app {
            var appFocused: CFTypeRef?
            let inner = AXUIElementCopyAttributeValue(
                app as! AXUIElement,
                kAXFocusedUIElementAttribute as CFString,
                &appFocused
            )
            if inner == .success, let appFocused {
                if let text = selectedText(from: appFocused as! AXUIElement), !text.isEmpty {
                    return text
                }
            }
        }

        return nil
    }

    private static func selectedText(from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value)
        guard status == .success else { return nil }
        return value as? String
    }

    /// Fallback used by Terminal, Chrome, VS Code, and other apps that don't
    /// expose AXSelectedText. Copies the current selection with Cmd+C, then
    /// restores the previous pasteboard.
    static func copySelectedText(timeout: TimeInterval = 0.45) -> String? {
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(pasteboard: pasteboard)
        let changeCount = pasteboard.changeCount

        postCommandC()

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if pasteboard.changeCount != changeCount { break }
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
        }

        let text: String?
        if pasteboard.changeCount != changeCount {
            text = pasteboard.string(forType: .string)
        } else {
            text = nil
        }

        snapshot.restore(to: pasteboard)
        return text
    }

    private static func postCommandC() {
        let source = CGEventSource(stateID: .hidSystemState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(CarbonHotkey.keyANSI_C), keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(CarbonHotkey.keyANSI_C), keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}

struct PasteboardSnapshot {
    private let items: [[NSPasteboard.PasteboardType: Data]]

    init(pasteboard: NSPasteboard = .general) {
        items = pasteboard.pasteboardItems?.map { item in
            var dict: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    dict[type] = data
                }
            }
            return dict
        } ?? []
    }

    func restore(to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        guard !items.isEmpty else { return }
        let restored: [NSPasteboardItem] = items.map { dict in
            let item = NSPasteboardItem()
            for (type, data) in dict {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(restored)
    }
}

enum AccessibilitySupport {
    static func isTrusted(prompt: Bool) -> Bool {
        if prompt {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            return AXIsProcessTrustedWithOptions(options)
        }
        return AXIsProcessTrusted()
    }

    static func requestTrust() {
        _ = isTrusted(prompt: true)
    }

    static func openSystemSettings() {
        let urls = [
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity?Privacy_Accessibility"
        ]
        for string in urls {
            if let url = URL(string: string), NSWorkspace.shared.open(url) {
                return
            }
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }

    static func focusedElementIsSecureField() -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        )
        guard status == .success, let focused else { return false }
        let element = focused as! AXUIElement
        let role = stringAttribute(kAXRoleAttribute as String, of: element)
        let subrole = stringAttribute(kAXSubroleAttribute as String, of: element)
        return isSecureField(role: role, subrole: subrole)
    }

    /// Password fields are `AXTextField` with subrole `AXSecureTextField`.
    /// Some web views still report the secure name as the role.
    static func isSecureField(role: String?, subrole: String?) -> Bool {
        let secure = kAXSecureTextFieldSubrole as String
        return role == secure || subrole == secure
    }

    private static func stringAttribute(_ name: String, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, name as CFString, &value)
        guard status == .success else { return nil }
        return value as? String
    }
}
