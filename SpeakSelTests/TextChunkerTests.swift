import XCTest
@testable import SpeakSel

final class TextChunkerTests: XCTestCase {
    func testEmptyAndWhitespace() {
        XCTAssertEqual(TextChunker.chunks(from: ""), [])
        XCTAssertEqual(TextChunker.chunks(from: "   \n\t  "), [])
    }

    func testShortTextIsSingleChunk() {
        XCTAssertEqual(TextChunker.chunks(from: "  Hello there.  ", maxCharacters: 100), ["Hello there."])
    }

    func testSplitsOnSentenceBoundary() {
        let text = "First sentence. Second sentence is here. Third."
        let chunks = TextChunker.chunks(from: text, maxCharacters: 30)
        XCTAssertEqual(chunks, ["First sentence.", "Second sentence is here.", "Third."])
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 30 })
    }

    func testSplitsOnWhitespaceWhenNoSentence() {
        let text = "alpha beta gamma delta epsilon"
        let chunks = TextChunker.chunks(from: text, maxCharacters: 12)
        XCTAssertEqual(chunks, ["alpha beta", "gamma delta", "epsilon"])
    }

    func testHardSplitsWhenNoWhitespace() {
        let text = String(repeating: "a", count: 10)
        let chunks = TextChunker.chunks(from: text, maxCharacters: 4)
        XCTAssertEqual(chunks, ["aaaa", "aaaa", "aa"])
    }

    func testNeverEmitsEmptyChunksOrExceedsMax() {
        let text = "One. Two! Three?\nFour five six seven eight nine ten."
        let chunks = TextChunker.chunks(from: text, maxCharacters: 8)
        XCTAssertFalse(chunks.contains { $0.isEmpty })
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 8 })
        XCTAssertFalse(chunks.isEmpty)
    }
}
