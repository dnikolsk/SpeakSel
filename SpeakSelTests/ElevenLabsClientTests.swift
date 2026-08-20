import XCTest
@testable import SpeakSel

final class ElevenLabsClientTests: XCTestCase {
    func testSynthesizeURLIncludesVoiceAndFormat() {
        let request = TTSRequest(
            text: "Hello",
            voiceId: "JBFqnCBsd6RMkjVDRZzb",
            modelId: TTSModel.flash.rawValue,
            speed: 1.0
        )
        let url = request.url()
        XCTAssertEqual(url.path, "/v1/text-to-speech/JBFqnCBsd6RMkjVDRZzb")
        XCTAssertEqual(url.host, "api.elevenlabs.io")
        XCTAssertTrue(url.query?.contains("output_format=mp3_44100_128") == true)
    }

    func testJSONBodyOmitsDefaultSpeedAndIncludesText() throws {
        let request = TTSRequest(
            text: "Hello world",
            voiceId: "abc",
            modelId: "eleven_flash_v2_5",
            speed: 1.0
        )
        let json = try decode(request.jsonBody())
        XCTAssertEqual(json["text"] as? String, "Hello world")
        XCTAssertEqual(json["model_id"] as? String, "eleven_flash_v2_5")
        XCTAssertNil(json["previous_text"])
        let settings = try XCTUnwrap(json["voice_settings"] as? [String: Any])
        XCTAssertNil(settings["speed"])
        XCTAssertEqual(double(settings["stability"]), 0.5)
        XCTAssertEqual(double(settings["similarity_boost"]), 0.75)
    }

    func testJSONBodyIncludesSpeedAndPreviousText() throws {
        let request = TTSRequest(
            text: "Next part",
            voiceId: "abc",
            modelId: "eleven_turbo_v2_5",
            speed: 1.15,
            previousText: "Earlier part."
        )
        let json = try decode(request.jsonBody())
        XCTAssertEqual(json["previous_text"] as? String, "Earlier part.")
        let settings = try XCTUnwrap(json["voice_settings"] as? [String: Any])
        XCTAssertEqual(double(settings["speed"]), 1.15)
    }

    func testErrorMessageFromDetailString() {
        let data = Data("{\"detail\":\"Invalid API key\"}".utf8)
        XCTAssertEqual(ElevenLabsError.message(fromBody: data, status: 401), "Invalid API key")
    }

    func testErrorMessageFromNestedDetail() {
        let data = Data("{\"detail\":{\"status\":\"quota_exceeded\",\"message\":\"You have exceeded your quota\"}}".utf8)
        XCTAssertEqual(
            ElevenLabsError.message(fromBody: data, status: 401),
            "You have exceeded your quota"
        )
    }

    func testHTTPErrorMapsUnauthorized() {
        let error = ElevenLabsError.httpStatus(401, "nope")
        XCTAssertEqual(error.errorDescription, "ElevenLabs rejected the API key.")
    }

    func testVoiceDecoding() throws {
        let data = Data("""
        {"voices":[{"voice_id":"JBFqnCBsd6RMkjVDRZzb","name":"George","category":"premade"}]}
        """.utf8)
        let decoded = try JSONDecoder().decode(VoicesResponse.self, from: data)
        XCTAssertEqual(decoded.voices.first?.id, "JBFqnCBsd6RMkjVDRZzb")
        XCTAssertEqual(decoded.voices.first?.name, "George")
    }

    private func decode(_ data: Data) throws -> [String: Any] {
        let obj = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(obj as? [String: Any])
    }

    private func double(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }
}
