import XCTest
@testable import SpeakSel

final class SelectionCaptureTests: XCTestCase {
    func testSecureFieldRecognizesSubrole() {
        XCTAssertTrue(AccessibilitySupport.isSecureField(role: "AXTextField", subrole: "AXSecureTextField"))
    }

    func testSecureFieldRecognizesRole() {
        XCTAssertTrue(AccessibilitySupport.isSecureField(role: "AXSecureTextField", subrole: nil))
    }

    func testOrdinaryTextFieldIsNotSecure() {
        XCTAssertFalse(AccessibilitySupport.isSecureField(role: "AXTextField", subrole: nil))
        XCTAssertFalse(AccessibilitySupport.isSecureField(role: "AXTextArea", subrole: "AXInlineText"))
    }

    func testClassifiesTerminalEmulators() {
        XCTAssertEqual(TUISelectionPolicy.classify(bundleID: "com.apple.Terminal"), .terminalEmulator)
        XCTAssertEqual(TUISelectionPolicy.classify(bundleID: "com.googlecode.iterm2"), .terminalEmulator)
        XCTAssertEqual(TUISelectionPolicy.classify(bundleID: "com.mitchellh.ghostty"), .terminalEmulator)
        XCTAssertEqual(TUISelectionPolicy.classify(bundleID: "net.kovidgoyal.kitty"), .terminalEmulator)
        XCTAssertEqual(TUISelectionPolicy.classify(bundleID: "dev.warp.Warp-Stable"), .terminalEmulator)
    }

    func testClassifiesIDEsThatHostClaudeCode() {
        XCTAssertEqual(TUISelectionPolicy.classify(bundleID: "com.todesktop.230313mzl4w4u92"), .ide)
        XCTAssertEqual(TUISelectionPolicy.classify(bundleID: "com.microsoft.VSCode"), .ide)
        XCTAssertEqual(TUISelectionPolicy.classify(bundleID: "com.apple.dt.Xcode"), .ide)
        XCTAssertEqual(TUISelectionPolicy.classify(bundleID: "dev.zed.Zed"), .ide)
    }

    func testClassifiesBrowsersAsOther() {
        XCTAssertEqual(TUISelectionPolicy.classify(bundleID: "com.google.Chrome"), .other)
        XCTAssertEqual(TUISelectionPolicy.classify(bundleID: "com.apple.Safari"), .other)
        XCTAssertEqual(TUISelectionPolicy.classify(bundleID: nil), .other)
    }

    func testTUICopyChordOnlyInTerminalsOrAfterIDEGesture() {
        XCTAssertTrue(TUISelectionPolicy.shouldTryTUICopy(kind: .terminalEmulator, recentSelectionGesture: false))
        XCTAssertTrue(TUISelectionPolicy.shouldTryTUICopy(kind: .ide, recentSelectionGesture: true))
        XCTAssertFalse(TUISelectionPolicy.shouldTryTUICopy(kind: .ide, recentSelectionGesture: false))
        XCTAssertFalse(TUISelectionPolicy.shouldTryTUICopy(kind: .other, recentSelectionGesture: true))
    }

    func testCopyOnSelectRequiresGestureThenClipboardWrite() {
        let now = Date()
        let mouseUp = now.addingTimeInterval(-1)
        let pbcopy = now.addingTimeInterval(-0.9)
        XCTAssertTrue(
            TUISelectionPolicy.shouldUseCopyOnSelectClipboard(
                now: now,
                pasteboardChangedAt: pbcopy,
                selectionGestureAt: mouseUp
            )
        )
    }

    func testCopyOnSelectAllowsPbcopySlightlyBeforeMouseUpHandler() {
        let now = Date()
        let mouseUp = now.addingTimeInterval(-1)
        let pbcopy = mouseUp.addingTimeInterval(-0.2)
        XCTAssertTrue(
            TUISelectionPolicy.shouldUseCopyOnSelectClipboard(
                now: now,
                pasteboardChangedAt: pbcopy,
                selectionGestureAt: mouseUp
            )
        )
    }

    func testCopyOnSelectIgnoresClipboardWithoutAHighlight() {
        let now = Date()
        XCTAssertFalse(
            TUISelectionPolicy.shouldUseCopyOnSelectClipboard(
                now: now,
                pasteboardChangedAt: now.addingTimeInterval(-2),
                selectionGestureAt: nil
            )
        )
    }

    func testCopyOnSelectIgnoresStaleClipboardFromEarlierCopy() {
        let now = Date()
        let mouseUp = now.addingTimeInterval(-1)
        let oldCopy = now.addingTimeInterval(-30)
        XCTAssertFalse(
            TUISelectionPolicy.shouldUseCopyOnSelectClipboard(
                now: now,
                pasteboardChangedAt: oldCopy,
                selectionGestureAt: mouseUp
            )
        )
    }

    func testTranslocatedPathDetection() {
        XCTAssertTrue(AppIdentity.isTranslocated(path: "/private/var/folders/xx/AppTranslocation/ABC/d/SpeakSel.app"))
        XCTAssertFalse(AppIdentity.isTranslocated(path: "/Applications/SpeakSel.app"))
    }

    func testPermissionHintForStaleAccessibilityRow() {
        let hint = AppIdentity.permissionMismatchHint(
            runningPath: "/Applications/SpeakSel.app",
            translocated: false
        )
        XCTAssertTrue(hint.contains("/Applications/SpeakSel.app"))
        XCTAssertTrue(hint.contains("older signed copy"))
    }

    func testPermissionHintForQuarantinedCopy() {
        let hint = AppIdentity.permissionMismatchHint(
            runningPath: "/private/var/folders/xx/AppTranslocation/ABC/d/SpeakSel.app",
            translocated: true
        )
        XCTAssertTrue(hint.contains("xattr -cr"))
    }

    func testCopyOnSelectExpiresAfterRecencyWindow() {
        let now = Date()
        let mouseUp = now.addingTimeInterval(-60)
        let pbcopy = now.addingTimeInterval(-59.5)
        XCTAssertFalse(
            TUISelectionPolicy.shouldUseCopyOnSelectClipboard(
                now: now,
                pasteboardChangedAt: pbcopy,
                selectionGestureAt: mouseUp
            )
        )
    }
}
