import Foundation

enum TextChunker {
    /// ElevenLabs accepts long strings, but smaller chunks start playback sooner
    /// and stay within typical plan limits.
    static let defaultMaxCharacters = 2500

    static func chunks(from text: String, maxCharacters: Int = defaultMaxCharacters) -> [String] {
        precondition(maxCharacters > 0, "maxCharacters must be positive")
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        if trimmed.count <= maxCharacters { return [trimmed] }

        var result: [String] = []
        var remaining = Substring(trimmed)

        while !remaining.isEmpty {
            if remaining.count <= maxCharacters {
                let last = remaining.trimmingCharacters(in: .whitespacesAndNewlines)
                if !last.isEmpty { result.append(last) }
                break
            }

            let window = remaining.prefix(maxCharacters)
            let splitEnd: String.Index
            if let sentence = window.lastIndex(where: { ".!?\n".contains($0) }),
               sentence > window.startIndex {
                splitEnd = window.index(after: sentence)
            } else if let space = window.lastIndex(where: { $0.isWhitespace }),
                      space > window.startIndex {
                splitEnd = space
            } else {
                splitEnd = window.endIndex
            }

            let piece = remaining[remaining.startIndex..<splitEnd]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty {
                result.append(piece)
            }

            let nextStart = splitEnd > remaining.startIndex
                ? splitEnd
                : remaining.index(after: remaining.startIndex)
            remaining = remaining[nextStart...].drop(while: { $0.isWhitespace })
        }

        return result
    }
}
