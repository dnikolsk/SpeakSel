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
}
