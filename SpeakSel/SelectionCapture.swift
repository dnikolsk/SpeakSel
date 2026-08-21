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
    static func startMonitoring() {
        SelectionCaptureMonitor.shared.start()
    }

    static func selectedText() throws -> String {
        guard AccessibilitySupport.isTrusted(prompt: false) else {
            throw SelectionCaptureError.accessibilityDenied
        }

        if AccessibilitySupport.focusedElementIsSecureField() {
            throw SelectionCaptureError.secureField
        }

        SelectionCaptureMonitor.shared.start()

        if let ax = axSelectedText()?.trimmingCharacters(in: .whitespacesAndNewlines), !ax.isEmpty {
            return ax
        }

        let monitor = SelectionCaptureMonitor.shared
        let focusedID = AccessibilitySupport.focusedAppBundleID()
        let kind = TUISelectionPolicy.classify(bundleID: focusedID)
        let recentGesture = monitor.hadRecentSelectionGesture()

        // Claude Code copies on mouse-up via pbcopy. That can land a moment
        // after the hotkey if the user speaks immediately after highlighting.
        if recentGesture {
            monitor.waitForPasteboardChange(timeout: 0.28)
        }

        if let clip = copyOnSelectClipboardIfAvailable() {
            return clip
        }

        let tryTUICopy = TUISelectionPolicy.shouldTryTUICopy(
            kind: kind,
            recentSelectionGesture: recentGesture
        )
        if let copied = copySelectedText(alsoTryTUICopy: tryTUICopy)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !copied.isEmpty {
            return copied
        }

        if let clip = copyOnSelectClipboardIfAvailable() {
            return clip
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

    private static func copyOnSelectClipboardIfAvailable() -> String? {
        guard TUISelectionPolicy.shouldUseCopyOnSelectClipboard(
            now: Date(),
            pasteboardChangedAt: SelectionCaptureMonitor.shared.lastPasteboardChange,
            selectionGestureAt: SelectionCaptureMonitor.shared.lastSelectionGestureAt
        ) else {
            return nil
        }
        let text = NSPasteboard.general.string(forType: .string)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let text, !text.isEmpty else { return nil }
        return text
    }

    /// Fallback used by Terminal, Chrome, VS Code, and other apps that don't
    /// expose AXSelectedText. Copies the current selection with Cmd+C, then
    /// restores the previous pasteboard.
    ///
    /// Fullscreen TUIs such as Claude Code often ignore Cmd+C (Terminal.app
    /// swallows it when there is no native selection). Those apps copy with
    /// Ctrl+Shift+C instead.
    static func copySelectedText(
        timeout: TimeInterval = 0.45,
        alsoTryTUICopy: Bool = false
    ) -> String? {
        waitForModifiersReleased()

        let pasteboard = NSPasteboard.general
        let originalCount = pasteboard.changeCount
        let snapshot = PasteboardSnapshot(pasteboard: pasteboard)
        var captured: String?

        defer {
            // Restore after a copy we triggered. If the pasteboard changed
            // without us capturing text, Claude Code's pbcopy likely won the
            // race — leave that selection on the clipboard.
            if captured != nil || pasteboard.changeCount == originalCount {
                snapshot.restore(to: pasteboard)
            }
        }

        let commandTimeout = alsoTryTUICopy ? min(timeout, 0.22) : timeout
        captured = copyWithChord(.commandC, timeout: commandTimeout)
        if captured == nil, alsoTryTUICopy {
            captured = copyWithChord(.controlShiftC, timeout: timeout)
        }
        return captured
    }

    private enum CopyChord {
        case commandC
        case controlShiftC

        var flags: CGEventFlags {
            switch self {
            case .commandC:
                return .maskCommand
            case .controlShiftC:
                return [.maskControl, .maskShift]
            }
        }
    }

    private static func copyWithChord(_ chord: CopyChord, timeout: TimeInterval) -> String? {
        let pasteboard = NSPasteboard.general
        let changeCount = pasteboard.changeCount
        postKey(CGKeyCode(CarbonHotkey.keyANSI_C), flags: chord.flags)

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if pasteboard.changeCount != changeCount { break }
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
        }

        guard pasteboard.changeCount != changeCount else { return nil }
        SelectionCaptureMonitor.shared.refreshPasteboardTimestamp()
        return pasteboard.string(forType: .string)
    }

    /// Carbon hotkeys fire while Control/Option are still held. TUIs match
    /// exact chords, so leftover modifiers make Cmd+C / Ctrl+Shift+C miss.
    static func waitForModifiersReleased(timeout: TimeInterval = 0.45) {
        let interesting: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if CGEventSource.flagsState(.hidSystemState).intersection(interesting).isEmpty {
                return
            }
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
        }
    }

    private static func postKey(_ key: CGKeyCode, flags: CGEventFlags) {
        // Private source so hardware Control/Option from the speak hotkey are
        // not merged into the synthesized copy chord.
        let source = CGEventSource(stateID: CGEventSourceStateID(rawValue: -1)!)

        func postModifier(_ modifierKey: UInt32, down: Bool, flags: CGEventFlags) {
            let event = CGEvent(
                keyboardEventSource: source,
                virtualKey: CGKeyCode(modifierKey),
                keyDown: down
            )
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
        }

        if flags.contains(.maskControl) {
            postModifier(CarbonHotkey.keyControl, down: true, flags: .maskControl)
        }
        if flags.contains(.maskShift) {
            postModifier(CarbonHotkey.keyShift, down: true, flags: flags.intersection([.maskControl, .maskShift]))
        }
        if flags.contains(.maskCommand) {
            postModifier(CarbonHotkey.keyCommand, down: true, flags: .maskCommand)
        }

        let down = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)

        if flags.contains(.maskCommand) {
            postModifier(CarbonHotkey.keyCommand, down: false, flags: [])
        }
        if flags.contains(.maskShift) {
            postModifier(CarbonHotkey.keyShift, down: false, flags: flags.intersection(.maskControl))
        }
        if flags.contains(.maskControl) {
            postModifier(CarbonHotkey.keyControl, down: false, flags: [])
        }
    }
}

