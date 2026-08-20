import XCTest
@testable import SpeakSel

final class HotkeyComboTests: XCTestCase {
    func testDefaultDisplayString() {
        XCTAssertEqual(HotkeyCombo.default.displayString, "⌃⌥R")
        XCTAssertTrue(HotkeyCombo.default.hasModifier)
    }

    func testModifierOrderAndKeyNames() {
        let combo = HotkeyCombo(
            keyCode: CarbonHotkey.keySpace,
            carbonModifiers: CarbonHotkey.command | CarbonHotkey.shift
        )
        XCTAssertEqual(combo.displayString, "⇧⌘Space")
    }

    func testCarbonModifierBuilder() {
        let mods = HotkeyCombo.carbonModifiers(command: true, shift: false, option: true, control: true)
        XCTAssertEqual(mods, CarbonHotkey.command | CarbonHotkey.option | CarbonHotkey.control)
        XCTAssertEqual(mods & CarbonHotkey.shift, 0)
    }

    func testBareKeyHasNoModifier() {
        let combo = HotkeyCombo(keyCode: CarbonHotkey.keyANSI_S, carbonModifiers: 0)
        XCTAssertFalse(combo.hasModifier)
        XCTAssertEqual(combo.displayString, "S")
    }

    func testRoundTripCodable() throws {
        let data = try JSONEncoder().encode(HotkeyCombo.default)
        let decoded = try JSONDecoder().decode(HotkeyCombo.self, from: data)
        XCTAssertEqual(decoded, .default)
    }

    func testModelIdentifiers() {
        XCTAssertEqual(TTSModel.flash.rawValue, "eleven_flash_v2_5")
        XCTAssertEqual(TTSModel.turbo.rawValue, "eleven_turbo_v2_5")
        XCTAssertEqual(TTSModel.multilingual.rawValue, "eleven_multilingual_v2")
        XCTAssertEqual(TTSModel.allCases.count, 3)
    }
}
