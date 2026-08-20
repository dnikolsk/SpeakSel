import Foundation

struct ElevenLabsVoice: Codable, Identifiable, Hashable {
    let voiceId: String
    let name: String
    var category: String?

    var id: String { voiceId }

    enum CodingKeys: String, CodingKey {
        case voiceId = "voice_id"
        case name
        case category
    }
}

struct VoicesResponse: Codable {
    let voices: [ElevenLabsVoice]
}

struct TTSRequest: Equatable {
    var text: String
    var voiceId: String
    var modelId: String
    var speed: Double
    var previousText: String?

    func jsonBody() throws -> Data {
        var settings: [String: Any] = [
            "stability": 0.5,
            "similarity_boost": 0.75
        ]
        if (0.7...1.2).contains(speed), abs(speed - 1.0) > 0.001 {
            settings["speed"] = speed
        }

        var body: [String: Any] = [
            "text": text,
            "model_id": modelId,
            "voice_settings": settings
        ]
        if let previousText, !previousText.isEmpty {
            body["previous_text"] = previousText
        }
        return try JSONSerialization.data(withJSONObject: body, options: [])
    }

    func url(baseURL: URL = ElevenLabsClient.defaultBaseURL) -> URL {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("v1/text-to-speech/\(voiceId)"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "output_format", value: "mp3_44100_128")
        ]
        return components.url!
    }
}

enum ElevenLabsError: LocalizedError, Equatable {
    case invalidURL
    case httpStatus(Int, String)
    case emptyAudio
    case missingAPIKey
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid ElevenLabs URL."
        case .httpStatus(let code, let message):
            if code == 401 { return "ElevenLabs rejected the API key." }
            if code == 429 { return "ElevenLabs rate limit hit. Try again in a moment." }
            return message.isEmpty ? "ElevenLabs error (\(code))." : message
        case .emptyAudio:
            return "ElevenLabs returned no audio."
        case .missingAPIKey:
            return "Add your ElevenLabs API key in SpeakSel settings."
        case .decoding(let message):
            return message
        }
    }

    static func message(fromBody data: Data, status: Int) -> String {
        if let obj = try? JSONSerialization.jsonObject(with: data) {
            if let dict = obj as? [String: Any] {
                if let detail = dict["detail"] as? String, !detail.isEmpty {
                    return detail
                }
                if let detail = dict["detail"] as? [String: Any] {
                    if let message = detail["message"] as? String, !message.isEmpty {
                        return message
                    }
                    if let statusName = detail["status"] as? String, !statusName.isEmpty {
                        return statusName.replacingOccurrences(of: "_", with: " ")
                    }
                }
                if let message = dict["message"] as? String, !message.isEmpty {
                    return message
                }
            }
        }
        if let raw = String(data: data, encoding: .utf8), !raw.isEmpty {
            return String(raw.prefix(240))
        }
        return "ElevenLabs error (\(status))."
    }
}

struct ElevenLabsClient {
    static let defaultBaseURL = URL(string: "https://api.elevenlabs.io")!
    static let defaultVoiceId = "JBFqnCBsd6RMkjVDRZzb" // George, ElevenLabs docs default
    static let defaultVoiceName = "George"

    var baseURL: URL
    var session: URLSession

    init(baseURL: URL = defaultBaseURL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func listVoices(apiKey: String) async throws -> [ElevenLabsVoice] {
        guard !apiKey.isEmpty else { throw ElevenLabsError.missingAPIKey }
        let url = baseURL.appendingPathComponent("v1/voices")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        let (data, response) = try await session.data(for: request)
        try Self.throwIfNeeded(data: data, response: response)
        do {
            return try JSONDecoder().decode(VoicesResponse.self, from: data).voices
        } catch {
            throw ElevenLabsError.decoding("Could not read the ElevenLabs voice list.")
        }
    }

    func synthesize(_ request: TTSRequest, apiKey: String) async throws -> Data {
        guard !apiKey.isEmpty else { throw ElevenLabsError.missingAPIKey }
        var urlRequest = URLRequest(url: request.url(baseURL: baseURL))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue(apiKey, forHTTPHeaderField: "xi-api-key")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("audio/mpeg", forHTTPHeaderField: "Accept")
        urlRequest.timeoutInterval = 90
        urlRequest.httpBody = try request.jsonBody()

        let (data, response) = try await session.data(for: urlRequest)
        try Self.throwIfNeeded(data: data, response: response)
        guard !data.isEmpty else { throw ElevenLabsError.emptyAudio }
        return data
    }

    private static func throwIfNeeded(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            throw ElevenLabsError.httpStatus(-1, "No HTTP response.")
        }
        guard (200...299).contains(http.statusCode) else {
            throw ElevenLabsError.httpStatus(http.statusCode, ElevenLabsError.message(fromBody: data, status: http.statusCode))
        }
    }
}