/// Claude Code (and similar fullscreen TUIs) draw their own selection. That
/// highlight is not Terminal's native selection, so AXSelectedText is empty
/// and Cmd+C often does nothing. Default Claude Code copies on mouse-up
/// instead; with copy-on-select off it uses Ctrl+Shift+C.
enum TUISelectionPolicy {
    static let recencyWindow: TimeInterval = 45
    static let copyAfterGestureSlack: TimeInterval = 3

    enum AppKind: Equatable {
        case terminalEmulator
        case ide
        case other
    }

    static func classify(bundleID: String?) -> AppKind {
        guard let id = bundleID?.lowercased(), !id.isEmpty else { return .other }

        let terminals = [
            "com.apple.terminal",
            "iterm",
            "ghostty",
            "kitty",
            "alacritty",
            "wezterm",
            "warp",
            "hyper",
            "prompt",
            "tabby",
            "termius",
            "terminus",
            "contour",
            "waveterm",
            "rio.app",
            "com.raphaelamorim.rio"
        ]
        if terminals.contains(where: { id.contains($0) }) {
            return .terminalEmulator
        }

        let ides = [
            "vscode",
            "vscodium",
            "todesktop",
            "com.cursor",
            "com.apple.dt.xcode",
            "jetbrains",
            "dev.zed",
            "com.zed",
            "sublime"
        ]
        if ides.contains(where: { id.contains($0) }) {
            return .ide
        }

        return .other
    }

    static func shouldTryTUICopy(kind: AppKind, recentSelectionGesture: Bool) -> Bool {
        switch kind {
        case .terminalEmulator:
            return true
        case .ide:
            return recentSelectionGesture
        case .other:
            return false
        }
    }

    /// True when a mouse highlight was followed by a clipboard write — the
    /// Claude Code copy-on-select path. Regular Cmd+C in another app is not
    /// enough on its own, so we do not speak stale clipboard contents.
    static func shouldUseCopyOnSelectClipboard(
        now: Date,
        pasteboardChangedAt: Date?,
        selectionGestureAt: Date?,
        recencyWindow: TimeInterval = recencyWindow,
        copyAfterGestureSlack: TimeInterval = copyAfterGestureSlack
    ) -> Bool {
        guard let pasteboardChangedAt, let selectionGestureAt else { return false }
        guard now.timeIntervalSince(pasteboardChangedAt) <= recencyWindow else { return false }
        guard now.timeIntervalSince(selectionGestureAt) <= recencyWindow else { return false }
        let delta = pasteboardChangedAt.timeIntervalSince(selectionGestureAt)
        return delta >= -0.5 && delta <= copyAfterGestureSlack
    }
}

final class SelectionCaptureMonitor {
    static let shared = SelectionCaptureMonitor()

    private(set) var lastPasteboardChange: Date?
    private(set) var lastSelectionGestureAt: Date?
    private var lastChangeCount: Int = 0
    private var dragOrigin: CGPoint?
    private var dragDistance: CGFloat = 0
    private var monitors: [Any] = []
    private var timer: Timer?
    private var started = false

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        lastChangeCount = NSPasteboard.general.changeCount

        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            self?.pollPasteboard()
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }

        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.handleMouse(event)
        }) {
            monitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] event in
            self?.handleMouse(event)
            return event
        }) {
            monitors.append(monitor)
        }
    }

    func hadRecentSelectionGesture(now: Date = Date(), window: TimeInterval = TUISelectionPolicy.recencyWindow) -> Bool {
        guard let lastSelectionGestureAt else { return false }
        return now.timeIntervalSince(lastSelectionGestureAt) <= window
    }

    func refreshPasteboardTimestamp() {
        pollPasteboard()
    }

    func waitForPasteboardChange(timeout: TimeInterval) {
        let baseline = NSPasteboard.general.changeCount
        pollPasteboard()
        if NSPasteboard.general.changeCount != baseline { return }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
            pollPasteboard()
            if NSPasteboard.general.changeCount != baseline { return }
        }
    }

    private func pollPasteboard() {
        let count = NSPasteboard.general.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        lastPasteboardChange = Date()
    }

    private func handleMouse(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            dragOrigin = event.locationInWindow
            dragDistance = 0
        case .leftMouseDragged:
            if let dragOrigin {
                let point = event.locationInWindow
                dragDistance = max(
                    dragDistance,
                    hypot(point.x - dragOrigin.x, point.y - dragOrigin.y)
                )
            }
        case .leftMouseUp:
            // Claude Code copies on mouse-up for drag, double-click (word),
            // and triple-click (line). A plain click is not a selection.
            if dragDistance >= 4 || event.clickCount >= 2 {
                lastSelectionGestureAt = Date()
                pollPasteboard()
            }
            dragOrigin = nil
            dragDistance = 0
        default:
            break
        }
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

    static func focusedAppBundleID() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var app: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &app
        )
        if status == .success, let app {
            var pid: pid_t = 0
            if AXUIElementGetPid(app as! AXUIElement, &pid) == .success {
                if let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier {
                    return bundleID
                }
            }
        }
        return NSWorkspace.shared.frontmostApplication?.bundleIdentifier
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
